/// Input validation and sanitization utilities
class InputValidator {
  // Maximum lengths for different input types
  static const int maxTitleLength = 200;
  static const int maxContentLength = 50000;
  static const int maxTagLength = 50;
  static const int maxUrlLength = 2048;

  /// Sanitize user input to prevent injection attacks
  static String sanitize(String input, {int? maxLength}) {
    if (input.isEmpty) return '';

    // Remove dangerous characters that could cause issues
    String clean = input
        .replaceAll(
          RegExp(r'[\x00-\x08\x0B-\x0C\x0E-\x1F]'),
          '',
        ) // Control chars
        .trim();

    // Apply max length if specified
    if (maxLength != null && clean.length > maxLength) {
      clean = clean.substring(0, maxLength);
    }

    return clean;
  }

  /// Sanitize title specifically
  static String sanitizeTitle(String title) {
    return sanitize(title, maxLength: maxTitleLength);
  }

  /// Sanitize content specifically
  static String sanitizeContent(String content) {
    return sanitize(content, maxLength: maxContentLength);
  }

  /// Sanitize tag specifically
  static String sanitizeTag(String tag) {
    String clean = tag
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '') // Only alphanumeric, space, dash
        .replaceAll(RegExp(r'\s+'), '-') // Replace spaces with dashes
        .trim();
    return sanitize(clean, maxLength: maxTagLength);
  }

  /// Validate URL format
  static bool isValidUrl(String url) {
    if (url.isEmpty || url.length > maxUrlLength) return false;

    try {
      final uri = Uri.parse(url);
      return uri.isAbsolute &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Validate API endpoint
  static String? validateEndpoint(String url) {
    if (url.isEmpty) {
      return 'Endpoint cannot be empty';
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'Must start with http:// or https://';
    }

    try {
      final uri = Uri.parse(url);
      if (!uri.isAbsolute) {
        return 'Invalid URL format';
      }
      if (uri.host.isEmpty) {
        return 'Invalid hostname';
      }
    } catch (e) {
      return 'Malformed URL: ${e.toString()}';
    }

    return null; // Valid
  }

  /// Validate API key format (basic check)
  static String? validateApiKey(String key, String provider) {
    if (key.isEmpty) {
      return 'API key cannot be empty';
    }

    // Provider-specific validation
    switch (provider) {
      case 'openai':
        if (!key.startsWith('sk-')) {
          return 'OpenAI API keys should start with "sk-"';
        }
        if (key.length < 20) {
          return 'API key seems too short';
        }
        break;
      case 'github':
        final validPrefix =
            key.startsWith('github_pat_') ||
            key.startsWith('ghp_') ||
            key.startsWith('gho_') ||
            key.startsWith('ghu_') ||
            key.startsWith('ghs_');
        if (!validPrefix) {
          return 'GitHub tokens usually start with "github_pat_" or "ghp_"';
        }
        break;
      case 'gemini':
        if (key.length < 20) {
          return 'API key seems too short';
        }
        break;
      case 'claude':
        if (!key.startsWith('sk-ant-')) {
          return 'Claude API keys usually start with "sk-ant-"';
        }
        break;
      case 'huggingface':
        if (!key.startsWith('hf_')) {
          return 'Hugging Face tokens usually start with "hf_"';
        }
        break;
    }

    // Check for only valid characters
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(key)) {
      return 'API key contains invalid characters';
    }

    return null; // Valid
  }

  /// Validate model name
  static String? validateModelName(String model) {
    if (model.isEmpty) {
      return 'Model name cannot be empty';
    }

    if (model.length > 100) {
      return 'Model name too long';
    }

    // Basic alphanumeric with some special chars
    if (!RegExp(r'^[a-zA-Z0-9_\-.:/@]+$').hasMatch(model)) {
      return 'Model name contains invalid characters';
    }

    return null; // Valid
  }

  /// Sanitize file path to prevent directory traversal
  static String sanitizeFilePath(String path) {
    // Remove any path traversal attempts
    return path
        .replaceAll('..', '')
        .replaceAll('//', '/')
        .replaceAll('\\', '/')
        .trim();
  }

  /// Check if string contains only safe characters for database storage
  static bool isSafeForDatabase(String input) {
    // Avoid SQL injection patterns
    final dangerous = [
      'DROP TABLE',
      'DELETE FROM',
      'INSERT INTO',
      'UPDATE ',
      'SELECT ',
      '--',
      '/*',
      '*/',
      'UNION',
      'exec(',
      'execute(',
    ];

    final upper = input.toUpperCase();
    for (final pattern in dangerous) {
      if (upper.contains(pattern)) {
        return false;
      }
    }

    return true;
  }

  /// Strip HTML tags from input
  static String stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  /// Validate email format
  static bool isValidEmail(String email) {
    if (email.isEmpty) return false;
    return RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(email);
  }
}
