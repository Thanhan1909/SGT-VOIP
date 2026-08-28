import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';

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
    );
  }

  static Future<SipAccount> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedStun = prefs.getString(AppConstants.keyStunUri);
    final savedTurn = prefs.getString(AppConstants.keyTurnUri);
    final savedTurnUser = prefs.getString(AppConstants.keyTurnUsername);
    final savedTurnPass = prefs.getString(AppConstants.keyTurnPassword);

    return SipAccount(
      wssUri: prefs.getString(AppConstants.keyWssUri) ?? AppConstants.defaultWssUri,
      domain: prefs.getString(AppConstants.keyDomain) ?? AppConstants.defaultDomain,
      extension: prefs.getString(AppConstants.keyExtension) ?? AppConstants.defaultExtension,
      password: prefs.getString(AppConstants.keyPassword) ?? AppConstants.defaultPassword,
      displayName: prefs.getString(AppConstants.keyDisplayName) ?? AppConstants.defaultDisplayName,
      stunUri: (savedStun != null && savedStun.isNotEmpty) ? savedStun : AppConstants.defaultStunUri,
      turnUri: (savedTurn != null && savedTurn.isNotEmpty) ? savedTurn : AppConstants.defaultTurnUri,
      turnUsername: (savedTurnUser != null && savedTurnUser.isNotEmpty) ? savedTurnUser : AppConstants.defaultTurnUsername,
      turnPassword: (savedTurnPass != null && savedTurnPass.isNotEmpty) ? savedTurnPass : AppConstants.defaultTurnPassword,
    );
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyWssUri, wssUri);
    await prefs.setString(AppConstants.keyDomain, domain);
    await prefs.setString(AppConstants.keyExtension, extension);
    await prefs.setString(AppConstants.keyPassword, password);
    await prefs.setString(AppConstants.keyDisplayName, displayName);
    await prefs.setString(AppConstants.keyStunUri, stunUri);
    await prefs.setString(AppConstants.keyTurnUri, turnUri);
    await prefs.setString(AppConstants.keyTurnUsername, turnUsername);
    await prefs.setString(AppConstants.keyTurnPassword, turnPassword);
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
    );
  }
}
