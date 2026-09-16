import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:memorybox/models/memory.dart';

void main() {
  group('Multi-Photo Chat Citation & Processing Tests', () {
    final now = DateTime.parse('2026-05-22T20:00:00.000Z');

    final multiPhotoMemory = Memory(
      id: 'mem-multi-1',
      type: MemoryType.photo,
      title: 'Trip to Mountain Peaks',
      content: 'Breathtaking sunrise views over the mountain range.',
      mediaPath: '/storage/photo1.jpg|/storage/photo2.jpg|/storage/photo3.jpg',
      tags: ['travel', 'mountains'],
      createdAt: now,
      aiAnalysis: AIAnalysis(
        description: 'Set of 3 photos showing mountain summits, alpine lake, and sunset.',
        extractedText: 'Trail elevation 3500m',
        extractedUrls: [],
        tags: ['mountains', 'lake'],
      ),
    );

    final singlePhotoMemory = Memory(
      id: 'mem-single-1',
      type: MemoryType.photo,
      title: 'Family Dinner',
      content: 'Pasta night at home.',
      mediaPath: '/storage/dinner.jpg',
      tags: ['family', 'dinner'],
      createdAt: now,
    );

    final screenshotMemory = Memory(
      id: 'mem-screenshot-1',
      type: MemoryType.screenshot,
      title: 'Flight Confirmation',
      content: 'Flight UA1234 to SFO',
      mediaPath: '/storage/flight_pass.png|/storage/receipt.png',
      tags: ['travel', 'flight'],
      createdAt: now,
    );

    final allMemories = [multiPhotoMemory, singlePhotoMemory, screenshotMemory];

    test('Multi-photo memory reports correct count and multiple flag', () {
      expect(multiPhotoMemory.hasMultipleMedia, isTrue);
      expect(multiPhotoMemory.mediaPaths.length, 3);
      expect(multiPhotoMemory.mediaPaths, [
        '/storage/photo1.jpg',
        '/storage/photo2.jpg',
        '/storage/photo3.jpg',
      ]);

      expect(singlePhotoMemory.hasMultipleMedia, isFalse);
      expect(singlePhotoMemory.mediaPaths.length, 1);
      expect(singlePhotoMemory.mediaPaths.first, '/storage/dinner.jpg');

      expect(screenshotMemory.hasMultipleMedia, isTrue);
      expect(screenshotMemory.mediaPaths.length, 2);
    });

    test('Citations with standard bold and type format are matched', () {
      final response =
          'Here are the photos found in your photo **Trip to Mountain Peaks** (Photo, May 22, 2026). Enjoy your memories!';

      final referenced = <Memory>[];
      final seenIds = <String>{};

      void addMemoryIfMatch(String title, String typeStr) {
        final cleanTitle = title
            .trim()
            .toLowerCase()
            .replaceAll('"', '')
            .replaceAll("'", '')
            .replaceAll('**', '')
            .replaceAll('*', '');
        final cleanType = typeStr.trim().toLowerCase();
        if (cleanTitle.isEmpty || cleanType.isEmpty) return;

        for (final memory in allMemories) {
          final memTitle = memory.title
              .toLowerCase()
              .replaceAll('"', '')
              .replaceAll("'", '');
          final memType = memory.type.name.toLowerCase();

          if (memType == cleanType) {
            if (memTitle == cleanTitle ||
                memTitle.contains(cleanTitle) ||
                cleanTitle.contains(memTitle)) {
              if (!seenIds.contains(memory.id)) {
                seenIds.add(memory.id);
                referenced.add(memory);
              }
            }
          }
        }
      }

      final citationRegex = RegExp(
        r'\*\*([^*]+)\*\*\s*\((Photo|Screenshot|Voice|Text),\s*[^)]+\)',
        caseSensitive: false,
        dotAll: true,
      );
      for (final match in citationRegex.allMatches(response)) {
        final title = (match.group(1) ?? '').replaceAll('\n', ' ');
        final typeStr = match.group(2) ?? '';
        addMemoryIfMatch(title, typeStr);
      }

      expect(referenced.length, 1);
      expect(referenced.first.id, 'mem-multi-1');
      expect(referenced.first.mediaPaths.length, 3);
    });

    test('Citations with only bold titles without parentheses are matched', () {
      final response =
          'I found 3 photos in your **Trip to Mountain Peaks** and 2 screenshots in **Flight Confirmation**.';

      final referenced = <Memory>[];
      final seenIds = <String>{};

      final boldTitleRegex = RegExp(r'\*\*([^*]+)\*\*');
      for (final match in boldTitleRegex.allMatches(response)) {
        final boldText = (match.group(1) ?? '')
            .trim()
            .toLowerCase()
            .replaceAll('"', '')
            .replaceAll("'", '');
        if (boldText.length < 3 ||
            boldText == 'memory title' ||
            boldText == 'title' ||
            boldText.startsWith('http')) {
          continue;
        }
        for (final memory in allMemories) {
          if (!seenIds.contains(memory.id)) {
            final memTitle = memory.title
                .toLowerCase()
                .replaceAll('"', '')
                .replaceAll("'", '')
                .trim();
            if (memTitle.isEmpty) continue;
            final matchTitle = memTitle.endsWith('...')
                ? memTitle.substring(0, memTitle.length - 3).trim()
                : memTitle;
            if (matchTitle == boldText ||
                (matchTitle.length >= 4 &&
                    (boldText.contains(matchTitle) ||
                        matchTitle.contains(boldText)))) {
              seenIds.add(memory.id);
              referenced.add(memory);
            }
          }
        }
      }

      expect(referenced.length, 2);
      expect(referenced.any((m) => m.id == 'mem-multi-1'), isTrue);
      expect(referenced.any((m) => m.id == 'mem-screenshot-1'), isTrue);
    });

    test('LLM serialization includes photo counts for multi-photo and single-photo', () {
      final dateFormat = DateFormat('MMM d, yyyy');

      String serialize(Memory m) {
        final formattedDate = dateFormat.format(m.createdAt);
        var desc = 'Type: ${m.type.name}\nTitle: ${m.title}\nDate: $formattedDate\n';
        if (m.type == MemoryType.photo || m.type == MemoryType.screenshot) {
          final photoCount = m.mediaPaths.length;
          if (photoCount > 1) {
            desc += 'Photos: $photoCount photos attached\n';
          } else if (photoCount == 1) {
            desc += 'Photos: 1 photo attached\n';
          }
        }
        if (m.content.isNotEmpty) desc += 'Content: ${m.content}\n';
        return desc;
      }

      final multiDesc = serialize(multiPhotoMemory);
      expect(multiDesc, contains('Photos: 3 photos attached'));

      final singleDesc = serialize(singlePhotoMemory);
      expect(singleDesc, contains('Photos: 1 photo attached'));

      final screenshotDesc = serialize(screenshotMemory);
      expect(screenshotDesc, contains('Photos: 2 photos attached'));
    });
  });
}
