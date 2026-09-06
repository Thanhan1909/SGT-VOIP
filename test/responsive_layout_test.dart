import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sip_ua/sip_ua.dart';

import 'package:flutter_sip_softphone/core/services/sip_manager.dart';
import 'package:flutter_sip_softphone/core/services/call_history_service.dart';
import 'package:flutter_sip_softphone/data/models/call_history_entry.dart';
import 'package:flutter_sip_softphone/data/repositories/call_history_repository.dart';
import 'package:flutter_sip_softphone/presentation/screens/app_shell.dart';
import 'package:flutter_sip_softphone/presentation/screens/call_history_screen.dart';
import 'package:flutter_sip_softphone/presentation/screens/dialpad_screen.dart';
import 'package:flutter_sip_softphone/presentation/screens/incoming_call_screen.dart';
import 'package:flutter_sip_softphone/presentation/screens/in_call_screen.dart';
import 'package:flutter_sip_softphone/presentation/widgets/transfer_dialog.dart';
import 'package:flutter_sip_softphone/presentation/widgets/dtmf_keypad_dialog.dart';

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
    this.id = 'call-responsive-test',
    this.direction = 'INCOMING',
    this.remote_identity =
        '201-very-long-extension-name-for-responsive-testing@domain.com',
    this.state = CallStateEnum.CALL_INITIATION,
  });

  @override
  void hangup([Map<String, dynamic>? options]) {}

  @override
  void answer(Map<String, dynamic> options, {dynamic mediaStream}) {}

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

    sip = SipManager();
    sip.resetForTesting();
    sip.setHelperForTesting(MockHelper());

    final repo = SharedPrefsCallHistoryRepository();
    historyService = CallHistoryService(repository: repo);
    sip.setCallHistoryServiceForTesting(historyService);
  });

  tearDown(() {
    SipManager().resetForTesting();
  });

  Widget createTestContainer({
    required Widget child,
    required Size size,
    double textScale = 1.0,
    double keyboardHeight = 0.0,
  }) {
    return ChangeNotifierProvider<SipManager>.value(
      value: sip,
      child: MaterialApp(
        navigatorKey: sip.navigatorKey,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardHeight),
          ),
          child: child,
        ),
      ),
    );
  }

  group('Responsive Layout & No RenderFlex Overflow Tests', () {
    testWidgets(
      '1. CallHistoryScreen empty state with keyboard on small 320x480 screen has no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          createTestContainer(
            child: const CallHistoryScreen(),
            size: const Size(320, 480),
            keyboardHeight: 280.0,
            textScale: 1.2,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.byType(CallHistoryScreen), findsOneWidget);
      },
    );

    testWidgets(
      '2. CallHistoryScreen with entries and large 2.0x font on 360x640 screen has no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final sipManager = SipManager();
        sipManager.resetForTesting();
        sipManager.setHelperForTesting(MockHelper());

        final repository = SharedPrefsCallHistoryRepository();
        final service = CallHistoryService(repository: repository);
        await service.loadEntries();
        await service.recordCallInitiation(
          correlationId: 'hist-1',
          localExtension: '100',
          remoteNumber: '0987654321',
          remoteDisplayName: 'Nguyễn Văn Rất Dài Và Đầy Đủ Tên Họ',
          direction: CallDirection.incoming,
        );

        sipManager.setCallHistoryServiceForTesting(service);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: sipManager.navigatorKey,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 640),
                textScaler: TextScaler.linear(2.0),
              ),
              child: ChangeNotifierProvider<SipManager>.value(
                value: sipManager,
                child: const CallHistoryScreen(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '3. DialpadScreen on small 320x480 screen with 1.5x font scale has no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          createTestContainer(
            child: const DialpadScreen(),
            size: const Size(320, 480),
            textScale: 1.5,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.byType(DialpadScreen), findsOneWidget);
      },
    );

    testWidgets(
      '4. AppShell navigation with keyboard on 360x640 screen has no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ChangeNotifierProvider<SipManager>.value(
            value: sip,
            child: const MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(360, 640),
                  viewInsets: EdgeInsets.only(bottom: 280),
                  textScaler: TextScaler.linear(1.3),
                ),
                child: AppShell(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.byType(AppShell), findsOneWidget);
      },
    );

    testWidgets(
      '5. IncomingCallScreen on small 320x480 screen with 1.5x font scale has no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final fakeCall = FakeCall(
          id: 'call-resp-incoming',
          remote_identity:
              'Nguyễn Văn Rất Dài - Phòng Kinh Doanh & Dịch Vụ Khách Hàng (202)',
        );
        sip.setCurrentCallForTesting(
          fakeCall,
          CallState(CallStateEnum.CALL_INITIATION),
        );

        await tester.pumpWidget(
          createTestContainer(
            child: const IncomingCallScreen(),
            size: const Size(320, 480),
            textScale: 1.5,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.byType(IncomingCallScreen), findsOneWidget);
      },
    );

    testWidgets(
      '6. InCallScreen on small 320x480 screen with 1.5x font scale has no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final fakeCall = FakeCall(
          id: 'call-resp-incall',
          remote_identity: 'Giám đốc Điều Hành Nguyễn Văn A (0988776655)',
        );
        sip.setCurrentCallForTesting(
          fakeCall,
          CallState(CallStateEnum.CONFIRMED),
        );

        await tester.pumpWidget(
          createTestContainer(
            child: const InCallScreen(),
            size: const Size(320, 480),
            textScale: 1.5,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.byType(InCallScreen), findsOneWidget);
      },
    );

    testWidgets(
      '7. TransferDialog with keyboard on small 320x480 screen has no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          createTestContainer(
            child: Scaffold(
              body: Center(child: TransferDialog(onTransfer: (_) {})),
            ),
            size: const Size(320, 480),
            keyboardHeight: 280.0,
            textScale: 1.3,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.byType(TransferDialog), findsOneWidget);
      },
    );

    testWidgets('8. DtmfKeypadDialog on small 320x480 screen has no overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        createTestContainer(
          child: Scaffold(
            body: Center(child: DtmfKeypadDialog(onTonePressed: (_) {})),
          ),
          size: const Size(320, 480),
          textScale: 1.2,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(find.byType(DtmfKeypadDialog), findsOneWidget);
    });
  });
}
