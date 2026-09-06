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

  String? _lastHandledActionKey;
  DateTime? _lastHandledActionTime;

  static String normalizeUuid(String? uuid) =>
      (uuid ?? '').trim().toLowerCase();

  bool _isDuplicateAction(String action, String callUuid) {
    final key = '$action:${normalizeUuid(callUuid)}';
    final now = DateTime.now();
    if (_lastHandledActionKey == key &&
        _lastHandledActionTime != null &&
        now.difference(_lastHandledActionTime!) < const Duration(seconds: 3)) {
      debugPrint(
        '[CallCoordinator] Duplicate action suppressed: $action for $callUuid',
      );
      return true;
    }
    _lastHandledActionKey = key;
    _lastHandledActionTime = now;
    return false;
  }

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
        // ACK immediately to prevent race conditions with subsequent reads
        await nativeCallBridge.ackCallAction();
        _handleCallAction(pending);
      }
    } catch (e) {
      debugPrint(
        '[CallCoordinator] Error checking pending cold-start action: $e',
      );
    }
  }

  void _handleCallAction(Map<String, String> event) {
    final action = event['action'] ?? '';
    final callUuid = (event['callUuid'] ?? '').trim();

    if (action.isEmpty) return;

    if (action == 'incoming_push') {
      delegate?.ensureConnected();
      return;
    }

    if (callUuid.isNotEmpty && _isDuplicateAction(action, callUuid)) {
      return;
    }

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

      default:
        debugPrint('[CallCoordinator] Unknown action: $action');
        break;
    }
  }

  void _handleAnswerAction(String callUuid) {
    final trimmed = callUuid.trim();
    if (trimmed.isEmpty) return;
    if (delegate?.hasActiveCall == true &&
        normalizeUuid(_activeCallUuid) == normalizeUuid(trimmed)) {
      debugPrint('[CallCoordinator] Answering active SIP call immediately.');
      delegate?.answerCall();
      _isNativeIncomingShown = false;
      nativeCallBridge.dismissIncomingCall(trimmed);
    } else {
      debugPrint(
        '[CallCoordinator] SIP call not yet arrived. Storing pending answer for $trimmed.',
      );
      _pendingAnswerUuid = trimmed;
      _pendingAnswerTimeout?.cancel();
      _pendingAnswerTimeout = Timer(const Duration(seconds: 15), () {
        debugPrint('[CallCoordinator] Pending answer for $trimmed expired.');
        if (_pendingAnswerUuid == trimmed) {
          _pendingAnswerUuid = null;
        }
      });
      delegate?.ensureConnected();
    }
  }

  void _handleDeclineAction(String callUuid) {
    final trimmed = callUuid.trim();
    if (trimmed.isEmpty) return;
    if (normalizeUuid(_pendingAnswerUuid) == normalizeUuid(trimmed)) {
      _pendingAnswerUuid = null;
      _pendingAnswerTimeout?.cancel();
    }
    _declinedCallUuids.add(trimmed);
    if (delegate?.hasActiveCall == true &&
        normalizeUuid(_activeCallUuid) == normalizeUuid(trimmed)) {
      delegate?.hangupCall();
    }
    _isNativeIncomingShown = false;
    nativeCallBridge.dismissIncomingCall(trimmed);
  }

  void onCancelPushReceived(String callUuid) {
    final trimmed = callUuid.trim();
    if (trimmed.isEmpty) return;
    if (normalizeUuid(_pendingAnswerUuid) == normalizeUuid(trimmed)) {
      _pendingAnswerUuid = null;
      _pendingAnswerTimeout?.cancel();
    }
    if (normalizeUuid(_activeCallUuid) == normalizeUuid(trimmed)) {
      _activeCallUuid = null;
      if (delegate?.hasActiveCall == true) {
        delegate?.hangupCall();
      }
    }
    nativeCallBridge.dismissIncomingCall(trimmed);
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
    final trimmed = callUuid.trim();
    _activeCallUuid = trimmed;

    // Check if user already declined this specific call UUID prior to INVITE arrival (case-insensitive)
    final matchedDeclined = _declinedCallUuids
        .where((u) => normalizeUuid(u) == normalizeUuid(trimmed))
        .toList();
    if (matchedDeclined.isNotEmpty) {
      debugPrint(
        '[CallCoordinator] Call $trimmed was declined by user prior to INVITE arrival. Hanging up.',
      );
      for (final u in matchedDeclined) {
        _declinedCallUuids.remove(u);
      }
      _isNativeIncomingShown = false;
      nativeCallBridge.dismissIncomingCall(trimmed);
      delegate?.hangupCall();
      return false;
    }

    // Check if user already tapped answer for this EXACT call UUID (case-insensitive)
    if (_pendingAnswerUuid != null &&
        normalizeUuid(_pendingAnswerUuid) == normalizeUuid(trimmed)) {
      debugPrint(
        '[CallCoordinator] Auto-answering incoming call $trimmed because user previously answered matching UUID.',
      );
      _pendingAnswerUuid = null;
      _pendingAnswerTimeout?.cancel();
      _isNativeIncomingShown = false;
      nativeCallBridge.dismissIncomingCall(trimmed);
      delegate?.answerCall();
      return true;
    }

    // If app is not in foreground, show CallStyle notification / CallKit
    if (!isAppForeground) {
      debugPrint(
        '[CallCoordinator] App in background: triggering native incoming notification.',
      );
      nativeCallBridge.showIncomingCall(
        callUuid: trimmed,
        callerName: callerName,
        callerNumber: callerNumber,
      );
      _isNativeIncomingShown = true;
    }

    return false;
  }

  void onCallConfirmed(String callUuid) {
    final trimmed = callUuid.trim();
    if (normalizeUuid(_pendingAnswerUuid) == normalizeUuid(trimmed) ||
        normalizeUuid(_pendingAnswerUuid) == normalizeUuid(_activeCallUuid)) {
      _pendingAnswerUuid = null;
      _pendingAnswerTimeout?.cancel();
    }
    if (_isNativeIncomingShown) {
      nativeCallBridge.dismissIncomingCall(_activeCallUuid ?? trimmed);
      _isNativeIncomingShown = false;
    }
  }

  void onCallTerminated(String callUuid) {
    final trimmed = callUuid.trim();
    final targetUuid = _activeCallUuid ?? trimmed;
    _activeCallUuid = null;
    if (normalizeUuid(_pendingAnswerUuid) == normalizeUuid(trimmed) ||
        normalizeUuid(_pendingAnswerUuid) == normalizeUuid(targetUuid)) {
      _pendingAnswerUuid = null;
      _pendingAnswerTimeout?.cancel();
    }
    _declinedCallUuids.removeWhere(
      (u) =>
          normalizeUuid(u) == normalizeUuid(trimmed) ||
          normalizeUuid(u) == normalizeUuid(targetUuid),
    );
    nativeCallBridge.dismissIncomingCall(targetUuid);
    _isNativeIncomingShown = false;
  }

  void dispose() {
    _callActionSub?.cancel();
    _pendingAnswerTimeout?.cancel();
    nativeCallBridge.dispose();
  }
}
