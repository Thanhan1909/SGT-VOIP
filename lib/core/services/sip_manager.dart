import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sip_ua/sip_ua.dart';
import '../../data/models/sip_account.dart';
import 'audio_manager.dart';

enum SipConnectionStatus {
  offline,
  connecting,
  registering,
  online,
  error,
}

class SipManager extends ChangeNotifier implements SipUaHelperListener {
  static final SipManager _instance = SipManager._internal();
  factory SipManager() => _instance;
  SipManager._internal();

  final SIPUAHelper _helper = SIPUAHelper();
  final AudioManager _audioManager = AudioManager();

  SipAccount? _account;
  SipConnectionStatus _connectionStatus = SipConnectionStatus.offline;
  String _statusMessage = 'Chưa kết nối';

  Call? _currentCall;
  CallState? _callState;
  bool _isMuted = false;
  bool _isOnHold = false;
  int _callDurationSeconds = 0;
  Timer? _callTimer;

  // Global navigator key for navigating to incoming / in-call screens
  GlobalKey<NavigatorState>? navigatorKey;

  // Getters
  SIPUAHelper get helper => _helper;
  SipAccount? get account => _account;
  SipConnectionStatus get connectionStatus => _connectionStatus;
  String get statusMessage => _statusMessage;
  Call? get currentCall => _currentCall;
  CallState? get callState => _callState;
  bool get isMuted => _isMuted;
  bool get isOnHold => _isOnHold;
  bool get isSpeakerOn => _audioManager.isSpeakerOn;
  int get callDurationSeconds => _callDurationSeconds;

