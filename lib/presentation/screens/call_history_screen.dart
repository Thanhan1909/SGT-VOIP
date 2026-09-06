import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/sip_manager.dart';
import '../../data/models/call_history_entry.dart';
import '../widgets/status_indicator.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _activeFilter = 'all'; // 'all', 'incoming', 'outgoing', 'missed'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final text = _searchController.text;
      if (text != _searchQuery) {
        setState(() {
          _searchQuery = text;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) {
      return timeStr;
    }
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day;
    if (isYesterday) {
      return 'Hôm qua $timeStr';
    }
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} $timeStr';
  }

  Future<void> _handleCallBack(String number, SipManager sip) async {
    final cleanNumber = number.trim();
    if (cleanNumber.isEmpty) return;

    final result = await sip.makeCall(cleanNumber);
    if (!mounted) return;

    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppConstants.accentRed,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showFilterAndSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'BỘ LỌC CUỘC GỌI',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.textSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            if (_activeFilter != 'all')
                              TextButton(
                                onPressed: () {
                                  setSheetState(() => _activeFilter = 'all');
                                  setState(() => _activeFilter = 'all');
                                },
                                child: const Text(
                                  'Đặt lại',
                                  style: TextStyle(
                                    color: AppConstants.accentGreen,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Filter Options
                      ListTile(
                        title: const Text('Tất cả'),
                        trailing: _activeFilter == 'all'
                            ? const Icon(
                                Icons.check,
                                color: AppConstants.accentGreen,
                              )
                            : null,
                        onTap: () {
                          setSheetState(() => _activeFilter = 'all');
                          setState(() => _activeFilter = 'all');
                          Navigator.pop(ctx);
                        },
                      ),
                      ListTile(
                        title: const Text('Gọi đến'),
                        trailing: _activeFilter == 'incoming'
                            ? const Icon(
                                Icons.check,
                                color: AppConstants.accentGreen,
                              )
                            : null,
                        onTap: () {
                          setSheetState(() => _activeFilter = 'incoming');
                          setState(() => _activeFilter = 'incoming');
                          Navigator.pop(ctx);
                        },
                      ),
                      ListTile(
                        title: const Text('Gọi đi'),
                        trailing: _activeFilter == 'outgoing'
                            ? const Icon(
                                Icons.check,
                                color: AppConstants.accentGreen,
                              )
                            : null,
                        onTap: () {
                          setSheetState(() => _activeFilter = 'outgoing');
                          setState(() => _activeFilter = 'outgoing');
                          Navigator.pop(ctx);
                        },
                      ),
                      ListTile(
                        title: const Text('Gọi nhỡ'),
                        trailing: _activeFilter == 'missed'
                            ? const Icon(
                                Icons.check,
                                color: AppConstants.accentRed,
                              )
                            : null,
                        onTap: () {
                          setSheetState(() => _activeFilter = 'missed');
                          setState(() => _activeFilter = 'missed');
                          Navigator.pop(ctx);
                        },
                      ),

                      const Divider(height: 24, indent: 16, endIndent: 16),

                      // Settings Section
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20.0),
                        child: Text(
                          'CẤU HÌNH',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppConstants.textSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ListTile(
                        leading: const Icon(
                          Icons.settings_outlined,
                          color: AppConstants.textPrimary,
                        ),
                        title: const Text('Cấu hình hệ thống'),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: AppConstants.textSecondary,
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.pushNamed(context, '/settings');
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sip = context.watch<SipManager>();
    final historyService = sip.callHistoryService;

    // Listen to changes from historyService
    return ListenableBuilder(
      listenable: historyService,
      builder: (context, _) {
        final filteredEntries = historyService.filterEntries(
          query: _searchQuery,
          filter: _activeFilter,
        );

        return Scaffold(
          backgroundColor: AppConstants.backgroundLight,
          appBar: AppBar(
            backgroundColor: AppConstants.surfaceLight,
            elevation: 0,
            title: const Text(
              'Cuộc gọi',
              style: TextStyle(
                color: AppConstants.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                child: StatusIndicator(
                  status: sip.connectionStatus,
                  statusText: sip.statusMessage,
                  onTap: () => sip.retryRegistration(),
                ),
              ),
              IconButton(
                icon: Badge(
                  isLabelVisible: _activeFilter != 'all',
                  smallSize: 8,
                  backgroundColor: AppConstants.accentGreen,
                  child: const Icon(
                    Icons.tune,
                    color: AppConstants.textPrimary,
                  ),
                ),
                tooltip: 'Bộ lọc & Cấu hình',
                onPressed: _showFilterAndSettingsSheet,
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Search Bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  color: AppConstants.surfaceLight,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Tìm theo tên hoặc số điện thoại',
                      hintStyle: const TextStyle(
                        color: AppConstants.textSecondary,
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppConstants.textSecondary,
                        size: 20,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                size: 18,
                                color: AppConstants.textSecondary,
                              ),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppConstants.backgroundLight,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10.0,
                        horizontal: 16.0,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                // Call List or Empty State
                Expanded(
                  child: filteredEntries.isEmpty
                      ? _buildEmptyState(historyService.entries.isEmpty)
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          itemCount: filteredEntries.length,
                          separatorBuilder: (context, index) => const Divider(
                            height: 1,
                            indent: 68,
                            endIndent: 16,
                            color: Color(0xFFEEEEEE),
                          ),
                          itemBuilder: (context, index) {
                            final entry = filteredEntries[index];
                            return _buildCallItem(entry, sip);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(bool isHistoryCompletelyEmpty) {
    final message = isHistoryCompletelyEmpty
        ? 'Chưa có lịch sử cuộc gọi'
        : 'Không tìm thấy cuộc gọi phù hợp';
    final icon = isHistoryCompletelyEmpty
        ? Icons.phone_in_talk_outlined
        : Icons.search_off;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 54,
              color: AppConstants.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                color: AppConstants.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallItem(CallHistoryEntry entry, SipManager sip) {
    final isMissed =
        entry.direction == CallDirection.incoming &&
        entry.result == CallResult.missed;
    final isDeclined = entry.result == CallResult.declined;

    final displayName = entry.remoteDisplayName.isNotEmpty
        ? entry.remoteDisplayName
        : entry.remoteNumber;

    // Determine direction icon and text
    IconData directionIcon;
    Color directionColor;
    String statusText;

    if (entry.direction == CallDirection.outgoing) {
      directionIcon = Icons.call_made;
      if (entry.result == CallResult.answered) {
        directionColor = AppConstants.accentGreen;
        statusText = 'Gọi đi • ${_formatDuration(entry.durationSeconds)}';
      } else if (entry.result == CallResult.failed) {
        directionColor = AppConstants.accentRed;
        statusText = 'Gọi đi thất bại';
      } else {
        directionColor = AppConstants.textSecondary;
        statusText = 'Không trả lời';
      }
    } else {
      // Incoming
      if (isMissed) {
        directionIcon = Icons.call_missed;
        directionColor = AppConstants.accentRed;
        statusText = 'Cuộc gọi nhỡ';
      } else if (isDeclined) {
        directionIcon = Icons.call_end;
        directionColor = AppConstants.textSecondary;
        statusText = 'Đã từ chối';
      } else if (entry.result == CallResult.answered) {
        directionIcon = Icons.call_received;
        directionColor = AppConstants.accentGreen;
        statusText = 'Gọi đến • ${_formatDuration(entry.durationSeconds)}';
      } else {
        directionIcon = Icons.call_received;
        directionColor = AppConstants.textSecondary;
        statusText = 'Gọi đến';
      }
    }

    final avatarInitial = displayName.isNotEmpty
        ? (RegExp(r'[a-zA-Z0-9]').hasMatch(displayName[0])
              ? displayName[0].toUpperCase()
              : 'C')
        : 'C';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 4.0,
      ),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: isMissed
            ? AppConstants.accentRed.withValues(alpha: 0.12)
            : AppConstants.accentGreen.withValues(alpha: 0.12),
        child: Text(
          avatarInitial,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isMissed ? AppConstants.accentRed : AppConstants.accentGreen,
          ),
        ),
      ),
      title: Text(
        displayName,
        style: TextStyle(
          fontSize: 16,
          fontWeight: isMissed ? FontWeight.bold : FontWeight.w500,
          color: isMissed ? AppConstants.accentRed : AppConstants.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Icon(directionIcon, size: 14, color: directionColor),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${entry.remoteNumber} • $statusText',
              style: TextStyle(
                fontSize: 13,
                color: isMissed
                    ? AppConstants.accentRed
                    : AppConstants.textSecondary,
                fontWeight: isMissed ? FontWeight.w500 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatDate(entry.startedAt),
            style: const TextStyle(
              fontSize: 12,
              color: AppConstants.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(
              Icons.phone,
              color: AppConstants.accentGreen,
              size: 20,
            ),
            tooltip: 'Gọi lại cho ${entry.remoteNumber}',
            onPressed: () => _handleCallBack(entry.remoteNumber, sip),
          ),
        ],
      ),
      // Tapping row does not trigger call accidentally
      onTap: null,
    );
  }
}
