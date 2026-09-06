import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter_sip_softphone/core/constants/app_constants.dart';
import 'package:flutter_sip_softphone/data/models/sip_account.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Phase 0: WSS Fixed Endpoint & Configuration Tests', () {
    test(
      '1. Default WSS URI matches production endpoint wss://sgtvoip.duckdns.org/ws or dart-define override',
      () {
        const expectedWss = String.fromEnvironment(
          'SGT_WSS_URI',
          defaultValue: 'wss://sgtvoip.duckdns.org/ws',
        );
        expect(AppConstants.defaultWssUri, expectedWss);
        expect(AppConstants.defaultDomain, 'sgtvoip.duckdns.org');
      },
    );

    test(
      '2. SharedPreferences rỗng tự động gán endpoint mặc định production hoặc override',
      () async {
        SharedPreferences.setMockInitialValues({});
        final account = await SipAccount.loadFromPrefs();
        expect(account.wssUri, AppConstants.defaultWssUri);
      },
    );

    test(
      '3. SharedPreferences chứa chuỗi rỗng tự chuyển sang endpoint mặc định và lưu lại',
      () async {
        SharedPreferences.setMockInitialValues({AppConstants.keyWssUri: ''});
        final account = await SipAccount.loadFromPrefs();
        expect(account.wssUri, AppConstants.defaultWssUri);

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString(AppConstants.keyWssUri),
          AppConstants.defaultWssUri,
        );
      },
    );

    test(
      '4. SharedPreferences giữ nguyên Quick Tunnel *.trycloudflare.com hợp lệ qua cold start',
      () async {
        const quickTunnelWss =
            'wss://connector-eve-tobacco-algorithms.trycloudflare.com/ws';
        SharedPreferences.setMockInitialValues({
          AppConstants.keyWssUri: quickTunnelWss,
        });
        final account = await SipAccount.loadFromPrefs();
        expect(account.wssUri, quickTunnelWss);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(AppConstants.keyWssUri), quickTunnelWss);
      },
    );

    test(
      '5. SharedPreferences chứa WSS tùy chỉnh hợp lệ của người dùng KHÔNG bị ghi đè',
      () async {
        const customWss = 'wss://custom-pbx.corp.vn:8089/ws';
        SharedPreferences.setMockInitialValues({
          AppConstants.keyWssUri: customWss,
        });
        final account = await SipAccount.loadFromPrefs();
        expect(account.wssUri, customWss);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(AppConstants.keyWssUri), customWss);
      },
    );

    test('6. Không hard-code username hoặc SIP password trong defaults', () {
      expect(AppConstants.defaultExtension, isEmpty);
      expect(AppConstants.defaultPassword, isEmpty);
      expect(AppConstants.defaultDisplayName, isEmpty);
    });

    test('7. WSS cũ không hợp lệ được thay bằng endpoint mặc định', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.keyWssUri: 'ws://insecure.example.com/not-ws',
      });

      final account = await SipAccount.loadFromPrefs();
      expect(account.wssUri, AppConstants.defaultWssUri);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(AppConstants.keyWssUri),
        AppConstants.defaultWssUri,
      );
    });

    test('8. Validator chấp nhận DuckDNS, Quick Tunnel và custom port', () {
      expect(SipAccount.isValidWssUri('wss://sgtvoip.duckdns.org/ws'), isTrue);
      expect(
        SipAccount.isValidWssUri('wss://random.trycloudflare.com/ws'),
        isTrue,
      );
      expect(SipAccount.isValidWssUri('wss://pbx.example.com:8089/ws'), isTrue);
      expect(SipAccount.isValidWssUri('ws://pbx.example.com/ws'), isFalse);
      expect(SipAccount.isValidWssUri('wss://pbx.example.com/other'), isFalse);
    });
  });
}
