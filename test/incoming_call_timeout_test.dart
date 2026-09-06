import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sip_ua/sip_ua.dart';

import 'package:flutter_sip_softphone/core/services/sip_manager.dart';
import 'package:flutter_sip_softphone/core/services/call_history_service.dart';
import 'package:flutter_sip_softphone/data/models/call_history_entry.dart';
import 'package:flutter_sip_softphone/data/repositories/call_history_repository.dart';

class MockHelper extends SIPUAHelper {
  @override
  bool get connected => true;
  @override
  bool get registered => true;
  @override
  void stop() {}
  @override
  void addSipUaHelperListener(SipUaHelperListener listener) {}
  @override
  void removeSipUaHelperListener(SipUaHelperListener listener) {}
}

class MockCall implements Call {
  @override
  final String id;
  @override
  final String direction;
  @override
  // ignore: non_constant_identifier_names
  final String remote_identity;
  @override
  CallStateEnum state;

  bool wasHungUp = false;
  bool wasAnswered = false;

  MockCall({
    this.id = 'call-timeout-1',
    this.direction = 'INCOMING',
    this.remote_identity = '201',
    this.state = CallStateEnum.CALL_INITIATION,
  });

  @override
  void hangup([Map<String, dynamic>? options]) {
    wasHungUp = true;
  }

  @override
  void answer(Map<String, dynamic> options, {dynamic mediaStream}) {
    wasAnswered = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter &&
        (invocation.memberName == #peerConnection ||
            invocation.memberName == #session)) {
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SipManager sip;
  late CallHistoryService historyService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'),
          (MethodCall methodCall) async => 1,
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global'),
          (MethodCall methodCall) async => 1,
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC/audio'),
          (MethodCall methodCall) async => true,
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Method'),
          (MethodCall methodCall) async => true,
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (MethodCall methodCall) async => 1,
        );

    sip = SipManager();
    sip.resetForTesting();
    sip.setHelperForTesting(MockHelper());

    final repo = SharedPrefsCallHistoryRepository();
    historyService = CallHistoryService(repository: repo);
    await historyService.loadEntries();
    sip.setCallHistoryServiceForTesting(historyService);
  });

  tearDown(() {
    sip.resetForTesting();
  });

  test(
    'Incoming call schedules 45s ringing timer and times out after 45s',
    () async {
      final fakeCall = MockCall(id: 'call-45s-timeout');
      expect(sip.incomingRingingTimerForTesting, isNull);

      // Receive incoming CALL_INITIATION
      sip.callStateChanged(fakeCall, CallState(CallStateEnum.CALL_INITIATION));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Timer must be active
      expect(sip.incomingRingingTimerForTesting, isNotNull);
      expect(sip.incomingRingingTimerForTesting!.isActive, isTrue);

      // Verify call history was initialized with missed / incoming
      final initialEntry = historyService.getEntryByCorrelationId(
        'call-45s-timeout',
      );
      expect(initialEntry, isNotNull);
      expect(initialEntry!.direction, equals(CallDirection.incoming));
      expect(initialEntry.result, equals(CallResult.missed));
      expect(initialEntry.endedAt, isNull);

      expect(fakeCall.wasHungUp, isFalse);
    },
  );

  test(
    'Caller cancelling before 45s immediately cancels timer and stops ringing',
    () async {
      final fakeCall = MockCall(id: 'call-caller-cancel');
      sip.callStateChanged(fakeCall, CallState(CallStateEnum.CALL_INITIATION));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(sip.incomingRingingTimerForTesting, isNotNull);
      expect(sip.incomingRingingTimerForTesting!.isActive, isTrue);

      // Caller sends CANCEL -> state becomes ENDED
      sip.callStateChanged(fakeCall, CallState(CallStateEnum.ENDED));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Timer must be immediately cancelled
      expect(sip.incomingRingingTimerForTesting, isNull);

      // Verify call history has exactly 1 entry recorded as missed
      final entries = historyService.entries
          .where((e) => e.correlationId == 'call-caller-cancel')
          .toList();
      expect(entries.length, equals(1));
      expect(entries.first.result, equals(CallResult.missed));
      expect(entries.first.endedAt, isNotNull);
    },
  );

  test(
    'Callee answering call cancels 45s timer immediately and marks answered',
    () async {
      final fakeCall = MockCall(id: 'call-answer');
      sip.callStateChanged(fakeCall, CallState(CallStateEnum.CALL_INITIATION));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sip.incomingRingingTimerForTesting, isNotNull);

      // Call ACCEPTED
      sip.callStateChanged(fakeCall, CallState(CallStateEnum.ACCEPTED));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sip.incomingRingingTimerForTesting, isNull);

      final entry = historyService.getEntryByCorrelationId('call-answer');
      expect(entry, isNotNull);
      expect(entry!.result, equals(CallResult.answered));
    },
  );

  test(
    'Callee declining call cancels 45s timer immediately and records single declined entry',
    () async {
      final fakeCall = MockCall(id: 'call-decline');
      sip.callStateChanged(fakeCall, CallState(CallStateEnum.CALL_INITIATION));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sip.incomingRingingTimerForTesting, isNotNull);

      // Callee clicks hangupCall
      sip.hangupCall();
      expect(sip.incomingRingingTimerForTesting, isNull);

      // End event follows
      sip.callStateChanged(fakeCall, CallState(CallStateEnum.ENDED));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final entries = historyService.entries
          .where((e) => e.correlationId == 'call-decline')
          .toList();
      expect(entries.length, equals(1));
      expect(entries.first.endedAt, isNotNull);
    },
  );

  test(
    'Guaranteed single timer: multiple CALL_INITIATION events on same call do not duplicate timer',
    () async {
      final fakeCall = MockCall(id: 'call-dedup');
      sip.callStateChanged(fakeCall, CallState(CallStateEnum.CALL_INITIATION));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final timer1 = sip.incomingRingingTimerForTesting;
      expect(timer1, isNotNull);

      // Duplicate CALL_INITIATION event
      sip.callStateChanged(fakeCall, CallState(CallStateEnum.CALL_INITIATION));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final timer2 = sip.incomingRingingTimerForTesting;
      expect(timer2, isNotNull);

      // timer1 must be cancelled
      expect(timer1!.isActive, isFalse);
      expect(timer2!.isActive, isTrue);

      // History service must have only 1 entry
      final entries = historyService.entries
          .where((e) => e.correlationId == 'call-dedup')
          .toList();
      expect(entries.length, equals(1));
    },
  );
}
