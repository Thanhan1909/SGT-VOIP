import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

class TransferDialog extends StatefulWidget {
  final Function(String targetExtension) onTransfer;

  const TransferDialog({
    Key? key,
    required this.onTransfer,
  }) : super(key: key);

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
      backgroundColor: AppConstants.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.white12),
      ),
      title: Row(
        children: const [
          Icon(Icons.phone_forwarded, color: AppConstants.accentBlue),
          SizedBox(width: 10),
          Text(
            'Chuyển Cuộc Gọi (Đá Luồng)',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nhập số máy nhánh mục tiêu hoặc chọn máy nhanh bên dưới:',
            style: TextStyle(color: AppConstants.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _extController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'VD: 1001 hoặc 1003',
              hintStyle: const TextStyle(color: Colors.white30),
              prefixIcon: const Icon(Icons.dialpad, color: AppConstants.accentBlue),
              filled: true,
              fillColor: AppConstants.cardDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Chuyển nhanh:',
            style: TextStyle(color: AppConstants.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _quickExtensions.map((item) {
              return ActionChip(
                backgroundColor: AppConstants.cardDark,
                avatar: const Icon(Icons.arrow_forward, size: 14, color: AppConstants.accentGreen),
                label: Text('${item['name']} (${item['ext']})', style: const TextStyle(color: Colors.white, fontSize: 12)),
                onPressed: () {
                  _extController.text = item['ext']!;
                },
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy', style: TextStyle(color: AppConstants.textMuted)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConstants.accentBlue,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.check, color: Colors.white, size: 18),
          label: const Text('Chuyển Ngay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          onPressed: () => _submit(_extController.text),
        ),
      ],
    );
  }
}
