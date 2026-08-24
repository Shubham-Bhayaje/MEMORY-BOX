import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// File management utilities for safe and efficient file operations
class FileHelper {
  // File size limits
  static const int maxImageSize = 50 * 1024 * 1024; // 50MB
  static const int maxAudioSize = 100 * 1024 * 1024; // 100MB
  static const int minDiskSpace = 50 * 1024 * 1024; // 50MB minimum

  // Image compression settings
  static const int imageQuality = 70;
  static const int maxImageWidth = 1920;
  static const int maxImageHeight = 1080;

  /// Check available disk space
  static Future<int> getAvailableDiskSpace() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final stat = await dir.stat();
      return stat.size;
    } catch (e) {
      debugPrint('Failed to get disk space: $e');
      return 0;
    }
  }

  /// Check if there's enough disk space
  static Future<bool> hasEnoughDiskSpace() async {
    final available = await getAvailableDiskSpace();
    return available >= minDiskSpace;
  }

  /// Safely copy file with validation
  static Future<File?> safeFileCopy({
    required File source,
    required String destPath,
    int? maxSize,
  }) async {
    try {
      // Check if source exists
      if (!await source.exists()) {
        throw Exception('Source file not found');
      }

      // Check disk space
      if (!await hasEnoughDiskSpace()) {
        throw Exception(
          'Insufficient storage space (need at least ${minDiskSpace ~/ (1024 * 1024)}MB free)',
        );
      }

      // Check file size
      final size = await source.length();
      final limit = maxSize ?? maxImageSize;
      if (size > limit) {
        throw Exception('File too large (max ${limit ~/ (1024 * 1024)}MB)');
      }

      // Ensure destination directory exists
      final destFile = File(destPath);
      await destFile.parent.create(recursive: true);

      // Copy file
      return await source.copy(destPath);
    } catch (e) {
      debugPrint('File copy failed: $e');
      return null;
    }
  }

  /// Compress image file
  static Future<File?> compressImage({
    required File file,
    int quality = imageQuality,
    int? minWidth,
    int? minHeight,
  }) async {
    try {
      final targetPath = '${file.path}_compressed.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: quality,
        minWidth: minWidth ?? maxImageWidth,
        minHeight: minHeight ?? maxImageHeight,
        format: CompressFormat.jpeg,
      );

      if (result == null) {
        debugPrint('Image compression failed');
        return file; // Return original if compression fails
      }

      // Check if compressed version is actually smaller
      final originalSize = await file.length();
      final compressedSize = await result.length();

      if (compressedSize < originalSize) {
        // Delete original, use compressed
        try {
          await file.delete();
        } catch (e) {
          debugPrint('Failed to delete original file: $e');
        }
        return File(result.path);
      } else {
        // Original is smaller, delete compressed version
        try {
          await File(result.path).delete();
        } catch (e) {
          debugPrint('Failed to delete compressed file: $e');
        }
        return file;
      }
    } catch (e) {
      debugPrint('Image compression error: $e');
      return file; // Return original on error
    }
  }

  /// Get file size in human-readable format
  static String getFileSizeString(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Calculate total size of all memories
  static Future<int> calculateTotalMemorySize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      int totalSize = 0;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (e) {
            debugPrint('Failed to get size of ${entity.path}: $e');
          }
        }
      }

      return totalSize;
    } catch (e) {
      debugPrint('Failed to calculate total size: $e');
      return 0;
    }
  }

  /// Clean up old temporary files
  static Future<void> cleanupTempFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();

      await for (final entity in dir.list(recursive: false)) {
        if (entity is File) {
          final fileName = entity.path.split('/').last;

          // Delete temporary/compressed files older than 24 hours
          if (fileName.contains('_compressed') ||
              fileName.contains('temp_') ||
              fileName.contains('cache_')) {
            try {
              final stat = await entity.stat();
              final age = now.difference(stat.modified);

              if (age.inHours > 24) {
                await entity.delete();
                debugPrint('Deleted old temp file: $fileName');
              }
            } catch (e) {
              debugPrint('Failed to delete temp file: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Cleanup failed: $e');
    }
  }

  /// Delete file safely
  static Future<bool> safeDelete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to delete file: $e');
      return false;
    }
  }

  /// Check if file exists and is readable
  static Future<bool> isFileValid(String? path) async {
    if (path == null || path.isEmpty) return false;

    try {
      final file = File(path);
      return await file.exists() && await file.length() > 0;
    } catch (e) {
      return false;
    }
  }

  /// Get file extension
  static String getFileExtension(String path) {
    return path.split('.').last.toLowerCase();
  }

  /// Validate file type
  static bool isValidImageFile(String path) {
    final ext = getFileExtension(path);
    return ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext);
  }

  static bool isValidAudioFile(String path) {
    final ext = getFileExtension(path);
    return ['m4a', 'mp3', 'wav', 'aac', 'ogg'].contains(ext);
  }

  /// Export all memories to a backup file
  static Future<String?> createBackup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${dir.path}/backups');
      await backupDir.create(recursive: true);

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backupPath = '${backupDir.path}/backup_$timestamp.zip';

      // TODO: Implement ZIP creation logic
      // This would require adding archive package dependency

      return backupPath;
    } catch (e) {
      debugPrint('Backup creation failed: $e');
      return null;
    }
  }
}
