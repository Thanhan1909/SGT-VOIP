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
  StreamSubscription<Map<String, String>>? _callActionSub;

  CallCoordinator({
    required this.nativeCallBridge,
    this.delegate,
  }) {
    _initBridgeListener();
  }

  String? get activeCallUuid => _activeCallUuid;
  String? get pendingAnswerUuid => _pendingAnswerUuid;
  bool get isNativeIncomingShown => _isNativeIncomingShown;

  void _initBridgeListener() {
    _callActionSub = nativeCallBridge.callActionStream.listen(_handleCallAction);
  }

  void _handleCallAction(Map<String, String> event) {
    final action = event['action'] ?? '';
    final callUuid = event['callUuid'] ?? '';
    debugPrint('[CallCoordinator] Received native action: $action, callUuid: $callUuid');

    switch (action) {
      case 'answer':
        _handleAnswerAction(callUuid);
        break;

      case 'decline':
        _handleDeclineAction(callUuid);
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
    if (delegate?.hasActiveCall == true) {
      debugPrint('[CallCoordinator] Answering active SIP call immediately.');
      delegate?.answerCall();
      _isNativeIncomingShown = false;
      nativeCallBridge.dismissIncomingCall(callUuid);
    } else {
      debugPrint('[CallCoordinator] SIP call not yet arrived. Storing pending answer for $callUuid.');
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
    _pendingAnswerUuid = null;
    _pendingAnswerTimeout?.cancel();
    if (delegate?.hasActiveCall == true) {
      delegate?.hangupCall();
    }
    _isNativeIncomingShown = false;
    nativeCallBridge.dismissIncomingCall(callUuid);
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

    // Check if user already tapped answer from CallStyle notification or CallKit
    if (_pendingAnswerUuid != null) {
      debugPrint('[CallCoordinator] Auto-answering incoming call $callUuid because user previously answered.');
      _pendingAnswerUuid = null;
      _pendingAnswerTimeout?.cancel();
      _isNativeIncomingShown = false;
      nativeCallBridge.dismissIncomingCall(callUuid);
      delegate?.answerCall();
      return true;
    }

    // If app is not in foreground, show CallStyle notification / CallKit
    if (!isAppForeground) {
      debugPrint('[CallCoordinator] App in background: triggering native incoming notification.');
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
    _pendingAnswerUuid = null;
    _pendingAnswerTimeout?.cancel();
    if (_isNativeIncomingShown) {
      nativeCallBridge.dismissIncomingCall(callUuid);
      _isNativeIncomingShown = false;
    }
  }

  void onCallTerminated(String callUuid) {
    _activeCallUuid = null;
    _pendingAnswerUuid = null;
    _pendingAnswerTimeout?.cancel();
    nativeCallBridge.dismissIncomingCall(callUuid);
    _isNativeIncomingShown = false;
  }

  void dispose() {
    _callActionSub?.cancel();
    _pendingAnswerTimeout?.cancel();
  }
}
