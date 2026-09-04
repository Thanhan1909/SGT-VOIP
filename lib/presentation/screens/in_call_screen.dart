import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sip_ua/sip_ua.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/sip_manager.dart';
import '../widgets/dtmf_keypad_dialog.dart';
import '../widgets/transfer_dialog.dart';

class InCallScreen extends StatefulWidget {
  const InCallScreen({Key? key}) : super(key: key);

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  bool _isPopping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCallActive();
    });
  }

  void _checkCallActive() {
    if (!mounted || _isPopping) return;
    final sip = context.read<SipManager>();
    final call = sip.currentCall;
    final state = sip.callState?.state;

    // Route Guard: Nếu F5 hoặc vào màn hình khi không có active call -> tự thoát về dialpad
    if (call == null ||
        state == CallStateEnum.ENDED ||
        state == CallStateEnum.FAILED) {
      _popBack();
    }
  }

  void _popBack() {
    if (_isPopping || !mounted) return;
    _isPopping = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _onHangup(SipManager sip) {
    sip.hangupCall();
    _popBack();
  }

  @override
  Widget build(BuildContext context) {
    final sip = context.watch<SipManager>();
    final call = sip.currentCall;
    final state = sip.callState?.state;

    // Auto-exit guard: Lắng nghe sự kiện kết thúc cuộc gọi
    if (call == null ||
        state == CallStateEnum.ENDED ||
        state == CallStateEnum.FAILED) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _popBack();
      });
    }

    final remoteIdentity = call?.remote_identity ?? 'Chưa xác định';
    final isConnected = call?.state == CallStateEnum.CONFIRMED ||
        call?.state == CallStateEnum.ACCEPTED ||
        state == CallStateEnum.CONFIRMED ||
        state == CallStateEnum.ACCEPTED;

    return WillPopScope(
      onWillPop: () async {
        _onHangup(sip);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppConstants.primaryDark,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                          child: Column(
                            children: [
                              const SizedBox(height: 12),

                              // Status Top Label
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isConnected
                                      ? AppConstants.accentGreen.withOpacity(0.2)
                                      : AppConstants.accentAmber.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isConnected ? AppConstants.accentGreen : AppConstants.accentAmber,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isConnected ? Icons.phone_in_talk : Icons.ring_volume,
                                      size: 16,
                                      color: isConnected ? AppConstants.accentGreen : AppConstants.accentAmber,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isConnected
                                          ? (sip.isOnHold ? 'Đang tạm giữ máy' : 'Đang đàm thoại')
                                          : (call?.direction.toUpperCase() == 'INCOMING'
                                              ? 'Đang đổ chuông...'
                                              : 'Đang kết nối...'),
                                      style: TextStyle(
                                        color: isConnected ? AppConstants.accentGreen : AppConstants.accentAmber,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const Spacer(flex: 1),

                              // Remote Caller Avatar / Icon
                              Container(
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppConstants.cardDark,
                                  border: Border.all(color: Colors.white24, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppConstants.accentBlue.withOpacity(0.2),
                                      blurRadius: 20,
                                      spreadRadius: 6,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.person,
                                  size: 58,
                                  color: Colors.white,
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Remote Caller Number / Name
                              Text(
                                remoteIdentity,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Tổng đài Asterisk PJSIP',
                                style: TextStyle(
                                  color: AppConstants.textMuted,
                                  fontSize: 13,
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Realtime Duration Timer
                              Text(
                                sip.formattedDuration,
                                style: TextStyle(
                                  color: isConnected ? Colors.white70 : Colors.white38,
                                  fontSize: 24,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              const Spacer(flex: 2),

                              // 6 Action Controls Grid: Mute, Speaker, Keypad, Hold, Transfer
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _buildCallControl(
                                          icon: sip.isMuted ? Icons.mic_off : Icons.mic,
                                          label: sip.isMuted ? 'Bật Mic' : 'Tắt Mic',
                                          isActive: sip.isMuted,
                                          onTap: () => sip.toggleMute(),
                                        ),
                                        _buildCallControl(
                                          icon: sip.isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                                          label: sip.isSpeakerOn ? 'Loa Ngoài' : 'Loa Trong',
                                          isActive: sip.isSpeakerOn,
                                          onTap: () => sip.toggleSpeaker(),
                                        ),
                                        _buildCallControl(
                                          icon: Icons.dialpad,
                                          label: 'Bàn phím DTMF',
                                          isActive: false,
                                          onTap: () {
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => DtmfKeypadDialog(
                                                onTonePressed: (tone) => sip.sendDTMF(tone),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _buildCallControl(
                                          icon: sip.isOnHold ? Icons.play_arrow : Icons.pause,
                                          label: sip.isOnHold ? 'Tiếp tục' : 'Giữ máy',
                                          isActive: sip.isOnHold,
                                          onTap: () => sip.toggleHold(),
                                        ),
                                        _buildCallControl(
                                          icon: Icons.phone_forwarded,
                                          label: 'Đá luồng (Transfer)',
                                          isActive: false,
                                          highlightColor: AppConstants.accentBlue,
                                          onTap: () {
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => TransferDialog(
                                                onTransfer: (targetExt) async {
                                                  final success = await sip.transferCall(targetExt);
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text(success
                                                            ? 'Đang chuyển cuộc gọi sang máy nhánh $targetExt...'
                                                            : 'Lỗi khi chuyển cuộc gọi'),
                                                        backgroundColor: success
                                                            ? AppConstants.accentBlue
                                                            : AppConstants.accentRed,
                                                      ),
                                                    );
                                                  }
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 28),

                              // End Call Red Button
                              Center(
                                child: GestureDetector(
                                  onTap: () => _onHangup(sip),
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: AppConstants.accentRed,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppConstants.accentRed.withOpacity(0.4),
                                          blurRadius: 18,
                                          spreadRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.call_end,
                                      color: Colors.white,
                                      size: 36,
                                    ),
                                  ),
                                ),
                              ),

                              const Spacer(flex: 1),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCallControl({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    Color? highlightColor,
  }) {
    final activeColor = highlightColor ?? AppConstants.accentAmber;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.2) : AppConstants.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? activeColor : Colors.white12,
            width: 1.2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isActive ? activeColor : Colors.white,
              size: 26,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isActive ? activeColor : AppConstants.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
