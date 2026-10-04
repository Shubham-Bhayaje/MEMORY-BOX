import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memorybox/services/share_receiver_service.dart';
import 'package:memorybox/screens/add_memory_sheet.dart';

void main() {
  group('SharedContent Model', () {
    test('empty SharedContent reports isEmpty correctly', () {
      const content = SharedContent();
      expect(content.isEmpty, isTrue);
      expect(content.hasText, isFalse);
      expect(content.hasImages, isFalse);
      expect(content.hasUrls, isFalse);
    });

    test('SharedContent with text is not empty', () {
      const content = SharedContent(text: 'Hello from Chrome');
      expect(content.isEmpty, isFalse);
      expect(content.hasText, isTrue);
      expect(content.hasImages, isFalse);
    });

    test('SharedContent with images is not empty', () {
      final content = SharedContent(
        images: [File('/tmp/test.jpg')],
        suggestedType: 'photo',
      );
      expect(content.isEmpty, isFalse);
      expect(content.hasImages, isTrue);
      expect(content.hasText, isFalse);
    });

    test('SharedContent with URLs detects hasUrls', () {
      const content = SharedContent(
        text: 'Check this out https://example.com',
        urls: ['https://example.com'],
        autoTags: ['shared', 'link'],
      );
      expect(content.hasUrls, isTrue);
      expect(content.autoTags, contains('link'));
    });

    test('SharedContent with blank text is empty', () {
      const content = SharedContent(text: '   ');
      expect(content.hasText, isFalse);
      expect(content.isEmpty, isTrue);
    });

    test('SharedContent suggestedType defaults to text', () {
      const content = SharedContent(text: 'Hello');
      expect(content.suggestedType, 'text');
    });

    test('SharedContent suggestedType can be screenshot', () {
      final content = SharedContent(
        images: [File('/tmp/screenshot_123.png')],
        suggestedType: 'screenshot',
      );
      expect(content.suggestedType, 'screenshot');
    });
  });

  group('URL Detection Regex', () {
    final urlRegex = RegExp(
      r'https?://[^\s<>\"\)\]]+',
      caseSensitive: false,
    );

    test('detects HTTP URLs', () {
      const text = 'Visit http://example.com for more info';
      final matches = urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
      expect(matches, ['http://example.com']);
    });

    test('detects HTTPS URLs', () {
      const text = 'Check https://www.google.com/search?q=flutter';
      final matches = urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
      expect(matches.length, 1);
      expect(matches.first, startsWith('https://www.google.com'));
    });

    test('detects multiple URLs in text', () {
      const text = 'Links: https://a.com and https://b.org/page';
      final matches = urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
      expect(matches.length, 2);
    });

    test('returns no matches for plain text', () {
      const text = 'This is just regular text with no links';
      final matches = urlRegex.allMatches(text).toList();
      expect(matches, isEmpty);
    });
  });

  group('AddMemorySheet with shared content', () {
    testWidgets('renders with shared text pre-populated', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => AddMemorySheet(
                      initialType: 'text',
                      initialContent: 'Shared text from Chrome',
                      initialTags: const ['shared', 'link'],
                      autoProcess: false,
                      onMemoryAdded: () {},
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify "Save Shared Content" header appears
      expect(find.text('Save Shared Content'), findsOneWidget);

      // Verify "Shared from another app" badge
      expect(find.text('Shared from another app'), findsOneWidget);

      // Verify shared text appears in at least one TextField (both title and content get populated)
      final textFields = find.byType(TextField);
      expect(textFields, findsWidgets);

      // Both title and content should contain the shared text
      final titleField = find.byWidgetPredicate((w) =>
          w is TextField &&
          w.controller != null &&
          w.controller!.text.isNotEmpty &&
          w.decoration?.hintText == 'Title');
      expect(titleField, findsOneWidget);

      final contentField = find.byWidgetPredicate((w) =>
          w is TextField &&
          w.controller != null &&
          w.controller!.text == 'Shared text from Chrome' &&
          w.decoration?.hintText == "What's on your mind?");
      expect(contentField, findsOneWidget);
    });

    testWidgets('renders with shared images pre-populated', (tester) async {
      // Create a temporary test image file
      final tempDir = Directory.systemTemp.createTempSync('share_test_');
      final testImage = File('${tempDir.path}/test_photo.jpg');
      testImage.writeAsBytesSync([0xFF, 0xD8, 0xFF]); // Minimal JPEG header

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => AddMemorySheet(
                      initialType: 'photo',
                      initialImages: [testImage],
                      initialTags: const ['shared'],
                      autoProcess: false,
                      onMemoryAdded: () {},
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify "Save Shared Content" header appears
      expect(find.text('Save Shared Content'), findsOneWidget);

      // Verify share badge
      expect(find.text('Shared from another app'), findsOneWidget);

      // Clean up
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('does NOT show shared badge when not from share', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => AddMemorySheet(
                      initialType: 'text',
                      onMemoryAdded: () {},
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Normal capture header
      expect(find.text('Capture Memory'), findsOneWidget);

      // No share badge
      expect(find.text('Shared from another app'), findsNothing);
    });
  });
}
