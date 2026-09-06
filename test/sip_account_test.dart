import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_sip_softphone/core/constants/app_constants.dart';
import 'package:flutter_sip_softphone/data/models/sip_account.dart';
import 'package:flutter_sip_softphone/core/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('SipAccount & SecureStorage Tests', () {
    test('SipAccount default instance does not contain hardcoded secret', () {
      final account = SipAccount.defaultAccount();
      expect(account.password, isEmpty);
      expect(account.turnPassword, isEmpty);
      expect(account.extension, isEmpty);
      expect(account.domain, 'sgtvoip.duckdns.org');
    });

    test(
      'Migration from SharedPreferences to SecureStorage works safely',
      () async {
        // Giả lập dữ liệu cũ từng lưu password trong SharedPreferences
        SharedPreferences.setMockInitialValues({
          AppConstants.keyPassword: 'LegacyPassword123',
          AppConstants.keyTurnPassword: 'LegacyTurnPass123',
          AppConstants.keyExtension: '201',
        });

        // Thực hiện migration
        await SecureStorageService.migrateFromSharedPreferences();

        // Kiểm tra: mật khẩu đã được chuyển vào SecureStorage
        final secureSipPass = await SecureStorageService.getSipPassword();
        final secureTurnPass = await SecureStorageService.getTurnPassword();
        expect(secureSipPass, 'LegacyPassword123');
        expect(secureTurnPass, 'LegacyTurnPass123');

        // Kiểm tra: SharedPreferences đã bị xóa sạch mật khẩu
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey(AppConstants.keyPassword), isFalse);
        expect(prefs.containsKey(AppConstants.keyTurnPassword), isFalse);
        expect(prefs.getString(AppConstants.keyExtension), '201');
      },
    );

    test(
      'SipAccount saveToPrefs and loadFromPrefs roundtrip with SecureStorage',
      () async {
        final account = SipAccount(
          wssUri: 'wss://sgtvoip.duckdns.org/ws',
          domain: 'sgtvoip.duckdns.org',
          extension: '202',
          password: 'SuperSecretPassword@202',
          displayName: 'Leader 202',
          stunUri: 'stun:stun.l.google.com:19302',
          turnUri: 'turn:sgtvoip.duckdns.org:3478',
          turnUsername: 'webrtc_user',
          turnPassword: 'TurnSecretPassword@202',
          iceGatheringTimeoutMs: 12000,
          forceRelayOnly: true,
          diagnosticLogging: true,
        );

        await account.saveToPrefs();

        // Load lại từ Storage
        final loadedAccount = await SipAccount.loadFromPrefs();

        expect(loadedAccount.extension, '202');
        expect(loadedAccount.password, 'SuperSecretPassword@202');
        expect(loadedAccount.turnPassword, 'TurnSecretPassword@202');
        expect(loadedAccount.displayName, 'Leader 202');
        expect(loadedAccount.iceGatheringTimeoutMs, 12000);
        expect(loadedAccount.forceRelayOnly, isTrue);
        expect(loadedAccount.diagnosticLogging, isTrue);

        // Xác minh SharedPreferences không lưu password cleartext
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey(AppConstants.keyPassword), isFalse);
        expect(prefs.containsKey(AppConstants.keyTurnPassword), isFalse);
      },
    );

    test(
      'Migration of legacy 8000ms iceGatheringTimeoutMs to 1000ms',
      () async {
        SharedPreferences.setMockInitialValues({
          AppConstants.keyIceGatheringTimeoutMs: 8000,
          AppConstants.keyExtension: '201',
        });

        final loadedAccount = await SipAccount.loadFromPrefs();
        expect(loadedAccount.iceGatheringTimeoutMs, 1000);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(AppConstants.keyIceGatheringTimeoutMs), 1000);
      },
    );

    test(
      'Custom user iceGatheringTimeoutMs is preserved without migration',
      () async {
        SharedPreferences.setMockInitialValues({
          AppConstants.keyIceGatheringTimeoutMs: 2500,
          AppConstants.keyExtension: '201',
        });

        final loadedAccount = await SipAccount.loadFromPrefs();
        expect(loadedAccount.iceGatheringTimeoutMs, 2500);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(AppConstants.keyIceGatheringTimeoutMs), 2500);
      },
    );
  });
}
