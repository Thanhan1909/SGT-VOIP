import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/sip_manager.dart';

class StatusIndicator extends StatelessWidget {
  final SipConnectionStatus status;
  final String statusText;
  final VoidCallback? onTap;

  const StatusIndicator({
    super.key,
    required this.status,
    required this.statusText,
    this.onTap,
  });

  Color get _statusColor {
    switch (status) {
      case SipConnectionStatus.online:
        return AppConstants.accentGreen;
      case SipConnectionStatus.connecting:
      case SipConnectionStatus.registering:
        return AppConstants.accentAmber;
      case SipConnectionStatus.error:
      case SipConnectionStatus.offline:
        return AppConstants.accentRed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppConstants.cardLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _statusColor.withValues(alpha: 0.5),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
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
                      color: _statusColor.withValues(alpha: 0.4),
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
                  color: AppConstants.textPrimary,
                  fontSize: 13,
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
