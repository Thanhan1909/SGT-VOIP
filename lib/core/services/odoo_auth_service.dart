import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../data/models/sip_account.dart';
import '../constants/app_constants.dart';
import 'http_client_factory/http_client_factory.dart';

class OdooAuthService with ChangeNotifier {
  static final OdooAuthService instance = OdooAuthService._internal();
  OdooAuthService._internal();
  factory OdooAuthService() => instance;

  final http.Client _client = createHttpClient();
  String _baseUrl = 'https://sgtvoip.duckdns.org';

  bool _isAuthenticated = false;
  Map<String, dynamic>? _userInfo;
  SipAccount? _inMemorySipAccount;
  int _ringTimeoutSeconds = 45;

  bool get isAuthenticated => _isAuthenticated;
  Map<String, dynamic>? get userInfo => _userInfo;
  SipAccount? get inMemorySipAccount => _inMemorySipAccount;
  int get ringTimeoutSeconds => _ringTimeoutSeconds;

  void setBaseUrl(String url) {
    _baseUrl = url.replaceAll(RegExp(r'/+$'), '');
  }

  String get effectiveBaseUrl {
    if (kIsWeb) {
      return ''; // Same-origin relative path on Web
    }
    return _baseUrl;
  }

  Future<Map<String, dynamic>> _callJsonRpc(
    String path,
    Map<String, dynamic> params,
  ) async {
    final url = Uri.parse('$effectiveBaseUrl$path');
    final payload = {
      'jsonrpc': '2.0',
      'method': 'call',
      'params': params,
      'id': DateTime.now().millisecondsSinceEpoch,
    };

    final response = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data.containsKey('error')) {
      final err = data['error'];
      final msg = err is Map
          ? (err['message'] ?? err['data']?['message'] ?? 'JSON-RPC Error')
          : err.toString();
      throw Exception(msg);
    }

    return (data['result'] is Map)
        ? (data['result'] as Map<String, dynamic>)
        : {'result': data['result']};
  }

  /// Check current Odoo user session
  Future<bool> checkSession() async {
    try {
      final res = await _callJsonRpc('/web/session/get_session_info', {});
      if (res['uid'] != null && res['uid'] != false) {
        _isAuthenticated = true;
        _userInfo = res;
        notifyListeners();
        return true;
      }
      _isAuthenticated = false;
      _userInfo = null;
      notifyListeners();
      return false;
    } catch (_) {
      _isAuthenticated = false;
      _userInfo = null;
      notifyListeners();
      return false;
    }
  }

  /// Login with Odoo username and password
  Future<bool> login({
    required String login,
    required String password,
    String db = 'sgt_odoo_01',
  }) async {
    try {
      final res = await _callJsonRpc('/web/session/authenticate', {
        'db': db,
        'login': login,
        'password': password,
      });

      if (res['uid'] != null && res['uid'] != false) {
        _isAuthenticated = true;
        _userInfo = res;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[OdooAuthService] Login failed: $e');
      rethrow;
    }
  }

  /// Fetch authenticated SIP/STUN/TURN configuration and user extension from Odoo
  Future<SipAccount?> fetchSipConfig() async {
    try {
      final res = await _callJsonRpc('/web/sip/config', {});
      if (res['error'] != null) {
        debugPrint(
          '[OdooAuthService] Error fetching SIP config: ${res['message'] ?? res['error']}',
        );
        return null;
      }

      final cfg = res['config'] as Map<String, dynamic>?;
      if (cfg == null) return null;

      final extension = cfg['extension']?.toString() ?? '';
      final password = cfg['password']?.toString() ?? '';
      final displayName =
          cfg['display_name']?.toString() ?? 'Extension $extension';
      final domain =
          cfg['sip_domain']?.toString() ?? AppConstants.defaultDomain;
      final wssUri = cfg['wss_uri']?.toString() ?? AppConstants.defaultWssUri;
      final stunUri =
          cfg['stun_uri']?.toString() ?? AppConstants.defaultStunUri;
      final turnUri =
          cfg['turn_uri']?.toString() ?? AppConstants.defaultTurnUri;
      final turnUsername =
          cfg['turn_username']?.toString() ?? AppConstants.defaultTurnUsername;
      final turnPassword = cfg['turn_password']?.toString() ?? '';

      _ringTimeoutSeconds = (cfg['ring_timeout'] is int)
          ? cfg['ring_timeout'] as int
          : 45;

      // In-memory SIP account: NEVER saved to web local storage
      _inMemorySipAccount = SipAccount(
        wssUri: wssUri,
        domain: domain,
        extension: extension,
        password: password,
        displayName: displayName,
        stunUri: stunUri,
        turnUri: turnUri,
        turnUsername: turnUsername,
        turnPassword: turnPassword,
        forceRelayOnly: cfg['force_relay_only'] == true,
        diagnosticLogging: cfg['diagnostic_logging'] == true,
      );

      notifyListeners();
      return _inMemorySipAccount;
    } catch (e) {
      debugPrint('[OdooAuthService] Failed to load SIP config: $e');
      return null;
    }
  }

  /// Query server-side call state by canonical call UUID
  Future<Map<String, dynamic>?> getCallState(String callUuid) async {
    try {
      final res = await _callJsonRpc('/web/sip/call/state', {
        'call_uuid': callUuid,
      });
      if (res['error'] != null) {
        return {'error': res['error'], 'message': res['message']};
      }
      return res['data'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[OdooAuthService] Error getting call state: $e');
      return null;
    }
  }

  /// Register Web Push subscription with Odoo proxy
  Future<bool> registerWebPushSubscription(
    Map<String, dynamic> subscription,
  ) async {
    try {
      final res = await _callJsonRpc('/web/sip/push/subscribe', {
        'endpoint': subscription['endpoint'],
        'p256dh': subscription['p256dh'],
        'auth': subscription['auth'],
        'device_id': subscription['device_id'] ?? '',
      });
      return res['success'] == true;
    } catch (e) {
      debugPrint('[OdooAuthService] Error registering web push: $e');
      return false;
    }
  }

  /// Unregister Web Push subscription
  Future<bool> unregisterWebPushSubscription(String endpoint) async {
    try {
      final res = await _callJsonRpc('/web/sip/push/unsubscribe', {
        'endpoint': endpoint,
      });
      return res['success'] == true;
    } catch (e) {
      debugPrint('[OdooAuthService] Error unregistering web push: $e');
      return false;
    }
  }

  /// Fetch public VAPID application server key from gateway
  Future<String?> fetchVapidPublicKey() async {
    try {
      final url = Uri.parse(
        '$effectiveBaseUrl/api/v1/webpush/vapid-public-key',
      );
      final resp = await _client.get(url);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return body['data']?['public_key'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('[OdooAuthService] Error fetching VAPID public key: $e');
      return null;
    }
  }
}
