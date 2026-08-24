import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/memory.dart';
import '../database/db_helper.dart';
import '../utils/rate_limiter.dart';

class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  final RateLimiter _rateLimiter = RateLimiter(
    maxRequestsPerMinute: 8,
    maxRequestsPerHour: 80,
  );

  Future<void> _checkRateLimit(String action) async {
    final result = await _rateLimiter.checkLimit(action);
    if (!result.allowed) {
      final wait = result.waitSeconds ?? 60;
      throw Exception(
        'AI usage limit reached. Please wait ${wait}s and try again.',
      );
    }
  }

  // Helper to get active settings
  Future<Map<String, String>> _getSettings() async {
    return await DBHelper().getSettings();
  }

  // --- VISION API: ANALYZE IMAGE ---
  Future<AIAnalysis> analyzeImage(File imageFile, String type) async {
    await _checkRateLimit('image_analysis');
    final settings = await _getSettings();
    final provider = settings['provider'] ?? 'github';
    final apiKey = settings['api_key'] ?? '';
    final customEndpoint = settings['api_endpoint'] ?? '';
    final modelName = settings['model_name'] ?? '';

    final imageBytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(imageBytes);
    final mimeType = _getMimeType(imageFile.path);

    final prompt =
        '''
    Analyze this uploaded ${type == 'screenshot' ? 'screenshot' : 'photo'} from my personal memory box. 
    Provide your analysis in raw JSON format matching this schema exactly. 
    Do not wrap the JSON in ```json or any other formatting, just return raw valid JSON.
    {
      "title": "A short, descriptive, specific title for this memory (max 6 words)",
      "description": "A clear, concise, detailed description of what is in this image and what it represents",
      "extracted_text": "All readable text, code, or key text snippets visible in the image",
      "extracted_urls": ["Any URLs or website addresses visible in the image"],
      "tags": ["3 to 5 relevant tags, lowercase, e.g., 'ideas', 'tech', 'receipt', 'design', 'inspiration'"]
    }
    ''';

    switch (provider) {
      case 'huggingface':
        return await _analyzeImageHuggingFace(
          base64Image,
          mimeType,
          prompt,
          apiKey,
          customEndpoint,
          modelName,
        );
      case 'github':
        return await _analyzeImageGitHub(
          base64Image,
          mimeType,
          prompt,
          apiKey,
          customEndpoint,
          modelName,
        );
      case 'openai':
        return await _analyzeImageOpenAI(
          base64Image,
          mimeType,
          prompt,
          apiKey,
          modelName,
        );
      case 'gemini':
        return await _analyzeImageGemini(
          base64Image,
          mimeType,
          prompt,
          apiKey,
          modelName,
        );
      case 'claude':
        return await _analyzeImageClaude(
          base64Image,
          mimeType,
          prompt,
          apiKey,
          modelName,
        );
      case 'local':
      default:
        return await _analyzeImageLocal(
          imageFile,
          prompt,
          customEndpoint,
          modelName,
        );
    }
  }

  // --- CHAT ASSISTANT API ---
  Future<String> chatWithMemory(String query, List<Memory> memories) async {
    await _checkRateLimit('chat');
    final settings = await _getSettings();
    final provider = settings['provider'] ?? 'github';
    final apiKey = settings['api_key'] ?? '';
    final customEndpoint = settings['api_endpoint'] ?? '';
    final modelName = settings['model_name'] ?? '';

    // Format memories context cleanly with human-readable dates and sanitized titles
    final dateFormat = DateFormat('MMM d, yyyy');
    final memoriesContext = memories
        .map((m) {
          // Clean title if it contains technical error string
          var title = m.title.trim();
          if (title.isEmpty ||
              title.startsWith('Image saved.') ||
              title.startsWith('Untitled')) {
            if (m.content.isNotEmpty) {
              final firstLine = m.content.split('\n').first.trim();
              title = firstLine.length > 40
                  ? '${firstLine.substring(0, 40)}...'
                  : firstLine;
            } else {
              final typeName = m.type.name[0].toUpperCase() + m.type.name.substring(1);
              title = '$typeName (${dateFormat.format(m.createdAt)})';
            }
          }

          final formattedDate = dateFormat.format(m.createdAt);
          var desc =
              'Type: ${m.type.name}\nTitle: $title\nDate: $formattedDate\n';
          if (m.content.isNotEmpty) desc += 'Content: ${m.content}\n';
          if (m.tags.isNotEmpty) desc += 'Tags: ${m.tags.join(', ')}\n';
          if (m.aiAnalysis != null &&
              !m.aiAnalysis!.description.startsWith('Image saved. AI vision analysis encountered an error')) {
            desc += 'AI Description: ${m.aiAnalysis!.description}\n';
            if (m.aiAnalysis!.extractedText.isNotEmpty) {
              desc += 'Extracted Text: ${m.aiAnalysis!.extractedText}\n';
            }
            if (m.aiAnalysis!.extractedUrls.isNotEmpty) {
              desc +=
                  'Extracted URLs: ${m.aiAnalysis!.extractedUrls.join(', ')}\n';
            }
          }
          return desc;
        })
        .join('\n---\n');

    final systemPrompt =
        '''
    You are my Memory Box Personal Assistant, a smart, warm, cognitive second brain. 
    Your role is to help me effortlessly find, recall, and understand my saved memories (notes, voice notes, photos, screenshots, and links).
    Be conversational, concise, friendly, and accurate.

    ---
    CRITICAL INSTRUCTIONS FOR CITATIONS & RELEVANCE:
    1. Strict Relevance & Zero Unrelated Citations:
       - ONLY answer using memories that DIRECTLY match or are genuinely relevant to the user's question.
       - If you CANNOT find any memory relevant to the query, clearly and politely state that no matching memory was found.
       - NEVER bring up, summarize, or cite unrelated memories just because they exist in your context (e.g., if the user asks for "logo" and there is no memory about a logo, DO NOT say "I couldn't find a logo, but here is a photo of CLUTCH").
       - When no matching memory is found, do NOT cite or mention any memory titles, and do NOT suggest unrelated memories.
    2. Conversational & Direct: Answer clearly and concisely. Avoid stiff or robotic phrasing.
    3. Source Citations (Only for genuinely relevant matches):
       - When citing a truly relevant memory, format the title in bold with its type and date naturally:
         e.g., "...found in your photo **Impact Protectors** (Photo, May 22, 2026)."
         e.g., "...according to your note **Meeting Summary** (Note, Aug 24, 2026)."
       - NEVER output raw ISO timestamps (like 2026-08-24T21:52:44). Use human dates like "Aug 24, 2026" or "Today".
       - NEVER use all-caps robotic labels like (PHOTO, 2026-08-24...).
       - Do NOT put square brackets around memory titles (do not write [Title](...)).
    4. Formatting & Markdown:
       - Use clean bullet points or numbered lists when presenting multiple items.
       - Highlight key names, amounts, codes, and keywords in **bold**.
       - Format web links as `[Website Name](https://...)`.
    5. Handle Unmatched Queries:
       - If no memory is found, respond concisely: e.g. "I couldn't find any memories about **[query]** in your memory box. Try searching for a different keyword or checking your recent notes."
       - Keep it short and do NOT cite or reference any unrelated memories.

    ---
    Here is the full context of my stored memories:
    $memoriesContext

    Using only these memories as your source of truth, answer the query: "$query".
    ''';

    switch (provider) {
      case 'github':
        return await _chatOpenAIStyle(
          systemPrompt,
          query,
          apiKey,
          customEndpoint,
          modelName,
        );
      case 'openai':
        return await _chatOpenAIStyle(
          systemPrompt,
          query,
          apiKey,
          'https://api.openai.com/v1',
          modelName,
        );
      case 'gemini':
        return await _chatGemini(systemPrompt, query, apiKey, modelName);
      case 'claude':
        return await _chatClaude(systemPrompt, query, apiKey, modelName);
      case 'huggingface':
        return await _chatOpenAIStyle(
          systemPrompt,
          query,
          apiKey,
          customEndpoint.isNotEmpty
              ? customEndpoint
              : 'https://router.huggingface.co/v1',
          modelName.isNotEmpty
              ? modelName
              : 'meta-llama/Llama-3.3-70B-Instruct',
        );
      case 'local':
      default:
        // Local Ollama running OpenAI-compatible chat completion
        final localBaseUrl = customEndpoint.isNotEmpty
            ? customEndpoint
            : 'http://localhost:11434';
        return await _chatOpenAIStyle(
          systemPrompt,
          query,
          '',
          '$localBaseUrl/v1',
          modelName.isNotEmpty ? modelName : 'gemma:2b',
        );
    }
  }

  // --- SPEECH TO TEXT: TRANSCRIBE AUDIO ---
  Future<String> transcribeAudio(File audioFile) async {
    await _checkRateLimit('transcription');
    final settings = await _getSettings();
    final provider = settings['provider'] ?? 'github';
    final apiKey = settings['api_key'] ?? '';
    final customEndpoint = settings['api_endpoint'] ?? '';
    final modelName = settings['model_name'] ?? '';

    // 1. If active provider is capable and configured, use it directly
    if (provider == 'huggingface' && apiKey.isNotEmpty) {
      try {
        return await _transcribeAudioHuggingFace(audioFile, apiKey, customEndpoint);
      } catch (e) {
        // Let fallback continue
      }
    } else if (provider == 'openai' && apiKey.isNotEmpty) {
      return await _transcribeAudioOpenAI(audioFile, apiKey);
    } else if (provider == 'gemini' && apiKey.isNotEmpty) {
      return await _transcribeAudioGemini(audioFile, apiKey, modelName);
    } else if (provider == 'local') {
      // Local doesn't strictly require key, but endpoint is needed
      final endpoint = customEndpoint.isNotEmpty
          ? customEndpoint
          : 'http://localhost:11434';
      try {
        return await _transcribeAudioLocal(audioFile, endpoint, modelName);
      } catch (e) {
        // If local active fails, let fallback continue to check other providers
        if (provider != 'local') rethrow;
      }
    }

    // 2. Intelligent fallback: check if other providers have configurations stored in provider_configs
    final dbHelper = DBHelper();

    // Check Hugging Face fallback
    final hfConfig = await dbHelper.getProviderConfig('huggingface');
    if (hfConfig != null &&
        hfConfig['api_key'] != null &&
        hfConfig['api_key']!.isNotEmpty) {
      try {
        return await _transcribeAudioHuggingFace(
          audioFile,
          hfConfig['api_key']!,
          hfConfig['api_endpoint'] ?? '',
        );
      } catch (_) {}
    }

    // Check Gemini fallback
    final geminiConfig = await dbHelper.getProviderConfig('gemini');
    if (geminiConfig != null &&
        geminiConfig['api_key'] != null &&
        geminiConfig['api_key']!.isNotEmpty) {
      return await _transcribeAudioGemini(
        audioFile,
        geminiConfig['api_key']!,
        geminiConfig['model_name'] ?? 'gemini-1.5-flash',
      );
    }

    // Check OpenAI fallback
    final openaiConfig = await dbHelper.getProviderConfig('openai');
    if (openaiConfig != null &&
        openaiConfig['api_key'] != null &&
        openaiConfig['api_key']!.isNotEmpty) {
      return await _transcribeAudioOpenAI(audioFile, openaiConfig['api_key']!);
    }

    // Check Local fallback
    final localConfig = await dbHelper.getProviderConfig('local');
    if (localConfig != null &&
        localConfig['api_endpoint'] != null &&
        localConfig['api_endpoint']!.isNotEmpty) {
      try {
        return await _transcribeAudioLocal(
          audioFile,
          localConfig['api_endpoint']!,
          localConfig['model_name'] ?? '',
        );
      } catch (_) {
        // If fallback local fails, ignore and proceed to exception
      }
    }

    // 3. No fallback is available, throw a clear instruction exception
    throw Exception(
      'Active provider (${provider.toUpperCase()}) does not support audio transcription, and no fallback provider (Hugging Face, Google Gemini, or OpenAI) is configured with an API key in Settings.',
    );
  }

  Future<String> _transcribeAudioOpenAI(File audioFile, String apiKey) async {
    final url = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
    try {
      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..fields['model'] = 'whisper-1'
        ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 25),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['text'].toString().trim();
      } else {
        throw Exception(
          'OpenAI Whisper error (${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to transcribe audio with OpenAI Whisper: $e');
    }
  }

  Future<String> _transcribeAudioGemini(
    File audioFile,
    String apiKey,
    String model,
  ) async {
    final activeModel = model.isNotEmpty ? model : 'gemini-1.5-flash';
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$activeModel:generateContent?key=$apiKey',
    );

    try {
      final bytes = await audioFile.readAsBytes();
      final base64Audio = base64Encode(bytes);

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'contents': [
                {
                  'parts': [
                    {
                      'text':
                          'Please transcribe this audio recording accurately. Provide only the transcription text, with no preamble, comments, or quotes. If the audio contains no clear speech, respond with "(No clear speech detected)".',
                    },
                    {
                      'inlineData': {
                        'mimeType': 'audio/mp4',
                        'data': base64Audio,
                      },
                    },
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final text =
            data['candidates'][0]['content']['parts'][0]['text'] as String;
        return text.trim();
      } else {
        throw Exception(
          'Gemini audio transcription error (${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Failed to transcribe audio with Gemini: $e');
    }
  }

  Future<String> _transcribeAudioLocal(
    File audioFile,
    String endpoint,
    String model,
  ) async {
    final localBaseUrl = endpoint.isNotEmpty
        ? endpoint
        : 'http://localhost:11434';
    final url = Uri.parse('$localBaseUrl/v1/audio/transcriptions');
    try {
      final request = http.MultipartRequest('POST', url)
        ..fields['model'] = model.isNotEmpty ? model : 'whisper-1'
        ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 25),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['text'].toString().trim();
      } else {
        throw Exception(
          'Local STT error (${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception(
        'Local transcription failed. Ensure a local OpenAI-compatible STT service (e.g. whisper.cpp or LocalAI) is running on $localBaseUrl. Error: $e',
      );
    }
  }

  // --- HUGGING FACE WHISPER STT IMPLEMENTATION ---
  Future<String> _transcribeAudioHuggingFace(
    File audioFile,
    String apiKey,
    String endpoint,
  ) async {
    final baseUrl = endpoint.isNotEmpty
        ? endpoint.replaceFirst(RegExp(r'/+$'), '')
        : 'https://router.huggingface.co/v1';
    final url = Uri.parse('$baseUrl/audio/transcriptions');

    try {
      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..fields['model'] = 'openai/whisper-large-v3-turbo'
        ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data.containsKey('text')) {
          final text = data['text'].toString().trim();
          if (text.isNotEmpty) return text;
        }
      }
    } catch (_) {}

    // Direct Hugging Face Inference API fallback
    final whisperModels = [
      'openai/whisper-large-v3-turbo',
      'openai/whisper-large-v3',
      'openai/whisper-small',
      'openai/whisper-base',
    ];

    String? lastError;
    final bytes = await audioFile.readAsBytes();

    for (final model in whisperModels) {
      try {
        final directUrl = Uri.parse(
          'https://api-inference.huggingface.co/models/$model',
        );
        final response = await http
            .post(
              directUrl,
              headers: {
                'Authorization': 'Bearer $apiKey',
                'x-wait-for-model': 'true',
                'Content-Type': 'audio/m4a',
              },
              body: bytes,
            )
            .timeout(const Duration(seconds: 40));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data is Map && data.containsKey('text')) {
            final text = data['text'].toString().trim();
            if (text.isNotEmpty) return text;
          }
        } else {
          lastError = '(${response.statusCode}) ${response.body}';
        }
      } catch (e) {
        lastError = e.toString();
      }
    }

    throw Exception(
      'Hugging Face Whisper transcription failed: ${lastError ?? "Unknown error"}',
    );
  }

  // --- HUGGING FACE VISION IMPLEMENTATION ---
  Future<AIAnalysis> _analyzeImageHuggingFace(
    String base64Image,
    String mimeType,
    String prompt,
    String token,
    String endpoint,
    String model,
  ) async {
    final baseUrl = endpoint.isNotEmpty
        ? endpoint.replaceFirst(RegExp(r'/+$'), '')
        : 'https://router.huggingface.co/v1';
    final url = Uri.parse('$baseUrl/chat/completions');

    // Select vision models in order of priority (tested on HF Inference router)
    final visionModels = <String>[];
    if (model.isNotEmpty &&
        (model.toLowerCase().contains('vision') ||
            model.toLowerCase().contains('vl') ||
            model.toLowerCase().contains('multimodal'))) {
      visionModels.add(model);
    }
    visionModels.addAll([
      'Qwen/Qwen2.5-VL-72B-Instruct',
      'Qwen/Qwen2.5-VL-7B-Instruct',
      'Qwen/Qwen2-VL-7B-Instruct',
      'meta-llama/Llama-3.2-11B-Vision-Instruct',
    ]);

    String? lastError;
    for (final visionModel in visionModels) {
      try {
        final response = await http
            .post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: json.encode({
                'messages': [
                  {
                    'role': 'user',
                    'content': [
                      {'type': 'text', 'text': prompt},
                      {
                        'type': 'image_url',
                        'image_url': {
                          'url': 'data:$mimeType;base64,$base64Image',
                        },
                      },
                    ],
                  },
                ],
                'model': visionModel,
                'temperature': 0.1,
                'max_tokens': 1024,
              }),
            )
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final content = data['choices'][0]['message']['content'] as String;
          return _parseAIResponse(content);
        } else {
          lastError =
              'Hugging Face Error (${response.statusCode}): ${response.body}';
          if (response.statusCode == 400 ||
              response.statusCode == 404 ||
              response.statusCode == 503) {
            continue;
          }
          break;
        }
      } catch (e) {
        lastError = e.toString();
      }
    }

    // Try cross-provider fallback (e.g. Gemini, GitHub, OpenAI) if configured
    final dbHelper = DBHelper();
    final geminiConfig = await dbHelper.getProviderConfig('gemini');
    if (geminiConfig != null &&
        geminiConfig['api_key'] != null &&
        geminiConfig['api_key']!.isNotEmpty) {
      try {
        return await _analyzeImageGemini(
          base64Image,
          mimeType,
          prompt,
          geminiConfig['api_key']!,
          geminiConfig['model_name'] ?? 'gemini-1.5-flash',
        );
      } catch (_) {}
    }

    final githubConfig = await dbHelper.getProviderConfig('github');
    if (githubConfig != null &&
        githubConfig['api_key'] != null &&
        githubConfig['api_key']!.isNotEmpty) {
      try {
        return await _analyzeImageGitHub(
          base64Image,
          mimeType,
          prompt,
          githubConfig['api_key']!,
          githubConfig['api_endpoint'] ?? '',
          'openai/gpt-4o-mini',
        );
      } catch (_) {}
    }

    return _generateFallbackAnalysis(
      lastError ?? 'Hugging Face vision analysis failed.',
    );
  }

  // --- GITHUB MODELS VISION IMPLEMENTATION ---
  Future<AIAnalysis> _analyzeImageGitHub(
    String base64Image,
    String mimeType,
    String prompt,
    String token,
    String endpoint,
    String model,
  ) async {
    final baseUrl = endpoint.isNotEmpty
        ? endpoint.replaceFirst(RegExp(r'/+$'), '')
        : 'https://models.github.ai/inference';
    final url = Uri.parse('$baseUrl/chat/completions');

    // Ensure multimodal vision model for GitHub Models
    final isVisionModel = model.isNotEmpty &&
        (model.contains('gpt-4o') ||
            model.contains('vision') ||
            model.contains('phi-3.5-vision'));
    final activeModel = isVisionModel ? model : 'openai/gpt-4o-mini';

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
                },
              ],
            },
          ],
          'model': activeModel,
          'temperature': 0.1,
          'max_tokens': 1024,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        return _parseAIResponse(content);
      } else {
        throw Exception(
          'GitHub Models Error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      return _generateFallbackAnalysis(e.toString());
    }
  }

  // --- OPENAI VISION IMPLEMENTATION ---
  Future<AIAnalysis> _analyzeImageOpenAI(
    String base64Image,
    String mimeType,
    String prompt,
    String apiKey,
    String model,
  ) async {
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');
    final activeModel = model.isNotEmpty ? model : 'gpt-4o-mini';

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: json.encode({
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
                },
              ],
            },
          ],
          'model': activeModel,
          'temperature': 0.1,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        return _parseAIResponse(content);
      } else {
        throw Exception(
          'OpenAI Error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      return _generateFallbackAnalysis(e.toString());
    }
  }

  // --- GEMINI VISION IMPLEMENTATION ---
  Future<AIAnalysis> _analyzeImageGemini(
    String base64Image,
    String mimeType,
    String prompt,
    String apiKey,
    String model,
  ) async {
    final activeModel = model.isNotEmpty ? model : 'gemini-1.5-flash';
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$activeModel:generateContent?key=$apiKey',
    );

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
                {
                  'inlineData': {'mimeType': mimeType, 'data': base64Image},
                },
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'temperature': 0.1,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final content =
            data['candidates'][0]['content']['parts'][0]['text'] as String;
        return _parseAIResponse(content);
      } else {
        throw Exception(
          'Gemini Error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      return _generateFallbackAnalysis(e.toString());
    }
  }

  // --- CLAUDE VISION IMPLEMENTATION ---
  Future<AIAnalysis> _analyzeImageClaude(
    String base64Image,
    String mimeType,
    String prompt,
    String apiKey,
    String model,
  ) async {
    final url = Uri.parse('https://api.anthropic.com/v1/messages');
    final activeModel = model.isNotEmpty ? model : 'claude-3-5-sonnet-20241022';

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: json.encode({
          'model': activeModel,
          'max_tokens': 1000,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': mimeType,
                    'data': base64Image,
                  },
                },
                {'type': 'text', 'text': prompt},
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final content = data['content'][0]['text'] as String;
        return _parseAIResponse(content);
      } else {
        throw Exception(
          'Claude Error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      return _generateFallbackAnalysis(e.toString());
    }
  }

  // --- LOCAL LLM VISION FALLBACK / OLLAMA LLaVA ---
  Future<AIAnalysis> _analyzeImageLocal(
    File imageFile,
    String prompt,
    String endpoint,
    String model,
  ) async {
    final localBaseUrl = endpoint.isNotEmpty
        ? endpoint
        : 'http://localhost:11434';
    final activeModel = model.isNotEmpty
        ? model
        : 'llava'; // Default Ollama vision model
    final url = Uri.parse('$localBaseUrl/api/generate');

    try {
      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'model': activeModel,
          'prompt': prompt,
          'images': [base64Image],
          'stream': false,
          'format': 'json',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final content = data['response'] as String;
        return _parseAIResponse(content);
      } else {
        throw Exception(
          'Local Ollama Vision failed (is Llava installed?): ${response.statusCode}',
        );
      }
    } catch (e) {
      // Local vision fallback using structural tags
      return _generateFallbackAnalysis(
        'Local LLM (Non-Vision Gemma active). Image stored, but auto-vision analysis requires a local model like LLaVA installed in Ollama. Exception: $e',
      );
    }
  }

  // --- OPENAI COMPATIBLE CHAT ASSISTANT ---
  Future<String> _chatOpenAIStyle(
    String systemPrompt,
    String query,
    String apiKey,
    String baseUrl,
    String model,
  ) async {
    final url = Uri.parse('$baseUrl/chat/completions');
    try {
      final headers = {'Content-Type': 'application/json'};
      if (apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $apiKey';
      }

      final response = await http
          .post(
            url,
            headers: headers,
            body: json.encode({
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': query},
              ],
              'model': model,
              'temperature': 0.3,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['choices'][0]['message']['content'].toString().trim();
      } else {
        return 'API Connection Error: ${response.statusCode} - ${response.body}';
      }
    } catch (e) {
      return 'Failed to reach active model. Please check connection. Error: $e';
    }
  }

  // --- GEMINI CHAT ASSISTANT ---
  Future<String> _chatGemini(
    String systemPrompt,
    String query,
    String apiKey,
    String model,
  ) async {
    final activeModel = model.isNotEmpty ? model : 'gemini-1.5-flash';
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$activeModel:generateContent?key=$apiKey',
    );

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'contents': [
                {
                  'parts': [
                    {'text': '$systemPrompt\n\nUser Question: $query'},
                  ],
                },
              ],
              'generationConfig': {'temperature': 0.3},
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text']
            .toString()
            .trim();
      } else {
        return 'Gemini Error: ${response.statusCode} - ${response.body}';
      }
    } catch (e) {
      return 'Failed to connect to Google Gemini: $e';
    }
  }

  // --- CLAUDE CHAT ASSISTANT ---
  Future<String> _chatClaude(
    String systemPrompt,
    String query,
    String apiKey,
    String model,
  ) async {
    final url = Uri.parse('https://api.anthropic.com/v1/messages');
    final activeModel = model.isNotEmpty ? model : 'claude-3-5-sonnet-20241022';

    try {
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: json.encode({
              'model': activeModel,
              'max_tokens': 1000,
              'system': systemPrompt,
              'messages': [
                {'role': 'user', 'content': query},
              ],
              'temperature': 0.3,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['content'][0]['text'].toString().trim();
      } else {
        return 'Claude Error: ${response.statusCode} - ${response.body}';
      }
    } catch (e) {
      return 'Failed to connect to Anthropic Claude: $e';
    }
  }

  // --- UTILS & HELPERS ---
  String _getMimeType(String path) {
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  AIAnalysis _parseAIResponse(String content) {
    try {
      // Strip markdown code block wrapper if present
      var clean = content.trim();
      if (clean.startsWith('```')) {
        clean = clean.substring(3);
        if (clean.startsWith('json')) {
          clean = clean.substring(4);
        }
      }
      if (clean.endsWith('```')) {
        clean = clean.substring(0, clean.length - 3);
      }
      clean = clean.trim();

      final parsed = json.decode(clean);
      return AIAnalysis.fromMap(parsed);
    } catch (e) {
      return _generateFallbackAnalysis(
        'Error parsing JSON output: $e\nRaw response: $content',
      );
    }
  }

  AIAnalysis _generateFallbackAnalysis(String errorMsg) {
    return AIAnalysis(
      description:
          'Image saved. AI vision analysis encountered an error or needs API keys configured.\nDetails: $errorMsg',
      extractedText: '',
      extractedUrls: [],
      tags: ['imported', 'image'],
    );
  }
}
