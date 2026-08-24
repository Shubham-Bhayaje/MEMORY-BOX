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

  Memory({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    this.mediaPath,
    this.aiAnalysis,
    required this.tags,
    required this.createdAt,
  });

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
    );
  }
}
