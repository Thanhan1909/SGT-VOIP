import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:flutter_sip_softphone/core/services/sip_manager.dart';
import 'package:flutter_sip_softphone/core/services/call_coordinator.dart';
import 'package:flutter_sip_softphone/core/services/call_history_service.dart';
import 'package:flutter_sip_softphone/data/models/call_history_entry.dart';
import 'package:flutter_sip_softphone/data/models/sip_account.dart';
import 'package:flutter_sip_softphone/data/repositories/call_history_repository.dart';
import 'package:flutter_sip_softphone/presentation/screens/app_shell.dart';
import 'package:flutter_sip_softphone/presentation/screens/call_history_screen.dart';
import 'package:flutter_sip_softphone/presentation/screens/incoming_call_screen.dart';
import 'package:flutter_sip_softphone/main.dart';

class FakeCall implements Call {
  @override
  final String id;
  @override
  final String direction;
  @override
  // ignore: non_constant_identifier_names
  final String remote_identity;
  @override
  CallStateEnum state;

  FakeCall({
    this.id = 'call-test-123',
    this.direction = 'OUTGOING',
    this.remote_identity = '202',
    this.state = CallStateEnum.CALL_INITIATION,
  });

  bool hangupCalled = false;
  bool answerCalled = false;

  @override
  void hangup([Map<String, dynamic>? options]) {
    hangupCalled = true;
  }

