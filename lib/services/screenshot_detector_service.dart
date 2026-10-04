import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Represents a newly detected screenshot from the device.
class DetectedScreenshot {
  final File file;
  final String name;
  final DateTime timestamp;

  const DetectedScreenshot({
    required this.file,
    required this.name,
    required this.timestamp,
  });
}

/// Service that listens for new screenshots taken on the device using
/// a native Android ContentObserver on MediaStore.Images.
class ScreenshotDetectorService {
  ScreenshotDetectorService._();
  static final ScreenshotDetectorService instance = ScreenshotDetectorService._();

  static const _eventChannel = EventChannel('com.memorybox.memorybox/screenshots');

  final StreamController<DetectedScreenshot> _controller =
      StreamController<DetectedScreenshot>.broadcast();
  StreamSubscription? _nativeSubscription;
  bool _initialized = false;
  bool _enabled = false;

  /// Stream of newly detected screenshots.
  Stream<DetectedScreenshot> get stream => _controller.stream;

  /// Whether screenshot detection is currently active.
  bool get isEnabled => _enabled;

  /// Initialize and start listening for screenshots.
  void init() {
    if (_initialized) return;
    _initialized = true;
    _enabled = true;

    _nativeSubscription = _eventChannel
        .receiveBroadcastStream()
        .listen(_handleNativeEvent, onError: (e) {
      debugPrint('ScreenshotDetector: native stream error: $e');
    });
  }

  /// Process incoming screenshot events from the native layer.
  void _handleNativeEvent(dynamic event) async {
    if (!_enabled) return;

    try {
      if (event is Map) {
        final path = event['path'] as String?;
        final name = event['name'] as String? ?? 'screenshot';
        final timestamp = event['timestamp'] as int? ?? 0;

        if (path == null || path.isEmpty) return;

        final file = File(path);
        if (!await file.exists()) {
          debugPrint('ScreenshotDetector: file does not exist: $path');
          return;
        }

        // Copy to app directory so it persists
        final copied = await _copyToAppDirectory(file);
        if (copied == null) return;

        final screenshot = DetectedScreenshot(
          file: copied,
          name: name,
          timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
        );

        _controller.add(screenshot);
      }
    } catch (e) {
      debugPrint('ScreenshotDetector: error processing event: $e');
    }
  }

  /// Copy the screenshot file to the app's documents directory.
  Future<File?> _copyToAppDirectory(File source) async {
    try {
      final size = await source.length();
      const maxSize = 50 * 1024 * 1024; // 50 MB
      if (size > maxSize) return null;

      final dir = await getApplicationDocumentsDirectory();
      final ext = source.path.split('.').last.toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      final safeExt = ext.isEmpty ? 'png' : ext;
      final newPath =
          '${dir.path}/screenshot_auto_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
      return await source.copy(newPath);
    } catch (e) {
      debugPrint('ScreenshotDetector: failed to copy file: $e');
      return null;
    }
  }

  /// Temporarily pause screenshot detection.
  void pause() => _enabled = false;

  /// Resume screenshot detection.
  void resume() => _enabled = true;

  /// Clean up resources.
  void dispose() {
    _nativeSubscription?.cancel();
    _controller.close();
    _initialized = false;
    _enabled = false;
  }
}
