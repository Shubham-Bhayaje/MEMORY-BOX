import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:memorybox/screens/floating_assistant.dart';
import 'package:memorybox/database/db_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Initialize sqflite ffi for tests
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('FloatingAssistantOverlay Tests', () {
    final GlobalKey screenshotKey = GlobalKey();

    setUp(() {
      DBHelper.databaseName = inMemoryDatabasePath;
    });

    tearDown(() async {
      await DBHelper().close();
    });

    Widget buildTestWidget({VoidCallback? onMemoryAdded}) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              RepaintBoundary(
                key: screenshotKey,
                child: const SizedBox(
                  width: 400,
                  height: 600,
                  child: Text('Background Content'),
                ),
              ),
              FloatingAssistantOverlay(
                screenshotKey: screenshotKey,
                onMemoryAdded: onMemoryAdded ?? () {},
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('Renders the assistant overlay bubble', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Check if the assistant bubble is present
      expect(find.byKey(const Key('assistant_bubble')), findsOneWidget);
    });

    testWidgets('Tapping the bubble opens and closes the menu', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Menu is initially closed, options shouldn't be visible
      expect(find.text('Add Note'), findsNothing);

      // Tap the floating bubble
      await tester.tap(find.byKey(const Key('assistant_bubble')));
      await tester.pumpAndSettle();

      // Menu should be open, showing option labels
      expect(find.text('Add Note'), findsOneWidget);
      expect(find.text('Pick Photo'), findsOneWidget);
      expect(find.text('Screenshot'), findsOneWidget);
      expect(find.text('Voice Note'), findsOneWidget);

      // Tap the bubble again to close it
      await tester.tap(find.byKey(const Key('assistant_bubble')));
      await tester.pumpAndSettle();

      expect(find.text('Add Note'), findsNothing);
    });

    testWidgets('Tapping Add Note option opens Note dialog', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap bubble to open menu
      await tester.tap(find.byKey(const Key('assistant_bubble')));
      await tester.pumpAndSettle();

      // Tap the "Add Note" option
      await tester.tap(find.text('Add Note'));
      await tester.pumpAndSettle();

      // Verify the Text Dialog Frame is opened
      expect(find.text('New Note'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2)); // Title and Content

      // Close the modal
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('New Note'), findsNothing);
    });

    testWidgets('Draggability updates bubble position', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Get initial position of the bubble
      final initialOffset = tester.getCenter(
        find.byKey(const Key('assistant_bubble')),
      );

      // Drag the bubble towards the left
      await tester.drag(
        find.byKey(const Key('assistant_bubble')),
        const Offset(-200, 50),
      );
      await tester.pumpAndSettle();

      // Position should be updated
      final updatedOffset = tester.getCenter(
        find.byKey(const Key('assistant_bubble')),
      );
      expect(updatedOffset.dy, isNot(equals(initialOffset.dy)));
    });
  });
}
