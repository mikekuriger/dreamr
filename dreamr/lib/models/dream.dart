// models/dream.dart
import 'package:dreamr/constants.dart';

class Dream {
  final int id;
  final int userId;
  final String text;
  final String analysis;
  final String summary;
  final String tone;
  final String imagePrompt;
  final bool hidden;
  final DateTime createdAt;
  final String? imageFile;
  final String? imageTile;
  final String notes;
  final int? interpreterId;
  final String? interpreterName;
  final String? interpreterIcon;

  Dream({
    required this.id,
    required this.userId,
    required this.text,
    required this.analysis,
    required this.summary,
    required this.tone,
    required this.imagePrompt,
    required this.hidden,
    required this.createdAt,
    this.imageFile,
    this.imageTile,
    this.notes = "",
    this.interpreterId,
    this.interpreterName,
    this.interpreterIcon,
  });

  Dream copyWith({
    int? id,
    int? userId,
    String? text,
    String? analysis,
    String? summary,
    String? tone,
    String? imagePrompt,
    bool? hidden,
    DateTime? createdAt,
    String? imageFile,
    String? imageTile,
    String? notes,
    int? interpreterId,
    String? interpreterName,
    String? interpreterIcon,
  }) {
    return Dream(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      text: text ?? this.text,
      analysis: analysis ?? this.analysis,
      summary: summary ?? this.summary,
      tone: tone ?? this.tone,
      imagePrompt: imagePrompt ?? this.imagePrompt,
      hidden: hidden ?? this.hidden,
      createdAt: createdAt ?? this.createdAt,
      imageFile: imageFile ?? this.imageFile,
      imageTile: imageTile ?? this.imageTile,
      notes: notes ?? this.notes,
      interpreterId: interpreterId ?? this.interpreterId,
      interpreterName: interpreterName ?? this.interpreterName,
      interpreterIcon: interpreterIcon ?? this.interpreterIcon,
    );
  }

  factory Dream.fromJson(Map<String, dynamic> json) {
    return Dream(
      id: json['id'] ?? 0,
      userId: int.tryParse(json['user_id'].toString()) ?? 0,
      text: json['text'] ?? '',
      analysis: json['analysis'] ?? '',
      summary: json['summary'] ?? '',
      tone: json['tone'] ?? '',
      imagePrompt: json['image_prompt'] ?? '',
      hidden: json['hidden'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      imageFile: json['image_file'] != null
        ? '${AppConfig.baseUrl}${json['image_file']}'
        : null,
      imageTile: json['image_tile'] != null
        ? '${AppConfig.baseUrl}${json['image_tile']}'
        : null,
      notes: (json['notes'] as String?)?.trim() ?? "",
      interpreterId: json['interpreter_id'] is int
        ? json['interpreter_id'] as int
        : int.tryParse(json['interpreter_id']?.toString() ?? ''),
      interpreterName: (json['interpreter_name'] as String?)?.trim(),
      interpreterIcon: json['interpreter_icon'] != null
        ? (json['interpreter_icon'].toString().startsWith('http')
            ? json['interpreter_icon'] as String
            : '${AppConfig.baseUrl}${json['interpreter_icon']}')
        : null,
    );
  }
}

class User {
  String email;
  String? firstName;
  String? birthdate;
  String? gender;
  String? timezone;
  String? avatarUrl;
  bool muteAudio;

  User({
    required this.email,
    this.firstName,
    this.birthdate,
    this.gender,
    this.timezone,
    this.avatarUrl,
    this.muteAudio = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      email: json['email'],
      firstName: json['first_name'],
      birthdate: json['birthdate'],
      gender: json['gender'],
      timezone: json['timezone'],
      avatarUrl: json['avatar_url'],
      muteAudio: json['mute_audio'] == true || json['mute_audio'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'firstName': firstName,
      'birthdate': birthdate,
      'gender': gender,
      'timezone': timezone,
      'mute_audio': muteAudio ? 1 : 0,
    };
  }
}