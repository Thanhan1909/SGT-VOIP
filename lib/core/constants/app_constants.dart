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
  static const String defaultTurnUsername = String.fromEnvironment(
    'SGT_TURN_USERNAME',
  );
  static const String defaultTurnPassword = '';
  // Set to 1000ms (down from 8000ms) to dramatically reduce call initiation latency
  static const int defaultIceGatheringTimeoutMs = 1000;
  static const int legacyIceGatheringTimeoutMs = 8000;

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

  // Semantic Theme Colors - Warm Light Palette (WCAG AA Compliant)
  static const Color backgroundLight = Color(0xFFF4E4D3); // Nền be ấm
  static const Color surfaceLight = Color(0xFFFFF9F2); // Card / Khung nền phụ
  static const Color cardLight = Color(0xFFFFFFFF); // Khung viền trắng
  static const Color textPrimary = Color(0xFF2D221C); // Chữ chính
  static const Color textSecondary = Color(0xFF74675D); // Chữ phụ
  static const Color textMuted = Color(0xFF8C7D73); // Chữ gợi ý / mờ
  static const Color borderLight = Color(0xFFE5D5C5); // Viền nhẹ
  static const Color dividerLight = Color(0xFFEFE2D4); // Kẻ ngang

  // Semantic Action Colors
  static const Color accentGreen = Color(0xFF21A366); // Nút gọi / Trả lời
  static const Color accentRed = Color(0xFFE5484D); // Nút gác máy / Từ chối
  static const Color accentAmber = Color(
    0xFFC05621,
  ); // Trạng thái chờ / Cảnh báo
  static const Color accentBlue = Color(0xFF2563EB); // Chuyển máy / Điểm nhấn

  // Backward compatibility aliases
  static const Color primaryDark = backgroundLight;
  static const Color surfaceDark = surfaceLight;
  static const Color cardDark = surfaceLight;
}
