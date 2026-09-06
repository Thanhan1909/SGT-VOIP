import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sip_softphone/core/services/call_coordinator.dart';
import 'package:flutter_sip_softphone/core/services/native_call_bridge.dart';

class MockNativeCallBridge implements NativeCallBridge {
  final StreamController<Map<String, String>> _actionController =
      StreamController<Map<String, String>>.broadcast();
  final StreamController<String> _tokenController =
      StreamController<String>.broadcast();

  final List<String> shownCalls = [];
  final List<String> dismissedCalls = [];

  void emitAction(String action, String callUuid) {
    _actionController.add({'action': action, 'callUuid': callUuid});
  }

  void emitVoipToken(String token) {
    _tokenController.add(token);
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
  Future<String?> getVoipToken() async => 'mock_voip_token_123';

  @override
  Stream<Map<String, String>> get callActionStream => _actionController.stream;

  @override
  Stream<String> get voipTokenStream => _tokenController.stream;

  @override
  void dispose() {
    _actionController.close();
    _tokenController.close();
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
  });
}
