import 'dart:convert';

enum MemoryType {
  text,
  voice,
  photo,
  screenshot;

  String toJson() => name;
  static MemoryType fromJson(String value) => MemoryType.values.byName(value);
}

class AIAnalysis {
  final String description;
  final String extractedText;
  final List<String> extractedUrls;
  final List<String> tags;

  AIAnalysis({
    required this.description,
    required this.extractedText,
    required this.extractedUrls,
    required this.tags,
  });

  Map<String, dynamic> toMap() {
    return {
      'description': description,
      'extracted_text': extractedText,
      'extracted_urls': extractedUrls,
      'tags': tags,
    };
  }

  factory AIAnalysis.fromMap(Map<String, dynamic> map) {
    return AIAnalysis(
      description: map['description'] ?? '',
      extractedText: map['extracted_text'] ?? '',
      extractedUrls: List<String>.from(map['extracted_urls'] ?? []),
      tags: List<String>.from(map['tags'] ?? []),
    );
  }

  String toJson() => json.encode(toMap());
  factory AIAnalysis.fromJson(String source) =>
      AIAnalysis.fromMap(json.decode(source));
}

class Memory {
  final String id;
  final MemoryType type;
  final String title;
  final String content;
  final String? mediaPath;
  final AIAnalysis? aiAnalysis;
  final List<String> tags;
  final DateTime createdAt;
  final bool isPinned;

  Memory({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    this.mediaPath,
    this.aiAnalysis,
    required this.tags,
    required this.createdAt,
    this.isPinned = false,
  });

  /// Returns all media file paths for this memory.
  /// Supports pipe-separated multiple paths (`path1|path2`) as well as single paths.
  List<String> get mediaPaths {
    if (mediaPath == null || mediaPath!.trim().isEmpty) return [];
    if (mediaPath!.contains('|')) {
      return mediaPath!
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [mediaPath!];
  }

  /// Whether this memory contains more than one media attachment.
  bool get hasMultipleMedia => mediaPaths.length > 1;

  Memory copyWith({
    String? id,
    MemoryType? type,
    String? title,
    String? content,
    String? mediaPath,
    AIAnalysis? aiAnalysis,
    List<String>? tags,
    DateTime? createdAt,
    bool? isPinned,
  }) {
    return Memory(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      mediaPath: mediaPath ?? this.mediaPath,
      aiAnalysis: aiAnalysis ?? this.aiAnalysis,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.toJson(),
      'title': title,
      'content': content,
      'media_path': mediaPath,
      'ai_analysis': aiAnalysis?.toJson(),
      'tags': tags.join(','),
      'created_at': createdAt.toIso8601String(),
      'is_pinned': isPinned ? 1 : 0,
    };
  }

  factory Memory.fromMap(Map<String, dynamic> map) {
    final aiAnalysisStr = map['ai_analysis'] as String?;
    final tagsStr = map['tags'] as String? ?? '';

    return Memory(
      id: map['id'],
      type: MemoryType.fromJson(map['type']),
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      mediaPath: map['media_path'],
      aiAnalysis: aiAnalysisStr != null && aiAnalysisStr.isNotEmpty
          ? AIAnalysis.fromJson(aiAnalysisStr)
          : null,
      tags: tagsStr.isEmpty ? [] : tagsStr.split(','),
      createdAt: DateTime.parse(map['created_at']),
      isPinned: map['is_pinned'] == 1 || map['is_pinned'] == true,
    );
  }
}
