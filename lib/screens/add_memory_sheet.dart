import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../theme/app_theme.dart';
import '../models/memory.dart';
import '../database/db_helper.dart';
import '../services/llm_service.dart';
import '../utils/error_handler.dart';
import '../utils/input_validator.dart';

class AddMemorySheet extends StatefulWidget {
  final VoidCallback onMemoryAdded;
  final Memory? memoryToEdit;
  final String? initialType;

  const AddMemorySheet({
    super.key,
    required this.onMemoryAdded,
    this.memoryToEdit,
    this.initialType,
  });

  @override
  State<AddMemorySheet> createState() => _AddMemorySheetState();
}

class _AddMemorySheetState extends State<AddMemorySheet>
    with TickerProviderStateMixin {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _tagController = TextEditingController();
  final _dbHelper = DBHelper();
  final _llmService = LLMService();
  final _imagePicker = ImagePicker();
  final _audioRecorder = AudioRecorder();
  final stt.SpeechToText _speechToText = stt.SpeechToText();

  String _selectedType = 'text';
  List<File> _selectedImages = [];
  String? _voicePath;
  bool _isRecording = false;
  bool _isAnalyzing = false;
  bool _isTranscribing = false;
  bool _isEnhancingText = false;
  bool _isSaving = false;
  AIAnalysis? _aiAnalysis;
  List<String> _tags = [];
  late AnimationController _pulseController;
  bool _speechEnabled = false;
  bool _useSystemSTT = true;

  final FocusNode _contentFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _contentFocusNode.addListener(() {
      setState(() {});
    });

    _loadSTTSetting();
    _hydrateEditState();
    _hydrateInitialType();
  }

  void _hydrateInitialType() {
    if (widget.initialType == null || widget.memoryToEdit != null) return;

    _selectedType = widget.initialType!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 260), () {
        if (!mounted) return;
        if (_selectedType == 'photo' || _selectedType == 'screenshot') {
          _pickImage(ImageSource.gallery);
        } else if (_selectedType == 'voice') {
          _toggleRecording();
        }
      });
    });
  }

  void _hydrateEditState() {
    final memory = widget.memoryToEdit;
    if (memory == null) return;

    _selectedType = memory.type.name;
    _titleController.text = memory.title;
    _contentController.text = memory.content;
    _tags = List<String>.from(memory.tags);
    _aiAnalysis = memory.aiAnalysis;

    if (memory.type == MemoryType.voice) {
      _voicePath = memory.mediaPath;
    } else if ((memory.type == MemoryType.photo ||
            memory.type == MemoryType.screenshot) &&
        memory.mediaPath != null) {
      _selectedImages = memory.mediaPaths
          .map((p) => File(p))
          .where((f) => f.existsSync())
          .toList();
    }
  }

  Future<void> _loadSTTSetting() async {
    try {
      final settings = await _dbHelper.getSettings();
      if (!mounted) return;
      setState(() {
        _useSystemSTT = (settings['use_system_stt'] ?? '1') == '1';
      });
    } catch (e) {
      debugPrint('Failed to load STT setting: $e');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    _pulseController.dispose();
    _audioRecorder.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        // Multi-select from gallery
        final pickedList = await _imagePicker.pickMultiImage(
          maxWidth: 1920,
          imageQuality: 85,
        );
        if (pickedList.isEmpty || !mounted) return;

        bool hasScreenshot = false;
        final newFiles = <File>[];
        for (final picked in pickedList) {
          final pathLower = picked.path.toLowerCase();
          if (pathLower.contains('screenshot') ||
              pathLower.contains('screencap') ||
              pathLower.contains('screen_shot') ||
              pathLower.contains('screen-shot')) {
            hasScreenshot = true;
          }
          newFiles.add(File(picked.path));
        }

        setState(() {
          _selectedImages.addAll(newFiles);
          if (_selectedType == 'photo' && hasScreenshot) {
            _selectedType = 'screenshot';
          }
          _aiAnalysis = null;
        });
      } else {
        // Single capture from camera
        final picked = await _imagePicker.pickImage(
          source: source,
          maxWidth: 1920,
          imageQuality: 85,
        );
        if (picked == null || !mounted) return;

        setState(() {
          _selectedImages.add(File(picked.path));
          _aiAnalysis = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorSnackBar(
        context,
        message: ErrorHandler.getUserMessage(e),
      );
    }
  }

  Future<void> _analyzeImage() async {
    if (_selectedImages.isEmpty || _isAnalyzing) return;

    setState(() => _isAnalyzing = true);
    _pulseController.repeat(reverse: true);
    try {
      final analysis = await _llmService.analyzeImage(
        _selectedImages.first,
        _selectedType,
      );
      if (!mounted) return;
      setState(() {
        _aiAnalysis = analysis;
        if (_titleController.text.trim().isEmpty) {
          _titleController.text = analysis.description.isNotEmpty
              ? _compactTitle(analysis.description)
              : 'Untitled ${AppTheme.getMemoryTypeLabel(_selectedType)}';
        }
        for (final tag in analysis.tags) {
          final clean = InputValidator.sanitizeTag(tag);
          if (clean.isNotEmpty && !_tags.contains(clean)) {
            _tags.add(clean);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorSnackBar(
        context,
        message: ErrorHandler.getUserMessage(e),
        onRetry: _analyzeImage,
      );
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        if (!_isRecording) _pulseController.stop();
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_isTranscribing || _isSaving) return;

    if (_isRecording) {
      await _stopRecording();
      return;
    }

    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _showSnack('Microphone permission is needed to record voice memories.');
        return;
      }

      if (_useSystemSTT) {
        try {
          if (!_speechEnabled) {
            _speechEnabled = await _speechToText.initialize(
              onStatus: (status) => debugPrint('Live STT status: $status'),
              onError: (error) => debugPrint('Live STT error: $error'),
            );
          }
        } catch (e) {
          debugPrint('Failed to initialize live speech recognition: $e');
          _speechEnabled = false;
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      if (widget.memoryToEdit == null) {
        _contentController.clear();
      }

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );

      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _voicePath = path;
      });
      _pulseController.repeat(reverse: true);

      if (_useSystemSTT && _speechEnabled) {
        _speechToText.listen(
          onResult: (result) {
            if (!mounted || !_isRecording) return;
            setState(() {
              _contentController.text = result.recognizedWords;
              if (_titleController.text.trim().isEmpty) {
                _titleController.text = _titleFromText(result.recognizedWords);
              }
            });
          },
          listenOptions: stt.SpeechListenOptions(
            listenMode: stt.ListenMode.dictation,
            partialResults: true,
            cancelOnError: false,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorSnackBar(
        context,
        message: ErrorHandler.getUserMessage(e),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (_useSystemSTT && _speechEnabled) {
        await _speechToText.stop();
      }
      _pulseController.stop();
      _pulseController.reset();

      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _voicePath = path;
      });

      if (path != null &&
          (!_useSystemSTT || _contentController.text.trim().isEmpty)) {
        _transcribeVoice(path);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRecording = false);
      ErrorHandler.showErrorSnackBar(
        context,
        message: ErrorHandler.getUserMessage(e),
      );
    }
  }

  Future<void> _transcribeVoice(String path) async {
    if (_isTranscribing) return;

    setState(() => _isTranscribing = true);
    _pulseController.repeat(reverse: true);
    try {
      final file = File(path);
      if (!await file.exists()) {
        throw Exception('File not found');
      }

      final transcription = await _llmService.transcribeAudio(file);
      if (!mounted) return;
      setState(() {
        _contentController.text = transcription;
        if (_titleController.text.trim().isEmpty) {
          _titleController.text = _titleFromText(transcription);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorSnackBar(
        context,
        message: 'Transcription failed. ${ErrorHandler.getUserMessage(e)}',
        onRetry: () => _transcribeVoice(path),
      );
    } finally {
      if (mounted) {
        setState(() => _isTranscribing = false);
        if (!_isRecording && !_isAnalyzing) _pulseController.stop();
      }
    }
  }

  void _changeType(String type) {
    if (_selectedType == type || _isRecording || _isSaving) return;
    setState(() {
      _selectedType = type;
      _aiAnalysis = null;
      if (type == 'text') {
        _selectedImages.clear();
        _voicePath = null;
      } else if (type == 'voice') {
        _selectedImages.clear();
      } else {
        _voicePath = null;
      }
    });
  }

  void _addTag() {
    final tag = InputValidator.sanitizeTag(_tagController.text);
    if (tag.isEmpty || _tags.contains(tag)) {
      _tagController.clear();
      return;
    }

    setState(() {
      _tags.add(tag);
      _tagController.clear();
    });
  }

  Future<void> _saveMemory() async {
    final title = InputValidator.sanitizeTitle(_titleController.text);
    final content = InputValidator.sanitizeContent(_contentController.text);
    final hasMedia = _selectedImages.isNotEmpty || _voicePath != null;

    if (title.trim().isEmpty && content.trim().isEmpty && !hasMedia) {
      _showSnack('Add text, media, or a recording before saving.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      String? savedMediaPath;
      if (_selectedImages.isNotEmpty) {
        final savedPaths = <String>[];
        for (final img in _selectedImages) {
          savedPaths.add(await _copyImageToAppDirectory(img));
        }
        savedMediaPath = savedPaths.join('|');
      } else if (_voicePath != null) {
        final file = File(_voicePath!);
        if (await file.exists()) {
          savedMediaPath = _voicePath;
        }
      }

      final isEditing = widget.memoryToEdit != null;
      final typeLabel = AppTheme.getMemoryTypeLabel(_selectedType);
      final memory = Memory(
        id: isEditing ? widget.memoryToEdit!.id : const Uuid().v4(),
        type: MemoryType.fromJson(_selectedType),
        title: title.trim().isNotEmpty ? title.trim() : 'Untitled $typeLabel',
        content: content.trim(),
        mediaPath: savedMediaPath,
        aiAnalysis: _aiAnalysis,
        tags: _tags
            .map(InputValidator.sanitizeTag)
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList(),
        createdAt: isEditing ? widget.memoryToEdit!.createdAt : DateTime.now(),
      );

      await _dbHelper.insertMemory(memory);
      widget.onMemoryAdded();

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorSnackBar(
        context,
        message: ErrorHandler.getUserMessage(e),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<String> _copyImageToAppDirectory(File source) async {
    final editPath = widget.memoryToEdit?.mediaPath;
    if (editPath != null && source.path == editPath) {
      return editPath;
    }

    if (!await source.exists()) {
      throw Exception('File not found');
    }

    final size = await source.length();
    const maxImageSize = 50 * 1024 * 1024;
    if (size > maxImageSize) {
      throw Exception('File too large');
    }

    final dir = await getApplicationDocumentsDirectory();
    final ext = source.path
        .split('.')
        .last
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    final safeExt = ext.isEmpty ? 'jpg' : ext;
    final newPath =
        '${dir.path}/img_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    await source.copy(newPath);
    return newPath;
  }

  String _compactTitle(String text) {
    final clean = InputValidator.sanitizeTitle(
      text,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= 60) return clean;
    return '${clean.substring(0, 57).trim()}...';
  }

  String _titleFromText(String text) {
    final clean = InputValidator.sanitizeTitle(
      text,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return '';
    final words = clean.split(' ');
    final title = words.take(6).join(' ');
    return title.length > 56 ? '${title.substring(0, 53).trim()}...' : title;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.92,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.5),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.15),
                  blurRadius: 32,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDragHandle(),
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTypeSelector(),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _titleController,
                          textInputAction: TextInputAction.next,
                          style: AppTheme.titleSm,
                          decoration: InputDecoration(
                            hintText: 'Title',
                            hintStyle: AppTheme.titleSm.copyWith(
                              color: AppTheme.onSurfaceVariant.withOpacity(0.5),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_selectedType == 'text') _buildTextInput(),
                        if (_selectedType == 'voice') _buildVoiceRecorder(),
                        if (_selectedType == 'photo' ||
                            _selectedType == 'screenshot')
                          _buildImagePicker(),
                        const SizedBox(height: 24),
                        _buildTagInput(),
                        const SizedBox(height: 32),
                        _buildSaveButton(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        width: 12,
        height: 1.5,
        decoration: BoxDecoration(
          color: AppTheme.outlineVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final editing = widget.memoryToEdit != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            editing ? 'Edit Memory' : 'Capture Memory',
            style: AppTheme.titleSm,
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              hoverColor: AppTheme.surfaceVariant,
              onTap: _isSaving ? null : () => Navigator.of(context).pop(),
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.close, size: 24, color: AppTheme.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector() {
    final types = [
      {'key': 'text', 'icon': Icons.notes_rounded, 'label': 'Text'},
      {'key': 'photo', 'icon': Icons.photo_camera_rounded, 'label': 'Photo'},
      {'key': 'screenshot', 'icon': Icons.screenshot_monitor_rounded, 'label': 'Screen'},
      {'key': 'voice', 'icon': Icons.mic_rounded, 'label': 'Voice'},
    ];

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: types.map((type) {
        final key = type['key'] as String;
        final isSelected = _selectedType == key;
        
        return Material(
          color: isSelected ? AppTheme.primaryContainer.withOpacity(0.1) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            hoverColor: AppTheme.surfaceVariant,
            onTap: () => _changeType(key),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppTheme.primaryContainer : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    type['icon'] as IconData,
                    color: isSelected ? AppTheme.primary : AppTheme.onSurfaceVariant,
                    size: 22,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    type['label'] as String,
                    style: AppTheme.labelCaps.copyWith(
                      color: isSelected ? AppTheme.primary : AppTheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextInput() {
    final isFocused = _contentFocusNode.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 128),
              decoration: BoxDecoration(
                color: isFocused ? AppTheme.surfaceContainerLowest : AppTheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  bottom: BorderSide(
                    color: isFocused ? AppTheme.secondary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _contentController,
                focusNode: _contentFocusNode,
                minLines: 5,
                maxLines: null,
                style: AppTheme.bodyMd,
                decoration: InputDecoration(
                  hintText: 'What\'s on your mind?',
                  hintStyle: AppTheme.bodyMd.copyWith(
                    color: AppTheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_isEnhancingText)
              Positioned(
                bottom: 12,
                right: 12,
                child: _buildAnalyzingBadge(),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (!_isEnhancingText && _aiAnalysis == null)
          ElevatedButton.icon(
            onPressed: _contentController.text.trim().length < 3
                ? null
                : _enhanceTextNote,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('AI Assist'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.secondary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.surfaceContainerHigh,
              disabledForegroundColor: AppTheme.outline,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        if (_aiAnalysis != null) ...[
          const SizedBox(height: 12),
          _buildAIResultCard(),
        ],
      ],
    );
  }

  Future<void> _enhanceTextNote() async {
    final text = _contentController.text.trim();
    if (text.isEmpty || _isEnhancingText) return;

    setState(() => _isEnhancingText = true);
    _pulseController.repeat(reverse: true);
    try {
      final analysis = await _llmService.enhanceTextNote(
        text,
        title: _titleController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _aiAnalysis = analysis;
        // Auto-fill title if empty and AI returned something useful
        if (_titleController.text.trim().isEmpty &&
            analysis.description.isNotEmpty) {
          _titleController.text = _compactTitle(analysis.description);
        }
        // Merge AI-suggested tags
        for (final tag in analysis.tags) {
          final clean = InputValidator.sanitizeTag(tag);
          if (clean.isNotEmpty && !_tags.contains(clean)) {
            _tags.add(clean);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorSnackBar(
        context,
        message: ErrorHandler.getUserMessage(e),
        onRetry: _enhanceTextNote,
      );
    } finally {
      if (mounted) {
        setState(() => _isEnhancingText = false);
        if (!_isRecording && !_isAnalyzing) _pulseController.stop();
      }
    }
  }

  Widget _buildAnalyzingBadge() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppTheme.secondary.withOpacity(0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
              ),
            ],
          ),
          child: Opacity(
            opacity: 0.6 + (_pulseController.value * 0.4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: AppTheme.secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'AI Analyzing...',
                  style: AppTheme.labelCaps.copyWith(
                    color: AppTheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVoiceRecorder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32),
          decoration: BoxDecoration(
            color: AppTheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return GestureDetector(
                    onTap: _isTranscribing ? null : _toggleRecording,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording
                            ? AppTheme.typeVoice.withOpacity(
                                0.2 + _pulseController.value * 0.2,
                              )
                            : AppTheme.primary,
                        boxShadow: _isRecording
                            ? [
                                BoxShadow(
                                  color: AppTheme.typeVoice.withOpacity(0.4),
                                  blurRadius: 16 * _pulseController.value,
                                  spreadRadius: 8 * _pulseController.value,
                                )
                              ]
                            : [],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              if (_isRecording)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red.withOpacity(
                              0.5 + (_pulseController.value * 0.5),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Recording...',
                      style: AppTheme.labelCaps.copyWith(color: AppTheme.error),
                    ),
                  ],
                )
              else if (_isTranscribing)
                Text(
                  'Transcribing...',
                  style: AppTheme.labelCaps.copyWith(color: AppTheme.typeVoice),
                )
              else if (_voicePath != null)
                Text(
                  'Voice Note Recorded',
                  style: AppTheme.labelCaps,
                )
              else
                Text(
                  'Tap to record',
                  style: AppTheme.labelCaps,
                ),
            ],
          ),
        ),
        if (!_isRecording && !_isTranscribing && _voicePath != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _transcribeVoice(_voicePath!),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Transcribe with AI'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.secondary,
              side: const BorderSide(color: AppTheme.secondary),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildTextInput(),
      ],
    );
  }

  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedImages.isNotEmpty) ...[
          // Primary image preview (first image)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  _selectedImages.first,
                  height: 240,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 240,
                    color: AppTheme.surfaceContainerLow,
                    child: const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: AppTheme.outline,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
              if (_isAnalyzing)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: _buildAnalyzingBadge(),
                ),
              // Photo count badge
              if (_selectedImages.length > 1)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_selectedImages.length} photos',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
          // Thumbnail strip for multiple images
          if (_selectedImages.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _selectedImages[index],
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 72,
                            height: 72,
                            color: AppTheme.surfaceContainerLow,
                            child: const Icon(Icons.broken_image, size: 20, color: AppTheme.outline),
                          ),
                        ),
                      ),
                      // Remove button
                      Positioned(
                        top: -6,
                        right: -6,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedImages.removeAt(index);
                              _aiAnalysis = null;
                            });
                          },
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppTheme.error,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: const Icon(Icons.close, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.add_photo_alternate, size: 18),
                  label: const Text('Add More'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('Camera'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_isAnalyzing && _aiAnalysis == null)
            ElevatedButton.icon(
              onPressed: _analyzeImage,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Analyze Image'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.secondary,
                foregroundColor: Colors.white,
              ),
            ),
          if (_aiAnalysis != null) ...[
            const SizedBox(height: 12),
            _buildAIResultCard(),
          ],
        ] else ...[
          Row(
            children: [
              Expanded(
                child: Material(
                  color: AppTheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _pickImage(ImageSource.gallery),
                    child: Container(
                      height: 120,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.photo_library, size: 32, color: AppTheme.primary),
                          const SizedBox(height: 8),
                          Text('Gallery', style: AppTheme.labelCaps),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Material(
                  color: AppTheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _pickImage(ImageSource.camera),
                    child: Container(
                      height: 120,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.camera_alt, size: 32, color: AppTheme.primary),
                          const SizedBox(height: 8),
                          Text('Camera', style: AppTheme.labelCaps),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _buildTextInput(),
      ],
    );
  }

  Widget _buildAIResultCard() {
    final analysis = _aiAnalysis!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.secondary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.secondary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 16,
                color: AppTheme.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                'AI Analysis',
                style: AppTheme.labelCaps.copyWith(
                  color: AppTheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            analysis.description,
            style: AppTheme.bodyMd.copyWith(color: AppTheme.onSurfaceVariant),
          ),
          if (analysis.extractedText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.5)),
              ),
              child: Text(
                analysis.extractedText,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTagInput() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const Icon(Icons.local_offer, color: AppTheme.onTertiaryContainer, size: 20),
          const SizedBox(width: 12),
          ..._tags.map((tag) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text(tag),
              onDeleted: () => setState(() => _tags.remove(tag)),
              backgroundColor: AppTheme.tertiaryContainer.withOpacity(0.1),
              deleteIconColor: AppTheme.tertiaryContainer,
              labelStyle: AppTheme.labelCaps.copyWith(color: AppTheme.tertiaryContainer),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Colors.transparent),
              ),
            ),
          )),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Add Tag'),
                    content: TextField(
                      controller: _tagController,
                      decoration: const InputDecoration(hintText: 'Enter tag name'),
                      autofocus: true,
                      onSubmitted: (_) {
                        _addTag();
                        Navigator.pop(context);
                      },
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          _addTag();
                          Navigator.pop(context);
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  );
                },
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.outlineVariant,
                  style: BorderStyle.solid, 
                ), 
              ),
              child: Row(
                children: [
                  const Icon(Icons.add, size: 16, color: AppTheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Tag', style: AppTheme.labelCaps.copyWith(color: AppTheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return InkWell(
      onTap: _isSaving ? null : _saveMemory,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: AppTheme.fabGradient,
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: _isSaving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.save, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Persist to Memory',
                      style: AppTheme.titleSm.copyWith(color: Colors.white),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
