import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// Service quản lý lưu trữ an toàn các thông tin bảo mật nhạy cảm (SIP password, TURN credential).
/// Sử dụng Android Keystore trên Android và Keychain trên iOS.
/// Tuyệt đối không in mật khẩu ra console log.
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _keySipPassword = 'secure_sip_password';
  static const String _keyTurnPassword = 'secure_turn_password';

  /// Đọc mật khẩu SIP từ Keystore / Keychain
  static Future<String?> getSipPassword() async {
    try {
      return await _storage.read(key: _keySipPassword);
    } catch (e) {
      debugPrint(
        '[SecureStorageService] Error reading SIP password from secure storage',
      );
      return null;
    }
  }

  /// Lưu mật khẩu SIP vào Keystore / Keychain
  static Future<void> setSipPassword(String password) async {
    try {
      await _storage.write(key: _keySipPassword, value: password);
    } catch (e) {
      debugPrint(
        '[SecureStorageService] Error saving SIP password to secure storage',
      );
      rethrow;
    }
  }

  /// Đọc mật khẩu TURN từ Keystore / Keychain
  static Future<String?> getTurnPassword() async {
    try {
      return await _storage.read(key: _keyTurnPassword);
    } catch (e) {
      debugPrint(
        '[SecureStorageService] Error reading TURN password from secure storage',
      );
      return null;
    }
  }

  /// Lưu mật khẩu TURN vào Keystore / Keychain
  static Future<void> setTurnPassword(String password) async {
    try {
      await _storage.write(key: _keyTurnPassword, value: password);
    } catch (e) {
      debugPrint(
        '[SecureStorageService] Error saving TURN password to secure storage',
      );
      rethrow;
    }
  }

  /// Tự động di chuyển (migration) mật khẩu cũ từ SharedPreferences sang SecureStorage
  /// và xóa sạch bản cũ khỏi SharedPreferences để đảm bảo bảo mật.
  static Future<void> migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Migration SIP password
      if (prefs.containsKey(AppConstants.keyPassword)) {
        final oldSipPass = prefs.getString(AppConstants.keyPassword);
        if (oldSipPass != null && oldSipPass.isNotEmpty) {
          await setSipPassword(oldSipPass);
          final migrated = await getSipPassword();
          if (migrated != oldSipPass) {
            throw StateError('SIP password secure-storage verification failed');
          }
        }
        await prefs.remove(AppConstants.keyPassword);
        debugPrint(
          '[SecureStorageService] Migrated SIP password from SharedPreferences to Keystore/Keychain',
        );
      }

      // Migration TURN password
      if (prefs.containsKey(AppConstants.keyTurnPassword)) {
        final oldTurnPass = prefs.getString(AppConstants.keyTurnPassword);
        if (oldTurnPass != null && oldTurnPass.isNotEmpty) {
          await setTurnPassword(oldTurnPass);
          final migrated = await getTurnPassword();
          if (migrated != oldTurnPass) {
            throw StateError(
              'TURN password secure-storage verification failed',
            );
          }
        }
        await prefs.remove(AppConstants.keyTurnPassword);
        debugPrint(
          '[SecureStorageService] Migrated TURN password from SharedPreferences to Keystore/Keychain',
        );
      }
    } catch (e) {
      // Deliberately retain the legacy value when secure storage is unavailable.
      // Losing a credential is worse than temporarily retaining the old copy.
      debugPrint('[SecureStorageService] Migration postponed: $e');
    }
  }

  /// Xóa toàn bộ secret khi đăng xuất hoặc reset dữ liệu
  static Future<void> clearAllSecrets() async {
    try {
      await _storage.delete(key: _keySipPassword);
      await _storage.delete(key: _keyTurnPassword);
    } catch (e) {
      debugPrint('[SecureStorageService] Error clearing secrets');
    }
  }
}
