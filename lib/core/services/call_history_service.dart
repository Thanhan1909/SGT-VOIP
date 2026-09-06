import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models/call_history_entry.dart';
import '../../data/repositories/call_history_repository.dart';

class CallHistoryService extends ChangeNotifier {
  final CallHistoryRepository repository;
  List<CallHistoryEntry> _entries = [];
  bool _isLoading = true;
  StreamSubscription<List<CallHistoryEntry>>? _repoSub;

  CallHistoryService({required this.repository}) {
    _init();
  }

  bool get isLoading => _isLoading;
  List<CallHistoryEntry> get entries => List.unmodifiable(_entries);

  void _init() {
    _repoSub = repository.watchEntries().listen((newList) {
      _entries = List.from(newList);
      notifyListeners();
    });
    loadEntries();
  }

  Future<void> loadEntries() async {
    _isLoading = true;
    notifyListeners();
    try {
      _entries = await repository.getEntries();
    } catch (e) {
      debugPrint('[CallHistoryService] Error loading entries: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _normalizeUuid(String uuid) => uuid.trim().toLowerCase();

  CallHistoryEntry? getEntryByCorrelationId(String correlationId) {
    final norm = _normalizeUuid(correlationId);
    if (norm.isEmpty) return null;
    try {
      return _entries.firstWhere(
        (e) => _normalizeUuid(e.correlationId) == norm,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> recordCallInitiation({
    required String correlationId,
    required String localExtension,
    required String remoteNumber,
    String remoteDisplayName = '',
    required CallDirection direction,
  }) async {
    final norm = _normalizeUuid(correlationId);
    if (norm.isEmpty) return;

    final existing = getEntryByCorrelationId(norm);
    if (existing != null) {
      // Avoid duplicate creation on repeated PROGRESS/STREAM events
      return;
    }

    final entry = CallHistoryEntry(
      id: 'call_${DateTime.now().millisecondsSinceEpoch}_$norm',
      correlationId: norm,
      localExtension: localExtension,
      remoteNumber: remoteNumber,
      remoteDisplayName: remoteDisplayName,
      direction: direction,
      result: direction == CallDirection.incoming
          ? CallResult.missed
          : CallResult.noAnswer,
      startedAt: DateTime.now(),
    );

    await repository.upsertEntry(entry);
    _entries = await repository.getEntries();
    notifyListeners();
  }

  Future<void> recordCallAnswered({required String correlationId}) async {
    final norm = _normalizeUuid(correlationId);
    if (norm.isEmpty) return;

    final existing = getEntryByCorrelationId(norm);
    final now = DateTime.now();

    if (existing != null) {
      if (existing.result == CallResult.answered &&
          existing.answeredAt != null) {
        return; // Already marked answered
      }
      final updated = existing.copyWith(
        answeredAt: existing.answeredAt ?? now,
        result: CallResult.answered,
      );
      await repository.upsertEntry(updated);
      _entries = await repository.getEntries();
      notifyListeners();
    }
  }

  Future<void> recordCallEnded({
    required String correlationId,
    required bool wasAnswered,
    required bool wasDeclinedByUser,
    String? cause,
  }) async {
    final norm = _normalizeUuid(correlationId);
    if (norm.isEmpty) return;

    final existing = getEntryByCorrelationId(norm);
    if (existing == null) return;
    if (existing.endedAt != null) return;

    final now = DateTime.now();
    final answered = existing.answeredAt != null || wasAnswered;
    final answeredAt = existing.answeredAt ?? (answered ? now : null);

    CallResult finalResult;
    int duration = 0;

    if (answered) {
      finalResult = CallResult.answered;
      duration = answeredAt != null ? now.difference(answeredAt).inSeconds : 0;
      if (duration < 0) duration = 0;
    } else {
      if (existing.direction == CallDirection.incoming) {
        if (wasDeclinedByUser ||
            (cause != null &&
                (cause.toLowerCase().contains('decline') ||
                    cause.toLowerCase().contains('reject')))) {
          finalResult = CallResult.declined;
        } else {
          finalResult = CallResult.missed;
        }
      } else {
        finalResult = CallResult.noAnswer;
      }
    }

    final updated = existing.copyWith(
      answeredAt: answeredAt,
      endedAt: now,
      result: finalResult,
      durationSeconds: duration,
      failureReason: cause,
    );

    await repository.upsertEntry(updated);
    _entries = await repository.getEntries();
    notifyListeners();
  }

  Future<void> recordCallFailed({
    required String correlationId,
    required String reason,
    bool isIncoming = false,
  }) async {
    final norm = _normalizeUuid(correlationId);
    if (norm.isEmpty) return;

    final existing = getEntryByCorrelationId(norm);
    final now = DateTime.now();

    if (existing == null) return;

    if (existing.answeredAt != null) {
      // If call was already answered, do not mark as failed; just finalize it
      await recordCallEnded(
        correlationId: correlationId,
        wasAnswered: true,
        wasDeclinedByUser: false,
        cause: reason,
      );
      return;
    }

    final finalResult = isIncoming ? CallResult.missed : CallResult.failed;

    final updated = existing.copyWith(
      endedAt: now,
      result: finalResult,
      failureReason: reason,
    );

    await repository.upsertEntry(updated);
    _entries = await repository.getEntries();
    notifyListeners();
  }

  List<CallHistoryEntry> filterEntries({
    String query = '',
    String filter = 'all',
  }) {
    final q = query.trim().toLowerCase();

    return _entries.where((entry) {
      // 1. Filter by category
      switch (filter) {
        case 'incoming':
          // direction=incoming and result != missed (declined is shown under incoming)
          if (entry.direction != CallDirection.incoming ||
              entry.result == CallResult.missed) {
            return false;
          }
          break;
        case 'outgoing':
          if (entry.direction != CallDirection.outgoing) {
            return false;
          }
          break;
        case 'missed':
          if (entry.direction != CallDirection.incoming ||
              entry.result != CallResult.missed) {
            return false;
          }
          break;
        case 'all':
        default:
          break;
      }

      // 2. Filter by search query
      if (q.isNotEmpty) {
        final matchesNumber = entry.remoteNumber.toLowerCase().contains(q);
        final matchesName = entry.remoteDisplayName.toLowerCase().contains(q);
        if (!matchesNumber && !matchesName) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Future<void> clearHistory() async {
    _entries.clear();
    notifyListeners();
    await repository.clearAll();
  }

  @override
  void dispose() {
    _repoSub?.cancel();
    super.dispose();
  }
}
