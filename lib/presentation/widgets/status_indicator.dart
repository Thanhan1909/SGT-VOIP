import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/sip_manager.dart';

class StatusIndicator extends StatelessWidget {
  final SipConnectionStatus status;
  final String statusText;
  final VoidCallback? onTap;

  const StatusIndicator({
    Key? key,
    required this.status,
    required this.statusText,
    this.onTap,
  }) : super(key: key);

  Color get _statusColor {
    switch (status) {
      case SipConnectionStatus.online:
        return AppConstants.accentGreen;
      case SipConnectionStatus.connecting:
      case SipConnectionStatus.registering:
        return AppConstants.accentAmber;
      case SipConnectionStatus.error:
      case SipConnectionStatus.offline:
      default:
        return AppConstants.accentRed;
    }
  }

  IconData get _statusIcon {
    switch (status) {
      case SipConnectionStatus.online:
        return Icons.check_circle_outline;
      case SipConnectionStatus.connecting:
      case SipConnectionStatus.registering:
        return Icons.sync;
      case SipConnectionStatus.error:
      case SipConnectionStatus.offline:
      default:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: AppConstants.cardDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _statusColor.withOpacity(0.4), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _statusColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _statusColor.withOpacity(0.5),
                    blurRadius: 6,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
