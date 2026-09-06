enum CallDirection { incoming, outgoing }

enum CallResult { answered, missed, declined, cancelled, noAnswer, failed }

class CallHistoryEntry {
  final String id;
  final String correlationId;
  final String localExtension;
  final String remoteNumber;
  final String remoteDisplayName;
  final CallDirection direction;
  final CallResult result;
  final DateTime startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final String? failureReason;

  const CallHistoryEntry({
    required this.id,
    required this.correlationId,
    required this.localExtension,
    required this.remoteNumber,
    this.remoteDisplayName = '',
    required this.direction,
    required this.result,
    required this.startedAt,
    this.answeredAt,
    this.endedAt,
    this.durationSeconds = 0,
    this.failureReason,
  });

  CallHistoryEntry copyWith({
    String? id,
    String? correlationId,
    String? localExtension,
    String? remoteNumber,
    String? remoteDisplayName,
    CallDirection? direction,
    CallResult? result,
    DateTime? startedAt,
    DateTime? answeredAt,
    DateTime? endedAt,
    int? durationSeconds,
    String? failureReason,
  }) {
    return CallHistoryEntry(
      id: id ?? this.id,
      correlationId: correlationId ?? this.correlationId,
      localExtension: localExtension ?? this.localExtension,
      remoteNumber: remoteNumber ?? this.remoteNumber,
      remoteDisplayName: remoteDisplayName ?? this.remoteDisplayName,
      direction: direction ?? this.direction,
      result: result ?? this.result,
      startedAt: startedAt ?? this.startedAt,
      answeredAt: answeredAt ?? this.answeredAt,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      failureReason: failureReason ?? this.failureReason,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'correlationId': correlationId,
      'localExtension': localExtension,
      'remoteNumber': remoteNumber,
      'remoteDisplayName': remoteDisplayName,
      'direction': direction.name,
      'result': result.name,
      'startedAt': startedAt.toIso8601String(),
      'answeredAt': answeredAt?.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'durationSeconds': durationSeconds,
      if (failureReason != null && failureReason!.isNotEmpty)
        'failureReason': failureReason,
    };
  }

  factory CallHistoryEntry.fromJson(Map<String, dynamic> json) {
    final dirStr = json['direction'] as String? ?? 'incoming';
    final direction = CallDirection.values.firstWhere(
      (e) => e.name.toLowerCase() == dirStr.toLowerCase(),
      orElse: () => CallDirection.incoming,
    );

    final resStr = json['result'] as String? ?? 'missed';
    final result = CallResult.values.firstWhere(
      (e) => e.name.toLowerCase() == resStr.toLowerCase(),
      orElse: () => CallResult.missed,
    );

    final startedAt = json['startedAt'] != null
        ? DateTime.tryParse(json['startedAt'] as String) ?? DateTime.now()
        : DateTime.now();

    final answeredAt = json['answeredAt'] != null
        ? DateTime.tryParse(json['answeredAt'] as String)
        : null;

    final endedAt = json['endedAt'] != null
        ? DateTime.tryParse(json['endedAt'] as String)
        : null;

    final durationSeconds = (json['durationSeconds'] as num?)?.toInt() ?? 0;

    return CallHistoryEntry(
      id: json['id'] as String? ?? '',
      correlationId: (json['correlationId'] as String? ?? '')
          .trim()
          .toLowerCase(),
      localExtension: json['localExtension'] as String? ?? '',
      remoteNumber: json['remoteNumber'] as String? ?? '',
      remoteDisplayName: json['remoteDisplayName'] as String? ?? '',
      direction: direction,
      result: result,
      startedAt: startedAt,
      answeredAt: answeredAt,
      endedAt: endedAt,
      durationSeconds: durationSeconds,
      failureReason: json['failureReason'] as String?,
    );
  }

  @override
  String toString() {
    return 'CallHistoryEntry(id: $id, correlationId: $correlationId, remote: $remoteNumber ($remoteDisplayName), dir: ${direction.name}, res: ${result.name}, dur: ${durationSeconds}s)';
  }
}
