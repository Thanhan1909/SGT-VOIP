import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sip_softphone/core/services/call_coordinator.dart';
import 'package:flutter_sip_softphone/core/services/native_call_bridge.dart';

class MockNativeCallBridge implements NativeCallBridge {
  final StreamController<Map<String, String>> _actionController =
      StreamController<Map<String, String>>.broadcast();
  final StreamController<String> _tokenController =
      StreamController<String>.broadcast();
  final StreamController<bool> _audioSessionController =
      StreamController<bool>.broadcast();

  final List<String> shownCalls = [];
  final List<String> dismissedCalls = [];
  Map<String, String>? pendingAction;
  bool ackCalled = false;

  void emitAction(String action, String callUuid) {
    _actionController.add({'action': action, 'callUuid': callUuid});
  }

  void emitVoipToken(String token) {
    _tokenController.add(token);
  }

  void emitAudioSessionState(bool active) {
    _audioSessionController.add(active);
  }

  @override
  Future<bool> showIncomingCall({
    required String callUuid,
    required String callerName,
    required String callerNumber,
  }) async {
    shownCalls.add(callUuid);
    return true;
  }

  @override
  Future<bool> dismissIncomingCall(String callUuid) async {
    dismissedCalls.add(callUuid);
    return true;
  }

  @override
  Future<bool> canUseFullScreenIntent() async => true;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<Map<String, String>?> getPendingCallAction() async => pendingAction;

  @override
  Future<bool> ackCallAction() async {
    ackCalled = true;
    pendingAction = null;
    return true;
  }

  @override
  Future<String?> getVoipToken() async => 'mock_voip_token_123';

  @override
  Stream<Map<String, String>> get callActionStream => _actionController.stream;

  @override
  Stream<String> get voipTokenStream => _tokenController.stream;

  @override
  Stream<bool> get audioSessionStateStream => _audioSessionController.stream;

  @override
  void dispose() {
    _actionController.close();
    _tokenController.close();
    _audioSessionController.close();
  }
}

class MockCallHandlerDelegate implements CallHandlerDelegate {
  bool activeCall = false;
  int answerCallsCount = 0;
  int hangupCallsCount = 0;
  int ensureConnectedCount = 0;

  @override
  bool get hasActiveCall => activeCall;

  @override
  Future<void> answerCall() async {
    answerCallsCount++;
  }

  @override
  void hangupCall() {
    hangupCallsCount++;
  }