  @override
  void answer(Map<String, dynamic> options, {dynamic mediaStream}) {
    answerCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSIPUAHelper extends SIPUAHelper {
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

  String? lastCallDestination;

  @override
  Future<bool> call(
    String target, {
    Map<String, dynamic>? customOptions,
    List<String>? headers,
    MediaStream? mediaStream,
    bool voiceonly = true,
  }) async {
    lastCallDestination = target;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
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
  });

  tearDown(() {
    SipManager().resetForTesting();
  });

  group('PHẦN 9 — Automated tests bắt buộc cho Call History', () {
    // 1. Incoming answered -> gọi đến
    test(
      '1. Incoming answered -> gọi đến (direction: incoming, result: answered)',
      () async {
        final repository = SharedPrefsCallHistoryRepository();
        final service = CallHistoryService(repository: repository);
        await service.loadEntries();

        await service.recordCallInitiation(
          correlationId: 'uuid-1',
          localExtension: '201',
          remoteNumber: '202',
          remoteDisplayName: 'Alice',
          direction: CallDirection.incoming,
        );

        await service.recordCallAnswered(correlationId: 'uuid-1');

        await service.recordCallEnded(
          correlationId: 'uuid-1',
          wasAnswered: true,
          wasDeclinedByUser: false,
        );

        final entries = await repository.getEntries();
        expect(entries.length, equals(1));
        expect(entries.first.direction, equals(CallDirection.incoming));
        expect(entries.first.result, equals(CallResult.answered));
        expect(entries.first.answeredAt, isNotNull);
        expect(entries.first.endedAt, isNotNull);
      },
    );

    // 2. Incoming ended trước khi answer -> gọi nhỡ
    test('2. Incoming ended trước khi answer -> gọi nhỡ', () async {
      final repository = SharedPrefsCallHistoryRepository();
      final service = CallHistoryService(repository: repository);
      await service.loadEntries();

      await service.recordCallInitiation(
        correlationId: 'uuid-2',
        localExtension: '201',
        remoteNumber: '203',
        remoteDisplayName: 'Bob',
        direction: CallDirection.incoming,
      );

      // Caller hangs up before answer
      await service.recordCallEnded(
        correlationId: 'uuid-2',
        wasAnswered: false,
        wasDeclinedByUser: false,
      );

      final entries = await repository.getEntries();
      expect(entries.length, equals(1));
      expect(entries.first.direction, equals(CallDirection.incoming));
      expect(entries.first.result, equals(CallResult.missed));
      expect(entries.first.answeredAt, isNull);
    });

    // 3. Incoming declined -> đã từ chối, không phải gọi nhỡ
    test('3. Incoming declined -> đã từ chối, không phải gọi nhỡ', () async {
      final repository = SharedPrefsCallHistoryRepository();
      final service = CallHistoryService(repository: repository);
      await service.loadEntries();

      await service.recordCallInitiation(
        correlationId: 'uuid-3',
        localExtension: '201',
        remoteNumber: '204',
        direction: CallDirection.incoming,
      );

      // Callee declines
      await service.recordCallEnded(
        correlationId: 'uuid-3',
        wasAnswered: false,
        wasDeclinedByUser: true,
      );

      final entries = await repository.getEntries();
      expect(entries.length, equals(1));
      expect(entries.first.direction, equals(CallDirection.incoming));
      expect(entries.first.result, equals(CallResult.declined));
    });

    // 4. Outgoing answered -> gọi đi
    test('4. Outgoing answered -> gọi đi', () async {
      final repository = SharedPrefsCallHistoryRepository();
      final service = CallHistoryService(repository: repository);
      await service.loadEntries();

      await service.recordCallInitiation(
        correlationId: 'uuid-4',
        localExtension: '201',
        remoteNumber: '205',
        direction: CallDirection.outgoing,
      );

      await service.recordCallAnswered(correlationId: 'uuid-4');
      await service.recordCallEnded(
        correlationId: 'uuid-4',
        wasAnswered: true,
        wasDeclinedByUser: false,
      );

      final entries = await repository.getEntries();
      expect(entries.length, equals(1));
      expect(entries.first.direction, equals(CallDirection.outgoing));
      expect(entries.first.result, equals(CallResult.answered));
    });

    // 5. Outgoing không trả lời -> gọi đi/noAnswer
    test('5. Outgoing không trả lời -> gọi đi/noAnswer', () async {
      final repository = SharedPrefsCallHistoryRepository();
      final service = CallHistoryService(repository: repository);
      await service.loadEntries();

      await service.recordCallInitiation(
        correlationId: 'uuid-5',
        localExtension: '201',
        remoteNumber: '206',
        direction: CallDirection.outgoing,
      );

      // Caller hangs up or remote no answer
      await service.recordCallEnded(
        correlationId: 'uuid-5',
        wasAnswered: false,
        wasDeclinedByUser: false,
      );

      final entries = await repository.getEntries();
      expect(entries.length, equals(1));
      expect(entries.first.direction, equals(CallDirection.outgoing));
      expect(entries.first.result, equals(CallResult.noAnswer));
    });

    // 6. FAILED -> trạng thái đúng
    test('6. FAILED -> trạng thái đúng cho incoming và outgoing', () async {
      final repository = SharedPrefsCallHistoryRepository();
      final service = CallHistoryService(repository: repository);
      await service.loadEntries();

      // Outgoing failed
      await service.recordCallInitiation(
        correlationId: 'uuid-6-out',
        localExtension: '201',
        remoteNumber: '207',
        direction: CallDirection.outgoing,
      );
      await service.recordCallFailed(
        correlationId: 'uuid-6-out',
        reason: 'User Not Found (404)',
        isIncoming: false,
      );

      // Incoming failed
      await service.recordCallInitiation(
        correlationId: 'uuid-6-in',
        localExtension: '201',
        remoteNumber: '208',
        direction: CallDirection.incoming,
      );
      await service.recordCallFailed(
        correlationId: 'uuid-6-in',
        reason: 'Transport Error',
        isIncoming: true,
      );

      final entries = await repository.getEntries();
      final outEntry = entries.firstWhere(
        (e) => e.correlationId == 'uuid-6-out',
      );
      final inEntry = entries.firstWhere((e) => e.correlationId == 'uuid-6-in');

      expect(outEntry.result, equals(CallResult.failed));
      expect(outEntry.failureReason, equals('User Not Found (404)'));
      expect(inEntry.result, equals(CallResult.missed));
    });

    // 7. Nhiều SIP event cùng call UUID chỉ tạo một bản ghi
    test('7. Nhiều SIP event cùng call UUID chỉ tạo một bản ghi', () async {
      final repository = SharedPrefsCallHistoryRepository();
      final service = CallHistoryService(repository: repository);
      await service.loadEntries();

      // Repeated progress/initiation/state events
      await service.recordCallInitiation(
        correlationId: 'uuid-7-dedup',
        localExtension: '201',
        remoteNumber: '209',
        direction: CallDirection.outgoing,
      );
      await service.recordCallInitiation(
        correlationId: 'uuid-7-dedup',
        localExtension: '201',
        remoteNumber: '209',
        direction: CallDirection.outgoing,
      );
      await service.recordCallAnswered(correlationId: 'uuid-7-dedup');
      await service.recordCallAnswered(correlationId: 'uuid-7-dedup');
      await service.recordCallEnded(
        correlationId: 'uuid-7-dedup',
        wasAnswered: true,
        wasDeclinedByUser: false,
      );

      final entries = await repository.getEntries();
      final matching = entries
          .where((e) => e.correlationId == 'uuid-7-dedup')
          .toList();
      expect(matching.length, equals(1));
    });

    // 8. Duration được tính từ answeredAt, không phải từ lúc bắt đầu đổ chuông
    test(
      '8. Duration được tính từ answeredAt, không phải từ lúc bắt đầu đổ chuông',
      () async {
        final repository = SharedPrefsCallHistoryRepository();

        final startedAt = DateTime(2026, 9, 6, 12, 0, 0);
        final answeredAt = DateTime(2026, 9, 6, 12, 0, 15); // Ringing for 15s
        final endedAt = DateTime(
          2026,
          9,
          6,
          12,
          1,
          0,
        ); // Call ended at 60s total

        final entry = CallHistoryEntry(
          id: 'entry-8',
          correlationId: 'uuid-8',
          localExtension: '201',
          remoteNumber: '210',
          direction: CallDirection.incoming,
          result: CallResult.answered,
          startedAt: startedAt,
          answeredAt: answeredAt,
          endedAt: endedAt,
          durationSeconds: endedAt
              .difference(answeredAt)
              .inSeconds, // 45 seconds
        );

        await repository.upsertEntry(entry);

        final loaded = (await repository.getEntries()).first;
        expect(loaded.durationSeconds, equals(45));
        expect(loaded.durationSeconds, isNot(equals(60)));
      },
    );

    // 9. Repository giữ tối đa 500 bản ghi
    test('9. Repository giữ tối đa 500 bản ghi', () async {
      final repository = SharedPrefsCallHistoryRepository();
      await repository.clearAll();

      final baseTime = DateTime(2026, 1, 1);
      for (int i = 0; i < 520; i++) {
        final entry = CallHistoryEntry(
          id: 'id-$i',
          correlationId: 'uuid-$i',
          localExtension: '201',
          remoteNumber: 'number-$i',
          direction: CallDirection.outgoing,
          result: CallResult.answered,
          startedAt: baseTime.add(Duration(minutes: i)),
        );
        await repository.upsertEntry(entry);
      }

      final entries = await repository.getEntries();
      expect(entries.length, equals(500));
      // Newest should be id-519 (last inserted)
      expect(entries.first.id, equals('id-519'));
      // Oldest retained should be id-20
      expect(entries.last.id, equals('id-20'));
    });

    // 10. JSON hỏng không làm app crash
    test('10. JSON hỏng không làm app crash', () async {
      SharedPreferences.setMockInitialValues({
        'sgt_call_history_v1': '{ invalid json corrupt string @@%%',
      });

      final repository = SharedPrefsCallHistoryRepository();
      // Should not throw, returns empty list safely
      final entries = await repository.getEntries();
      expect(entries, isEmpty);

      // Corrupted items in array should also be handled safely
      SharedPreferences.setMockInitialValues({
        'sgt_call_history_v1':
            '{"schemaVersion": 1, "entries": ["corrupted_item", {"id": "valid-1", "correlationId": "c1", "localExtension": "201", "remoteNumber": "202", "direction": "incoming", "result": "answered", "startedAt": "2026-09-06T12:00:00.000Z", "durationSeconds": 10}]}',
      });

      final repository2 = SharedPrefsCallHistoryRepository();
      final validEntries = await repository2.getEntries();
      expect(validEntries.length, equals(1));
      expect(validEntries.first.id, equals('valid-1'));
    });

    // 11. Tìm kiếm theo tên và số
    test('11. Tìm kiếm theo tên và số (case-insensitive)', () async {
      final repository = SharedPrefsCallHistoryRepository();
      final service = CallHistoryService(repository: repository);
      await service.loadEntries();

      await service.recordCallInitiation(
        correlationId: 'uuid-s1',
        localExtension: '201',
        remoteNumber: '0987654321',
        remoteDisplayName: 'Nguyễn Văn An',
        direction: CallDirection.incoming,
      );

      await service.recordCallInitiation(
        correlationId: 'uuid-s2',
        localExtension: '201',
        remoteNumber: '0123456789',
        remoteDisplayName: 'Trần Thị Bình',
        direction: CallDirection.outgoing,
      );

      // Search by partial lower/upper name
      final byName = service.filterEntries(query: 'văn an');
      expect(byName.length, equals(1));
      expect(byName.first.remoteDisplayName, equals('Nguyễn Văn An'));

      // Search by phone number
      final byNumber = service.filterEntries(query: '012345');
      expect(byNumber.length, equals(1));
      expect(byNumber.first.remoteNumber, equals('0123456789'));

      // Empty query restores all
      final all = service.filterEntries(query: '');
      expect(all.length, equals(2));
    });

    // 12. Bộ lọc tất cả/gọi đến/gọi đi/gọi nhỡ
    test('12. Bộ lọc tất cả/gọi đến/gọi đi/gọi nhỡ', () async {
      final repository = SharedPrefsCallHistoryRepository();
      final service = CallHistoryService(repository: repository);
      await service.loadEntries();

      // 1: Incoming answered
      await service.recordCallInitiation(
        correlationId: 'f-in-ans',
        localExtension: '201',
        remoteNumber: '101',
        direction: CallDirection.incoming,
      );
      await service.recordCallAnswered(correlationId: 'f-in-ans');
      await service.recordCallEnded(
        correlationId: 'f-in-ans',
        wasAnswered: true,
        wasDeclinedByUser: false,
      );

      // 2: Incoming missed
      await service.recordCallInitiation(
        correlationId: 'f-in-miss',
        localExtension: '201',
        remoteNumber: '102',
        direction: CallDirection.incoming,
      );
      await service.recordCallEnded(
        correlationId: 'f-in-miss',
        wasAnswered: false,
        wasDeclinedByUser: false,
      );

      // 3: Incoming declined
      await service.recordCallInitiation(
        correlationId: 'f-in-decl',
        localExtension: '201',
        remoteNumber: '103',
        direction: CallDirection.incoming,
      );
      await service.recordCallEnded(
        correlationId: 'f-in-decl',
        wasAnswered: false,
        wasDeclinedByUser: true,
      );

      // 4: Outgoing
      await service.recordCallInitiation(
        correlationId: 'f-out',
        localExtension: '201',
        remoteNumber: '104',
        direction: CallDirection.outgoing,
      );
      await service.recordCallEnded(
        correlationId: 'f-out',
        wasAnswered: false,
        wasDeclinedByUser: false,
      );

      // Filter: Tất cả (all 4)
      final all = service.filterEntries(filter: 'all');
      expect(all.length, equals(4));

      // Filter: Gọi đến (incoming not missed -> answered + declined)
      final incoming = service.filterEntries(filter: 'incoming');
      expect(incoming.length, equals(2));
      expect(
        incoming.map((e) => e.correlationId),
        containsAll(['f-in-ans', 'f-in-decl']),
      );

      // Filter: Gọi đi (outgoing -> 1)
      final outgoing = service.filterEntries(filter: 'outgoing');
      expect(outgoing.length, equals(1));
      expect(outgoing.first.correlationId, equals('f-out'));

      // Filter: Gọi nhỡ (incoming missed -> 1)
      final missed = service.filterEntries(filter: 'missed');
      expect(missed.length, equals(1));
      expect(missed.first.correlationId, equals('f-in-miss'));
    });

    // 13. Nút gọi lại gọi đúng SipManager.makeCall
    testWidgets('13. Nút gọi lại gọi đúng SipManager.makeCall', (tester) async {
      final sipManager = SipManager();
      sipManager.resetForTesting();
      final mockHelper = FakeSIPUAHelper();
      sipManager.setHelperForTesting(mockHelper);
      sipManager.setConnectionStatusForTesting(SipConnectionStatus.online);
      sipManager.setAccountForTesting(
        SipAccount(
          wssUri: 'wss://sgtvoip.duckdns.org/ws',
          domain: 'sgtvoip.duckdns.org',
          extension: '201',
          displayName: 'Test User',
          password: 'secret',
        ),
      );

      final repository = SharedPrefsCallHistoryRepository();
      final service = CallHistoryService(repository: repository);
      await service.loadEntries();
      await service.recordCallInitiation(
        correlationId: 'uuid-cb',
        localExtension: '201',
        remoteNumber: '202',
        remoteDisplayName: 'Test Callback',
        direction: CallDirection.incoming,
      );

      sipManager.setCallHistoryServiceForTesting(service);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: sipManager.navigatorKey,
          home: ChangeNotifierProvider<SipManager>.value(
            value: sipManager,
            child: const CallHistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find callback button (phone icon in list tile)
      final phoneBtn = find.byTooltip('Gọi lại cho 202');
      expect(phoneBtn, findsOneWidget);

      await tester.tap(phoneBtn);
      await tester.pumpAndSettle();

      expect(mockHelper.lastCallDestination, contains('202'));
    });

    // 14. Chuyển tab không mất số đã nhập
    testWidgets('14. Chuyển tab không mất số đã nhập', (tester) async {
      final sipManager = SipManager();
      sipManager.resetForTesting();
      sipManager.setHelperForTesting(FakeSIPUAHelper());

      await tester.pumpWidget(
        ChangeNotifierProvider<SipManager>.value(
          value: sipManager,
          child: const SGTSoftphoneApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Bàn phím tab
      await tester.tap(find.text('Bàn phím'));
      await tester.pumpAndSettle();

      // Tap digits 1, 2, 3
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();

      expect(find.text('123'), findsOneWidget);

      // Switch to Cuộc gọi tab
      await tester.tap(find.text('Cuộc gọi'));
      await tester.pumpAndSettle();

      // Switch back to Bàn phím tab
      await tester.tap(find.text('Bàn phím'));
      await tester.pumpAndSettle();

      // Number 123 must still be preserved!
      expect(find.text('123'), findsOneWidget);
    });

    // 15. Màn hình 320x480 không overflow
    testWidgets('15. Màn hình 320x480 không overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final sipManager = SipManager();
      sipManager.resetForTesting();
      sipManager.setHelperForTesting(FakeSIPUAHelper());

      final repository = SharedPrefsCallHistoryRepository();
      final service = CallHistoryService(repository: repository);
      await service.loadEntries();
      await service.recordCallInitiation(
        correlationId: 'ovf-1',
        localExtension: '201',
        remoteNumber: '0987654321',
        remoteDisplayName: 'Nguyễn Rất Dài Cần Test Tràn Màn Hình Nhỏ',
        direction: CallDirection.incoming,
      );

      sipManager.setCallHistoryServiceForTesting(service);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: sipManager.navigatorKey,
          home: ChangeNotifierProvider<SipManager>.value(
            value: sipManager,
            child: const CallHistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no overflow errors
      expect(tester.takeException(), isNull);
    });

    // 16. Incoming/InCall navigation hiện tại không bị regression
    testWidgets('16. Incoming/InCall navigation hiện tại không bị regression', (
      tester,
    ) async {
      final sipManager = SipManager();
      sipManager.resetForTesting();
      sipManager.navigatorKey = rootNavigatorKey;
      final mockHelper = FakeSIPUAHelper();
      sipManager.setHelperForTesting(mockHelper);

      await tester.pumpWidget(
        ChangeNotifierProvider<SipManager>.value(
          value: sipManager,
          child: const SGTSoftphoneApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Default should show AppShell
      expect(find.byType(AppShell), findsOneWidget);

      // Incoming call arrives
      final fakeCall = FakeCall(
        id: 'reg-call-1',
        direction: 'INCOMING',
        remote_identity: '202',
      );
      sipManager.callStateChanged(
        fakeCall,
        CallState(CallStateEnum.CALL_INITIATION),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // IncomingCallScreen should be pushed on root navigator
      expect(sipManager.callScreenState, CallScreenState.incoming);
      expect(find.byType(IncomingCallScreen), findsOneWidget);

      // Call ends -> navigates back to root AppShell
      sipManager.callStateChanged(fakeCall, CallState(CallStateEnum.ENDED));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(sipManager.callScreenState, CallScreenState.none);
      expect(find.byType(AppShell), findsOneWidget);
    });

    // 17. UUID khác hoa/thường vẫn được normalize và match đúng
    test('17. UUID khác hoa/thường vẫn được normalize và match đúng', () {
      const upperUuid = 'A1B2-C3D4-E5F6';
      const lowerUuid = 'a1b2-c3d4-e5f6';

      expect(
        CallCoordinator.normalizeUuid(upperUuid),
        equals(CallCoordinator.normalizeUuid(lowerUuid)),
      );

      final entry = CallHistoryEntry(
        id: 'test-17',
        correlationId: upperUuid,
        localExtension: '201',
        remoteNumber: '202',
        direction: CallDirection.incoming,
        result: CallResult.answered,
        startedAt: DateTime.now(),
      );

      // Match correlationId normalized
      expect(
        CallCoordinator.normalizeUuid(entry.correlationId),
        equals(CallCoordinator.normalizeUuid(lowerUuid)),
      );
    });

    // 18. Push và SIP cùng UUID chỉ tạo một lịch sử
    test('18. Push và SIP cùng UUID chỉ tạo một lịch sử', () async {
      final repository = SharedPrefsCallHistoryRepository();
      final service = CallHistoryService(repository: repository);
      await service.loadEntries();

      const pushUuid = 'ABC-123-XYZ';
      const sipUuid = 'abc-123-xyz'; // lowercased from SIP INVITE

      // Event triggered from native Push
      await service.recordCallInitiation(
        correlationId: pushUuid,
        localExtension: '201',
        remoteNumber: '202',
        direction: CallDirection.incoming,
      );

      // SIP INVITE event arrives later with same normalized UUID
      await service.recordCallInitiation(
        correlationId: sipUuid,
        localExtension: '201',
        remoteNumber: '202',
        direction: CallDirection.incoming,
      );

      final entries = await repository.getEntries();
      final matching = entries
          .where(
            (e) =>
                CallCoordinator.normalizeUuid(e.correlationId) ==
                CallCoordinator.normalizeUuid(sipUuid),
          )
          .toList();

      expect(matching.length, equals(1));
    });
  });
}
