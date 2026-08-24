import 'package:flutter_test/flutter_test.dart';
import 'package:memorybox/main.dart';
import 'package:memorybox/database/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Initialize sqflite ffi for tests
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    DBHelper.databaseName = inMemoryDatabasePath;
  });

  tearDown(() async {
    await DBHelper().close();
  });

  testWidgets('App launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MemoryBoxApp());
    expect(find.text('Memory Box'), findsOneWidget);
  });
}
