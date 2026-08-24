import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

/// Secure storage wrapper for sensitive data like API keys
/// Uses platform-specific secure storage (Keychain on iOS, KeyStore on Android)
class SecureStorage {
  static final Map<String, String> _debugFallbackStore = {};
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // API Key Storage
  static Future<void> saveApiKey(String provider, String apiKey) async {
    final storageKey = 'api_key_$provider';
    try {
      await _storage.write(key: storageKey, value: apiKey);
      _debugFallbackStore[storageKey] = apiKey;
    } catch (e) {
      debugPrint('Failed to save API key: $e');
      if (kDebugMode) {
        _debugFallbackStore[storageKey] = apiKey;
        return;
      }
      rethrow;
    }
  }

  static Future<String?> getApiKey(String provider) async {
    final storageKey = 'api_key_$provider';
    try {
      final value = await _storage.read(key: storageKey);
      return value ?? _debugFallbackStore[storageKey];
    } catch (e) {
      debugPrint('Failed to read API key: $e');
      return _debugFallbackStore[storageKey];
    }
  }

  static Future<void> deleteApiKey(String provider) async {
    final storageKey = 'api_key_$provider';
    _debugFallbackStore.remove(storageKey);
    try {
      await _storage.delete(key: storageKey);
    } catch (e) {
      debugPrint('Failed to delete API key: $e');
    }
  }

  // Clear all secure storage (useful for logout/reset)
  static Future<void> clearAll() async {
    _debugFallbackStore.clear();
    try {
      await _storage.deleteAll();
    } catch (e) {
      debugPrint('Failed to clear secure storage: $e');
    }
  }

  // Check if provider has API key stored
  static Future<bool> hasApiKey(String provider) async {
    final key = await getApiKey(provider);
    return key != null && key.isNotEmpty;
  }

  // Get all stored provider keys (for UI display)
  static Future<List<String>> getStoredProviders() async {
    try {
      final all = await _storage.readAll();
      final keys = {...all.keys, ..._debugFallbackStore.keys};
      return keys
          .where((key) => key.startsWith('api_key_'))
          .map((key) => key.replaceFirst('api_key_', ''))
          .toList();
    } catch (e) {
      debugPrint('Failed to get stored providers: $e');
      return _debugFallbackStore.keys
          .where((key) => key.startsWith('api_key_'))
          .map((key) => key.replaceFirst('api_key_', ''))
          .toList();
    }
  }
}
