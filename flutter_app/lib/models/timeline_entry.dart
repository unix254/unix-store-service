import 'package:intl/intl.dart';

class TimelineEntry {
  final String id;
  final String requisitionId;
  final String entryType; // 'system' | 'comment'
  final String? actorName;
  final String message;
  final DateTime createdAt;

  const TimelineEntry({
    required this.id,
    required this.requisitionId,
    required this.entryType,
    this.actorName,
    required this.message,
    required this.createdAt,
  });

  factory TimelineEntry.fromJson(Map<String, dynamic> j) => TimelineEntry(
        id:             j['id'] as String,
        requisitionId:  j['requisition_id'] as String,
        entryType:      j['entry_type'] as String? ?? 'system',
        actorName:      j['actor_name'] as String?,
        message:        j['message'] as String,
        createdAt:      DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      );

  bool get isSystem  => entryType == 'system';
  bool get isComment => entryType == 'comment';

  String get formattedTime => DateFormat('dd MMM, HH:mm').format(createdAt.toLocal());
}
