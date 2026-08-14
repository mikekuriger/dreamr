// models/life_event.dart

class LifeEvent {
  final int id;
  final int userId;
  final DateTime occurredAt;
  final String title;
  final String? details;
  final List<String>? tags;
  final DateTime createdAt;

  LifeEvent({
    required this.id,
    required this.userId,
    required this.occurredAt,
    required this.title,
    this.details,
    this.tags,
    required this.createdAt,
  });

  LifeEvent copyWith({
    int? id,
    int? userId,
    DateTime? occurredAt,
    String? title,
    String? details,
    List<String>? tags,
    DateTime? createdAt,
  }) {
    return LifeEvent(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      occurredAt: occurredAt ?? this.occurredAt,
      title: title ?? this.title,
      details: details ?? this.details,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory LifeEvent.fromJson(Map<String, dynamic> json) {
    List<String>? parseTags(dynamic tagsData) {
      if (tagsData == null) return null;
      if (tagsData is List) return tagsData.map((e) => e.toString()).toList();
      if (tagsData is String) {
        if (tagsData.isEmpty) return null;
        return tagsData.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      return null;
    }

    return LifeEvent(
      id: json['id'] ?? 0,
      userId: int.tryParse(json['user_id'].toString()) ?? 0,
      occurredAt: DateTime.parse(json['occurred_at']),
      title: json['title'] ?? '',
      details: json['details'],
      tags: parseTags(json['tags']),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'occurred_at': occurredAt.toIso8601String(),
      'title': title,
      'details': details,
      'tags': tags?.join(','),
      'created_at': createdAt.toIso8601String(),
    };
  }
}