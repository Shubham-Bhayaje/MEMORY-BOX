import 'package:flutter_test/flutter_test.dart';
import 'package:memorybox/models/memory.dart';

void main() {
  group('Memory Model Tests', () {
    test('Memory Serialization and Deserialization with AIAnalysis', () {
      final now = DateTime.parse('2026-05-22T20:00:00.000Z');
      final original = Memory(
        id: 'test-id',
        type: MemoryType.photo,
        title: 'Original Photo Title',
        content: 'Original note content text.',
        mediaPath: '/path/to/original.jpg',
        aiAnalysis: AIAnalysis(
          description: 'A beautiful mountain scenery description.',
          extractedText: 'Mountain peak 4000m',
          extractedUrls: ['https://mountain.com'],
          tags: ['nature', 'scenery', 'hiking'],
        ),
        tags: ['original', 'tag'],
        createdAt: now,
      );

      final map = original.toMap();
      expect(map['id'], 'test-id');
      expect(map['type'], 'photo');
      expect(map['title'], 'Original Photo Title');
      expect(map['content'], 'Original note content text.');
      expect(map['media_path'], '/path/to/original.jpg');
      expect(map['tags'], 'original,tag');
      expect(map['created_at'], '2026-05-22T20:00:00.000Z');

      final deserialized = Memory.fromMap(map);
      expect(deserialized.id, 'test-id');
      expect(deserialized.type, MemoryType.photo);
      expect(deserialized.title, 'Original Photo Title');
      expect(deserialized.content, 'Original note content text.');
      expect(deserialized.mediaPath, '/path/to/original.jpg');
      expect(deserialized.tags, containsAll(['original', 'tag']));
      expect(deserialized.createdAt, now);

      expect(deserialized.aiAnalysis, isNotNull);
      expect(
        deserialized.aiAnalysis!.description,
        'A beautiful mountain scenery description.',
      );
      expect(deserialized.aiAnalysis!.extractedText, 'Mountain peak 4000m');
      expect(
        deserialized.aiAnalysis!.extractedUrls,
        contains('https://mountain.com'),
      );
      expect(
        deserialized.aiAnalysis!.tags,
        containsAll(['nature', 'scenery', 'hiking']),
      );
    });

    test('Memory Serialization and Deserialization without AIAnalysis', () {
      final now = DateTime.parse('2026-05-22T21:00:00.000Z');
      final original = Memory(
        id: 'test-id-no-ai',
        type: MemoryType.text,
        title: 'Quick Note',
        content: 'Just a text note.',
        tags: [],
        createdAt: now,
      );

      final map = original.toMap();
      expect(map['ai_analysis'], isNull);

      final deserialized = Memory.fromMap(map);
      expect(deserialized.id, 'test-id-no-ai');
      expect(deserialized.aiAnalysis, isNull);
      expect(deserialized.tags, isEmpty);
    });
  });

  group('Memory mediaPaths Tests', () {
    test('Single media path returns list with one element', () {
      final memory = Memory(
        id: 'single',
        type: MemoryType.photo,
        title: 'Single Photo',
        content: '',
        mediaPath: '/path/to/photo.jpg',
        tags: [],
        createdAt: DateTime.now(),
      );

      expect(memory.mediaPaths, ['/path/to/photo.jpg']);
      expect(memory.hasMultipleMedia, isFalse);
    });

    test('Pipe-delimited paths return multiple elements', () {
      final memory = Memory(
        id: 'multi',
        type: MemoryType.photo,
        title: 'Multi Photo',
        content: '',
        mediaPath: '/path/photo1.jpg|/path/photo2.jpg|/path/photo3.jpg',
        tags: [],
        createdAt: DateTime.now(),
      );

      expect(memory.mediaPaths, ['/path/photo1.jpg', '/path/photo2.jpg', '/path/photo3.jpg']);
      expect(memory.hasMultipleMedia, isTrue);
    });

    test('Null mediaPath returns empty list', () {
      final memory = Memory(
        id: 'null-media',
        type: MemoryType.text,
        title: 'Text Note',
        content: 'Some text',
        mediaPath: null,
        tags: [],
        createdAt: DateTime.now(),
      );

      expect(memory.mediaPaths, isEmpty);
      expect(memory.hasMultipleMedia, isFalse);
    });

    test('Empty string mediaPath returns empty list', () {
      final memory = Memory(
        id: 'empty-media',
        type: MemoryType.text,
        title: 'Empty media',
        content: '',
        mediaPath: '',
        tags: [],
        createdAt: DateTime.now(),
      );

      expect(memory.mediaPaths, isEmpty);
      expect(memory.hasMultipleMedia, isFalse);
    });

    test('Pipe-delimited paths with whitespace are trimmed', () {
      final memory = Memory(
        id: 'spaces',
        type: MemoryType.photo,
        title: 'Spaced paths',
        content: '',
        mediaPath: ' /a.jpg | /b.jpg ',
        tags: [],
        createdAt: DateTime.now(),
      );

      expect(memory.mediaPaths, ['/a.jpg', '/b.jpg']);
    });
  });
}
