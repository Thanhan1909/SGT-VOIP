import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

class TransferDialog extends StatefulWidget {
  final Function(String targetExtension) onTransfer;

  const TransferDialog({super.key, required this.onTransfer});

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog> {
  final TextEditingController _extController = TextEditingController();

  final List<Map<String, String>> _quickExtensions = [
    {'name': 'Sale 201', 'ext': '201'},
    {'name': 'Leader 202', 'ext': '202'},
    {'name': 'Giám Đốc 203', 'ext': '203'},
  ];

  @override
  void dispose() {
    _extController.dispose();
    super.dispose();
  }

  void _submit(String extension) {
    if (extension.trim().isNotEmpty) {
      Navigator.of(context).pop();
      widget.onTransfer(extension.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      backgroundColor: AppConstants.surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppConstants.borderLight),
      ),
      title: const Row(
        children: [
          Icon(Icons.phone_forwarded, color: AppConstants.accentGreen),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Chuyển Cuộc Gọi',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppConstants.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nhập số máy nhánh mục tiêu hoặc chọn máy nhanh bên dưới:',
            style: TextStyle(color: AppConstants.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _extController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(
              color: AppConstants.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: 'VD: 201 hoặc 203',
              hintStyle: const TextStyle(color: AppConstants.textMuted),
              prefixIcon: const Icon(
                Icons.dialpad,
                color: AppConstants.accentGreen,
              ),
              filled: true,
              fillColor: AppConstants.cardLight,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppConstants.borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppConstants.accentGreen,
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Chuyển nhanh:',
            style: TextStyle(
              color: AppConstants.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _quickExtensions.map((item) {
              return ActionChip(
                backgroundColor: AppConstants.cardLight,
                side: const BorderSide(color: AppConstants.borderLight),
                avatar: const Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: AppConstants.accentGreen,
                ),
                label: Text(
                  '${item['name']} (${item['ext']})',
                  style: const TextStyle(
                    color: AppConstants.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _extController.text = item['ext']!;
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Text(
              'Hủy',
              style: TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConstants.accentGreen,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          icon: const Icon(Icons.check, color: Colors.white, size: 18),
          label: const Text(
            'Chuyển Ngay',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          onPressed: () => _submit(_extController.text),
        ),
      ],
    );
  }
}
