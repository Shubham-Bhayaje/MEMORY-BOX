/// Rate limiter to prevent API abuse and control costs
class RateLimiter {
  final int maxRequestsPerMinute;
  final int maxRequestsPerHour;
  final Map<String, List<DateTime>> _requests = {};

  RateLimiter({this.maxRequestsPerMinute = 10, this.maxRequestsPerHour = 100});

  /// Check if request is allowed under rate limits
  Future<RateLimitResult> checkLimit(String userId) async {
    final now = DateTime.now();
    final userRequests = _requests[userId] ?? [];

    // Remove requests older than 1 hour
    userRequests.removeWhere((time) => now.difference(time).inHours >= 1);

    // Count requests in last minute
    final requestsLastMinute = userRequests
        .where((time) => now.difference(time).inSeconds < 60)
        .length;

    // Count requests in last hour
    final requestsLastHour = userRequests.length;

    // Check minute limit
    if (requestsLastMinute >= maxRequestsPerMinute) {
      final oldestInMinute = userRequests
          .where((time) => now.difference(time).inSeconds < 60)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final waitSeconds = 60 - now.difference(oldestInMinute).inSeconds;

      return RateLimitResult(
        allowed: false,
        reason:
            'Rate limit exceeded: $maxRequestsPerMinute requests per minute',
        waitSeconds: waitSeconds,
        remaining: 0,
      );
    }

    // Check hour limit
    if (requestsLastHour >= maxRequestsPerHour) {
      final oldestInHour = userRequests.reduce((a, b) => a.isBefore(b) ? a : b);
      final waitSeconds = 3600 - now.difference(oldestInHour).inSeconds;

      return RateLimitResult(
        allowed: false,
        reason: 'Rate limit exceeded: $maxRequestsPerHour requests per hour',
        waitSeconds: waitSeconds,
        remaining: 0,
      );
    }

    // Add request to history
    userRequests.add(now);
    _requests[userId] = userRequests;

    return RateLimitResult(
      allowed: true,
      remaining: maxRequestsPerMinute - requestsLastMinute - 1,
    );
  }

  /// Get current usage stats
  RateLimitStats getStats(String userId) {
    final now = DateTime.now();
    final userRequests = _requests[userId] ?? [];

    final requestsLastMinute = userRequests
        .where((time) => now.difference(time).inSeconds < 60)
        .length;
    final requestsLastHour = userRequests.length;

    return RateLimitStats(
      requestsLastMinute: requestsLastMinute,
      requestsLastHour: requestsLastHour,
      maxPerMinute: maxRequestsPerMinute,
      maxPerHour: maxRequestsPerHour,
    );
  }

  /// Reset rate limit for a user (admin function)
  void reset(String userId) {
    _requests.remove(userId);
  }

  /// Clear all rate limit data
  void clearAll() {
    _requests.clear();
  }
}

class RateLimitResult {
  final bool allowed;
  final String? reason;
  final int? waitSeconds;
  final int? remaining;

  RateLimitResult({
    required this.allowed,
    this.reason,
    this.waitSeconds,
    this.remaining,
  });
}

class RateLimitStats {
  final int requestsLastMinute;
  final int requestsLastHour;
  final int maxPerMinute;
  final int maxPerHour;

  RateLimitStats({
    required this.requestsLastMinute,
    required this.requestsLastHour,
    required this.maxPerMinute,
    required this.maxPerHour,
  });

  double get minuteUsagePercent =>
      (requestsLastMinute / maxPerMinute * 100).clamp(0, 100);

  double get hourUsagePercent =>
      (requestsLastHour / maxPerHour * 100).clamp(0, 100);
}
