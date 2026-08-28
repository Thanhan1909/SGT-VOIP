import 'package:flutter/material.dart';

class AppConstants {
  // Default Asterisk Infrastructure Settings
  // WSS qua Cloudflare Tunnel (cập nhật khi tunnel đổi URL)
  static const String defaultWssUri =
      'wss://discounts-scheduled-martha-resist.trycloudflare.com/ws';
  static const String defaultDomain = 'sgtvoip.duckdns.org';
  static const String defaultExtension = '201';
  static const String defaultPassword = 'Sale201@123';
  static const String defaultDisplayName = 'Nhân viên Sale 201';

  // ICE NAT / STUN / TURN Settings
  static const String defaultStunUri = 'stun:stun.l.google.com:19302';
  static const String defaultTurnUri = 'turn:sgtvoip.duckdns.org:3478';
  static const String defaultTurnUsername = 'webrtc_user';
  static const String defaultTurnPassword = 'webrtc_password123';

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