  String get formattedDuration {
    final mins = (_callDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> initialize({GlobalKey<NavigatorState>? navKey}) async {
    navigatorKey = navKey;
    _helper.addSipUaHelperListener(this);
    await _audioManager.init();
    _account = await SipAccount.loadFromPrefs();
    await register();
  }

  Future<void> register({SipAccount? newAccount}) async {
    if (newAccount != null) {
      _account = newAccount;
      await _account!.saveToPrefs();
    }

    _account ??= await SipAccount.loadFromPrefs();

    final acc = _account!;
    _connectionStatus = SipConnectionStatus.connecting;
    _statusMessage = 'Đang kết nối WSS...';
    notifyListeners();

    try {
      final settings = UaSettings();

      // Configure SIP Credentials
      settings.webSocketUrl = acc.wssUri;
      settings.webSocketSettings.allowBadCertificate = true;
      settings.uri = 'sip:${acc.extension}@${acc.domain}';
      settings.authorizationUser = acc.extension;
      settings.password = acc.password;
      settings.displayName = acc.displayName.isNotEmpty ? acc.displayName : acc.extension;
      settings.userAgent = 'Flutter SGT VoIP Softphone / Asterisk 20';
      settings.register = true;
      settings.register_expires = 300;

      // Configure STUN / TURN ICE Servers
      final iceServers = <Map<String, dynamic>>[];
      if (acc.stunUri.isNotEmpty) {
        iceServers.add({'urls': acc.stunUri});
      }
      if (acc.turnUri.isNotEmpty) {
        final turnMap = <String, dynamic>{'urls': acc.turnUri};
        if (acc.turnUsername.isNotEmpty) turnMap['username'] = acc.turnUsername;
        if (acc.turnPassword.isNotEmpty) turnMap['credential'] = acc.turnPassword;
        iceServers.add(turnMap);
      }

      settings.iceServers = iceServers.map((e) => e.map((k, v) => MapEntry(k, v.toString()))).toList();
      settings.dtmfMode = DtmfMode.RFC2833;

      _helper.start(settings);
    } catch (e) {
      debugPrint('[SipManager] Register error: $e');
      _connectionStatus = SipConnectionStatus.error;
      _statusMessage = 'Lỗi kết nối: $e';
      notifyListeners();
    }
  }

  Future<void> unregister() async {
    try {
      _helper.unregister(true);
      _helper.stop();
      _connectionStatus = SipConnectionStatus.offline;
      _statusMessage = 'Đã ngắt kết nối';
      notifyListeners();
    } catch (e) {
      debugPrint('[SipManager] Unregister error: $e');
    }
  }

  // ── Call Actions ──────────────────────────────────────────────────────────

  Future<void> makeCall(String targetNumber) async {
    final cleanNumber = targetNumber.trim();
    if (cleanNumber.isEmpty) return;

    if (_connectionStatus != SipConnectionStatus.online) {
      debugPrint('[SipManager] Cannot call: SIP is not online');
      return;
    }

    final targetUri = 'sip:$cleanNumber@${_account!.domain}';
    debugPrint('[SipManager] Calling target: $targetUri');

    _isMuted = false;
    _isOnHold = false;
    _audioManager.setSpeakerphone(false);

    try {
      _helper.call(
        targetUri,
        voiceOnly: true,
      );

      _audioManager.playRingback();
    } catch (e) {
      debugPrint('[SipManager] Make call error: $e');
    }
  }

  void answerCall() {
    if (_currentCall != null) {
      _audioManager.stopAll();
      _currentCall!.answer(_helper.buildCallOptions(true));
      _startCallTimer();
      notifyListeners();
    }
  }

  void hangupCall() {
    _audioManager.stopAll();
    _stopCallTimer();
    if (_currentCall != null) {
      try {
        _currentCall!.hangup();
      } catch (e) {
        debugPrint('[SipManager] Hangup error: $e');
      }
    }
    _currentCall = null;
    _callState = null;
    notifyListeners();
  }

  void toggleMute() {
    if (_currentCall == null) return;
    _isMuted = !_isMuted;
    _currentCall!.mute(true, false); // mute audio
    notifyListeners();
  }

  void toggleHold() {
    if (_currentCall == null) return;
    _isOnHold = !_isOnHold;
    if (_isOnHold) {
      _currentCall!.hold();
    } else {
      _currentCall!.unhold();
    }
    notifyListeners();
  }

  void toggleSpeaker() {
    _audioManager.toggleSpeakerphone();
    notifyListeners();
  }

  void sendDTMF(String tone) {
    if (_currentCall != null && _currentCall!.state == CallStateEnum.CONFIRMED) {
      try {
        _currentCall!.sendDTMF(tone);
      } catch (e) {
        debugPrint('[SipManager] sendDTMF error: $e');
      }
    }
  }

  /// Đá luồng / Chuyển cuộc gọi (Call Transfer via SIP REFER)
  Future<bool> transferCall(String targetExtension) async {
    if (_currentCall == null || targetExtension.trim().isEmpty) return false;
    final target = targetExtension.trim();
    final targetUri = target.contains('@') ? target : '$target@${_account!.domain}';

    debugPrint('[SipManager] Transferring call to: $targetUri');
    try {
      _currentCall!.refer(targetUri);
      return true;
    } catch (e) {
      debugPrint('[SipManager] Transfer call error: $e');
      return false;
    }
  }

  // ── Call Timer Helpers ───────────────────────────────────────────────────

  void _startCallTimer() {
    _stopCallTimer();
    _callDurationSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _callDurationSeconds++;
      notifyListeners();
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }

  // ── SipUaHelperListener Callbacks ────────────────────────────────────────

  @override
  void registrationStateChanged(RegistrationState state) {
    debugPrint('[SipManager] Registration state: ${state.state}');
    switch (state.state) {
      case RegistrationStateEnum.REGISTERED:
        _connectionStatus = SipConnectionStatus.online;
        _statusMessage = 'Đã đăng ký (${_account?.extension})';
        break;
      case RegistrationStateEnum.UNREGISTERED:
        _connectionStatus = SipConnectionStatus.offline;
        _statusMessage = 'Chưa đăng ký';
        break;
      case RegistrationStateEnum.REGISTRATION_FAILED:
        _connectionStatus = SipConnectionStatus.error;
        _statusMessage = 'Đăng ký thất bại (${state.cause?.toString() ?? 'Lỗi'})';
        break;
      case RegistrationStateEnum.NONE:
      default:
        _connectionStatus = SipConnectionStatus.offline;
        _statusMessage = 'Ngoại tuyến';
        break;
    }
    notifyListeners();
  }

  @override
  void callStateChanged(Call call, CallState state) {
    debugPrint('[SipManager] Call state: ${state.state}, origin: ${call.direction}');
    _currentCall = call;
    _callState = state;

    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
        if (call.direction == Direction.incoming) {
          _audioManager.playRingtone();
          _navigateToIncomingCall();
        }
        break;

      case CallStateEnum.PROGRESS:
        if (call.direction == Direction.outgoing) {
          _audioManager.playRingback();
          _navigateToInCall();
        }
        break;

      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        _audioManager.stopAll();
        _startCallTimer();
        _navigateToInCall();
        break;

      case CallStateEnum.HOLD:
        _isOnHold = true;
        break;

      case CallStateEnum.UNHOLD:
        _isOnHold = false;
        break;

      case CallStateEnum.MUTED:
        _isMuted = true;
        break;

      case CallStateEnum.UNMUTED:
        _isMuted = false;
        break;

      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
        _audioManager.stopAll();
        _stopCallTimer();
        _currentCall = null;
        _callState = null;
        _navigateBackToDialpad();
        break;

      default:
        break;
    }
    notifyListeners();
  }

  @override
  void transportStateChanged(TransportState state) {
    debugPrint('[SipManager] Transport state: ${state.state}');
    if (state.state == TransportStateEnum.CONNECTED) {
      _connectionStatus = SipConnectionStatus.registering;
      _statusMessage = 'Đang đăng ký SIP...';
    } else if (state.state == TransportStateEnum.DISCONNECTED) {
      _connectionStatus = SipConnectionStatus.offline;
      _statusMessage = 'Mất kết nối WSS';
    }
    notifyListeners();
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    debugPrint('[SipManager] New SIP message received: ${msg.request.body}');
  }

  @override
  void onNewNotify(Notify ntf) {
    debugPrint('[SipManager] New SIP notify received: ${ntf.request?.body}');
  }

  @override
  void onNewReinvite(ReInvite event) {
    debugPrint('[SipManager] New SIP reinvite received');
    event.accept?.call({});
  }

  // ── Navigation Routing Helpers ───────────────────────────────────────────

  void _navigateToIncomingCall() {
    navigatorKey?.currentState?.pushNamed('/incoming');
  }

  void _navigateToInCall() {
    navigatorKey?.currentState?.pushNamed('/in_call');
  }

  void _navigateBackToDialpad() {
    navigatorKey?.currentState?.popUntil(ModalRoute.withName('/'));
  }
}
