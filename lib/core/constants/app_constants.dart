import 'package:flutter/material.dart';

class AppConstants {
  // Default Asterisk Infrastructure Settings
  // Production endpoints are injected by CI with --dart-define.  Quick Tunnel
  // URLs must never be compiled in because they expire whenever cloudflared
  // restarts.  A blank WSS value makes a bad release fail visibly instead of
  // silently connecting to the router HTTPS interface.
  static const String defaultWssUri = String.fromEnvironment('SGT_WSS_URI');
  // Certificate bypass is never enabled implicitly by a debug build. It must
  // be explicitly opted into for a local-only debug session and is ignored by
  // release/profile builds.
  static const bool allowBadCertificateInDebug = bool.fromEnvironment(
    'SGT_ALLOW_BAD_CERTIFICATE',
    defaultValue: false,
  );
  static const String defaultDomain = String.fromEnvironment(
    'SGT_SIP_DOMAIN',
    defaultValue: 'sgtvoip.duckdns.org',
  );
  // Each device must be assigned explicitly. Shipping a shared extension as a
  // default causes contact replacement and unpredictable incoming calls.
  static const String defaultExtension = '';
  static const String defaultPassword = '';
  static const String defaultDisplayName = '';

  // ICE NAT / STUN / TURN Settings
  static const String defaultStunUri = 'stun:stun.l.google.com:19302';
  static const String defaultTurnUri = String.fromEnvironment('SGT_TURN_URIS');
  static const String defaultTurnUsername =
      String.fromEnvironment('SGT_TURN_USERNAME');
  static const String defaultTurnPassword = '';
  static const int defaultIceGatheringTimeoutMs = 8000;

  // SharedPreferences Keys
  static const String keyWssUri = 'sip_wss_uri';
  static const String keyDomain = 'sip_domain';
  static const String keyExtension = 'sip_extension';
  static const String keyPassword = 'sip_password';
  static const String keyDisplayName = 'sip_display_name';
  static const String keyStunUri = 'sip_stun_uri';
  static const String keyTurnUri = 'sip_turn_uri';
  static const String keyTurnUsername = 'sip_turn_username';
  static const String keyTurnPassword = 'sip_turn_password';
  static const String keyIceGatheringTimeoutMs = 'sip_ice_gathering_timeout_ms';
  static const String keyForceRelayOnly = 'sip_force_relay_only';
  static const String keyDiagnosticLogging = 'sip_diagnostic_logging';

  // Theme Colors
  static const Color primaryDark = Color(0xFF121418);
  static const Color surfaceDark = Color(0xFF1A1E24);
  static const Color cardDark = Color(0xFF242A32);
  static const Color accentGreen = Color(0xFF22C55E);
  static const Color accentRed = Color(0xFFEF4444);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color textMuted = Color(0xFF94A3B8);
}
