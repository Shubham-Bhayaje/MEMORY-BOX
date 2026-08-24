import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

/// Centralized logging utility for the app
class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    level: kDebugMode ? Level.debug : Level.warning,
  );

  static final Logger _productionLogger = Logger(
    printer: SimplePrinter(),
    level: Level.error,
    output: _FileOutput(),
  );

  /// Log debug message
  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log info message
  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log warning message
  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
    if (!kDebugMode) {
      _productionLogger.w(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Log error message
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    if (!kDebugMode) {
      _productionLogger.e(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Log fatal error
  static void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
    _productionLogger.f(message, error: error, stackTrace: stackTrace);
  }

  /// Log API request
  static void apiRequest(
    String method,
    String url, {
    Map<String, dynamic>? headers,
  }) {
    debug('API Request: $method $url', headers);
  }

  /// Log API response
  static void apiResponse(int statusCode, String url, {dynamic body}) {
    if (statusCode >= 200 && statusCode < 300) {
      debug('API Response: $statusCode $url');
    } else {
      warning('API Response: $statusCode $url', body);
    }
  }

  /// Log database operation
  static void database(String operation, {dynamic data}) {
    debug('Database: $operation', data);
  }

  /// Log user action
  static void userAction(String action, {Map<String, dynamic>? metadata}) {
    info('User Action: $action', metadata);
  }
}

/// Custom output that writes logs to a file in production
class _FileOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    // TODO: Implement file writing logic
    // This would write logs to a file for later analysis
    for (final line in event.lines) {
      debugPrint(line);
    }
  }
}
