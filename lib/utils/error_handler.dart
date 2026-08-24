import 'package:flutter/material.dart';
import 'logger.dart';

/// Centralized error handling with user-friendly messages
class ErrorHandler {
  /// Show user-friendly error dialog
  static void showErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
    String? technicalDetails,
    VoidCallback? onRetry,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 15, height: 1.5)),
            if (technicalDetails != null) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                title: const Text(
                  'Technical Details',
                  style: TextStyle(fontSize: 13),
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      technicalDetails,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          if (onRetry != null)
            TextButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                onRetry();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Show error snackbar (less intrusive)
  static void showErrorSnackBar(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onRetry,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        duration: duration,
        action: onRetry != null
            ? SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Handle and log errors
  static void handleError(
    String context,
    dynamic error,
    StackTrace? stackTrace,
  ) {
    AppLogger.error('Error in $context', error, stackTrace);

    // TODO: Send to crash reporting service (Crashlytics, Sentry)
    // if (!kDebugMode) {
    //   FirebaseCrashlytics.instance.recordError(error, stackTrace);
    // }
  }

  /// Get user-friendly error message from exception
  static String getUserMessage(dynamic error) {
    if (error is String) return error;

    final String errorStr = error.toString();

    // Network errors
    if (errorStr.contains('SocketException') ||
        errorStr.contains('Connection refused') ||
        errorStr.contains('Failed host lookup')) {
      return 'No internet connection. Please check your network and try again.';
    }

    if (errorStr.contains('TimeoutException') ||
        errorStr.contains('timed out')) {
      return 'Request timed out. Please try again.';
    }

    // API errors
    if (errorStr.contains('401') || errorStr.contains('Unauthorized')) {
      return 'Invalid API key. Please check your settings.';
    }

    if (errorStr.contains('403') || errorStr.contains('Forbidden')) {
      return 'Access denied. Please check your API permissions.';
    }

    if (errorStr.contains('429') || errorStr.contains('Too Many Requests')) {
      return 'Too many requests. Please wait a moment and try again.';
    }

    if (errorStr.contains('500') ||
        errorStr.contains('502') ||
        errorStr.contains('503')) {
      return 'Server error. The service is temporarily unavailable.';
    }

    // File errors
    if (errorStr.contains('File not found') ||
        errorStr.contains('No such file')) {
      return 'File not found. It may have been deleted.';
    }

    if (errorStr.contains('Insufficient storage') ||
        errorStr.contains('No space left')) {
      return 'Not enough storage space on your device.';
    }

    if (errorStr.contains('File too large')) {
      return 'File is too large. Maximum size is 50MB.';
    }

    // Database errors
    if (errorStr.contains('database') || errorStr.contains('sql')) {
      return 'Database error. Please try restarting the app.';
    }

    // Permission errors
    if (errorStr.contains('Permission denied') ||
        errorStr.contains('permission')) {
      return 'Permission denied. Please grant the required permissions.';
    }

    // Informative Exception message
    if (errorStr.startsWith('Exception: ')) {
      final msg = errorStr.substring('Exception: '.length).trim();
      if (msg.isNotEmpty && !msg.startsWith('{') && !msg.contains('Instance of') && msg.length < 160) {
        return msg;
      }
    }

    // Generic fallback
    return 'Something went wrong. Please try again.';
  }

  /// Wrap async operations with error handling
  static Future<T?> tryCatch<T>({
    required Future<T> Function() operation,
    required String context,
    T? Function(dynamic error)? onError,
  }) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      handleError(context, error, stackTrace);
      return onError?.call(error);
    }
  }

  /// Wrap sync operations with error handling
  static T? tryCatchSync<T>({
    required T Function() operation,
    required String context,
    T? Function(dynamic error)? onError,
  }) {
    try {
      return operation();
    } catch (error, stackTrace) {
      handleError(context, error, stackTrace);
      return onError?.call(error);
    }
  }
}
