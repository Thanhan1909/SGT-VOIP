import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sip_ua/sip_ua.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/sip_manager.dart';
import '../widgets/dtmf_keypad_dialog.dart';
import '../widgets/transfer_dialog.dart';

class InCallScreen extends StatelessWidget {
  const InCallScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final sip = context.watch<SipManager>();
    final call = sip.currentCall;

    final remoteIdentity = call?.remote_identity ?? 'Chưa xác định';
    final isConnected = call?.state == CallStateEnum.CONFIRMED || call?.state == CallStateEnum.ACCEPTED;

    return WillPopScope(
      onWillPop: () async => false, // Prevent accidental back press during active call
      child: Scaffold(
        backgroundColor: AppConstants.primaryDark,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 30),

              // Status Top Label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isConnected ? AppConstants.accentGreen.withOpacity(0.2) : AppConstants.accentAmber.withOpacity(0.2),
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
                          : (call?.direction.toUpperCase() == 'INCOMING' ? 'Đang đổ chuông...' : 'Đang kết nối...'),
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
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppConstants.cardDark,
                      border: Border.all(color: Colors.white24, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppConstants.accentBlue.withOpacity(0.2),
                          blurRadius: 24,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Remote Caller Number / Name
              Text(
                remoteIdentity,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Tổng đài Asterisk PJSIP',
                style: TextStyle(
                  color: AppConstants.textMuted,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 16),

              // Realtime Duration Timer
              if (isConnected)
                Text(
                  sip.formattedDuration,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 24,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),

              const Spacer(flex: 2),

              // 6 Action Controls Grid: Mute, Speaker, Keypad, Hold, Transfer, Extra
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
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
                    const SizedBox(height: 20),
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
                                        backgroundColor: success ? AppConstants.accentBlue : AppConstants.accentRed,
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

              const SizedBox(height: 36),

              // End Call Red Button
              Center(
                child: GestureDetector(
                  onTap: () => sip.hangupCall(),
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: AppConstants.accentRed,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppConstants.accentRed.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 1),
            ],
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
              size: 28,
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