  @override
  Future<void> ensureConnected() async {
    ensureConnectedCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockNativeCallBridge mockBridge;
  late MockCallHandlerDelegate mockDelegate;
  late CallCoordinator coordinator;

  setUp(() {
    mockBridge = MockNativeCallBridge();
    mockDelegate = MockCallHandlerDelegate();
    coordinator = CallCoordinator(
      nativeCallBridge: mockBridge,
      delegate: mockDelegate,
    );
  });

  tearDown(() {
    coordinator.dispose();
    mockBridge.dispose();
  });

  group('CallCoordinator Phase 4 Tests', () {
    test(
      '1. App in background triggers native CallStyle/CallKit notification',
      () {
        final autoAnswered = coordinator.onIncomingCallReceived(
          callUuid: 'call-bg-001',
          callerName: 'Sale 201',
          callerNumber: '201',
          isAppForeground: false,
        );

        expect(autoAnswered, isFalse);
        expect(coordinator.isNativeIncomingShown, isTrue);
        expect(mockBridge.shownCalls, contains('call-bg-001'));
        expect(mockDelegate.answerCallsCount, equals(0));
      },
    );

    test('2. App in foreground does NOT trigger native notification', () {
      final autoAnswered = coordinator.onIncomingCallReceived(
        callUuid: 'call-fg-002',
        callerName: 'Leader 202',
        callerNumber: '202',
        isAppForeground: true,
      );

      expect(autoAnswered, isFalse);
      expect(coordinator.isNativeIncomingShown, isFalse);
      expect(mockBridge.shownCalls, isEmpty);
    });

    test(
      '3. Answer action from native notification answers active call and dismisses UI',
      () async {
        mockDelegate.activeCall = true;
        coordinator.onIncomingCallReceived(
          callUuid: 'call-answer-003',
          callerName: 'Leader 202',
          callerNumber: '202',
          isAppForeground: false,
        );

        mockBridge.emitAction('answer', 'call-answer-003');
        await pumpEventQueue();

        expect(mockDelegate.answerCallsCount, equals(1));
        expect(mockBridge.dismissedCalls, contains('call-answer-003'));
        expect(coordinator.isNativeIncomingShown, isFalse);
      },
    );

    test(
      '4. Decline action from native notification hangs up active call and dismisses UI',
      () async {
        mockDelegate.activeCall = true;
        coordinator.onIncomingCallReceived(
          callUuid: 'call-decline-004',
          callerName: '201',
          callerNumber: '201',
          isAppForeground: false,
        );

        mockBridge.emitAction('decline', 'call-decline-004');
        await pumpEventQueue();

        expect(mockDelegate.hangupCallsCount, equals(1));
        expect(mockBridge.dismissedCalls, contains('call-decline-004'));
        expect(coordinator.isNativeIncomingShown, isFalse);
      },
    );

    test(
      '5. Cold start / Push race condition: user answers before SIP INVITE arrives',
      () async {
        mockDelegate.activeCall = false;

        // User presses "Answer" on CallStyle notification / CallKit
        mockBridge.emitAction('answer', 'call-coldstart-005');
        await pumpEventQueue();

        expect(coordinator.pendingAnswerUuid, equals('call-coldstart-005'));
        expect(mockDelegate.answerCallsCount, equals(0));
        expect(mockDelegate.ensureConnectedCount, equals(1));

        // Moments later, SIP INVITE arrives with matching callUuid
        mockDelegate.activeCall = true;
        final autoAnswered = coordinator.onIncomingCallReceived(
          callUuid: 'call-coldstart-005',
          callerName: '201',
          callerNumber: '201',
          isAppForeground: false,
        );

        expect(autoAnswered, isTrue);
        expect(mockDelegate.answerCallsCount, equals(1));
        expect(coordinator.pendingAnswerUuid, isNull);
        expect(mockBridge.dismissedCalls, contains('call-coldstart-005'));
      },
    );

    test(
      '6. Call termination dismisses native incoming notification (no ghost notification)',
      () {
        coordinator.onIncomingCallReceived(
          callUuid: 'call-term-006',
          callerName: '201',
          callerNumber: '201',
          isAppForeground: false,
        );
        expect(coordinator.isNativeIncomingShown, isTrue);

        coordinator.onCallTerminated('call-term-006');

        expect(mockBridge.dismissedCalls, contains('call-term-006'));
        expect(coordinator.isNativeIncomingShown, isFalse);
        expect(coordinator.activeCallUuid, isNull);
      },
    );

    test(
      '7. PushKit incoming_push action triggers SIP reconnect/wakeup',
      () async {
        mockBridge.emitAction('incoming_push', 'call-push-007');
        await pumpEventQueue();

        expect(mockDelegate.ensureConnectedCount, equals(1));
      },
    );

    test('8. Mismatched UUID: user answered call A, call B arrives', () async {
      mockDelegate.activeCall = false;

      // User answered call A
      mockBridge.emitAction('answer', 'call-A');
      await pumpEventQueue();

      expect(coordinator.pendingAnswerUuid, equals('call-A'));

      // Call B arrives
      final autoAnswered = coordinator.onIncomingCallReceived(
        callUuid: 'call-B',
        callerName: 'Caller B',
        callerNumber: '203',
        isAppForeground: false,
      );

      // Must NOT answer call B!
      expect(autoAnswered, isFalse);
      expect(mockDelegate.answerCallsCount, equals(0));
      expect(coordinator.activeCallUuid, equals('call-B'));
      // Call A remains pending until its own INVITE or timeout
      expect(coordinator.pendingAnswerUuid, equals('call-A'));
    });

    test(
      '9. Decline prior to INVITE arrival drops the call upon INVITE',
      () async {
        mockDelegate.activeCall = false;

        // User declined call C before INVITE arrived
        mockBridge.emitAction('decline', 'call-C');
        await pumpEventQueue();

        expect(coordinator.declinedCallUuids, contains('call-C'));
        expect(mockBridge.dismissedCalls, contains('call-C'));

        // Now INVITE arrives for call C
        mockDelegate.activeCall = true;
        final autoAnswered = coordinator.onIncomingCallReceived(
          callUuid: 'call-C',
          callerName: 'Caller C',
          callerNumber: '201',
          isAppForeground: false,
        );

        expect(autoAnswered, isFalse);
        expect(mockDelegate.hangupCallsCount, equals(1));
        expect(coordinator.declinedCallUuids, isNot(contains('call-C')));
      },
    );

    test('10. Remote cancel prior to INVITE arrival dismisses UI', () async {
      mockBridge.emitAction('cancel', 'call-cancelled');
      await pumpEventQueue();

      expect(mockBridge.dismissedCalls, contains('call-cancelled'));
      expect(coordinator.isNativeIncomingShown, isFalse);
    });

    test('11. Call A ends, then Call B arrives cleanly', () async {
      // Call A
      coordinator.onIncomingCallReceived(
        callUuid: 'call-A-seq',
        callerName: 'Caller A',
        callerNumber: '201',
        isAppForeground: false,
      );
      coordinator.onCallConfirmed('call-A-seq');
      coordinator.onCallTerminated('call-A-seq');

      expect(coordinator.activeCallUuid, isNull);
      expect(coordinator.pendingAnswerUuid, isNull);

      // Call B
      final autoAnswered = coordinator.onIncomingCallReceived(
        callUuid: 'call-B-seq',
        callerName: 'Caller B',
        callerNumber: '202',
        isAppForeground: false,
      );

      expect(autoAnswered, isFalse);
      expect(coordinator.activeCallUuid, equals('call-B-seq'));
    });

    test(
      '12. Cold start durable pending action is consumed and ACKed',
      () async {
        final freshBridge = MockNativeCallBridge();
        freshBridge.pendingAction = {
          'action': 'answer',
          'callUuid': 'cold-call-99',
        };
        final freshDelegate = MockCallHandlerDelegate();

        final freshCoord = CallCoordinator(
          nativeCallBridge: freshBridge,
          delegate: freshDelegate,
        );

        await pumpEventQueue();

        expect(freshCoord.pendingAnswerUuid, equals('cold-call-99'));
        expect(freshBridge.ackCalled, isTrue);

        freshCoord.dispose();
        freshBridge.dispose();
      },
    );

    test('13. Duplicate call action within 3 seconds is suppressed', () async {
      mockDelegate.activeCall = true;
      coordinator.onIncomingCallReceived(
        callUuid: 'call-dedup-101',
        callerName: '201',
        callerNumber: '201',
        isAppForeground: false,
      );

      // Emit first answer action
      mockBridge.emitAction('answer', 'call-dedup-101');
      await pumpEventQueue();
      expect(mockDelegate.answerCallsCount, equals(1));

      // Immediately emit identical answer action (e.g. from both receiver and intent)
      mockBridge.emitAction('answer', 'call-dedup-101');
      await pumpEventQueue();

      // Count should still be 1 because second action was deduplicated
      expect(mockDelegate.answerCallsCount, equals(1));
    });

    test(
      '14. AudioSessionStateStream emits activation and deactivation events',
      () async {
        final states = <bool>[];
        final sub = mockBridge.audioSessionStateStream.listen(states.add);

        mockBridge.emitAudioSessionState(true);
        await pumpEventQueue();
        mockBridge.emitAudioSessionState(false);
        await pumpEventQueue();

        expect(states, equals([true, false]));
        await sub.cancel();
      },
    );
  });
}
