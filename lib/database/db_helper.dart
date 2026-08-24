import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/memory.dart';
import '../utils/secure_storage.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  static String databaseName = 'memory_box.db';
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final String path;
    if (databaseName == inMemoryDatabasePath) {
      path = inMemoryDatabasePath;
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, databaseName);
    }

    return await openDatabase(
      path,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        try {
          await db.execute('''
            UPDATE memories 
            SET type = 'screenshot' 
            WHERE type = 'photo' 
              AND (
                tags LIKE '%screenshot%' 
                OR media_path LIKE '%screenshot%' 
                OR media_path LIKE '%screencap%'
                OR title LIKE '%screen capture%'
              )
          ''');
        } catch (_) {}
      },
    );
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create memories table
    await db.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        media_path TEXT,
        ai_analysis TEXT,
        tags TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Create settings table
    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY DEFAULT 1,
        provider TEXT NOT NULL,
        api_key TEXT,
        api_endpoint TEXT,
        model_name TEXT,
        use_system_stt INTEGER DEFAULT 1,
        system_overlay_enabled INTEGER DEFAULT 0,
        pending_overlay_action TEXT
      )
    ''');

    // Create provider_configs table
    await db.execute('''
      CREATE TABLE provider_configs (
        provider TEXT PRIMARY KEY,
        api_key TEXT,
        api_endpoint TEXT,
        model_name TEXT
      )
    ''');

    // Insert default settings
    await db.insert('settings', {
      'id': 1,
      'provider': 'github', // Default provider
      'api_key': '',
      'api_endpoint': 'https://models.github.ai/inference',
      'model_name': 'openai/gpt-4o-mini',
      'use_system_stt': 1,
      'system_overlay_enabled': 0,
    });

    // Populate default configurations for all providers
    final providers = [
      {
        'provider': 'local',
        'api_key': '',
        'api_endpoint': 'http://localhost:11434',
        'model_name': 'gemma3:4b',
      },
      {
        'provider': 'github',
        'api_key': '',
        'api_endpoint': 'https://models.github.ai/inference',
        'model_name': 'openai/gpt-4o-mini',
      },
      {
        'provider': 'openai',
        'api_key': '',
        'api_endpoint': 'https://api.openai.com/v1',
        'model_name': 'gpt-4o-mini',
      },
      {
        'provider': 'gemini',
        'api_key': '',
        'api_endpoint': 'https://generativelanguage.googleapis.com',
        'model_name': 'gemini-1.5-flash',
      },
      {
        'provider': 'claude',
        'api_key': '',
        'api_endpoint': 'https://api.anthropic.com/v1',
        'model_name': 'claude-3-5-sonnet-20241022',
      },
      {
        'provider': 'huggingface',
        'api_key': '',
        'api_endpoint': 'https://router.huggingface.co/v1',
        'model_name': 'meta-llama/Llama-3.3-70B-Instruct',
      },
    ];

    for (final p in providers) {
      await db.insert('provider_configs', p);
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Create provider_configs table if migrating from version 1
      await db.execute('''
        CREATE TABLE provider_configs (
          provider TEXT PRIMARY KEY,
          api_key TEXT,
          api_endpoint TEXT,
          model_name TEXT
        )
      ''');

      // Populate default configurations
      final providers = [
        {
          'provider': 'local',
          'api_key': '',
          'api_endpoint': 'http://localhost:11434',
          'model_name': 'gemma3:4b',
        },
        {
          'provider': 'github',
          'api_key': '',
          'api_endpoint': 'https://models.github.ai/inference',
          'model_name': 'openai/gpt-4o-mini',
        },
        {
          'provider': 'openai',
          'api_key': '',
          'api_endpoint': 'https://api.openai.com/v1',
          'model_name': 'gpt-4o-mini',
        },
        {
          'provider': 'gemini',
          'api_key': '',
          'api_endpoint': 'https://generativelanguage.googleapis.com',
          'model_name': 'gemini-1.5-flash',
        },
        {
          'provider': 'claude',
          'api_key': '',
          'api_endpoint': 'https://api.anthropic.com/v1',
          'model_name': 'claude-3-5-sonnet-20241022',
        },
      ];

      for (final p in providers) {
        await db.insert(
          'provider_configs',
          p,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // Migrate existing active settings in 'settings' table to the corresponding provider's configuration
      final List<Map<String, dynamic>> currentSettings = await db.query(
        'settings',
        where: 'id = 1',
      );
      if (currentSettings.isNotEmpty) {
        final currentProvider =
            currentSettings[0]['provider'] as String? ?? 'github';
        final apiKey = currentSettings[0]['api_key'] as String? ?? '';
        final apiEndpoint = currentSettings[0]['api_endpoint'] as String? ?? '';
        final modelName = currentSettings[0]['model_name'] as String? ?? '';

        await db.update(
          'provider_configs',
          {
            'api_key': apiKey,
            'api_endpoint': apiEndpoint,
            'model_name': modelName,
          },
          where: 'provider = ?',
          whereArgs: [currentProvider],
        );
      }
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE settings ADD COLUMN use_system_stt INTEGER DEFAULT 1',
      );
    }
    if (oldVersion < 4) {
      try {
        await db.execute(
          'ALTER TABLE settings ADD COLUMN system_overlay_enabled INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 5) {
      try {
        await db.execute(
          'ALTER TABLE settings ADD COLUMN pending_overlay_action TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 6) {
      await _migrateApiKeysToSecureStorage(db);
    }
  }

  Future<void> _migrateApiKeysToSecureStorage(Database db) async {
    try {
      final settingsRows = await db.query('settings', where: 'id = 1');
      if (settingsRows.isNotEmpty) {
        final provider = settingsRows.first['provider'] as String? ?? 'github';
        final apiKey = settingsRows.first['api_key'] as String? ?? '';
        if (apiKey.isNotEmpty) {
          await SecureStorage.saveApiKey(provider, apiKey);
        }
      }

      final providerRows = await db.query('provider_configs');
      for (final row in providerRows) {
        final provider = row['provider'] as String?;
        final apiKey = row['api_key'] as String? ?? '';
        if (provider != null && provider.isNotEmpty && apiKey.isNotEmpty) {
          await SecureStorage.saveApiKey(provider, apiKey);
        }
      }

      await db.update('settings', {'api_key': ''}, where: 'id = 1');
      await db.update('provider_configs', {'api_key': ''});
    } catch (_) {
      // Keep migration non-fatal so old databases can still open.
    }
  }

  // --- MEMORY OPERATIONS ---

  Future<int> insertMemory(Memory memory) async {
    final db = await database;
    return await db.insert(
      'memories',
      memory.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Memory>> getMemories({String? search, String? type}) async {
    final db = await database;
    String? whereClause;
    List<dynamic>? whereArgs;

    if (search != null && search.isNotEmpty && type != null && type != 'all') {
      whereClause =
          '(title LIKE ? OR content LIKE ? OR tags LIKE ? OR ai_analysis LIKE ?) AND type = ?';
      whereArgs = ['%$search%', '%$search%', '%$search%', '%$search%', type];
    } else if (search != null && search.isNotEmpty) {
      whereClause =
          'title LIKE ? OR content LIKE ? OR tags LIKE ? OR ai_analysis LIKE ?';
      whereArgs = ['%$search%', '%$search%', '%$search%', '%$search%'];
    } else if (type != null && type != 'all') {
      whereClause = 'type = ?';
      whereArgs = [type];
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'memories',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) {
      return Memory.fromMap(maps[i]);
    });
  }

  Future<int> deleteMemory(String id) async {
    final db = await database;
    return await db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> purgeAllMemories() async {
    final db = await database;
    return await db.delete('memories');
  }

  Future<String> exportAllDataAsJson() async {
    final memories = await getMemories();
    final data = {
      'exported_at': DateTime.now().toIso8601String(),
      'version': '1.0.0',
      'total_memories': memories.length,
      'memories': memories.map((m) => m.toMap()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<String> exportMemoriesAsMarkdown() async {
    final memories = await getMemories();
    final buffer = StringBuffer();
    buffer.writeln('# Memory Box Vault Export');
    buffer.writeln('Exported on: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total Memories: ${memories.length}\n');

    for (final memory in memories) {
      buffer.writeln('## [${memory.type.name.toUpperCase()}] ${memory.title}');
      buffer.writeln('**Date:** ${memory.createdAt.toIso8601String()}');
      if (memory.tags.isNotEmpty) {
        buffer.writeln('**Tags:** ${memory.tags.map((t) => '#$t').join(' ')}');
      }
      if (memory.content.isNotEmpty) {
        buffer.writeln('\n${memory.content}\n');
      }
      if (memory.aiAnalysis != null) {
        buffer.writeln('### AI Analysis');
        buffer.writeln(memory.aiAnalysis!.description);
        if (memory.aiAnalysis!.extractedText.isNotEmpty) {
          buffer.writeln('\n*Extracted Text:*');
          buffer.writeln(memory.aiAnalysis!.extractedText);
        }
        if (memory.aiAnalysis!.extractedUrls.isNotEmpty) {
          buffer.writeln('\n*Extracted URLs:*');
          for (final url in memory.aiAnalysis!.extractedUrls) {
            buffer.writeln('- $url');
          }
        }
      }
      buffer.writeln('\n---\n');
    }
    return buffer.toString();
  }

  // --- SETTINGS OPERATIONS ---

  Future<Map<String, String>> getSettings() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'settings',
      where: 'id = 1',
    );

    if (maps.isNotEmpty) {
      final provider = maps[0]['provider'] as String? ?? 'github';
      final legacyApiKey = maps[0]['api_key'] as String? ?? '';
      var apiKey = await SecureStorage.getApiKey(provider) ?? '';

      if (apiKey.isEmpty && legacyApiKey.isNotEmpty) {
        await SecureStorage.saveApiKey(provider, legacyApiKey);
        await db.update('settings', {'api_key': ''}, where: 'id = 1');
        apiKey = legacyApiKey;
      }

      return {
        'provider': provider,
        'api_key': apiKey,
        'api_endpoint': maps[0]['api_endpoint'] as String? ?? '',
        'model_name': maps[0]['model_name'] as String? ?? '',
        'use_system_stt': maps[0]['use_system_stt']?.toString() ?? '1',
        'system_overlay_enabled':
            maps[0]['system_overlay_enabled']?.toString() ?? '0',
        'pending_overlay_action':
            maps[0]['pending_overlay_action'] as String? ?? '',
      };
    }
    return {
      'provider': 'github',
      'api_key': await SecureStorage.getApiKey('github') ?? '',
      'api_endpoint': 'https://models.github.ai/inference',
      'model_name': 'openai/gpt-4o-mini',
      'use_system_stt': '1',
      'system_overlay_enabled': '0',
      'pending_overlay_action': '',
    };
  }

  // --- PENDING OVERLAY ACTION OPERATIONS ---

  Future<int> updatePendingOverlayAction(String? action) async {
    final db = await database;
    return await db.update('settings', {
      'pending_overlay_action': action,
    }, where: 'id = 1');
  }

  Future<String?> getPendingOverlayAction() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'settings',
      columns: ['pending_overlay_action'],
      where: 'id = 1',
    );
    if (maps.isNotEmpty) {
      return maps[0]['pending_overlay_action'] as String?;
    }
    return null;
  }

  Future<int> updateSystemOverlayEnabled(bool enabled) async {
    final db = await database;
    return await db.update('settings', {
      'system_overlay_enabled': enabled ? 1 : 0,
    }, where: 'id = 1');
  }

  Future<int> saveSettings({
    required String provider,
    required String apiKey,
    required String apiEndpoint,
    required String modelName,
    bool? useSystemSTT,
  }) async {
    final db = await database;

    if (apiKey.trim().isEmpty) {
      await SecureStorage.deleteApiKey(provider);
    } else {
      await SecureStorage.saveApiKey(provider, apiKey.trim());
    }

    final Map<String, dynamic> updateData = {
      'provider': provider,
      'api_key': '',
      'api_endpoint': apiEndpoint,
      'model_name': modelName,
    };
    if (useSystemSTT != null) {
      updateData['use_system_stt'] = useSystemSTT ? 1 : 0;
    }

    await db.update('settings', updateData, where: 'id = 1');

    return await db.insert('provider_configs', {
      'provider': provider,
      'api_key': '',
      'api_endpoint': apiEndpoint,
      'model_name': modelName,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>?> getProviderConfig(String provider) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'provider_configs',
      where: 'provider = ?',
      whereArgs: [provider],
    );

    if (maps.isNotEmpty) {
      final legacyApiKey = maps[0]['api_key'] as String? ?? '';
      var apiKey = await SecureStorage.getApiKey(provider) ?? '';

      if (apiKey.isEmpty && legacyApiKey.isNotEmpty) {
        await SecureStorage.saveApiKey(provider, legacyApiKey);
        await db.update(
          'provider_configs',
          {'api_key': ''},
          where: 'provider = ?',
          whereArgs: [provider],
        );
        apiKey = legacyApiKey;
      }

      return {
        'provider': maps[0]['provider'] as String,
        'api_key': apiKey,
        'api_endpoint': maps[0]['api_endpoint'] as String? ?? '',
        'model_name': maps[0]['model_name'] as String? ?? '',
      };
    }
    return null;
  }
}
