import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
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

      // Explicitly set transportType to WS (Fixes Null check operator crash in sip_ua)
      settings.transportType = TransportType.WS;
      settings.webSocketUrl = acc.wssUri;
      settings.webSocketSettings.allowBadCertificate = true;
      settings.webSocketSettings.transport_scheme =
          acc.wssUri.startsWith('wss') ? 'wss' : 'ws';
      settings.uri = 'sip:${acc.extension}@${acc.domain}';
      settings.authorizationUser = acc.extension;
      settings.password = acc.password;
      settings.realm = 'asterisk';
      settings.displayName =
          acc.displayName.isNotEmpty ? acc.displayName : acc.extension;
      settings.userAgent = 'Flutter SGT VoIP Softphone / Asterisk 20';
      settings.register = true;
      settings.register_expires = 300;

      // Configure STUN / TURN ICE Servers for NAT Traversal
      final iceServers = <Map<String, String>>[
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ];
      if (acc.stunUri.isNotEmpty && !acc.stunUri.contains('google.com')) {
        iceServers.add({'urls': acc.stunUri});
      }
      if (acc.turnUri.isNotEmpty) {
        final turnMap = <String, String>{'urls': acc.turnUri};
        if (acc.turnUsername.isNotEmpty) turnMap['username'] = acc.turnUsername;
        if (acc.turnPassword.isNotEmpty) turnMap['credential'] = acc.turnPassword;
        iceServers.add(turnMap);
      }

      settings.iceServers = iceServers;
      settings.dtmfMode = DtmfMode.RFC2833;

      if (_helper.connected || _helper.registered) {
        _helper.stop();
      }

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

    // 1. Request Microphone Runtime Permission before native audio initialization (Android / iOS)
    if (!kIsWeb) {
      try {
        final micStatus = await Permission.microphone.request();
        if (!micStatus.isGranted) {
          debugPrint('[SipManager] Error: Microphone permission denied by user');
          _statusMessage = 'Cần cấp quyền Microphone để gọi';
          notifyListeners();
          return;
        }
      } catch (permErr) {
        debugPrint('[SipManager] Permission check note: $permErr');
      }
    }

    final targetUri = 'sip:$cleanNumber@${_account!.domain}';
    debugPrint('[SipManager] Calling target: $targetUri');

    _isMuted = false;
    _isOnHold = false;
    _audioManager.setSpeakerphone(false);

    try {
      // 2. Strict Voice-only constraints (Audio: true, Video: false)
      final mediaConstraints = <String, dynamic>{
        'audio': true,
        'video': false,
      };
      _helper.call(
        targetUri,
        voiceonly: true,
        customOptions: {'mediaConstraints': mediaConstraints},
      );

      _audioManager.playRingback();
    } catch (e) {
      debugPrint('[SipManager] Make call error: $e');
    }
  }

  Future<void> answerCall() async {
    if (_currentCall != null) {
      if (!kIsWeb) {
        try {
          final micStatus = await Permission.microphone.request();
          if (!micStatus.isGranted) {
            debugPrint('[SipManager] Error: Microphone permission denied by user');
            return;
          }
        } catch (permErr) {
          debugPrint('[SipManager] Permission check note: $permErr');
        }
      }
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

  /// Đá luồng / Chuyển cuộc gọi (Hỗ trợ cả SIP REFER và DTMF ##)
  Future<bool> transferCall(String targetExtension) async {
    if (_currentCall == null || targetExtension.trim().isEmpty) return false;
    final target = targetExtension.trim();
    final targetUri =
        target.contains('@') ? target : '$target@${_account!.domain}';

    debugPrint('[SipManager] Transferring call to: $targetUri');
    try {
      // 1. Chuyển cuộc gọi chuẩn SIP REFER
      _currentCall!.refer('sip:$targetUri');
      return true;
    } catch (e) {
      debugPrint('[SipManager] SIP REFER failed ($e), falling back to DTMF ##');
      try {
        // 2. Dự phòng bằng DTMF Feature ##
        _currentCall!.sendDTMF('##$target');
        return true;
      } catch (dtmfErr) {
        debugPrint('[SipManager] DTMF Transfer error: $dtmfErr');
        return false;
      }
    }
  }

  void transferViaDTMF(String targetExtension) {
    if (_currentCall != null) {
      _currentCall!.sendDTMF('##${targetExtension.trim()}');
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
        if (call.direction.toUpperCase() == 'INCOMING') {
          _audioManager.playRingtone();
          _navigateToIncomingCall();
        }
        break;

      case CallStateEnum.PROGRESS:
        if (call.direction.toUpperCase() == 'OUTGOING') {
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



  // ── Navigation Routing Helpers ───────────────────────────────────────────

  bool _isInCallScreenOpen = false;

  void _navigateToIncomingCall() {
    if (!_isInCallScreenOpen) {
      _isInCallScreenOpen = true;
      navigatorKey?.currentState?.pushNamed('/incoming').then((_) {
        _isInCallScreenOpen = false;
      });
    }
  }

  void _navigateToInCall() {
    if (!_isInCallScreenOpen) {
      _isInCallScreenOpen = true;
      navigatorKey?.currentState?.pushNamed('/in_call').then((_) {
        _isInCallScreenOpen = false;
      });
    }
  }

  void _navigateBackToDialpad() {
    if (_isInCallScreenOpen) {
      _isInCallScreenOpen = false;
      try {
        navigatorKey?.currentState?.popUntil(ModalRoute.withName('/'));
      } catch (e) {
        debugPrint('[SipManager] Navigate back error: $e');
      }
    }
  }
}
