import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:memorybox/database/db_helper.dart';
import 'package:memorybox/models/memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Initialize ffi for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DBHelper Tests', () {
    late DBHelper dbHelper;

    setUp(() {
      DBHelper.databaseName = inMemoryDatabasePath;
      dbHelper = DBHelper();
    });

    tearDown(() async {
      await dbHelper.close();
    });

    test('Insert and Retrieve Note Memory', () async {
      final memory = Memory(
        id: 'test-id-1',
        type: MemoryType.text,
        title: 'Test Title Note',
        content: 'This is a test note to remember.',
        tags: ['test', 'note'],
        createdAt: DateTime.now(),
      );

      // Insert memory
      await dbHelper.insertMemory(memory);

      // Retrieve all memories
      final memories = await dbHelper.getMemories();
      expect(memories.any((m) => m.id == 'test-id-1'), isTrue);

      final retrieved = memories.firstWhere((m) => m.id == 'test-id-1');
      expect(retrieved.title, 'Test Title Note');
      expect(retrieved.content, 'This is a test note to remember.');
      expect(retrieved.type, MemoryType.text);
      expect(retrieved.tags, containsAll(['test', 'note']));

      // Cleanup
      await dbHelper.deleteMemory('test-id-1');
      final afterDelete = await dbHelper.getMemories();
      expect(afterDelete.any((m) => m.id == 'test-id-1'), isFalse);
    });

    test('Search Memories', () async {
      final note1 = Memory(
        id: 'test-search-1',
        type: MemoryType.text,
        title: 'Meeting about project Alpha',
        content: 'We discussed building a Flutter app.',
        tags: ['meeting', 'alpha'],
        createdAt: DateTime.now(),
      );

      final note2 = Memory(
        id: 'test-search-2',
        type: MemoryType.text,
        title: 'Recipe for pancakes',
        content: 'Mix milk, eggs, and flour.',
        tags: ['cooking', 'breakfast'],
        createdAt: DateTime.now(),
      );

      await dbHelper.insertMemory(note1);
      await dbHelper.insertMemory(note2);

      // Search for "Alpha"
      final searchAlpha = await dbHelper.getMemories(search: 'Alpha');
      expect(searchAlpha.length, 1);
      expect(searchAlpha.first.id, 'test-search-1');

      // Search for "recipe"
      final searchRecipe = await dbHelper.getMemories(search: 'recipe');
      expect(searchRecipe.length, 1);
      expect(searchRecipe.first.id, 'test-search-2');

      // Search for tag "breakfast"
      final searchBreakfast = await dbHelper.getMemories(search: 'breakfast');
      expect(searchBreakfast.length, 1);
      expect(searchBreakfast.first.id, 'test-search-2');

      // Filter by type "text"
      final filterText = await dbHelper.getMemories(type: 'text');
      expect(filterText.any((m) => m.id == 'test-search-1'), isTrue);
      expect(filterText.any((m) => m.id == 'test-search-2'), isTrue);

      // Cleanup
      await dbHelper.deleteMemory('test-search-1');
      await dbHelper.deleteMemory('test-search-2');
    });

    test('Settings Save and Retrieve with Provider Configs', () async {
      // Get initial settings
      final initial = await dbHelper.getSettings();
      expect(initial['provider'], isNotNull);

      // Save OpenAI settings
      await dbHelper.saveSettings(
        provider: 'openai',
        apiKey: 'sk-test-openai-key',
        apiEndpoint: 'https://api.openai.com/v1',
        modelName: 'gpt-4o-mini',
      );

      // Save Gemini settings
      await dbHelper.saveSettings(
        provider: 'gemini',
        apiKey: 'gemini-key-xyz',
        apiEndpoint: 'https://generativelanguage.googleapis.com',
        modelName: 'gemini-1.5-flash',
      );

      // Verify active settings is Gemini
      final active = await dbHelper.getSettings();
      expect(active['provider'], 'gemini');
      expect(active['api_key'], 'gemini-key-xyz');

      // Verify provider config for OpenAI was preserved
      final openaiConfig = await dbHelper.getProviderConfig('openai');
      expect(openaiConfig, isNotNull);
      expect(openaiConfig!['api_key'], 'sk-test-openai-key');
      expect(openaiConfig['api_endpoint'], 'https://api.openai.com/v1');
      expect(openaiConfig['model_name'], 'gpt-4o-mini');

      // Verify provider config for Gemini is correct
      final geminiConfig = await dbHelper.getProviderConfig('gemini');
      expect(geminiConfig, isNotNull);
      expect(geminiConfig!['api_key'], 'gemini-key-xyz');

      // Revert settings to original to avoid side effects
      await dbHelper.saveSettings(
        provider: initial['provider']!,
        apiKey: initial['api_key']!,
        apiEndpoint: initial['api_endpoint']!,
        modelName: initial['model_name']!,
      );
    });

    test('Settings Save and Retrieve use_system_stt toggle', () async {
      final initial = await dbHelper.getSettings();
      final initialUseSTT = initial['use_system_stt'];

      // Save setting with useSystemSTT: false
      await dbHelper.saveSettings(
        provider: initial['provider']!,
        apiKey: initial['api_key']!,
        apiEndpoint: initial['api_endpoint']!,
        modelName: initial['model_name']!,
        useSystemSTT: false,
      );

      // Verify it is saved as '0'
      final savedFalse = await dbHelper.getSettings();
      expect(savedFalse['use_system_stt'], '0');

      // Save setting with useSystemSTT: true
      await dbHelper.saveSettings(
        provider: initial['provider']!,
        apiKey: initial['api_key']!,
        apiEndpoint: initial['api_endpoint']!,
        modelName: initial['model_name']!,
        useSystemSTT: true,
      );

      // Verify it is saved as '1'
      final savedTrue = await dbHelper.getSettings();
      expect(savedTrue['use_system_stt'], '1');

      // Revert to initial
      await dbHelper.saveSettings(
        provider: initial['provider']!,
        apiKey: initial['api_key']!,
        apiEndpoint: initial['api_endpoint']!,
        modelName: initial['model_name']!,
        useSystemSTT: initialUseSTT == '1',
      );
    });

    test('Purge all memories and export data', () async {
      final memory1 = Memory(
        id: 'export-1',
        type: MemoryType.text,
        title: 'Project Architecture',
        content: 'Clean layered Flutter architecture.',
        tags: ['arch', 'flutter'],
        createdAt: DateTime.now(),
      );
      final memory2 = Memory(
        id: 'export-2',
        type: MemoryType.photo,
        title: 'Diagram',
        content: 'System diagram',
        tags: ['diagram'],
        createdAt: DateTime.now(),
      );

      await dbHelper.insertMemory(memory1);
      await dbHelper.insertMemory(memory2);

      // Verify JSON Export
      final jsonExport = await dbHelper.exportAllDataAsJson();
      expect(jsonExport, contains('Project Architecture'));
      expect(jsonExport, contains('Diagram'));
      expect(jsonExport, contains('total_memories": 2'));

      // Verify Markdown Export
      final mdExport = await dbHelper.exportMemoriesAsMarkdown();
      expect(mdExport, contains('# Memory Box Vault Export'));
      expect(mdExport, contains('## [TEXT] Project Architecture'));
      expect(mdExport, contains('## [PHOTO] Diagram'));

      // Purge all memories
      final deleted = await dbHelper.purgeAllMemories();
      expect(deleted, 2);

      final afterPurge = await dbHelper.getMemories();
      expect(afterPurge, isEmpty);
    });

    test('Pin Memories and Ordering', () async {
      final oldNormal = Memory(
        id: 'old-normal',
        type: MemoryType.text,
        title: 'Old Normal Note',
        content: '',
        tags: [],
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        isPinned: false,
      );

      final newNormal = Memory(
        id: 'new-normal',
        type: MemoryType.text,
        title: 'New Normal Note',
        content: '',
        tags: [],
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        isPinned: false,
      );

      final oldPinned = Memory(
        id: 'old-pinned',
        type: MemoryType.text,
        title: 'Old Pinned Note',
        content: '',
        tags: [],
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        isPinned: true,
      );

      await dbHelper.insertMemory(oldNormal);
      await dbHelper.insertMemory(newNormal);
      await dbHelper.insertMemory(oldPinned);

      final memories = await dbHelper.getMemories();
      expect(memories.length, 3);
      // Pinned note should be first even though it's older!
      expect(memories[0].id, 'old-pinned');
      expect(memories[1].id, 'new-normal');
      expect(memories[2].id, 'old-normal');

      // Toggle pin of newNormal to true
      await dbHelper.togglePin('newNormal', true);
      await dbHelper.togglePin('new-normal', true);
      final updatedMemories = await dbHelper.getMemories();
      expect(updatedMemories[0].id, 'new-normal');
      expect(updatedMemories[1].id, 'old-pinned');

      // Unpin old-pinned
      await dbHelper.togglePin('old-pinned', false);
      final unpinnedMemories = await dbHelper.getMemories();
      expect(unpinnedMemories[0].id, 'new-normal');
      expect(unpinnedMemories.last.id, 'old-pinned');

      await dbHelper.purgeAllMemories();
    });

    test('Biometric Lock Settings', () async {
      expect(await dbHelper.getBiometricLockEnabled(), isFalse);

      await dbHelper.setBiometricLockEnabled(true);
      expect(await dbHelper.getBiometricLockEnabled(), isTrue);

      final settings = await dbHelper.getSettings();
      expect(settings['biometric_lock_enabled'], '1');

      await dbHelper.setBiometricLockEnabled(false);
      expect(await dbHelper.getBiometricLockEnabled(), isFalse);
    });

    test('On This Day Memories Retrieval', () async {
      final now = DateTime.now();
      final anniversaryMemory = Memory(
        id: 'anniversary-1',
        type: MemoryType.text,
        title: 'Memory From Last Year',
        content: 'Historical thought',
        tags: ['past'],
        createdAt: DateTime(now.year - 1, now.month, now.day, 12, 0),
      );

      await dbHelper.insertMemory(anniversaryMemory);

      final onThisDay = await dbHelper.getOnThisDayMemories();
      expect(onThisDay.isNotEmpty, isTrue);
      expect(onThisDay.any((m) => m.id == 'anniversary-1'), isTrue);

      await dbHelper.purgeAllMemories();
    });

    test('Export Vault as ZIP archive', () async {
      final memory = Memory(
        id: 'zip-test-1',
        type: MemoryType.text,
        title: 'Note for ZIP Export',
        content: 'ZIP content verification',
        tags: ['zip'],
        createdAt: DateTime.now(),
      );

      await dbHelper.insertMemory(memory);

      final zipFile = await dbHelper.exportVaultAsZip();
      expect(await zipFile.exists(), isTrue);
      expect(await zipFile.length(), greaterThan(0));

      await zipFile.delete();
      await dbHelper.purgeAllMemories();
    });
  });
}
