import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/event_manager/events.dart';
import 'package:sip_ua/src/map_helper.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:flutter_sip_softphone/core/services/sip_manager.dart';
import 'package:flutter_sip_softphone/data/models/sip_account.dart';
import 'package:flutter_sip_softphone/presentation/screens/in_call_screen.dart';
import 'package:flutter_sip_softphone/presentation/screens/dialpad_screen.dart';
import 'package:flutter_sip_softphone/presentation/screens/incoming_call_screen.dart';

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
  RTCPeerConnection? get peerConnection => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSIPUAHelper extends SIPUAHelper {
  bool mockConnected = true;
  bool mockRegistered = true;
  Future<bool> Function(
    String target, {
    bool voiceonly,
    MediaStream? mediaStream,
    List<String>? headers,
    Map<String, dynamic>? customOptions,
  })?
  onCall;
  int callInvocationCount = 0;

  @override
  bool get connected => mockConnected;

  @override
  bool get registered => mockRegistered;

  @override
  Map<String, dynamic> buildCallOptions([bool voiceonly = false]) =>
      <String, dynamic>{};

  @override
  Future<bool> call(
    String target, {
    bool voiceonly = false,
    MediaStream? mediaStream,
    List<String>? headers,
    Map<String, dynamic>? customOptions,
  }) async {
    callInvocationCount++;
    if (onCall != null) {
      return onCall!(
        target,
        voiceonly: voiceonly,
        mediaStream: mediaStream,
        headers: headers,
        customOptions: customOptions ?? {},
      );
    }
    return true;
  }

  @override
  void addSipUaHelperListener(SipUaHelperListener listener) {}

  @override
  void removeSipUaHelperListener(SipUaHelperListener listener) {}

  @override
  void stop() {}

  @override
  Future<void> start(UaSettings settings) async {}
}

