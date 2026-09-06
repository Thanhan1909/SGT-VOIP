import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/secure_storage_service.dart';

class SipAccount {
  final String wssUri;
  final String domain;
  final String extension;
  final String password;
  final String displayName;
  final String stunUri;
  final String turnUri;
  final String turnUsername;
  final String turnPassword;
  final int iceGatheringTimeoutMs;
  final bool forceRelayOnly;
  final bool diagnosticLogging;

  SipAccount({
    required this.wssUri,
    required this.domain,
    required this.extension,
    required this.password,
    required this.displayName,
    this.stunUri = AppConstants.defaultStunUri,
    this.turnUri = AppConstants.defaultTurnUri,
    this.turnUsername = AppConstants.defaultTurnUsername,
    this.turnPassword = AppConstants.defaultTurnPassword,
    this.iceGatheringTimeoutMs = AppConstants.defaultIceGatheringTimeoutMs,
    this.forceRelayOnly = false,
    this.diagnosticLogging = false,
  });

  factory SipAccount.defaultAccount() {
    return SipAccount(
      wssUri: AppConstants.defaultWssUri,
      domain: AppConstants.defaultDomain,
      extension: AppConstants.defaultExtension,
      password: AppConstants.defaultPassword,
      displayName: AppConstants.defaultDisplayName,
      stunUri: AppConstants.defaultStunUri,
      turnUri: AppConstants.defaultTurnUri,
      turnUsername: AppConstants.defaultTurnUsername,
      turnPassword: AppConstants.defaultTurnPassword,
      iceGatheringTimeoutMs: AppConstants.defaultIceGatheringTimeoutMs,
      forceRelayOnly: false,
      diagnosticLogging: false,
    );
  }

  static Future<SipAccount> loadFromPrefs() async {
    // 1. Tự động chuyển đổi dữ liệu mật khẩu cũ nếu còn lưu trong SharedPreferences
    await SecureStorageService.migrateFromSharedPreferences();

    final prefs = await SharedPreferences.getInstance();
    final savedStun = prefs.getString(AppConstants.keyStunUri);
    final savedTurn = prefs.getString(AppConstants.keyTurnUri);
    final savedTurnUser = prefs.getString(AppConstants.keyTurnUsername);

    // 2. Đọc mật khẩu an toàn từ Keystore / Keychain
    final securePassword = await SecureStorageService.getSipPassword() ?? '';
    final secureTurnPass = await SecureStorageService.getTurnPassword() ?? '';

    return SipAccount(
      wssUri:
          prefs.getString(AppConstants.keyWssUri) ?? AppConstants.defaultWssUri,
      domain:
          prefs.getString(AppConstants.keyDomain) ?? AppConstants.defaultDomain,
      extension: prefs.getString(AppConstants.keyExtension) ??
          AppConstants.defaultExtension,
      password: securePassword,
      displayName: prefs.getString(AppConstants.keyDisplayName) ??
          AppConstants.defaultDisplayName,
      stunUri: (savedStun != null && savedStun.isNotEmpty)
          ? savedStun
          : AppConstants.defaultStunUri,
      turnUri: (savedTurn != null && savedTurn.isNotEmpty)
          ? savedTurn
          : AppConstants.defaultTurnUri,
      turnUsername: (savedTurnUser != null && savedTurnUser.isNotEmpty)
          ? savedTurnUser
          : AppConstants.defaultTurnUsername,
      turnPassword: secureTurnPass,
      iceGatheringTimeoutMs:
          prefs.getInt(AppConstants.keyIceGatheringTimeoutMs) ??
              AppConstants.defaultIceGatheringTimeoutMs,
      forceRelayOnly: prefs.getBool(AppConstants.keyForceRelayOnly) ?? false,
      diagnosticLogging:
          prefs.getBool(AppConstants.keyDiagnosticLogging) ?? false,
    );
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyWssUri, wssUri);
    await prefs.setString(AppConstants.keyDomain, domain);
    await prefs.setString(AppConstants.keyExtension, extension);
    await prefs.setString(AppConstants.keyDisplayName, displayName);
    await prefs.setString(AppConstants.keyStunUri, stunUri);
    await prefs.setString(AppConstants.keyTurnUri, turnUri);
    await prefs.setString(AppConstants.keyTurnUsername, turnUsername);
    await prefs.setInt(
        AppConstants.keyIceGatheringTimeoutMs, iceGatheringTimeoutMs);
    await prefs.setBool(AppConstants.keyForceRelayOnly, forceRelayOnly);
    await prefs.setBool(AppConstants.keyDiagnosticLogging, diagnosticLogging);

    // Lưu mật khẩu an toàn vào Keystore/Keychain, KHÔNG ghi vào SharedPreferences
    await SecureStorageService.setSipPassword(password);
    await SecureStorageService.setTurnPassword(turnPassword);
    if (await SecureStorageService.getSipPassword() != password ||
        await SecureStorageService.getTurnPassword() != turnPassword) {
      throw StateError('Không thể xác minh credential trong secure storage');
    }
    await prefs.remove(AppConstants.keyPassword);
    await prefs.remove(AppConstants.keyTurnPassword);
  }

  SipAccount copyWith({
    String? wssUri,
    String? domain,
    String? extension,
    String? password,
    String? displayName,
    String? stunUri,
    String? turnUri,
    String? turnUsername,
    String? turnPassword,
    int? iceGatheringTimeoutMs,
    bool? forceRelayOnly,
    bool? diagnosticLogging,
  }) {
    return SipAccount(
      wssUri: wssUri ?? this.wssUri,
      domain: domain ?? this.domain,
      extension: extension ?? this.extension,
      password: password ?? this.password,
      displayName: displayName ?? this.displayName,
      stunUri: stunUri ?? this.stunUri,
      turnUri: turnUri ?? this.turnUri,
      turnUsername: turnUsername ?? this.turnUsername,
      turnPassword: turnPassword ?? this.turnPassword,
      iceGatheringTimeoutMs:
          iceGatheringTimeoutMs ?? this.iceGatheringTimeoutMs,
      forceRelayOnly: forceRelayOnly ?? this.forceRelayOnly,
      diagnosticLogging: diagnosticLogging ?? this.diagnosticLogging,
    );
  }
}
