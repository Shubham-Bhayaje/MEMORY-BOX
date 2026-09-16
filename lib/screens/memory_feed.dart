import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../theme/app_theme.dart';
import '../models/memory.dart';
import '../database/db_helper.dart';
import '../utils/error_handler.dart';
import '../utils/input_validator.dart';
import 'add_memory_sheet.dart';

class MemoryFeed extends StatefulWidget {
  final VoidCallback? onMemoriesChanged;

  const MemoryFeed({super.key, this.onMemoriesChanged});

  @override
  State<MemoryFeed> createState() => MemoryFeedState();
}

class MemoryFeedState extends State<MemoryFeed> with TickerProviderStateMixin {
  final _dbHelper = DBHelper();
  final _searchController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final stt.SpeechToText _speechToText = stt.SpeechToText();

  List<Memory> _memories = [];
  List<Memory> _onThisDayMemories = [];
  bool _dismissedOnThisDay = false;
  bool _isLoading = true;

  /// Whether the feed currently has any memories to display.
  bool get hasMemories => _memories.isNotEmpty;
  String? _errorMessage;
  String _filterType = 'all';
  String? _playingId;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  Timer? _searchDebounce;
  StreamSubscription<void>? _playerCompleteSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;

  late AnimationController _micPulseController;
  bool _speechEnabled = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _micPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingId = null;
          _audioPosition = Duration.zero;
        });
      }
    });
    _positionSubscription = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _audioPosition = pos);
    });
    _durationSubscription = _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _audioDuration = dur);
    });
    _initSpeech();
    loadMemories();
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

  Future<void> _toggleVoiceSearch() async {
    if (_isListening) {
      await _speechToText.stop();
      _micPulseController.stop();
      _micPulseController.reset();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    if (!_speechEnabled) {
      await _initSpeech();
    }

    if (!_speechEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition is not available.')),
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
          _searchController.text = result.recognizedWords;
        });
        _onSearchChanged(result.recognizedWords);
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _playerCompleteSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _searchController.dispose();
    _audioPlayer.dispose();
    _micPulseController.dispose();
    _speechToText.stop();
    super.dispose();
  }

  Future<void> loadMemories({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final query = InputValidator.sanitizeContent(_searchController.text);
      final memories = await _dbHelper.getMemories(
        search: query.trim(),
        type: _filterType == 'all' ? null : _filterType,
      );

      List<Memory> onThisDay = [];
      if (_filterType == 'all' && query.trim().isEmpty) {
        onThisDay = await _dbHelper.getOnThisDayMemories();
      }

      if (!mounted) return;
      setState(() {
        _memories = memories;
        _onThisDayMemories = onThisDay;
        _isLoading = false;
        _errorMessage = null;
      });
      widget.onMemoriesChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = ErrorHandler.getUserMessage(e);
      });
    }
  }

  Future<void> _togglePin(Memory memory) async {
    final newPinned = !memory.isPinned;
    await _dbHelper.togglePin(memory.id, newPinned);
    await loadMemories(showLoader: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newPinned ? 'Memory pinned to top.' : 'Memory unpinned.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      loadMemories(showLoader: false);
    });
  }

  Future<void> _deleteMemory(Memory memory) async {
    final previous = List<Memory>.from(_memories);
    setState(() => _memories.removeWhere((item) => item.id == memory.id));

    try {
      await _dbHelper.deleteMemory(memory.id);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted "${memory.title}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await _dbHelper.insertMemory(memory);
              if (mounted) loadMemories(showLoader: false);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _memories = previous);
      ErrorHandler.showErrorSnackBar(
        context,
        message: ErrorHandler.getUserMessage(e),
        onRetry: () => _deleteMemory(memory),
      );
    }
  }

  void _editMemory(Memory memory) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddMemorySheet(
        memoryToEdit: memory,
        onMemoryAdded: () {
          loadMemories(showLoader: false);
        },
      ),
    );
  }

  void _openCapture() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddMemorySheet(
        onMemoryAdded: () {
          loadMemories(showLoader: false);
        },
      ),
    );
  }

  Future<void> _playVoice(Memory memory) async {
    final path = memory.mediaPath;
    if (path == null || path.isEmpty) return;

    try {
      if (_playingId == memory.id) {
        await _audioPlayer.stop();
        if (mounted) setState(() => _playingId = null);
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        throw Exception('File not found');
      }

      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(path));
      if (mounted) setState(() => _playingId = memory.id);
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorSnackBar(
        context,
        message: ErrorHandler.getUserMessage(e),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchBar(),
        _buildFilters(),
        const SizedBox(height: 16),
        Expanded(
          child: Stack(
            children: [
              Positioned(
                left: 43,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppTheme.surfaceVariant,
                        AppTheme.surfaceVariant,
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.1, 0.9, 1.0],
                    ),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _isLoading
                    ? _buildLoadingSkeleton()
                    : _errorMessage != null
                        ? _buildErrorState()
                        : _memories.isEmpty
                            ? _buildEmptyState()
                            : Builder(
                                builder: (context) {
                                  final showOnThisDay =
                                      _onThisDayMemories.isNotEmpty &&
                                          !_dismissedOnThisDay &&
                                          _searchController.text.trim().isEmpty &&
                                          _filterType == 'all';
                                  return RefreshIndicator(
                                    onRefresh: () =>
                                        loadMemories(showLoader: false),
                                    child: ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        8,
                                        20,
                                        92,
                                      ),
                                      itemCount: _memories.length +
                                          (showOnThisDay ? 1 : 0),
                                      itemBuilder: (context, index) {
                                        if (showOnThisDay && index == 0) {
                                          return _buildOnThisDaySection();
                                        }
                                        final memoryIndex = showOnThisDay
                                            ? index - 1
                                            : index;
                                        return _buildMemoryCard(
                                          _memories[memoryIndex],
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final hasText = _searchController.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: AppTheme.outlineVariant.withValues(alpha: 0.5),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 8),
              child: Icon(
                Icons.search_rounded,
                color: _isListening ? AppTheme.typeVoice : AppTheme.outline,
                size: 22,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppTheme.onSurface,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  fillColor: Colors.transparent,
                  hintText: _isListening
                      ? 'Listening...'
                      : 'Search memories, tags, or words...',
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
                    horizontal: 2,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: hasText
                  ? IconButton(
                      key: const ValueKey('clear-search'),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: AppTheme.outline,
                      ),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : AnimatedBuilder(
                      key: const ValueKey('voice-search'),
                      animation: _micPulseController,
                      builder: (context, _) {
                        return Container(
                          width: 36,
                          height: 36,
                          decoration: _isListening
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
                                  color: AppTheme.primaryContainer
                                      .withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              _isListening
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              color: _isListening
                                  ? AppTheme.typeVoice
                                  : AppTheme.primary,
                              size: 19,
                            ),
                            tooltip: _isListening
                                ? 'Stop listening'
                                : 'Voice search',
                            onPressed: _toggleVoiceSearch,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _buildFilterChip('all', 'All'),
          const SizedBox(width: 8),
          _buildFilterChip('text', 'Notes'),
          const SizedBox(width: 8),
          _buildFilterChip('voice', 'Voice'),
          const SizedBox(width: 8),
          _buildFilterChip('photo', 'Photos'),
          const SizedBox(width: 8),
          _buildFilterChip('screenshot', 'Screenshots'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _filterType == key;
    final bgColor = isSelected ? AppTheme.secondaryContainer : AppTheme.surfaceContainerLow;
    final textColor = isSelected ? Colors.white : AppTheme.onSurfaceVariant;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _filterType = key);
        loadMemories(showLoader: false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTheme.labelCaps.copyWith(color: textColor),
        ),
      ),
    );
  }

  Widget _buildOnThisDaySection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.secondary.withValues(alpha: 0.12),
              AppTheme.primary.withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.secondary.withValues(alpha: 0.25),
            width: 1.2,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: AppTheme.secondary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'On This Day',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                        Text(
                          'Rediscover past memories & ideas',
                          style: AppTheme.bodyMd.copyWith(
                            fontSize: 11,
                            color: AppTheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: AppTheme.outline),
                  tooltip: 'Dismiss for now',
                  onPressed: () => setState(() => _dismissedOnThisDay = true),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 106,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _onThisDayMemories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, idx) {
                  final memory = _onThisDayMemories[idx];
                  final timeAgo = _formatTimeAgo(memory.createdAt);
                  return InkWell(
                    onTap: () => _editMemory(memory),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                AppTheme.getMemoryTypeIcon(memory.type.name),
                                size: 14,
                                color: AppTheme.getMemoryTypeColor(memory.type.name),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  timeAgo,
                                  style: AppTheme.labelCaps.copyWith(
                                    color: AppTheme.secondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            memory.title.isNotEmpty ? memory.title : 'Untitled Memory',
                            style: AppTheme.bodyMd.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            memory.content.isNotEmpty
                                ? memory.content
                                : (memory.aiAnalysis?.description ?? ''),
                            style: AppTheme.bodyMd.copyWith(
                              fontSize: 11,
                              color: AppTheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays >= 365) {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    } else if (difference.inDays >= 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else if (difference.inDays >= 7) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else {
      return 'Today';
    }
  }

  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      key: const ValueKey('memory-loading'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 92),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.surfaceContainer,
                  border: Border.all(color: AppTheme.surface, width: 4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: index == 0 ? 138 : 118,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeletonBox(width: 100, height: 14),
                      const SizedBox(height: 14),
                      _skeletonBox(width: double.infinity, height: 12),
                      const SizedBox(height: 8),
                      _skeletonBox(width: MediaQuery.of(context).size.width * 0.4, height: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _skeletonBox({double? width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      key: const ValueKey('memory-error'),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: AppTheme.error,
            ),
            const SizedBox(height: 14),
            Text(
              'Memories could not load',
              style: AppTheme.headlineMdMobile,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: AppTheme.bodyMd.copyWith(color: AppTheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: loadMemories,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasSearch = _searchController.text.trim().isNotEmpty;

    // Filter-specific empty titles & descriptions
    String emptyTitle;
    String emptyDesc;
    if (hasSearch) {
      emptyTitle = 'No matching memories';
      emptyDesc = 'Try a different word, tag, or clear the filters.';
    } else if (_filterType == 'all') {
      emptyTitle = 'Start your memory box';
      emptyDesc = 'Save notes, voice thoughts, photos, screenshots, and links as soon as they happen.';
    } else if (_filterType == 'voice') {
      emptyTitle = 'No voice notes yet';
      emptyDesc = 'Tap + to record a quick voice thought.';
    } else if (_filterType == 'photo') {
      emptyTitle = 'No photos yet';
      emptyDesc = 'Tap + to capture or pick a photo.';
    } else if (_filterType == 'screenshot') {
      emptyTitle = 'No screenshots yet';
      emptyDesc = 'Tap + to capture a screenshot.';
    } else {
      emptyTitle = 'No ${_filterType} memories yet';
      emptyDesc = 'Tap + to add your first ${_filterType} memory.';
    }

    return Center(
      key: const ValueKey('memory-empty'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: AppTheme.primaryContainer.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              ),
              child: Icon(
                hasSearch
                    ? Icons.manage_search_rounded
                    : _filterType == 'all'
                        ? Icons.inventory_2_rounded
                        : AppTheme.getMemoryTypeIcon(_filterType),
                size: 42,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              emptyTitle,
              textAlign: TextAlign.center,
              style: AppTheme.headlineMdMobile,
            ),
            const SizedBox(height: 8),
            Text(
              emptyDesc,
              textAlign: TextAlign.center,
              style: AppTheme.bodyMd.copyWith(color: AppTheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            if (hasSearch)
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _filterType = 'all');
                  loadMemories(showLoader: false);
                },
                icon: const Icon(Icons.close_rounded),
                label: const Text('Clear search'),
              )
            else
              ElevatedButton.icon(
                onPressed: _openCapture,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Capture first memory'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryCard(Memory memory) {
    final dateStr = DateFormat("MMM d, yyyy 'at' h:mm a").format(memory.createdAt);
    final hasImage = memory.mediaPath != null &&
        (memory.type == MemoryType.photo || memory.type == MemoryType.screenshot);

    final dotBg = AppTheme.getMemoryTypeColor(memory.type.name);
    final dotIcon = AppTheme.getMemoryTypeIcon(memory.type.name);
    const dotIconColor = Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotBg,
              border: Border.all(color: AppTheme.surface, width: 4),
            ),
            child: Icon(dotIcon, color: dotIconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Builder(
              builder: (context) {
                bool isHovered = false;
                final isPlayingThis = _playingId == memory.id;
                final formattedTime = isPlayingThis && _audioPosition > Duration.zero
                    ? '${_audioPosition.inMinutes}:${(_audioPosition.inSeconds % 60).toString().padLeft(2, '0')}'
                    : (memory.type == MemoryType.voice ? 'Voice' : '');

                return StatefulBuilder(
                  builder: (context, setCardState) {
                    return MouseRegion(
                      onEnter: (_) => setCardState(() => isHovered = true),
                      onExit: (_) => setCardState(() => isHovered = false),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerLowest, // #FFFFFF
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: AppTheme.cardShadow,
                          border: Border.all(
                            color: isHovered ? AppTheme.secondary : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _editMemory(memory),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            if (memory.isPinned) ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.secondary
                                                      .withValues(alpha: 0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.push_pin_rounded,
                                                      size: 11,
                                                      color: AppTheme.secondary,
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      'PINNED',
                                                      style: AppTheme.labelCaps
                                                          .copyWith(
                                                            color: AppTheme
                                                                .secondary,
                                                            fontSize: 9.5,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            Text(
                                              dateStr.toUpperCase(),
                                              style: AppTheme.labelCaps.copyWith(
                                                color: AppTheme.outline,
                                              ),
                                            ),
                                          ],
                                        ),
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_horiz, color: AppTheme.outline),
                                          onSelected: (val) {
                                            if (val == 'edit') {
                                              _editMemory(memory);
                                            } else if (val == 'pin') {
                                              _togglePin(memory);
                                            } else if (val == 'delete') {
                                              _deleteMemory(memory);
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: 'pin',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    memory.isPinned
                                                        ? Icons.push_pin_outlined
                                                        : Icons.push_pin_rounded,
                                                    size: 18,
                                                    color: AppTheme.secondary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(memory.isPinned ? 'Unpin' : 'Pin to top'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit_rounded, size: 18, color: AppTheme.onSurfaceVariant),
                                                  SizedBox(width: 8),
                                                  Text('Edit'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete_rounded, size: 18, color: AppTheme.error),
                                                  SizedBox(width: 8),
                                                  Text('Delete', style: TextStyle(color: AppTheme.error)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (hasImage)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      child: Builder(
                                        builder: (context) {
                                          final paths = memory.mediaPaths;
                                          if (paths.length <= 1) {
                                            // Single image — same as before
                                            return Stack(
                                              children: [
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: Image.file(
                                                    File(paths.first),
                                                    width: double.infinity,
                                                    height: 200,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => Container(
                                                      height: 96,
                                                      color: AppTheme.surfaceContainer,
                                                      child: const Center(
                                                        child: Icon(Icons.broken_image_rounded, color: AppTheme.outline),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                if (memory.aiAnalysis != null && memory.aiAnalysis!.description.isNotEmpty)
                                                  Positioned(
                                                    top: 8,
                                                    right: 8,
                                                    child: AppTheme.glassContainer(
                                                      padding: const EdgeInsets.all(8),
                                                      radius: 999,
                                                      child: const Icon(Icons.auto_awesome, color: AppTheme.secondary, size: 18),
                                                    ),
                                                  ),
                                              ],
                                            );
                                          }
                                          // Multi-photo carousel
                                          return _MultiPhotoCarousel(
                                            paths: paths,
                                            hasAiAnalysis: memory.aiAnalysis != null && memory.aiAnalysis!.description.isNotEmpty,
                                          );
                                        },
                                      ),
                                    ),
                                  if (memory.type == MemoryType.voice && memory.mediaPath != null)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      child: Row(
                                        children: [
                                          GestureDetector(
                                            onTap: () => _playVoice(memory),
                                            child: Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: isPlayingThis ? AppTheme.error : AppTheme.primary,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                isPlayingThis ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Row(
                                              children: List.generate(15, (index) {
                                                final height = 10.0 + (index % 4) * 5.0;
                                                final isPastBar = isPlayingThis && (_audioDuration.inMilliseconds > 0) &&
                                                    ((index / 15.0) <= (_audioPosition.inMilliseconds / _audioDuration.inMilliseconds));

                                                return Container(
                                                  width: 4,
                                                  height: height,
                                                  margin: const EdgeInsets.only(right: 4),
                                                  decoration: BoxDecoration(
                                                    color: isPastBar
                                                        ? AppTheme.primary
                                                        : AppTheme.primaryContainer.withValues(alpha: 0.6),
                                                    borderRadius: BorderRadius.circular(2),
                                                  ),
                                                );
                                              }),
                                            ),
                                          ),
                                          Text(
                                            formattedTime,
                                            style: AppTheme.labelCaps.copyWith(
                                              color: isPlayingThis ? AppTheme.primary : AppTheme.outline,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          memory.title,
                                          style: AppTheme.titleSm.copyWith(fontSize: 15.5),
                                        ),
                                        if (memory.content.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            memory.content,
                                            style: AppTheme.bodyMd.copyWith(color: AppTheme.onSurfaceVariant),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        if (memory.aiAnalysis != null && memory.aiAnalysis!.description.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          AppTheme.glassContainer(
                                            padding: const EdgeInsets.all(12),
                                            radius: 8,
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Icon(Icons.auto_awesome, color: AppTheme.secondary, size: 16),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    memory.aiAnalysis!.description,
                                                    style: AppTheme.bodyMd.copyWith(
                                                      color: AppTheme.onSurfaceVariant,
                                                      fontStyle: FontStyle.italic,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        if (memory.tags.isNotEmpty) ...[
                                          const SizedBox(height: 12),
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
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Swipeable multi-photo carousel used inside memory feed cards.
class _MultiPhotoCarousel extends StatefulWidget {
  final List<String> paths;
  final bool hasAiAnalysis;

  const _MultiPhotoCarousel({
    required this.paths,
    required this.hasAiAnalysis,
  });

  @override
  State<_MultiPhotoCarousel> createState() => _MultiPhotoCarouselState();
}

class _MultiPhotoCarouselState extends State<_MultiPhotoCarousel> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          children: [
            SizedBox(
              height: 200,
              child: PageView.builder(
                itemCount: widget.paths.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(widget.paths[index]),
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 96,
                        color: AppTheme.surfaceContainer,
                        child: const Center(
                          child: Icon(Icons.broken_image_rounded, color: AppTheme.outline),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Counter badge
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_currentPage + 1}/${widget.paths.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (widget.hasAiAnalysis)
              Positioned(
                top: 8,
                right: 8,
                child: AppTheme.glassContainer(
                  padding: const EdgeInsets.all(8),
                  radius: 999,
                  child: const Icon(Icons.auto_awesome, color: AppTheme.secondary, size: 18),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Dot indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.paths.length, (index) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _currentPage == index ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _currentPage == index ? AppTheme.primary : AppTheme.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}
