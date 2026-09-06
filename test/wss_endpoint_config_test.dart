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
      '4. SharedPreferences chứa Quick Tunnel *.trycloudflare.com tự động chuyển sang endpoint mặc định',
      () async {
        SharedPreferences.setMockInitialValues({
          AppConstants.keyWssUri:
              'wss://connector-eve-tobacco-algorithms.trycloudflare.com/ws',
        });
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
  });
}
