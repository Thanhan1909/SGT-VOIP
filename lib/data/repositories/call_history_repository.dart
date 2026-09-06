import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/call_history_entry.dart';

abstract class CallHistoryRepository {
  Future<List<CallHistoryEntry>> getEntries();
  Future<void> upsertEntry(CallHistoryEntry entry);
  Future<void> deleteEntry(String id);
  Future<void> clearAll();
  Stream<List<CallHistoryEntry>> watchEntries();
}

class SharedPrefsCallHistoryRepository implements CallHistoryRepository {
  static const String prefKey = 'sgt_call_history_v1';
  static const int currentSchemaVersion = 1;
  static const int maxRecords = 500;

  final SharedPreferences? prefs;
  final StreamController<List<CallHistoryEntry>> _streamController =
      StreamController<List<CallHistoryEntry>>.broadcast();

  // Sequential queue to guarantee serialized writes and prevent lost updates
  Future<void> _writeQueue = Future.value();

  SharedPrefsCallHistoryRepository({this.prefs});

  Future<SharedPreferences> _getPrefs() async {
    return prefs ?? await SharedPreferences.getInstance();
  }

  List<CallHistoryEntry>? _cachedEntries;

  @override
  Stream<List<CallHistoryEntry>> watchEntries() => _streamController.stream;

  @override
  Future<List<CallHistoryEntry>> getEntries() async {
    if (_cachedEntries != null) {
      return List.from(_cachedEntries!);
    }
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(prefKey);
      if (raw == null || raw.trim().isEmpty) {
        _cachedEntries = [];
        return [];
      }

      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _cachedEntries = [];
        return [];
      }

      final list = decoded['entries'] as List<dynamic>?;
      if (list == null) {
        _cachedEntries = [];
        return [];
      }

      final entries = <CallHistoryEntry>[];
      bool needsSelfHeal = false;

      for (final item in list) {
        if (item is Map<String, dynamic>) {
          try {
            var entry = CallHistoryEntry.fromJson(item);
            // Self-heal: If app died/crashed while a call was in-progress (endedAt == null)
            // complete it safely so it doesn't stay hanging indefinitely.
            if (entry.endedAt == null) {
              final healEnd = entry.answeredAt ?? entry.startedAt;
              final healResult = entry.answeredAt != null
                  ? CallResult.answered
                  : (entry.direction == CallDirection.incoming
                        ? CallResult.missed
                        : CallResult.noAnswer);
              final healDuration = entry.answeredAt != null
                  ? healEnd.difference(entry.answeredAt!).inSeconds
                  : 0;

              entry = entry.copyWith(
                endedAt: healEnd,
                result: healResult,
                durationSeconds: healDuration < 0 ? 0 : healDuration,
              );
              needsSelfHeal = true;
            }
            entries.add(entry);
          } catch (e) {
            debugPrint('[CallHistoryRepository] Skipping corrupted item: $e');
          }
        }
      }

      // Sort newest first
      entries.sort((a, b) => b.startedAt.compareTo(a.startedAt));

      if (entries.length > maxRecords) {
        entries.removeRange(maxRecords, entries.length);
      }

      _cachedEntries = List.from(entries);

      if (needsSelfHeal) {
        // Persist self-healed entries in the background
        unawaited(_saveEntriesRaw(entries));
      }

      return List.from(_cachedEntries!);
    } catch (e) {
      debugPrint('[CallHistoryRepository] Error reading call history: $e');
      _cachedEntries = [];
      return [];
    }
  }

  @override
  Future<void> upsertEntry(CallHistoryEntry entry) {
    // Chain sequentially to avoid race condition
    _writeQueue = _writeQueue
        .then((_) async {
          final current = await getEntries();
          final normalizedCorrId = entry.correlationId.trim().toLowerCase();

          final index = current.indexWhere((e) {
            if (normalizedCorrId.isNotEmpty &&
                e.correlationId.trim().toLowerCase() == normalizedCorrId) {
              return true;
            }
            return e.id == entry.id;
          });

          if (index >= 0) {
            // Update existing record in place
            current[index] = entry;
          } else {
            // Prepend new record
            current.insert(0, entry);
          }

          // Re-sort newest first
          current.sort((a, b) => b.startedAt.compareTo(a.startedAt));

          // Enforce max 500 limit
          if (current.length > maxRecords) {
            current.removeRange(maxRecords, current.length);
          }

          _cachedEntries = List.from(current);
          await _saveEntriesRaw(current);
          _streamController.add(List.unmodifiable(current));
        })
        .catchError((e) {
          debugPrint('[CallHistoryRepository] Error in upsertEntry: $e');
        });

    return _writeQueue;
  }

  @override
  Future<void> deleteEntry(String id) {
    _writeQueue = _writeQueue
        .then((_) async {
          final current = await getEntries();
          current.removeWhere((e) => e.id == id || e.correlationId == id);
          _cachedEntries = List.from(current);
          await _saveEntriesRaw(current);
          _streamController.add(List.unmodifiable(current));
        })
        .catchError((e) {
          debugPrint('[CallHistoryRepository] Error in deleteEntry: $e');
        });

    return _writeQueue;
  }

  @override
  Future<void> clearAll() {
    _writeQueue = _writeQueue
        .then((_) async {
          final prefs = await _getPrefs();
          await prefs.remove(prefKey);
          _cachedEntries = [];
          _streamController.add([]);
        })
        .catchError((e) {
          debugPrint('[CallHistoryRepository] Error in clearAll: $e');
        });

    return _writeQueue;
  }

  Future<void> _saveEntriesRaw(List<CallHistoryEntry> entries) async {
    try {
      final prefs = await _getPrefs();
      final payload = {
        'schemaVersion': currentSchemaVersion,
        'updatedAt': DateTime.now().toIso8601String(),
        'entries': entries.map((e) => e.toJson()).toList(),
      };
      await prefs.setString(prefKey, jsonEncode(payload));
    } catch (e) {
      debugPrint('[CallHistoryRepository] Error serializing call history: $e');
    }
  }

  void dispose() {
    _streamController.close();
  }
}
