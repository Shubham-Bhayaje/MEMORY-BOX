import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Represents content received from Android's share sheet.
class SharedContent {
  final String? text;
  final List<String>? urls;
  final List<File> images;
  final String suggestedType; // 'text', 'photo', 'screenshot'
  final List<String> autoTags;

  const SharedContent({
    this.text,
    this.urls,
    this.images = const [],
    this.suggestedType = 'text',
    this.autoTags = const [],
  });

  bool get hasImages => images.isNotEmpty;
  bool get hasText => text != null && text!.trim().isNotEmpty;
  bool get hasUrls => urls != null && urls!.isNotEmpty;
  bool get isEmpty => !hasImages && !hasText;
}

/// Service that listens for content shared from other apps via Android's
/// share sheet (ACTION_SEND / ACTION_SEND_MULTIPLE).
///
/// Handles both cold starts (app launched from share) and warm starts
/// (app already running when share arrives).
class ShareReceiverService {
  ShareReceiverService._();
  static final ShareReceiverService instance = ShareReceiverService._();

  final StreamController<SharedContent> _controller =
      StreamController<SharedContent>.broadcast();
  StreamSubscription? _warmSubscription;
  bool _initialized = false;

  /// Stream of shared content arriving from other apps.
  Stream<SharedContent> get stream => _controller.stream;

  /// URL regex for detecting links in shared text.
  static final RegExp _urlRegex = RegExp(
    r'https?://[^\s<>\"\)\]]+',
    caseSensitive: false,
  );

  /// Initialize the service. Call once from the app's main screen.
  void init() {
    if (_initialized) return;
    _initialized = true;

    // Cold start — app was launched directly from share sheet
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((List<SharedMediaFile> files) {
      if (files.isNotEmpty) {
        _handleIncoming(files);
      }
    }).catchError((e) {
      debugPrint('ShareReceiver: cold start error: $e');
    });

    // Warm start — app is already running, new share arrives
    _warmSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedMediaFile> files) {
      if (files.isNotEmpty) {
        _handleIncoming(files);
      }
    }, onError: (e) {
      debugPrint('ShareReceiver: warm start stream error: $e');
    });
  }

  /// Process incoming shared media files into a [SharedContent] object.
  Future<void> _handleIncoming(List<SharedMediaFile> files) async {
    try {
      String? sharedText;
      final List<String> extractedUrls = [];
      final List<File> sharedImages = [];
      final List<String> autoTags = ['shared'];
      String suggestedType = 'text';

      for (final file in files) {
        if (file.type == SharedMediaType.image) {
          // Image shared — copy to app sandbox
          final copied = await _copyToAppDirectory(file.path);
          if (copied != null) {
            sharedImages.add(copied);
          }
        } else if (file.type == SharedMediaType.url ||
            file.type == SharedMediaType.text) {
          // Text or URL shared
          final content = file.path; // For text type, path contains the text
          if (content.isNotEmpty) {
            // Check if it's actually a URL
            if (_urlRegex.hasMatch(content)) {
              final urls = _urlRegex
                  .allMatches(content)
                  .map((m) => m.group(0)!)
                  .toList();
              extractedUrls.addAll(urls);
              autoTags.add('link');
              // Keep full text (may contain URL + description)
              sharedText = (sharedText ?? '') +
                  (sharedText != null && sharedText.isNotEmpty ? '\n' : '') +
                  content;
            } else {
              sharedText = (sharedText ?? '') +
                  (sharedText != null && sharedText.isNotEmpty ? '\n' : '') +
                  content;
            }
          }
        } else if (file.type == SharedMediaType.file) {
          // Generic file — check if it's an image by extension
          final ext = file.path.toLowerCase().split('.').last;
          if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif']
              .contains(ext)) {
            final copied = await _copyToAppDirectory(file.path);
            if (copied != null) {
              sharedImages.add(copied);
            }
          }
        }
      }

      // Determine suggested type
      if (sharedImages.isNotEmpty) {
        suggestedType = 'photo';
        // Check if any image path suggests a screenshot
        for (final img in sharedImages) {
          final pathLower = img.path.toLowerCase();
          if (pathLower.contains('screenshot') ||
              pathLower.contains('screencap') ||
              pathLower.contains('screen_shot') ||
              pathLower.contains('screen-shot')) {
            suggestedType = 'screenshot';
            break;
          }
        }
      }

      final content = SharedContent(
        text: sharedText,
        urls: extractedUrls.isNotEmpty ? extractedUrls : null,
        images: sharedImages,
        suggestedType: suggestedType,
        autoTags: autoTags,
      );

      if (!content.isEmpty) {
        _controller.add(content);
      }

      // Reset the intent so it doesn't fire again on hot restart
      ReceiveSharingIntent.instance.reset();
    } catch (e) {
      debugPrint('ShareReceiver: error processing shared content: $e');
    }
  }

  /// Copy a shared file into the app's documents directory so it persists
  /// even after the source app revokes URI permissions.
  Future<File?> _copyToAppDirectory(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) {
        debugPrint('ShareReceiver: source file does not exist: $sourcePath');
        return null;
      }

      final size = await source.length();
      const maxSize = 50 * 1024 * 1024; // 50 MB
      if (size > maxSize) {
        debugPrint('ShareReceiver: file too large ($size bytes), skipping');
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final ext = sourcePath
          .split('.')
          .last
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      final safeExt = ext.isEmpty ? 'jpg' : ext;
      final newPath =
          '${dir.path}/shared_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
      final copied = await source.copy(newPath);
      return copied;
    } catch (e) {
      debugPrint('ShareReceiver: failed to copy file: $e');
      return null;
    }
  }

  /// Clean up resources.
  void dispose() {
    _warmSubscription?.cancel();
    _controller.close();
    _initialized = false;
  }
}
