import 'dart:async';
import 'package:flutter/foundation.dart';
import 'native_call_bridge.dart';

abstract class CallHandlerDelegate {
  bool get hasActiveCall;
  Future<void> answerCall();
  void hangupCall();
  Future<void> ensureConnected();
}

class CallCoordinator {
  final NativeCallBridge nativeCallBridge;
  CallHandlerDelegate? delegate;

  String? _activeCallUuid;
  String? _pendingAnswerUuid;
  Timer? _pendingAnswerTimeout;
  bool _isNativeIncomingShown = false;
  final Set<String> _declinedCallUuids = <String>{};
  StreamSubscription<Map<String, String>>? _callActionSub;

  CallCoordinator({required this.nativeCallBridge, this.delegate}) {
    _initBridgeListener();
    checkPendingColdStartAction();
  }

  String? get activeCallUuid => _activeCallUuid;
  String? get pendingAnswerUuid => _pendingAnswerUuid;
  bool get isNativeIncomingShown => _isNativeIncomingShown;
  Set<String> get declinedCallUuids => Set.unmodifiable(_declinedCallUuids);

  void _initBridgeListener() {
    _callActionSub = nativeCallBridge.callActionStream.listen(
      _handleCallAction,
    );
  }

  Future<void> checkPendingColdStartAction() async {
    try {
      final pending = await nativeCallBridge.getPendingCallAction();
      if (pending != null && pending.isNotEmpty) {
        debugPrint(
          '[CallCoordinator] Consuming pending cold-start action: $pending',
        );
        _handleCallAction(pending);
        await nativeCallBridge.ackCallAction();
      }
    } catch (e) {
      debugPrint(
        '[CallCoordinator] Error checking pending cold-start action: $e',
      );
    }
  }

  void _handleCallAction(Map<String, String> event) {
    final action = event['action'] ?? '';
    final callUuid = event['callUuid'] ?? '';
    debugPrint(
      '[CallCoordinator] Received native action: $action, callUuid: $callUuid',
    );

    switch (action) {
      case 'answer':
        _handleAnswerAction(callUuid);
        break;

      case 'decline':
        _handleDeclineAction(callUuid);
        break;

      case 'cancel':
        onCancelPushReceived(callUuid);
        break;

      case 'incoming_push':
        delegate?.ensureConnected();
        break;

      default:
        debugPrint('[CallCoordinator] Unknown action: $action');
        break;
    }
  }

  void _handleAnswerAction(String callUuid) {
    if (callUuid.isEmpty) return;
    if (delegate?.hasActiveCall == true && _activeCallUuid == callUuid) {
      debugPrint('[CallCoordinator] Answering active SIP call immediately.');
      delegate?.answerCall();
      _isNativeIncomingShown = false;
      nativeCallBridge.dismissIncomingCall(callUuid);
    } else {
      debugPrint(
        '[CallCoordinator] SIP call not yet arrived. Storing pending answer for $callUuid.',
      );
      _pendingAnswerUuid = callUuid;
      _pendingAnswerTimeout?.cancel();
      _pendingAnswerTimeout = Timer(const Duration(seconds: 15), () {
        debugPrint('[CallCoordinator] Pending answer for $callUuid expired.');
        if (_pendingAnswerUuid == callUuid) {
          _pendingAnswerUuid = null;
        }
      });
      delegate?.ensureConnected();
    }
  }

  void _handleDeclineAction(String callUuid) {
    if (callUuid.isEmpty) return;
    if (_pendingAnswerUuid == callUuid) {
      _pendingAnswerUuid = null;
      _pendingAnswerTimeout?.cancel();
    }
    _declinedCallUuids.add(callUuid);
    if (delegate?.hasActiveCall == true && _activeCallUuid == callUuid) {
      delegate?.hangupCall();
    }
    _isNativeIncomingShown = false;
    nativeCallBridge.dismissIncomingCall(callUuid);
  }

  void onCancelPushReceived(String callUuid) {
    if (callUuid.isEmpty) return;
    if (_pendingAnswerUuid == callUuid) {
      _pendingAnswerUuid = null;
      _pendingAnswerTimeout?.cancel();
    }
    if (_activeCallUuid == callUuid) {
      _activeCallUuid = null;
      if (delegate?.hasActiveCall == true) {
        delegate?.hangupCall();
      }
    }
    nativeCallBridge.dismissIncomingCall(callUuid);
    _isNativeIncomingShown = false;
  }

  /// Called by SipManager when incoming INVITE arrives.
  /// Returns `true` if call was automatically answered due to pending answer from notification.
  bool onIncomingCallReceived({
    required String callUuid,
    required String callerName,
    required String callerNumber,
    required bool isAppForeground,
  }) {
    _activeCallUuid = callUuid;

    // Check if user already declined this specific call UUID prior to INVITE arrival
    if (_declinedCallUuids.contains(callUuid)) {
      debugPrint(
        '[CallCoordinator] Call $callUuid was declined by user prior to INVITE arrival. Hanging up.',
      );
      _declinedCallUuids.remove(callUuid);
      _isNativeIncomingShown = false;
      nativeCallBridge.dismissIncomingCall(callUuid);
      delegate?.hangupCall();
      return false;
    }

    // Check if user already tapped answer for this EXACT call UUID
    if (_pendingAnswerUuid != null && _pendingAnswerUuid == callUuid) {
      debugPrint(
        '[CallCoordinator] Auto-answering incoming call $callUuid because user previously answered matching UUID.',
      );
      _pendingAnswerUuid = null;
      _pendingAnswerTimeout?.cancel();
      _isNativeIncomingShown = false;
      nativeCallBridge.dismissIncomingCall(callUuid);
      delegate?.answerCall();
      return true;
    }

    // If app is not in foreground, show CallStyle notification / CallKit
    if (!isAppForeground) {
      debugPrint(
        '[CallCoordinator] App in background: triggering native incoming notification.',
      );
      nativeCallBridge.showIncomingCall(
        callUuid: callUuid,
        callerName: callerName,
        callerNumber: callerNumber,
      );
      _isNativeIncomingShown = true;
    }

    return false;
  }

  void onCallConfirmed(String callUuid) {
    if (_pendingAnswerUuid == callUuid) {
      _pendingAnswerUuid = null;
      _pendingAnswerTimeout?.cancel();
    }
    if (_isNativeIncomingShown) {
      nativeCallBridge.dismissIncomingCall(callUuid);
      _isNativeIncomingShown = false;
    }
  }

  void onCallTerminated(String callUuid) {
    if (_activeCallUuid == callUuid) {
      _activeCallUuid = null;
    }
    if (_pendingAnswerUuid == callUuid) {
      _pendingAnswerUuid = null;
      _pendingAnswerTimeout?.cancel();
    }
    _declinedCallUuids.remove(callUuid);
    nativeCallBridge.dismissIncomingCall(callUuid);
    _isNativeIncomingShown = false;
  }

  void dispose() {
    _callActionSub?.cancel();
    _pendingAnswerTimeout?.cancel();
    nativeCallBridge.dispose();
  }
}
