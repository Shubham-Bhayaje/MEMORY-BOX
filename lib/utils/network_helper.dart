import 'dart:io';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Network utility class for robust HTTP requests with retry logic
class NetworkHelper {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  /// Check if device has internet connectivity
  static Future<bool> hasConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        return false;
      }

      // Actually test connection by pinging a reliable server
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      debugPrint('Connection check failed: $e');
      return false;
    }
  }

  /// Make a retryable POST request with exponential backoff
  static Future<Response> retryablePost({
    required String url,
    required Map<String, dynamic>? data,
    Map<String, dynamic>? headers,
    int maxRetries = 3,
    Duration? timeout,
  }) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      try {
        final response = await _dio.post(
          url,
          data: data,
          options: Options(
            headers: headers,
            sendTimeout: timeout,
            receiveTimeout: timeout,
          ),
        );

        // If status code is OK or client error, don't retry
        if (response.statusCode! < 500) {
          return response;
        }

        // Server error, retry
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
        );
      } on DioException catch (e) {
        attempts++;

        // Don't retry on client errors or if max retries reached
        if (e.response?.statusCode != null && e.response!.statusCode! < 500) {
          rethrow;
        }

        if (attempts >= maxRetries) {
          rethrow;
        }

        // Exponential backoff: 1s, 2s, 4s, etc.
        final delay = Duration(seconds: (1 << (attempts - 1)));
        debugPrint(
          'Request failed, retrying in ${delay.inSeconds}s... (attempt $attempts/$maxRetries)',
        );
        await Future.delayed(delay);
      } catch (e) {
        attempts++;
        if (attempts >= maxRetries) {
          rethrow;
        }

        final delay = Duration(seconds: (1 << (attempts - 1)));
        await Future.delayed(delay);
      }
    }

    throw Exception('Max retries ($maxRetries) exceeded');
  }

  /// Make a retryable GET request
  static Future<Response> retryableGet({
    required String url,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    int maxRetries = 3,
    Duration? timeout,
  }) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      try {
        final response = await _dio.get(
          url,
          queryParameters: queryParameters,
          options: Options(headers: headers, receiveTimeout: timeout),
        );

        if (response.statusCode! < 500) {
          return response;
        }

        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
        );
      } on DioException catch (e) {
        attempts++;

        if (e.response?.statusCode != null && e.response!.statusCode! < 500) {
          rethrow;
        }

        if (attempts >= maxRetries) {
          rethrow;
        }

        final delay = Duration(seconds: (1 << (attempts - 1)));
        await Future.delayed(delay);
      } catch (e) {
        attempts++;
        if (attempts >= maxRetries) {
          rethrow;
        }

        final delay = Duration(seconds: (1 << (attempts - 1)));
        await Future.delayed(delay);
      }
    }

    throw Exception('Max retries ($maxRetries) exceeded');
  }

  /// Handle network errors with user-friendly messages
  static String getErrorMessage(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timeout. Please check your internet and try again.';

        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          if (statusCode == 401) {
            return 'Invalid API key. Please check your settings.';
          } else if (statusCode == 403) {
            return 'Access forbidden. Check your API permissions.';
          } else if (statusCode == 429) {
            return 'Too many requests. Please wait a moment.';
          } else if (statusCode != null && statusCode >= 500) {
            return 'Server error. Please try again later.';
          }
          return 'Request failed: ${error.response?.statusMessage ?? "Unknown error"}';

        case DioExceptionType.cancel:
          return 'Request cancelled.';

        case DioExceptionType.unknown:
          if (error.error is SocketException) {
            return 'No internet connection. Please check your network.';
          }
          return 'Connection error. Please check your internet and try again.';

        default:
          return 'Network error: ${error.message}';
      }
    }

    return 'Unexpected error: ${error.toString()}';
  }

  /// Check if error is recoverable (can retry)
  static bool isRecoverableError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.unknown:
          return true;

        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          return statusCode != null && statusCode >= 500;

        default:
          return false;
      }
    }

    return false;
  }

  /// Download file with progress callback
  static Future<void> downloadFile({
    required String url,
    required String savePath,
    Function(int received, int total)? onProgress,
  }) async {
    try {
      await _dio.download(url, savePath, onReceiveProgress: onProgress);
    } catch (e) {
      throw Exception('Failed to download file: ${getErrorMessage(e)}');
    }
  }
}
