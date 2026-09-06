import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sip_ua/sip_ua.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/sip_manager.dart';
import '../widgets/dtmf_keypad_dialog.dart';
import '../widgets/transfer_dialog.dart';

class InCallScreen extends StatefulWidget {
  const InCallScreen({super.key});

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

    // Route Guard: Nếu vào màn hình khi không có active call và không đang dialing -> tự thoát về dialpad
    if ((call == null && !sip.isDialing) ||
        state == CallStateEnum.ENDED ||
        state == CallStateEnum.FAILED) {
      _popBack();
    }
  }

  void _popBack() {
    if (_isPopping || !mounted) return;
    _isPopping = true;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
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
    if ((call == null && !sip.isDialing) ||
        state == CallStateEnum.ENDED ||
        state == CallStateEnum.FAILED) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _popBack();
      });
    }

    final remoteIdentity = call?.remote_identity ?? 'Chưa xác định';
    final isConnected =
        call?.state == CallStateEnum.CONFIRMED ||
        call?.state == CallStateEnum.ACCEPTED ||
        state == CallStateEnum.CONFIRMED ||
        state == CallStateEnum.ACCEPTED;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onHangup(sip);
      },
      child: Scaffold(
        backgroundColor: AppConstants.backgroundLight,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20.0,
                            vertical: 16.0,
                          ),
                          child: Column(
                            children: [
                              const SizedBox(height: 12),

                              // Status Top Pill Label
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isConnected
                                      ? AppConstants.accentGreen.withValues(
                                          alpha: 0.15,
                                        )
                                      : AppConstants.accentAmber.withValues(
                                          alpha: 0.15,
                                        ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isConnected
                                        ? AppConstants.accentGreen
                                        : AppConstants.accentAmber,
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isConnected
                                          ? Icons.phone_in_talk
                                          : Icons.ring_volume,
                                      size: 16,
                                      color: isConnected
                                          ? AppConstants.accentGreen
                                          : AppConstants.accentAmber,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      sip.friendlyCallStatus,
                                      style: TextStyle(
                                        color: isConnected
                                            ? AppConstants.accentGreen
                                            : AppConstants.accentAmber,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const Spacer(flex: 1),

                              // Remote Caller Avatar
                              Container(
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppConstants.surfaceLight,
                                  border: Border.all(
                                    color: AppConstants.borderLight,
                                    width: 2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x0F000000),
                                      blurRadius: 16,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.person,
                                  size: 58,
                                  color: AppConstants.textSecondary,
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Remote Caller Number / Name
                              Text(
                                remoteIdentity,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppConstants.textPrimary,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Realtime Duration Timer
                              Text(
                                sip.formattedDuration,
                                style: TextStyle(
                                  color: isConnected
                                      ? AppConstants.textPrimary
                                      : AppConstants.textMuted,
                                  fontSize: 26,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              const Spacer(flex: 2),

                              // 5 Action Controls: Mute, Speaker, Keypad, Hold, Transfer
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildCallControl(
                                            icon: sip.isMuted
                                                ? Icons.mic_off
                                                : Icons.mic,
                                            label: sip.isMuted
                                                ? 'Bật Mic'
                                                : 'Tắt Mic',
                                            isActive: sip.isMuted,
                                            onTap: () => sip.toggleMute(),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _buildCallControl(
                                            icon: sip.isSpeakerOn
                                                ? Icons.volume_up
                                                : Icons.volume_down,
                                            label: kIsWeb
                                                ? 'Loa (Web)'
                                                : (sip.isSpeakerOn
                                                      ? 'Loa Ngoài'
                                                      : 'Loa Trong'),
                                            isActive: sip.isSpeakerOn,
                                            isDisabled: kIsWeb,
                                            onTap: kIsWeb
                                                ? () {}
                                                : () => sip.toggleSpeaker(),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _buildCallControl(
                                            icon: Icons.dialpad,
                                            label: 'Bàn phím DTMF',
                                            isActive: false,
                                            onTap: () {
                                              showDialog(
                                                context: context,
                                                builder: (ctx) =>
                                                    DtmfKeypadDialog(
                                                      onTonePressed: (tone) =>
                                                          sip.sendDTMF(tone),
                                                    ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 100,
                                          child: _buildCallControl(
                                            icon: sip.isOnHold
                                                ? Icons.play_arrow
                                                : Icons.pause,
                                            label: sip.isOnHold
                                                ? 'Tiếp tục'
                                                : 'Giữ máy',
                                            isActive: sip.isOnHold,
                                            onTap: () => sip.toggleHold(),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        SizedBox(
                                          width: 100,
                                          child: _buildCallControl(
                                            icon: Icons.phone_forwarded,
                                            label: 'Chuyển cuộc gọi',
                                            isActive: false,
                                            onTap: () {
                                              showDialog(
                                                context: context,
                                                builder: (ctx) => TransferDialog(
                                                  onTransfer: (targetExt) async {
                                                    final success = await sip
                                                        .transferCall(
                                                          targetExt,
                                                        );
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            success
                                                                ? 'Đang chuyển cuộc gọi sang máy nhánh $targetExt...'
                                                                : 'Lỗi khi chuyển cuộc gọi',
                                                          ),
                                                          backgroundColor:
                                                              success
                                                              ? AppConstants
                                                                    .accentGreen
                                                              : AppConstants
                                                                    .accentRed,
                                                        ),
                                                      );
                                                    }
                                                  },
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 28),

                              // End Call Red Button
                              Center(
                                child: Semantics(
                                  button: true,
                                  label: 'Kết thúc cuộc gọi',
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _onHangup(sip),
                                      borderRadius: BorderRadius.circular(36),
                                      child: Container(
                                        width: 72,
                                        height: 72,
                                        decoration: const BoxDecoration(
                                          color: AppConstants.accentRed,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Color(0x4DE5484D),
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
    bool isDisabled = false,
  }) {
    const activeColor = AppConstants.accentAmber;
    final bgColor = isDisabled
        ? const Color(0xFFEFE8E1)
        : (isActive
              ? activeColor.withValues(alpha: 0.15)
              : AppConstants.cardLight);
    final borderColor = isDisabled
        ? AppConstants.borderLight
        : (isActive ? activeColor : AppConstants.borderLight);
    final iconColor = isDisabled
        ? const Color(0xFFB5ABA2)
        : (isActive ? activeColor : AppConstants.textPrimary);
    final textColor = isDisabled
        ? const Color(0xFFB5ABA2)
        : (isActive ? activeColor : AppConstants.textPrimary);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