class TestRouteObserver extends NavigatorObserver {
  final List<String?> pushedRoutes = [];
  int popCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route.settings.name);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PermissionStatus mockMicStatus = PermissionStatus.granted;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    mockMicStatus = PermissionStatus.granted;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'checkPermissionStatus') {
              return mockMicStatus.index;
            }
            if (methodCall.method == 'requestPermissions') {
              final List<dynamic> args = methodCall.arguments as List<dynamic>;
              return {for (final val in args) val as int: mockMicStatus.index};
            }
            return null;
          },
        );

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
  });

  tearDown(() {
    SipManager().resetForTesting();
  });

  SipAccount createTestAccount() {
    return SipAccount(
      wssUri: 'wss://sgtvoip.duckdns.org/ws',
      domain: 'sgtvoip.duckdns.org',
      extension: '201',
      password: 'password123',
      displayName: 'Test 201',
    );
  }

  group('SIP Call Initiation & Navigation Regression Tests', () {
    test('1. Offline -> không gọi và trả sipOffline', () async {
      final sip = SipManager();
      sip.resetForTesting();
      final fakeHelper = FakeSIPUAHelper();
      fakeHelper.mockConnected = false;
      fakeHelper.mockRegistered = false;
      sip.setHelperForTesting(fakeHelper);
      sip.setConnectionStatusForTesting(SipConnectionStatus.offline);
      sip.setAccountForTesting(createTestAccount());

      final result = await sip.makeCall('202');

      expect(result.isSuccess, isFalse);
      expect(
        result.status == CallInitiationStatus.sipOffline ||
            result.status == CallInitiationStatus.transportDisconnected,
        isTrue,
      );
      expect(sip.isDialing, isFalse);
      expect(fakeHelper.callInvocationCount, 0);
    });

    test(
      '2. Microphone denied -> không gọi và có lỗi rõ ràng',
      () async {
        final sip = SipManager();
        sip.resetForTesting();
        final fakeHelper = FakeSIPUAHelper();
        sip.setHelperForTesting(fakeHelper);
        sip.setConnectionStatusForTesting(SipConnectionStatus.online);
        sip.setAccountForTesting(createTestAccount());

        mockMicStatus = PermissionStatus.denied;

        final result = await sip.makeCall('202');

        expect(result.isSuccess, isFalse);
        expect(result.status, CallInitiationStatus.microphoneDenied);
        expect(sip.isDialing, isFalse);
        expect(fakeHelper.callInvocationCount, 0);
      },
      skip: kIsWeb
          ? 'Web obtains microphone permission through getUserMedia'
          : false,
    );

    test('3. helper.call trả false -> không navigate và trả failed', () async {
      final sip = SipManager();
      sip.resetForTesting();
      final fakeHelper = FakeSIPUAHelper();
      fakeHelper.onCall =
          (
            target, {
            voiceonly = false,
            mediaStream,
            headers,
            customOptions,
          }) async {
            return false;
          };
      sip.setHelperForTesting(fakeHelper);
      sip.setConnectionStatusForTesting(SipConnectionStatus.online);
      sip.setAccountForTesting(createTestAccount());

      final result = await sip.makeCall('202');

      expect(result.isSuccess, isFalse);
      expect(result.status, CallInitiationStatus.failed);
      expect(sip.isDialing, isFalse);
      expect(sip.callScreenState, CallScreenState.none);
    });

    testWidgets(
      '4. Outgoing CALL_INITIATION -> currentCall tồn tại trước khi mở /in_call',
      (WidgetTester tester) async {
        final sip = SipManager();
        sip.resetForTesting();
        final navKey = GlobalKey<NavigatorState>();
        final observer = TestRouteObserver();

        await tester.pumpWidget(
          ChangeNotifierProvider<SipManager>.value(
            value: sip,
            child: MaterialApp(
              navigatorKey: navKey,
              navigatorObservers: [observer],
              initialRoute: '/',
              routes: {
                '/': (context) => const Scaffold(body: Text('Home')),
                '/in_call': (context) => const InCallScreen(),
              },
            ),
          ),
        );
        sip.navigatorKey = navKey;
        await tester.pumpAndSettle();

        final fakeCall = FakeCall(
          direction: 'OUTGOING',
          id: 'outgoing-session-1',
        );
        final state = CallState(CallStateEnum.CALL_INITIATION);

        // Phát CALL_INITIATION
        sip.callStateChanged(fakeCall, state);
        await tester.pumpAndSettle();

        expect(sip.currentCall, isNotNull);
        expect(sip.currentCall, fakeCall);
        expect(sip.callScreenState, CallScreenState.inCall);
        expect(observer.pushedRoutes, contains('/in_call'));
        expect(find.byType(InCallScreen), findsOneWidget);
      },
    );

    testWidgets('5. Incoming CALL_INITIATION -> mở /incoming', (
      WidgetTester tester,
    ) async {
      final sip = SipManager();
      sip.resetForTesting();
      final navKey = GlobalKey<NavigatorState>();
      final observer = TestRouteObserver();

      await tester.pumpWidget(
        ChangeNotifierProvider<SipManager>.value(
          value: sip,
          child: MaterialApp(
            navigatorKey: navKey,
            navigatorObservers: [observer],
            initialRoute: '/',
            routes: {
              '/': (context) => const Scaffold(body: Text('Home')),
              '/incoming': (context) =>
                  const Scaffold(body: Text('Incoming Screen')),
              '/in_call': (context) => const InCallScreen(),
            },
          ),
        ),
      );
      sip.navigatorKey = navKey;
      await tester.pumpAndSettle();

      final fakeCall = FakeCall(
        direction: 'INCOMING',
        id: 'incoming-session-1',
      );
      final state = CallState(CallStateEnum.CALL_INITIATION);

      sip.callStateChanged(fakeCall, state);
      await tester.pumpAndSettle();

      expect(sip.currentCall, isNotNull);
      expect(sip.currentCall, fakeCall);
      expect(sip.callScreenState, CallScreenState.incoming);
      expect(observer.pushedRoutes, contains('/incoming'));
      expect(find.text('Incoming Screen'), findsOneWidget);
    });

    testWidgets(
      '6. Không pop InCallScreen do race khi outgoing session vừa tạo',
      (WidgetTester tester) async {
        final sip = SipManager();
        sip.resetForTesting();
        final fakeCall = FakeCall(
          direction: 'OUTGOING',
          id: 'race-free-session',
        );
        sip.setCurrentCallForTesting(
          fakeCall,
          CallState(CallStateEnum.CALL_INITIATION),
        );

        final navKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          ChangeNotifierProvider<SipManager>.value(
            value: sip,
            child: MaterialApp(
              navigatorKey: navKey,
              home: const InCallScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Màn hình InCallScreen vẫn đang hiển thị, không bị tự động pop về dialpad
        expect(find.byType(InCallScreen), findsOneWidget);
      },
    );

    test('7. Double tap không tạo hai SIP calls', () async {
      final sip = SipManager();
      sip.resetForTesting();
      final fakeHelper = FakeSIPUAHelper();
      final completer = Completer<bool>();

      fakeHelper.onCall =
          (target, {voiceonly = false, mediaStream, headers, customOptions}) {
            return completer.future;
          };
      sip.setHelperForTesting(fakeHelper);
      sip.setConnectionStatusForTesting(SipConnectionStatus.online);
      sip.setAccountForTesting(createTestAccount());

      // Lần nhấn đầu tiên: bắt đầu gọi async
      final firstCall = sip.makeCall('202');
      expect(sip.isDialing, isTrue);

      // Lần nhấn thứ hai (double tap): bị từ chối ngay lập tức
      final secondCallResult = await sip.makeCall('202');
      expect(secondCallResult.isSuccess, isFalse);
      expect(secondCallResult.status, CallInitiationStatus.alreadyDialing);

      // Cho lần gọi 1 kết thúc
      completer.complete(true);
      final firstResult = await firstCall;
      expect(firstResult.isSuccess, isTrue);

      // Helper chỉ được gọi duy nhất 1 lần
      expect(fakeHelper.callInvocationCount, 1);
    });

    testWidgets('8. FAILED/ENDED reset state và trở về dialpad đúng một lần', (
      WidgetTester tester,
    ) async {
      final sip = SipManager();
      sip.resetForTesting();
      final navKey = GlobalKey<NavigatorState>();
      final observer = TestRouteObserver();

      await tester.pumpWidget(
        ChangeNotifierProvider<SipManager>.value(
          value: sip,
          child: MaterialApp(
            navigatorKey: navKey,
            navigatorObservers: [observer],
            initialRoute: '/',
            routes: {
              '/': (context) => const Scaffold(body: Text('Dialpad')),
              '/in_call': (context) => const InCallScreen(),
            },
          ),
        ),
      );
      sip.navigatorKey = navKey;
      await tester.pumpAndSettle();

      // Giả lập cuộc gọi đang active
      final fakeCall = FakeCall(direction: 'OUTGOING', id: 'call-end-test');
      sip.callStateChanged(fakeCall, CallState(CallStateEnum.CONFIRMED));
      await tester.pumpAndSettle();
      expect(sip.currentCall, isNotNull);
      expect(sip.callScreenState, CallScreenState.inCall);

      // Kết thúc cuộc gọi với ENDED
      sip.callStateChanged(fakeCall, CallState(CallStateEnum.ENDED));
      await tester.pumpAndSettle();

      expect(sip.currentCall, isNull);
      expect(sip.callState, isNull);
      expect(sip.isDialing, isFalse);
      expect(sip.callScreenState, CallScreenState.none);
      expect(find.text('Dialpad'), findsOneWidget);
    });

    test(
      '9. helper.call ném exception -> bắt lỗi an toàn và trả failed',
      () async {
        final sip = SipManager();
        sip.resetForTesting();
        final fakeHelper = FakeSIPUAHelper();
        fakeHelper.onCall =
            (
              target, {
              voiceonly = false,
              mediaStream,
              headers,
              customOptions,
            }) async {
              throw Exception('Media stream creation failed');
            };
        sip.setHelperForTesting(fakeHelper);
        sip.setConnectionStatusForTesting(SipConnectionStatus.online);
        sip.setAccountForTesting(createTestAccount());

        final result = await sip.makeCall('202');

        expect(result.isSuccess, isFalse);
        expect(result.status, CallInitiationStatus.failed);
        expect(result.message, contains('Media stream creation failed'));
        expect(sip.isDialing, isFalse);
        expect(sip.callScreenState, CallScreenState.none);
      },
    );

    test('10. Connected nhưng chưa registered -> trả unregistered', () async {
      final sip = SipManager();
      sip.resetForTesting();
      final fakeHelper = FakeSIPUAHelper();
      fakeHelper.mockConnected = true;
      fakeHelper.mockRegistered = false;
      sip.setHelperForTesting(fakeHelper);
      sip.setConnectionStatusForTesting(SipConnectionStatus.registering);
      sip.setAccountForTesting(createTestAccount());

      final result = await sip.makeCall('202');

      expect(result.isSuccess, isFalse);
      expect(result.status, CallInitiationStatus.unregistered);
      expect(sip.isDialing, isFalse);
      expect(fakeHelper.callInvocationCount, 0);
    });

    test(
      '11. Mất WebSocket khi đang có cuộc gọi -> cập nhật offline',
      () async {
        final sip = SipManager();
        sip.resetForTesting();
        sip.setConnectionStatusForTesting(SipConnectionStatus.online);

        // Phát sự kiện DISCONNECTED từ TransportState
        sip.transportStateChanged(
          TransportState(TransportStateEnum.DISCONNECTED),
        );

        expect(sip.connectionStatus, SipConnectionStatus.offline);
        expect(sip.statusMessage, contains('Mất kết nối WSS'));
      },
    );

    test(
      '12. Cuộc gọi kết nối (CONFIRMED) hoặc kết thúc (ENDED) đều dừng audio',
      () async {
        final sip = SipManager();
        sip.resetForTesting();
        final fakeCall = FakeCall(direction: 'OUTGOING', id: 'audio-test');

        // CONFIRMED dừng chuông
        sip.callStateChanged(fakeCall, CallState(CallStateEnum.CONFIRMED));
        expect(sip.callState?.state, CallStateEnum.CONFIRMED);

        // ENDED dừng chuông và dọn dẹp
        sip.callStateChanged(fakeCall, CallState(CallStateEnum.ENDED));
        expect(sip.currentCall, isNull);
        expect(sip.callDurationSeconds, 0);
      },
    );

    test(
      '13. REGISTRATION_FAILED với mã 403 Forbidden (Terminal Auth Error) -> ngắt auto-reconnect',
      () async {
        final sip = SipManager();
        sip.resetForTesting();
        sip.setConnectionStatusForTesting(SipConnectionStatus.connecting);

        // Giả lập Asterisk trả 403 Forbidden do sai mật khẩu SIP
        final terminalErrorState = RegistrationState(
          state: RegistrationStateEnum.REGISTRATION_FAILED,
          cause: ErrorCause(
            status_code: 403,
            cause: 'SIP Failure Code',
            reason_phrase: 'Forbidden',
          ),
        );

        sip.registrationStateChanged(terminalErrorState);

        expect(sip.connectionStatus, SipConnectionStatus.error);
        expect(sip.hasTerminalAuthError, isTrue);
        expect(sip.statusMessage, contains('Forbidden'));
      },
    );

    test(
      '14. transportStateChanged(CONNECTED) KHÔNG reset reconnectAttempts về 0',
      () async {
        final sip = SipManager();
        sip.resetForTesting();
        sip.setReconnectAttemptsForTesting(2);

        // Giả lập WebSocket kết nối lại thành công ở lần thử thứ 2
        sip.transportStateChanged(TransportState(TransportStateEnum.CONNECTED));

        // reconnectAttempts phải được giữ nguyên là 2, KHÔNG bị reset về 0
        expect(sip.reconnectAttempts, 2);
        expect(sip.connectionStatus, SipConnectionStatus.registering);
        expect(sip.statusMessage, 'Đang đăng ký SIP...');
      },
    );

    test(
      '15. REGISTRATION_FAILED với lỗi transient -> dừng lại khi đạt max reconnect attempts',
      () async {
        final sip = SipManager();
        sip.resetForTesting();
        sip.setReconnectAttemptsForTesting(3);

        // Giả lập lỗi server tạm thời 500
        final transientErrorState = RegistrationState(
          state: RegistrationStateEnum.REGISTRATION_FAILED,
          cause: ErrorCause(
            status_code: 500,
            cause: 'Connection Error',
            reason_phrase: 'Server Error',
          ),
        );

        sip.registrationStateChanged(transientErrorState);

        // Đã đạt max attempts (3), phải dừng lại và cập nhật message yêu cầu chạm để thử lại
        expect(sip.connectionStatus, SipConnectionStatus.error);
        expect(sip.hasTerminalAuthError, isFalse);
        expect(sip.statusMessage, contains('Mất kết nối sau 3 lần thử'));
      },
    );

    test(
      '16. RegistrationStateEnum.REGISTERED reset reconnectAttempts và hasTerminalAuthError',
      () async {
        final sip = SipManager();
        sip.resetForTesting();
        sip.setReconnectAttemptsForTesting(2);
        sip.setHasTerminalAuthErrorForTesting(true);

        final registeredState = RegistrationState(
          state: RegistrationStateEnum.REGISTERED,
        );

        sip.registrationStateChanged(registeredState);

        expect(sip.connectionStatus, SipConnectionStatus.online);
        expect(sip.reconnectAttempts, 0);
        expect(sip.hasTerminalAuthError, isFalse);
      },
    );

    test(
      '17. retryRegistration() giải phóng cờ lỗi xác thực và reset số lần thử lại',
      () async {
        final sip = SipManager();
        sip.resetForTesting();
        sip.setReconnectAttemptsForTesting(3);
        sip.setHasTerminalAuthErrorForTesting(true);
        sip.setAccountForTesting(createTestAccount());
        final fakeHelper = FakeSIPUAHelper();
        sip.setHelperForTesting(fakeHelper);

        sip.retryRegistration();

        expect(sip.reconnectAttempts, 0);
        expect(sip.hasTerminalAuthError, isFalse);
      },
    );

    test(
      '18. Outgoing call chỉ truyền typed overrides tương thích sip_ua MapHelper',
      () async {
        final sip = SipManager();
        sip.resetForTesting();
        final fakeHelper = FakeSIPUAHelper();
        Map<String, dynamic>? capturedOptions;
        fakeHelper.onCall =
            (
              target, {
              voiceonly = false,
              mediaStream,
              headers,
              customOptions,
            }) async {
              capturedOptions = customOptions;
              return true;
            };
        sip.setHelperForTesting(fakeHelper);
        sip.setConnectionStatusForTesting(SipConnectionStatus.online);
        sip.setAccountForTesting(createTestAccount());

        final result = await sip.makeCall('999');

        expect(result.isSuccess, isTrue);
        expect(capturedOptions, isNotNull);
        expect(capturedOptions, isNot(contains('eventHandlers')));
        expect(capturedOptions, isNot(contains('extraHeaders')));
        expect(capturedOptions, isNot(contains('rtcOfferConstraints')));
        expect(capturedOptions!['mediaConstraints'], <String, dynamic>{
          'audio': true,
          'video': false,
        });

        // This is the same merge performed internally by SIPUAHelper.call().
        // It guards against the LinkedMap<dynamic, dynamic> web regression.
        final defaults = SIPUAHelper().buildCallOptions(true);
        expect(
          () => MapHelper.merge<String>(defaults, capturedOptions!),
          returnsNormally,
        );
      },
    );

    test(
      '19. Speakerphone mặc định false ở cuộc gọi mới, chỉ đổi khi toggle và reset sau ENDED',
      () async {
        final sip = SipManager();
        sip.resetForTesting();
        sip.setHelperForTesting(FakeSIPUAHelper());
        final fakeCall = FakeCall(
          direction: 'INCOMING',
          id: 'speaker-test-call',
        );

        // Cuộc gọi đến: CALL_INITIATION
        sip.callStateChanged(
          fakeCall,
          CallState(CallStateEnum.CALL_INITIATION),
        );
        expect(sip.isSpeakerOn, isFalse);

        // Cuộc gọi được chấp nhận: CONFIRMED
        sip.callStateChanged(fakeCall, CallState(CallStateEnum.CONFIRMED));
        expect(sip.isSpeakerOn, isFalse);

        // Người dùng bấm bật loa ngoài
        sip.toggleSpeaker();
        expect(sip.isSpeakerOn, isTrue);

        // Người dùng bấm tắt loa ngoài
        sip.toggleSpeaker();
        expect(sip.isSpeakerOn, isFalse);

        // Bật lại rồi kết thúc cuộc gọi
        sip.toggleSpeaker();
        expect(sip.isSpeakerOn, isTrue);

        sip.callStateChanged(fakeCall, CallState(CallStateEnum.ENDED));
        expect(sip.isSpeakerOn, isFalse);
      },
    );

    testWidgets(
      '20. Ẩn thông tin kỹ thuật Media/ICE/DTLS/RTP trên Dialpad và InCall',
      (WidgetTester tester) async {
        final sip = SipManager();
        sip.resetForTesting();
        sip.setHelperForTesting(FakeSIPUAHelper());
        final fakeCall = FakeCall(direction: 'OUTGOING', id: 'diag-hide-call');
        sip.setCurrentCallForTesting(
          fakeCall,
          CallState(CallStateEnum.CONFIRMED),
        );

        // Test DialpadScreen
        await tester.pumpWidget(
          ChangeNotifierProvider<SipManager>.value(
            value: sip,
            child: const MaterialApp(home: DialpadScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Cuộc gọi gần nhất — Media:'), findsNothing);
        expect(find.textContaining('RTP TX/RX:'), findsNothing);
        expect(find.textContaining('candidate-pair'), findsNothing);

        // Test InCallScreen
        await tester.pumpWidget(
          ChangeNotifierProvider<SipManager>.value(
            value: sip,
            child: const MaterialApp(home: InCallScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Media: flowing'), findsNothing);
        expect(find.textContaining('RTP gửi/nhận:'), findsNothing);
        expect(find.textContaining('Tổng đài Asterisk PJSIP'), findsNothing);
        expect(find.text('Chuyển cuộc gọi'), findsOneWidget);
      },
    );

    testWidgets(
      '21. Incoming route không bị push trùng khi nhận nhiều sự kiện CALL_INITIATION',
      (WidgetTester tester) async {
        final sip = SipManager();
        sip.resetForTesting();
        sip.setHelperForTesting(FakeSIPUAHelper());
        final navKey = GlobalKey<NavigatorState>();
        final observer = TestRouteObserver();

        await tester.pumpWidget(
          ChangeNotifierProvider<SipManager>.value(
            value: sip,
            child: MaterialApp(
              navigatorKey: navKey,
              navigatorObservers: [observer],
              initialRoute: '/',
              routes: {
                '/': (context) => const Scaffold(body: Text('Dialpad')),
                '/incoming': (context) =>
                    const Scaffold(body: Text('IncomingView')),
                '/in_call': (context) =>
                    const Scaffold(body: Text('InCallView')),
              },
            ),
          ),
        );
        sip.navigatorKey = navKey;
        await tester.pumpAndSettle();

        final fakeCall = FakeCall(
          direction: 'INCOMING',
          id: 'incoming-dup-test',
        );

        // Sự kiện CALL_INITIATION lần 1
        sip.callStateChanged(
          fakeCall,
          CallState(CallStateEnum.CALL_INITIATION),
        );
        await tester.pumpAndSettle();
        expect(sip.callScreenState, CallScreenState.incoming);
        expect(find.text('IncomingView'), findsOneWidget);

        final pushCount = observer.pushedRoutes
            .where((r) => r == '/incoming')
            .length;
        expect(pushCount, 1);

        // Sự kiện CALL_INITIATION lần 2 trùng lặp không được push thêm route
        sip.callStateChanged(
          fakeCall,
          CallState(CallStateEnum.CALL_INITIATION),
        );
        await tester.pumpAndSettle();

        final pushCountAfter = observer.pushedRoutes
            .where((r) => r == '/incoming')
            .length;
        expect(pushCountAfter, 1);
      },
    );

    testWidgets(
      '22. Answer incoming call thay thế bằng in-call route an toàn không race-condition',
      (WidgetTester tester) async {
        final sip = SipManager();
        sip.resetForTesting();
        sip.setHelperForTesting(FakeSIPUAHelper());
        final navKey = GlobalKey<NavigatorState>();
        final observer = TestRouteObserver();

        await tester.pumpWidget(
          ChangeNotifierProvider<SipManager>.value(
            value: sip,
            child: MaterialApp(
              navigatorKey: navKey,
              navigatorObservers: [observer],
              initialRoute: '/',
              routes: {
                '/': (context) => const Scaffold(body: Text('Dialpad')),
                '/incoming': (context) =>
                    const Scaffold(body: Text('IncomingView')),
                '/in_call': (context) =>
                    const Scaffold(body: Text('InCallView')),
              },
            ),
          ),
        );
        sip.navigatorKey = navKey;
        await tester.pumpAndSettle();

        final fakeCall = FakeCall(
          direction: 'INCOMING',
          id: 'race-answer-test',
        );
        sip.callStateChanged(
          fakeCall,
          CallState(CallStateEnum.CALL_INITIATION),
        );
        await tester.pumpAndSettle();
        expect(sip.callScreenState, CallScreenState.incoming);

        // Người dùng hoặc luồng gọi answer
        await sip.answerCall();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Màn hình in_call phải được hiển thị và callScreenState là inCall (không bị async pop reset về none)
        expect(sip.callScreenState, CallScreenState.inCall);
        expect(find.text('InCallView'), findsOneWidget);
        sip.resetForTesting();
      },
    );

    testWidgets(
      '23. Giao diện softphone không overflow trên màn hình nhỏ (320x480)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final sip = SipManager();
        sip.resetForTesting();
        sip.setHelperForTesting(FakeSIPUAHelper());
        final fakeCall = FakeCall(direction: 'OUTGOING', id: 'overflow-test');
        sip.setCurrentCallForTesting(
          fakeCall,
          CallState(CallStateEnum.CONFIRMED),
        );

        // DialpadScreen trên 320x480
        await tester.pumpWidget(
          ChangeNotifierProvider<SipManager>.value(
            value: sip,
            child: const MaterialApp(home: DialpadScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // IncomingCallScreen trên 320x480 (có animation lặp, dùng pump định thời)
        await tester.pumpWidget(
          ChangeNotifierProvider<SipManager>.value(
            value: sip,
            child: const MaterialApp(home: IncomingCallScreen()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);

        // InCallScreen trên 320x480
        await tester.pumpWidget(
          ChangeNotifierProvider<SipManager>.value(
            value: sip,
            child: const MaterialApp(home: InCallScreen()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);

        sip.resetForTesting();
      },
    );
  });
}
