import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import '../theme/app_theme.dart';
import '../models/memory.dart';
import '../database/db_helper.dart';
import '../services/llm_service.dart';
import '../utils/error_handler.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _dbHelper = DBHelper();
  final _llmService = LLMService();
  final List<_ChatMessage> _messages = [];
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isThinking = false;
  bool _isListening = false;
  bool _speechEnabled = false;
  String? _playingVoiceId;
  late AnimationController _dotController;
  late AnimationController _micPulseController;

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _micPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _initSpeech();
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingVoiceId = null);
    });

    // Welcome message
    _messages.add(
      _ChatMessage(
        text:
            "Hi. I can help you recall anything you have saved: notes, voice clips, screenshots, photos, and links. Ask a specific question and I will search your memory box.\n\nTry: *\"What was that 3D animation website?\"*",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setState(() => _isListening = false);
              _micPulseController.stop();
              _micPulseController.reset();
            }
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() => _isListening = false);
            _micPulseController.stop();
            _micPulseController.reset();
          }
        },
      );
    } catch (_) {
      _speechEnabled = false;
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (_isListening) {
      await _speechToText.stop();
      _micPulseController.stop();
      _micPulseController.reset();
      if (mounted) setState(() => _isListening = false);
      if (_messageController.text.trim().isNotEmpty) {
        _sendMessage();
      }
      return;
    }

    if (!_speechEnabled) {
      await _initSpeech();
    }

    if (!_speechEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition is not supported or permission denied.')),
        );
      }
      return;
    }

    setState(() => _isListening = true);
    _micPulseController.repeat(reverse: true);
    await _speechToText.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _messageController.text = result.recognizedWords;
        });
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
      ),
    );
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _messages.add(
        _ChatMessage(
          text:
              "Conversation cleared. How can I assist you with your memories today?",
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _dotController.dispose();
    _micPulseController.dispose();
    _audioPlayer.dispose();
    _speechToText.stop();
    super.dispose();
  }

  List<Map<String, String>> _extractLinks(String text) {
    final List<Map<String, String>> links = [];
    final Set<String> seenUrls = {};

    // First, find markdown links like [Label](http://...)
    final markdownRegex = RegExp(
      r'\[([^\]]+)\]\(((?:https?:\/\/|www\.)[^\s\)]+)\)',
    );
    for (final match in markdownRegex.allMatches(text)) {
      final label = match.group(1) ?? '';
      var url = match.group(2) ?? '';
      if (url.startsWith('www.')) {
        url = 'https://$url';
      }
      if (!seenUrls.contains(url)) {
        seenUrls.add(url);
        links.add({'label': label, 'url': url});
      }
    }

    // Next, find plain URLs that aren't already captured
    final urlRegex = RegExp(r'(https?:\/\/[^\s\)]+)');
    for (final match in urlRegex.allMatches(text)) {
      var url = match.group(0) ?? '';
      if (!seenUrls.contains(url)) {
        seenUrls.add(url);
        String label = url;
        try {
          final uri = Uri.parse(url);
          label = uri.host;
          if (label.startsWith('www.')) {
            label = label.substring(4);
          }
        } catch (_) {}
        links.add({'label': label, 'url': url});
      }
    }
    return links;
  }

  List<Memory> _fetchReferencedMemories(
    String response,
    List<Memory> allMemories,
  ) {
    final lower = response.toLowerCase().trim();
    if (lower.startsWith("i couldn't find any") ||
        lower.startsWith("i couldn't find a") ||
        lower.startsWith("i didn't find any") ||
        lower.startsWith("i was unable to find") ||
        lower.startsWith("no memories found") ||
        lower.startsWith("no matching memories")) {
      return [];
    }

    final List<Memory> referenced = [];
    final Set<String> seenIds = {};

    void addMemoryIfMatch(String title, String typeStr) {
      final cleanTitle = title
          .trim()
          .toLowerCase()
          .replaceAll('"', '')
          .replaceAll("'", '')
          .replaceAll('**', '')
          .replaceAll('*', '');
      final cleanType = typeStr.trim().toLowerCase();
      if (cleanTitle.isEmpty || cleanType.isEmpty) return;

      for (final memory in allMemories) {
        final memTitle = memory.title
            .toLowerCase()
            .replaceAll('"', '')
            .replaceAll("'", '');
        final memType = memory.type.name.toLowerCase();

        if (memType == cleanType) {
          if (memTitle == cleanTitle ||
              memTitle.contains(cleanTitle) ||
              cleanTitle.contains(memTitle)) {
            if (!seenIds.contains(memory.id)) {
              seenIds.add(memory.id);
              referenced.add(memory);
            }
          }
        }
      }
    }

    final labelRegex = RegExp(
      r'\*\*(?:Memory\s+)?Title\*\*:\s*(.{1,250}?)\s*\((Photo|Screenshot|Voice|Text),\s*[^)]+\)',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in labelRegex.allMatches(response)) {
      final title = (match.group(1) ?? '').replaceAll('\n', ' ');
      final typeStr = match.group(2) ?? '';
      addMemoryIfMatch(title, typeStr);
    }

    final citationRegex = RegExp(
      r'\*\*([^*]+)\*\*\s*\((Photo|Screenshot|Voice|Text),\s*[^)]+\)',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in citationRegex.allMatches(response)) {
      final title = (match.group(1) ?? '').replaceAll('\n', ' ');
      final typeStr = match.group(2) ?? '';
      if (title.trim().toLowerCase() != 'memory title') {
        addMemoryIfMatch(title, typeStr);
      }
    }

    final genericCitationRegex = RegExp(
      r'\((Photo|Screenshot|Voice|Text),\s*[^)]+\)',
      caseSensitive: false,
    );

    String cleanTitleText(String text) {
      var t = text.trim();
      t = t.replaceFirst(RegExp(r'^[\s\-*#\d.]+\s*'), '');
      t = t.replaceFirst(
        RegExp(r'^\*\*(?:Memory\s+)?Title\*\*:\s*', caseSensitive: false),
        '',
      );
      t = t.replaceFirst(
        RegExp(r'^(?:Memory\s+)?Title:\s*', caseSensitive: false),
        '',
      );
      if (t.startsWith('**') && t.endsWith('**') && t.length > 4) {
        t = t.substring(2, t.length - 2);
      } else if (t.startsWith('*') && t.endsWith('*') && t.length > 2) {
        t = t.substring(1, t.length - 1);
      }
      t = t.trim();
      if ((t.startsWith('"') && t.endsWith('"') && t.length > 2) ||
          (t.startsWith("'") && t.endsWith("'") && t.length > 2)) {
        t = t.substring(1, t.length - 1);
      }
      return t.trim();
    }

    final lines = response.split('\n');
    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      for (final match in genericCitationRegex.allMatches(line)) {
        final typeStr = match.group(1) ?? '';
        final matchStart = match.start;
        var before = cleanTitleText(line.substring(0, matchStart));

        if (before.isEmpty && lineIndex > 0) {
          for (int prev = lineIndex - 1; prev >= 0; prev--) {
            final prevCleaned = cleanTitleText(lines[prev]);
            if (prevCleaned.isNotEmpty) {
              before = prevCleaned;
              break;
            }
          }
        }

        addMemoryIfMatch(before, typeStr);
      }
    }

    if (referenced.isEmpty) {
      final responseLower = response
          .toLowerCase()
          .replaceAll('**', '')
          .replaceAll('*', '');
      for (final memory in allMemories) {
        if (memory.type == MemoryType.photo ||
            memory.type == MemoryType.screenshot) {
          final memTitle = memory.title
              .toLowerCase()
              .replaceAll('"', '')
              .replaceAll("'", '');
          if (memTitle.length < 8) continue;
          final matchTitle = memTitle.endsWith('...')
              ? memTitle.substring(0, memTitle.length - 3).trim()
              : memTitle;
          if (matchTitle.length >= 8 && responseLower.contains(matchTitle)) {
            if (!seenIds.contains(memory.id)) {
              seenIds.add(memory.id);
              referenced.add(memory);
            }
          }
        }
      }
    }

    return referenced;
  }

  Future<void> _sendMessage() async {
    final query = _messageController.text.trim();
    if (query.isEmpty || _isThinking) return;

    setState(() {
      _messages.add(
        _ChatMessage(text: query, isUser: true, timestamp: DateTime.now()),
      );
      _isThinking = true;
    });
    _messageController.clear();
    _scrollToBottom();

    try {
      final memories = await _dbHelper.getMemories();
      final response = await _llmService.chatWithMemory(query, memories);
      final referenced = _fetchReferencedMemories(response, memories);

      setState(() {
        _messages.add(
          _ChatMessage(
            text: response,
            isUser: false,
            timestamp: DateTime.now(),
            referencedMemories: referenced,
          ),
        );
        _isThinking = false;
      });
    } catch (e) {
      setState(() {
        _messages.add(
          _ChatMessage(
            text:
              "I couldn't reach your AI provider. Please check Settings and try again.\n\n${ErrorHandler.getUserMessage(e)}",
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
        _isThinking = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_messages.length > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: AppTheme.surfaceContainerLowest.withValues(alpha: 0.5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.forum_outlined, size: 14, color: AppTheme.outline),
                    const SizedBox(width: 6),
                    Text(
                      '${_messages.length} messages',
                      style: AppTheme.labelCaps.copyWith(color: AppTheme.outline, fontSize: 11),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _isThinking ? null : _clearChat,
                  icon: const Icon(Icons.refresh_rounded, size: 14, color: AppTheme.outline),
                  label: Text(
                    'Clear Chat',
                    style: AppTheme.labelCaps.copyWith(color: AppTheme.outline, fontSize: 11),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _messages.isEmpty
              ? _buildEmptyChat()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  itemCount: _messages.length + (_isThinking ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length && _isThinking) {
                      return _buildThinkingBubble();
                    }
                    return _buildMessageBubble(_messages[index]);
                  },
                ),
        ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.tertiaryFixed.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.psychology,
              color: AppTheme.tertiary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Ask me anything about your saved memories',
              style: GoogleFonts.jetBrainsMono(
                color: AppTheme.tertiary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage message) {
    final maxWidth = MediaQuery.of(context).size.width;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment:
            message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: message.isUser ? maxWidth * 0.82 : maxWidth * 0.92,
                  ),
                  child: message.isUser
                      ? _buildUserBubble(message)
                      : _buildAIBubble(message),
                ),
              ),
            ],
          ),
          if (!message.isUser && message.referencedMemories.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildSourcesSection(message.referencedMemories),
          ],
          const SizedBox(height: 6),
          if (!message.isUser)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          size: 11,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'RECALL AI',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Response copied to clipboard!'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.copy_rounded, size: 12, color: AppTheme.outline),
                          const SizedBox(width: 4),
                          Text(
                            'Copy',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.outline,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '·  ${_formatTime(message.timestamp)}',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      color: AppTheme.outline,
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                _formatTime(message.timestamp),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: AppTheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUserBubble(_ChatMessage message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppTheme.primary,
            Color(0xFF6D28D9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(4),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        message.text,
        style: GoogleFonts.inter(
          fontSize: 15,
          color: Colors.white,
          fontWeight: FontWeight.w500,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildAIBubble(_ChatMessage message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
        border: Border.all(
          color: AppTheme.outlineVariant.withValues(alpha: 0.55),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownBody(
            data: message.text,
            builders: {
              'code': CodeBlockBuilder(context, false),
            },
            onTapLink: (text, href, title) async {
              if (href != null) {
                final uri = Uri.parse(href);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                }
              }
            },
            styleSheet: MarkdownStyleSheet(
              p: GoogleFonts.inter(
                fontSize: 15,
                color: const Color(0xFF1F2937),
                height: 1.55,
              ),
              strong: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
              blockquote: GoogleFonts.inter(
                color: AppTheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              blockquoteDecoration: BoxDecoration(
                border: const Border(
                  left: BorderSide(
                    color: AppTheme.primary,
                    width: 3,
                  ),
                ),
                color: AppTheme.surfaceContainerLow.withValues(alpha: 0.5),
              ),
              blockquotePadding:
                  const EdgeInsets.only(left: 12, top: 4, bottom: 4),
              a: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
              listBullet: GoogleFonts.inter(
                fontSize: 15,
                color: AppTheme.primary,
                fontWeight: FontWeight.bold,
              ),
              blockSpacing: 12.0,
              h1: GoogleFonts.hankenGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.onSurface,
                height: 1.4,
              ),
              h2: GoogleFonts.hankenGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.onSurface,
                height: 1.4,
              ),
              h3: GoogleFonts.hankenGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
          Builder(
            builder: (context) {
              final links = _extractLinks(message.text);
              if (links.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: links.map((link) {
                      final label = link['label'] ?? '';
                      final url = link['url'] ?? '';
                      return Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.outlineVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () async {
                                final uri = Uri.parse(url);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(10),
                                bottomLeft: Radius.circular(10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.link_rounded,
                                      size: 14,
                                      color: AppTheme.primary,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      label,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              height: 16,
                              width: 1,
                              color: AppTheme.outlineVariant,
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.copy_rounded,
                                size: 12,
                              ),
                              color: AppTheme.outline,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: url),
                                );
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(
                                  SnackBar(
                                    content: Text('Link copied: $url'),
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  border: Border.all(color: AppTheme.secondaryFixedDim, width: 1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: AnimatedBuilder(
                  animation: _dotController,
                  builder: (context, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildDot(0.0),
                        _buildDot(0.2),
                        _buildDot(0.4),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(double delay) {
    final t = (_dotController.value + delay) % 1.0;
    final dy = (t < 0.5 ? -t * 2 : -(1.0 - t) * 2) * 4;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppTheme.primaryFixedDim,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = bottomInset > 0
        ? 10.0
        : (MediaQuery.of(context).padding.bottom + 20.0);
    final hasText = _messageController.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottomPadding),
      color: Colors.transparent,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: AppTheme.outlineVariant.withValues(alpha: 0.5),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Borderless clean input text field
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: TextField(
                      controller: _messageController,
                      onChanged: (_) => setState(() {}),
                      enabled: !_isThinking,
                      onSubmitted: (_) => _sendMessage(),
                      textInputAction: TextInputAction.send,
                      keyboardType: TextInputType.multiline,
                      minLines: 1,
                      maxLines: 4,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: AppTheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        fillColor: Colors.transparent,
                        hintText: _isListening
                            ? 'Listening to your question...'
                            : 'Ask Recall...',
                        hintStyle: GoogleFonts.inter(
                          color: _isListening
                              ? AppTheme.typeVoice
                              : AppTheme.onSurfaceVariant.withValues(alpha: 0.6),
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Single Right Action: Voice Mic (when empty) OR Send Button (when typing/thinking)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: hasText || _isThinking
                      ? Container(
                          key: const ValueKey('send-btn'),
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            color: AppTheme.secondaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: _isThinking
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.arrow_upward_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                            onPressed: _isThinking ? null : _sendMessage,
                          ),
                        )
                      : AnimatedBuilder(
                          key: const ValueKey('mic-btn'),
                          animation: _micPulseController,
                          builder: (context, child) {
                            final isRecording = _isListening;
                            return Container(
                              width: 38,
                              height: 38,
                              decoration: isRecording
                                  ? BoxDecoration(
                                      color: AppTheme.typeVoice.withValues(
                                        alpha: 0.2 + _micPulseController.value * 0.3,
                                      ),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppTheme.typeVoice,
                                        width: 1.5,
                                      ),
                                    )
                                  : BoxDecoration(
                                      color: AppTheme.primaryContainer.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                                  color: isRecording
                                      ? AppTheme.typeVoice
                                      : AppTheme.primary,
                                  size: 20,
                                ),
                                tooltip: isRecording ? 'Stop listening' : 'Voice Recall',
                                onPressed: _isThinking ? null : _toggleVoiceInput,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMemoryDetailDialog(BuildContext context, Memory memory) {
    final hasImage = memory.mediaPath != null &&
        (memory.type == MemoryType.photo || memory.type == MemoryType.screenshot);
    final hasVoice = memory.type == MemoryType.voice && memory.mediaPath != null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isPlayingThis = _playingVoiceId == memory.id;

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
                maxWidth: 600,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dialog Top Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.getMemoryTypeColor(memory.type.name).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    AppTheme.getMemoryTypeIcon(memory.type.name),
                                    size: 14,
                                    color: AppTheme.getMemoryTypeColor(memory.type.name),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    AppTheme.getMemoryTypeLabel(memory.type.name),
                                    style: AppTheme.labelCaps.copyWith(
                                      color: AppTheme.getMemoryTypeColor(memory.type.name),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              DateFormat("MMM d, yyyy").format(memory.createdAt),
                              style: AppTheme.labelCaps.copyWith(color: AppTheme.outline),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.outline),
                          onPressed: () {
                            if (_playingVoiceId == memory.id) {
                              _audioPlayer.stop();
                              _playingVoiceId = null;
                            }
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Dialog Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            memory.title,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.onSurface,
                            ),
                          ),
                          if (hasImage) ...[
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: InteractiveViewer(
                                minScale: 0.8,
                                maxScale: 4.0,
                                child: Image.file(
                                  File(memory.mediaPath!),
                                  width: double.infinity,
                                  height: 240,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 120,
                                    color: AppTheme.surfaceVariant,
                                    child: const Center(
                                      child: Icon(Icons.broken_image, color: AppTheme.outline),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (hasVoice) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  IconButton.filled(
                                    icon: Icon(isPlayingThis ? Icons.stop_rounded : Icons.play_arrow_rounded),
                                    onPressed: () async {
                                      if (isPlayingThis) {
                                        await _audioPlayer.stop();
                                        setDialogState(() => _playingVoiceId = null);
                                        setState(() => _playingVoiceId = null);
                                      } else {
                                        await _audioPlayer.stop();
                                        await _audioPlayer.play(DeviceFileSource(memory.mediaPath!));
                                        setDialogState(() => _playingVoiceId = memory.id);
                                        setState(() => _playingVoiceId = memory.id);
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      isPlayingThis ? 'Playing audio recording...' : 'Voice Recording',
                                      style: AppTheme.bodyMd.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (memory.content.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'CONTENT',
                              style: AppTheme.labelCaps.copyWith(color: AppTheme.outline),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              memory.content,
                              style: GoogleFonts.inter(
                                fontSize: 14.5,
                                color: AppTheme.onSurface,
                                height: 1.5,
                              ),
                            ),
                          ],
                          if (memory.aiAnalysis != null) ...[
                            if (memory.aiAnalysis!.description.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.secondaryFixed.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppTheme.secondaryFixedDim),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.auto_awesome, size: 16, color: AppTheme.secondary),
                                        const SizedBox(width: 6),
                                        Text(
                                          'AI Analysis & Description',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.secondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      memory.aiAnalysis!.description,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: AppTheme.onSurface,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (memory.aiAnalysis!.extractedUrls.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(
                                'EXTRACTED LINKS',
                                style: AppTheme.labelCaps.copyWith(color: AppTheme.outline),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: memory.aiAnalysis!.extractedUrls.map((url) {
                                  return ActionChip(
                                    avatar: const Icon(Icons.open_in_new, size: 14, color: AppTheme.primary),
                                    label: Text(url, style: const TextStyle(fontSize: 12)),
                                    onPressed: () async {
                                      final uri = Uri.parse(url);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                          if (memory.tags.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: memory.tags.map((tag) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.tertiaryContainer.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Text(
                                    '#$tag',
                                    style: AppTheme.labelCaps.copyWith(color: AppTheme.tertiaryContainer),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSourcesSection(List<Memory> memories) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome_motion_rounded,
                      size: 13,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'SOURCES (${memories.length})',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: memories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, idx) =>
                _buildReferencedMemoryCard(memories[idx]),
          ),
        ),
      ],
    );
  }

  Widget _buildReferencedMemoryCard(Memory memory) {
    final hasImage = memory.mediaPath != null &&
        (memory.type == MemoryType.photo ||
            memory.type == MemoryType.screenshot);

    Color badgeColor;
    IconData typeIcon;
    String typeLabel;

    switch (memory.type) {
      case MemoryType.photo:
        badgeColor = const Color(0xFF8B5CF6);
        typeIcon = Icons.image_rounded;
        typeLabel = 'Photo';
        break;
      case MemoryType.screenshot:
        badgeColor = const Color(0xFF06B6D4);
        typeIcon = Icons.screenshot_rounded;
        typeLabel = 'Screenshot';
        break;
      case MemoryType.voice:
        badgeColor = const Color(0xFFF59E0B);
        typeIcon = Icons.mic_rounded;
        typeLabel = 'Voice';
        break;
      case MemoryType.text:
      default:
        badgeColor = const Color(0xFF3B82F6);
        typeIcon = Icons.article_rounded;
        typeLabel = 'Note';
        break;
    }

    // Clean title from fallback error strings
    String displayTitle = memory.title.trim();
    if (displayTitle.startsWith('Image saved.') ||
        displayTitle.startsWith('Untitled')) {
      if (memory.content.isNotEmpty) {
        displayTitle = memory.content.split('\n').first.trim();
      } else {
        displayTitle = '$typeLabel Memory';
      }
    }
    if (displayTitle.length > 32) {
      displayTitle = '${displayTitle.substring(0, 32)}...';
    }

    final formattedDate = _formatHumanDate(memory.createdAt);

    return InkWell(
      onTap: () => _showMemoryDetailDialog(context, memory),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.outlineVariant.withValues(alpha: 0.65),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail / Icon box
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 48,
                height: 56,
                color: badgeColor.withValues(alpha: 0.12),
                child: hasImage
                    ? Image.file(
                        File(memory.mediaPath!),
                        width: 48,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          typeIcon,
                          color: badgeColor,
                          size: 22,
                        ),
                      )
                    : Icon(
                        typeIcon,
                        color: badgeColor,
                        size: 22,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            // Info column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          typeLabel.toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    displayTitle,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurface,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formattedDate,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      color: AppTheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatHumanDate(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);
    if (difference.inDays == 0 && dt.day == now.day) {
      return 'Today, ${DateFormat('h:mm a').format(dt)}';
    } else if (difference.inDays == 1 ||
        (difference.inDays == 0 && dt.day != now.day)) {
      return 'Yesterday, ${DateFormat('h:mm a').format(dt)}';
    } else {
      return DateFormat('MMM d, yyyy').format(dt);
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $ampm';
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<Memory> referencedMemories;

  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.referencedMemories = const [],
  });
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  final bool isUser;

  CodeBlockBuilder(this.context, this.isUser);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final String code = element.textContent.trimRight();
    final String className = element.attributes['class'] ?? '';
    final String language = className.startsWith('language-')
        ? className.substring(9)
        : '';
    final bool isInline = !code.contains('\n') && language.isEmpty;

    if (isInline) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: isUser ? Colors.white.withValues(alpha: 0.2) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          code,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            color: isUser ? Colors.white : Colors.red.shade800,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  language.isEmpty ? 'CODE' : language.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xffcccccc),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code copied to clipboard!'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: Color(0xffcccccc),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: GoogleFonts.inter(
                            color: const Color(0xffcccccc),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                code,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: const Color(0xffd4d4d4),
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
