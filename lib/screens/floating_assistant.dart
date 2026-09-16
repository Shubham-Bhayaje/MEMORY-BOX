import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/rendering.dart';
import '../theme/app_theme.dart';
import '../models/memory.dart';
import '../database/db_helper.dart';
import '../services/llm_service.dart';

enum AssistantModalMode { none, text, photo, screenshot, voice, reply }

class FloatingAssistantOverlay extends StatefulWidget {
  final GlobalKey screenshotKey;
  final VoidCallback onMemoryAdded;
  final bool showBubble;

  const FloatingAssistantOverlay({
    super.key,
    required this.screenshotKey,
    required this.onMemoryAdded,
    this.showBubble = true,
  });

  @override
  FloatingAssistantOverlayState createState() =>
      FloatingAssistantOverlayState();
}

class FloatingAssistantOverlayState extends State<FloatingAssistantOverlay>
    with TickerProviderStateMixin {
  // Public method to start voice assistant from outside
  void startVoiceAssistant() {
    _startVoiceAssistant();
  }

  void openTextModal() {
    setState(() {
      _closeAllOverlays();
      _modalMode = AssistantModalMode.text;
    });
  }

  void openVoiceModal() {
    setState(() {
      _closeAllOverlays();
      _modalMode = AssistantModalMode.voice;
    });
    _startVoiceRecording();
  }

  void openScreenshotWithFile(File file) {
    setState(() {
      _closeAllOverlays();
      _pickedImageFile = file;
      _modalMode = AssistantModalMode.screenshot;
    });
  }

  void openPhotoWithFile(File file) {
    setState(() {
      _closeAllOverlays();
      _pickedImageFile = file;
      _modalMode = AssistantModalMode.photo;
    });
  }

  // Draggable physics coordinates
  double _x = 0;
  double _y = 0;
  bool _isInitialized = false;
  final double _bubbleSize = 56.0;

  // Snapping controller
  late AnimationController _snapController;
  double _startX = 0;
  double _endX = 0;

  // Pulse controller for voice/mic
  late AnimationController _pulseController;

  // Overlay / Menu State
  bool _isMenuOpen = false;
  AssistantModalMode _modalMode = AssistantModalMode.none;

  // TTS & STT instances
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _speechEnabled = false;

  // LLM and DB Helpers
  final DBHelper _dbHelper = DBHelper();
  final LLMService _llmService = LLMService();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();

  // Dialog Form Controllers
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _infoController = TextEditingController();

  // Photo / Screenshot states
  File? _pickedImageFile;
  bool _isAnalyzing = false;
  AIAnalysis? _aiAnalysis;

  // Voice recording states
  bool _isRecording = false;
  bool _isTranscribing = false;
  String? _voiceFilePath;
  bool _useSystemSTT = true;

  // Voice Assistant (Long Press) states
  bool _isListening = false;
  bool _isThinking = false;
  String _listeningTranscript = "";
  String _aiReplyText = "";
  bool _isTtsSpeaking = false;
  List<Memory> _referencedMemories = [];

  @override
  void initState() {
    super.initState();
    _snapController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 300),
        )..addListener(() {
          setState(() {
            _x = ui.lerpDouble(
              _startX,
              _endX,
              CurvedAnimation(
                parent: _snapController,
                curve: Curves.easeOutBack,
              ).value,
            )!;
          });
        });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _initSpeechRecognizer();
    _initTts();
    _loadSTTSetting();
  }

  Future<void> _initSpeechRecognizer() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onStatus: (status) => debugPrint('Assistant STT status: $status'),
        onError: (error) => debugPrint('Assistant STT error: $error'),
      );
    } catch (e) {
      debugPrint('Failed to initialize speech recognition: $e');
    }
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _flutterTts.setStartHandler(() {
        setState(() => _isTtsSpeaking = true);
      });
      _flutterTts.setCompletionHandler(() {
        setState(() => _isTtsSpeaking = false);
      });
      _flutterTts.setErrorHandler((msg) {
        setState(() => _isTtsSpeaking = false);
      });
    } catch (e) {
      debugPrint('Failed to initialize TTS: $e');
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
    _snapController.dispose();
    _pulseController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _infoController.dispose();
    _audioRecorder.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  void _closeAllOverlays() {
    _flutterTts.stop();
    _pulseController.stop();
    if (_isRecording) {
      _audioRecorder.stop();
      _speechToText.stop();
    }
    setState(() {
      _isMenuOpen = false;
      _modalMode = AssistantModalMode.none;
      _isListening = false;
      _isThinking = false;
      _isRecording = false;
      _isTranscribing = false;
      _pickedImageFile = null;
      _voiceFilePath = null;
      _aiAnalysis = null;
      _titleController.clear();
      _contentController.clear();
      _infoController.clear();
      _listeningTranscript = "";
      _referencedMemories = [];
    });
  }

  // --- CAPTURE SCREENSHOT ---
  Future<String?> _captureScreenshot() async {
    try {
      // 1. Wait for any pending frame/layout phase to finish painting
      if (WidgetsBinding.instance.schedulerPhase != SchedulerPhase.idle) {
        await WidgetsBinding.instance.endOfFrame;
      }

      // Let's add a short buffer delay for layout stabilizes
      await Future.delayed(const Duration(milliseconds: 50));

      RenderRepaintBoundary? boundary;
      for (int i = 0; i < 5; i++) {
        boundary =
            widget.screenshotKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary != null && !boundary.debugNeedsPaint) {
          break;
        }
        debugPrint(
          'Repaint boundary is dirty, waiting for next frame... (attempt $i)',
        );
        await WidgetsBinding.instance.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      if (boundary == null) {
        debugPrint('RepaintBoundary context or render object not found.');
        return null;
      }

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final pngBytes = byteData.buffer.asUint8List();
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(pngBytes);
      return path;
    } catch (e) {
      debugPrint('Failed to capture screenshot: $e');
      return null;
    }
  }

  // --- RECORDING ACTIONS ---
  Future<void> _startVoiceRecording() async {
    if (await _audioRecorder.hasPermission()) {
      if (_useSystemSTT) {
        try {
          if (!_speechEnabled) {
            await _initSpeechRecognizer();
          }
        } catch (e) {
          debugPrint('Live STT init failed: $e');
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/assistant_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      _contentController.clear();
      _titleController.clear();

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );

      setState(() {
        _isRecording = true;
        _voiceFilePath = path;
      });

      _pulseController.repeat(reverse: true);

      if (_useSystemSTT && _speechEnabled) {
        _speechToText.listen(
          onResult: (result) {
            if (mounted && _isRecording) {
              setState(() {
                _contentController.text = result.recognizedWords;
                if (_titleController.text.trim().isEmpty) {
                  final words = result.recognizedWords.split(RegExp(r'\s+'));
                  if (words.isNotEmpty && result.recognizedWords.isNotEmpty) {
                    _titleController.text = words.take(5).join(' ');
                  }
                }
              });
            }
          },
          listenOptions: stt.SpeechListenOptions(
            listenMode: stt.ListenMode.dictation,
            partialResults: true,
            cancelOnError: false,
          ),
        );
      }
    }
  }

  Future<void> _stopVoiceRecording() async {
    final path = await _audioRecorder.stop();
    if (_useSystemSTT && _speechEnabled) {
      await _speechToText.stop();
    }
    _pulseController.stop();
    setState(() {
      _isRecording = false;
      _voiceFilePath = path;
    });

    if (path != null) {
      if (!_useSystemSTT || _contentController.text.trim().isEmpty) {
        _transcribeVoice(path);
      }
    }
  }

  Future<void> _transcribeVoice(String path) async {
    setState(() => _isTranscribing = true);
    try {
      final file = File(path);
      if (await file.exists()) {
        final transcription = await _llmService.transcribeAudio(file);
        setState(() {
          _contentController.text = transcription;
          if (_titleController.text.trim().isEmpty) {
            final words = transcription.split(RegExp(r'\s+'));
            if (words.isNotEmpty && transcription.isNotEmpty) {
              _titleController.text = words.take(5).join(' ');
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transcription failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTranscribing = false);
    }
  }

  // --- SAVE MEMORY HANDLERS ---
  Future<void> _saveTextMemory() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;

    final memory = Memory(
      id: const Uuid().v4(),
      type: MemoryType.text,
      title: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : 'Quick Note',
      content: content,
      mediaPath: null,
      aiAnalysis: null,
      tags: ['quick-floater'],
      createdAt: DateTime.now(),
    );

    await _dbHelper.insertMemory(memory);
    widget.onMemoryAdded();
    _closeAllOverlays();
    _showToast('Memory saved');
  }

  Future<void> _savePhotoMemory() async {
    if (_pickedImageFile == null) return;

    // Copy file to app docs directory
    final dir = await getApplicationDocumentsDirectory();
    final ext = _pickedImageFile!.path.split('.').last;
    final newPath =
        '${dir.path}/floater_img_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _pickedImageFile!.copy(newPath);

    final memory = Memory(
      id: const Uuid().v4(),
      type: MemoryType.photo,
      title: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : (_aiAnalysis?.description ?? 'Quick Photo'),
      content: _contentController.text.trim(),
      mediaPath: newPath,
      aiAnalysis: _aiAnalysis,
      tags: ['quick-floater', ...?_aiAnalysis?.tags],
      createdAt: DateTime.now(),
    );

    await _dbHelper.insertMemory(memory);
    widget.onMemoryAdded();
    _closeAllOverlays();
    _showToast('Photo memory saved');
  }

  Future<void> _saveScreenshotMemory() async {
    if (_pickedImageFile == null) return;

    final memory = Memory(
      id: const Uuid().v4(),
      type: MemoryType.screenshot,
      title: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : 'Screen Capture',
      content: _contentController.text.trim().isNotEmpty
          ? _contentController.text.trim()
          : (_infoController.text.isNotEmpty
                ? 'Context: ${_infoController.text}'
                : ''),
      mediaPath: _pickedImageFile!.path,
      aiAnalysis: _aiAnalysis,
      tags: ['quick-floater', 'screenshot', ...?_aiAnalysis?.tags],
      createdAt: DateTime.now(),
    );

    await _dbHelper.insertMemory(memory);
    widget.onMemoryAdded();
    _closeAllOverlays();
    _showToast('Screenshot memory saved');
  }

  Future<void> _saveVoiceMemory() async {
    if (_voiceFilePath == null) return;

    final memory = Memory(
      id: const Uuid().v4(),
      type: MemoryType.voice,
      title: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : 'Quick Voice Note',
      content: _contentController.text.trim(),
      mediaPath: _voiceFilePath,
      aiAnalysis: null,
      tags: ['quick-floater', 'voice-note'],
      createdAt: DateTime.now(),
    );

    await _dbHelper.insertMemory(memory);
    widget.onMemoryAdded();
    _closeAllOverlays();
    _showToast('Voice memory saved');
  }

  // --- AI IMAGE ANALYSIS ---
  Future<void> _analyzeSelectedImage(String type) async {
    if (_pickedImageFile == null) return;
    setState(() => _isAnalyzing = true);
    try {
      final analysis = await _llmService.analyzeImage(_pickedImageFile!, type);
      if (!mounted) return;
      setState(() {
        _aiAnalysis = analysis;
        if (_titleController.text.isEmpty) {
          _titleController.text = analysis.description.length > 50
              ? '${analysis.description.substring(0, 50)}...'
              : analysis.description;
        }
      });
    } catch (e) {
      debugPrint('AI analysis error: $e');
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  // --- LONG PRESS VOICE ASSISTANT ---
  Future<void> _startVoiceAssistant() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _closeAllOverlays();
      _isListening = true;
      _listeningTranscript = "Listening...";
    });

    _pulseController.repeat(reverse: true);

    try {
      if (!_speechEnabled) {
        await _initSpeechRecognizer();
      }

      if (_speechEnabled) {
        await _speechToText.listen(
          onResult: (result) {
            setState(() {
              _listeningTranscript = result.recognizedWords;
            });
          },
          listenOptions: stt.SpeechListenOptions(
            listenMode: stt.ListenMode.confirmation,
            partialResults: true,
            cancelOnError: false,
          ),
        );

        // Simple timeout to auto-ask if user stops speaking
        Future.delayed(const Duration(seconds: 8), () {
          if (mounted &&
              _isListening &&
              _listeningTranscript != "Listening..." &&
              _listeningTranscript.trim().isNotEmpty) {
            _stopAndQueryAssistant();
          }
        });
      } else {
        setState(() {
          _isListening = false;
          _showToast("Speech Recognition not supported on this device");
        });
      }
    } catch (e) {
      setState(() {
        _isListening = false;
        _showToast("Failed to start voice listener");
      });
    }
  }

  Future<void> _stopAndQueryAssistant() async {
    if (!_isListening) return;
    await _speechToText.stop();
    _pulseController.stop();

    final query = _listeningTranscript.trim();
    if (query.isEmpty || query == "Listening...") {
      _closeAllOverlays();
      _showToast("No speech detected");
      return;
    }

    setState(() {
      _isListening = false;
      _isThinking = true;
    });

    try {
      final memories = await _dbHelper.getMemories();
      final reply = await _llmService.chatWithMemory(query, memories);
      final referenced = _fetchReferencedMemories(reply, memories);

      setState(() {
        _isThinking = false;
        _modalMode = AssistantModalMode.reply;
        _aiReplyText = reply;
        _referencedMemories = referenced;
      });

      // Play audio response
      await _flutterTts.speak(
        reply.replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1'),
      ); // Strip raw links for TTS
    } catch (e) {
      setState(() {
        _isThinking = false;
        _modalMode = AssistantModalMode.reply;
        _aiReplyText = "I couldn't complete the query: $e";
        _referencedMemories = [];
      });
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: AppTheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double screenWidth = size.width;
    final double screenHeight = size.height;

    // Initialize position to bottom right
    if (!_isInitialized && screenWidth > 0 && screenHeight > 0) {
      _x = screenWidth - _bubbleSize - 16.0;
      _y = screenHeight - 170.0;
      _isInitialized = true;
    }

    final bool hasActiveOverlay =
        _modalMode != AssistantModalMode.none || _isListening || _isThinking;
    final bool hasMenuOpen = _isMenuOpen && widget.showBubble;

    // Don't render anything if bubble is hidden and no active overlay
    if (!widget.showBubble && !hasActiveOverlay) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Backdrop tap dismisser for menu
        if (hasMenuOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _isMenuOpen = false),
            ),
          ),

        // Backdrop filter for overlay focus - ONLY show when dialogs are active
        if (hasActiveOverlay)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeAllOverlays,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(color: Colors.black.withOpacity(0.3)),
                ),
              ),
            ),
          ),

          // Centered Overlay Dialogs based on mode
          if (_modalMode != AssistantModalMode.none ||
              _isListening ||
              _isThinking)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: _buildDialogContent(),
              ),
            ),

          // Floating Action Menu options - ONLY if bubble is visible
          if (hasMenuOpen) _buildFloatingMenu(screenWidth, screenHeight),

          // Persistent Assistant Bubble
          if (widget.showBubble)
            Positioned(
              left: _x,
              top: _y,
              child: GestureDetector(
                key: const Key('assistant_bubble'),
                onPanUpdate: (details) {
                  setState(() {
                    _x += details.delta.dx;
                    _y += details.delta.dy;
                    // Clamp within bounds
                    _x = _x.clamp(16.0, screenWidth - _bubbleSize - 16.0);
                    _y = _y.clamp(80.0, screenHeight - 120.0);
                  });
                },
                onPanEnd: (details) {
                  _startX = _x;
                  _endX = (_x + _bubbleSize / 2 < screenWidth / 2)
                      ? 16.0
                      : screenWidth - _bubbleSize - 16.0;
                  _snapController.forward(from: 0);
                },
                onTap: () {
                  if (_modalMode != AssistantModalMode.none ||
                      _isListening ||
                      _isThinking) {
                    _closeAllOverlays();
                  } else {
                    setState(() {
                      _isMenuOpen = !_isMenuOpen;
                    });
                  }
                },
                onLongPress: _startVoiceAssistant,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _bubbleSize,
                  height: _bubbleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.primaryGradient,
                    boxShadow: AppTheme.coloredShadow(AppTheme.primary),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
  }

  // --- FLOATING MENU WIDGET ---
  Widget _buildFloatingMenu(double screenWidth, double screenHeight) {
    final bool isOnLeft = _x < screenWidth / 2;
    final double menuWidth = 200.0;

    // Position menu next to bubble with better spacing
    double menuX = isOnLeft ? _x + _bubbleSize + 8.0 : _x - menuWidth - 8.0;

    // Clamp to screen bounds
    menuX = menuX.clamp(8.0, screenWidth - menuWidth - 8.0);

    // Vertically align with bubble
    double menuY = _y - 50.0;
    if (menuY < 80) menuY = 80.0;
    if (menuY + 240 > screenHeight - 80) {
      menuY = screenHeight - 320;
    }

    final List<Map<String, dynamic>> menuItems = [
      {
        'icon': Icons.edit_note_rounded,
        'label': 'Add Note',
        'color': AppTheme.typeText,
        'mode': AssistantModalMode.text,
      },
      {
        'icon': Icons.mic_rounded,
        'label': 'Voice Note',
        'color': AppTheme.typeVoice,
        'mode': AssistantModalMode.voice,
      },
      {
        'icon': Icons.photo_library_rounded,
        'label': 'Pick Photo',
        'color': AppTheme.typePhoto,
        'mode': AssistantModalMode.photo,
      },
      {
        'icon': Icons.screenshot_monitor_rounded,
        'label': 'Screenshot',
        'color': AppTheme.typeScreenshot,
        'mode': AssistantModalMode.screenshot,
      },
    ];

    return Positioned(
      left: menuX,
      top: menuY,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            alignment: isOnLeft ? Alignment.centerLeft : Alignment.centerRight,
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          );
        },
        child: Material(
          color: Colors.transparent,
          elevation: 8,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: menuWidth,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.border.withOpacity(0.5),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: menuItems.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Column(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          setState(() {
                            _isMenuOpen = false;
                          });

                          // Small delay for animation
                          await Future.delayed(
                            const Duration(milliseconds: 100),
                          );

                          if (item['mode'] == AssistantModalMode.photo) {
                            final picked = await _imagePicker.pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 1920,
                              imageQuality: 85,
                            );
                            if (picked != null && mounted) {
                              setState(() {
                                _pickedImageFile = File(picked.path);
                                _modalMode = AssistantModalMode.photo;
                              });
                            }
                          } else if (item['mode'] ==
                              AssistantModalMode.screenshot) {
                            final path = await _captureScreenshot();
                            if (path != null && mounted) {
                              setState(() {
                                _pickedImageFile = File(path);
                                _modalMode = AssistantModalMode.screenshot;
                              });
                            } else {
                              _showToast("Screenshot capture failed");
                            }
                          } else if (item['mode'] == AssistantModalMode.voice) {
                            if (mounted) {
                              setState(() {
                                _modalMode = AssistantModalMode.voice;
                              });
                              _startVoiceRecording();
                            }
                          } else {
                            if (mounted) {
                              setState(() {
                                _modalMode = item['mode'] as AssistantModalMode;
                              });
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: (item['color'] as Color).withOpacity(
                                    0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  item['icon'] as IconData,
                                  color: item['color'] as Color,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item['label'] as String,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: AppTheme.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (index < menuItems.length - 1)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: AppTheme.border.withOpacity(0.3),
                        indent: 12,
                        endIndent: 12,
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // --- DIALOG BUILDER ---
  Widget _buildDialogContent() {
    if (_isListening) {
      return _buildListeningCard();
    }
    if (_isThinking) {
      return _buildThinkingCard();
    }

    switch (_modalMode) {
      case AssistantModalMode.text:
        return _buildTextModal();
      case AssistantModalMode.photo:
        return _buildPhotoModal();
      case AssistantModalMode.screenshot:
        return _buildScreenshotModal();
      case AssistantModalMode.voice:
        return _buildVoiceModal();
      case AssistantModalMode.reply:
        return _buildReplyModal();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTextModal() {
    return _buildDialogFrame(
      title: 'New Note',
      icon: Icons.edit_note_rounded,
      color: AppTheme.typeText,
      onSave: _saveTextMemory,
      body: Column(
        children: [
          TextField(
            controller: _titleController,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              hintText: 'Title (optional)',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentController,
            maxLines: 5,
            style: const TextStyle(fontSize: 14, height: 1.5),
            decoration: const InputDecoration(
              hintText: 'Type note details here...',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoModal() {
    return _buildDialogFrame(
      title: 'Add Photo Memory',
      icon: Icons.photo_library_rounded,
      color: AppTheme.typePhoto,
      onSave: _savePhotoMemory,
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_pickedImageFile != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  _pickedImageFile!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isAnalyzing
                    ? null
                    : () => _analyzeSelectedImage('photo'),
                icon: _isAnalyzing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(
                  _isAnalyzing ? 'Analyzing...' : '✨ Auto-Analyze with AI',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            if (_aiAnalysis != null) ...[
              const SizedBox(height: 10),
              _buildAIAnalysisWidget(),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: 'Title',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              maxLines: 3,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Extra context/notes (optional)',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenshotModal() {
    return _buildDialogFrame(
      title: 'Screenshot Memory',
      icon: Icons.screenshot_monitor_rounded,
      color: AppTheme.typeScreenshot,
      onSave: _saveScreenshotMemory,
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_pickedImageFile != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  _pickedImageFile!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isAnalyzing
                    ? null
                    : () => _analyzeSelectedImage('screenshot'),
                icon: _isAnalyzing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(
                  _isAnalyzing ? 'Analyzing...' : '✨ Auto-Analyze with AI',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            if (_aiAnalysis != null) ...[
              const SizedBox(height: 10),
              _buildAIAnalysisWidget(),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: 'Screenshot Title',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              maxLines: 3,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Additional info or context...',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceModal() {
    return _buildDialogFrame(
      title: 'Voice Recorder',
      icon: Icons.mic_rounded,
      color: AppTheme.typeVoice,
      onSave: _saveVoiceMemory,
      body: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              return GestureDetector(
                onTap: () {
                  if (_isRecording) {
                    _stopVoiceRecording();
                  } else {
                    _startVoiceRecording();
                  }
                },
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording
                        ? AppTheme.typeVoice.withOpacity(
                            0.08 + _pulseController.value * 0.08,
                          )
                        : AppTheme.surfaceAlt,
                    border: Border.all(
                      color: _isRecording
                          ? AppTheme.typeVoice
                          : AppTheme.border,
                      width: 2,
                    ),
                    boxShadow: _isRecording
                        ? AppTheme.coloredShadow(AppTheme.typeVoice)
                        : [],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 38,
                    color: _isRecording
                        ? AppTheme.typeVoice
                        : AppTheme.textTertiary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            _isRecording
                ? 'Recording voice... Tap to stop'
                : _isTranscribing
                    ? '✨ Transcribing with AI...'
                    : _voiceFilePath != null
                        ? '✅ Voice recording saved locally'
                        : 'Tap to start recording',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _isRecording || _isTranscribing
                  ? AppTheme.typeVoice
                  : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              hintText: 'Title (optional)',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentController,
            maxLines: 3,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Transcription/notes text here...',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListeningCard() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border, width: 1.5),
          boxShadow: AppTheme.mediumShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primary.withOpacity(
                      0.1 + _pulseController.value * 0.08,
                    ),
                    border: Border.all(color: AppTheme.primary, width: 2),
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    color: AppTheme.primary,
                    size: 36,
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'Listening to your question...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _listeningTranscript,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: _closeAllOverlays,
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _stopAndQueryAssistant,
                  child: const Text('Ask AI'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingCard() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border, width: 1.5),
          boxShadow: AppTheme.mediumShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 3),
            const SizedBox(height: 20),
            const Text(
              'Searching memories...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '"$_listeningTranscript"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyModal() {
    final links = _extractLinksFromText(_aiReplyText);

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border, width: 1.5),
          boxShadow: AppTheme.mediumShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.psychology_rounded,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'AI Assistant Reply',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _isTtsSpeaking
                        ? Icons.volume_up_rounded
                        : Icons.volume_mute_rounded,
                    color: AppTheme.primary,
                  ),
                  onPressed: () {
                    if (_isTtsSpeaking) {
                      _flutterTts.stop();
                      setState(() => _isTtsSpeaking = false);
                    } else {
                      _flutterTts.speak(
                        _aiReplyText.replaceAll(
                          RegExp(r'\[([^\]]+)\]\([^\)]+\)'),
                          r'$1',
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const Divider(color: AppTheme.border, height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MarkdownBody(
                      data: _aiReplyText,
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
                        p: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                          height: 1.5,
                        ),
                        strong: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        em: const TextStyle(
                          fontStyle: FontStyle.italic,
                          color: AppTheme.textSecondary,
                        ),
                        a: const TextStyle(
                          color: AppTheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                        blockSpacing: 12.0,
                      ),
                    ),
                    if (_referencedMemories.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ..._referencedMemories
                          .map((memory) => _buildReferencedMemoryCard(memory)),
                    ],
                  ],
                ),
              ),
            ),
            if (links.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: links.map((link) {
                  final label = link['label'] ?? '';
                  final url = link['url'] ?? '';
                  return Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
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
                            topLeft: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.link_rounded,
                                  size: 13,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(height: 14, width: 1, color: AppTheme.border),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 11),
                          color: AppTheme.textSecondary,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: url));
                            _showToast('Copied link: $url');
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _closeAllOverlays,
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogFrame({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onSave,
    required Widget body,
  }) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border, width: 1.5),
          boxShadow: AppTheme.mediumShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const Divider(color: AppTheme.border, height: 20),
            body,
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _closeAllOverlays,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAIAnalysisWidget() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: AppTheme.cardShimmer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.secondary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: AppTheme.secondary,
              ),
              const SizedBox(width: 6),
              const Text(
                'AI Image Analysis',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _aiAnalysis!.description,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          if (_aiAnalysis!.extractedText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _aiAnalysis!.extractedText,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Map<String, String>> _extractLinksFromText(String text) {
    final List<Map<String, String>> links = [];
    final Set<String> seen = {};

    final markdownRegex = RegExp(
      r'\[([^\]]+)\]\(((?:https?:\/\/|www\.)[^\s\)]+)\)',
    );
    for (final match in markdownRegex.allMatches(text)) {
      final label = match.group(1) ?? '';
      var url = match.group(2) ?? '';
      if (url.startsWith('www.')) url = 'https://$url';
      if (!seen.contains(url)) {
        seen.add(url);
        links.add({'label': label, 'url': url});
      }
    }

    final urlRegex = RegExp(r'(https?:\/\/[^\s\)]+)');
    for (final match in urlRegex.allMatches(text)) {
      var url = match.group(0) ?? '';
      if (!seen.contains(url)) {
        seen.add(url);
        String label = url;
        try {
          final uri = Uri.parse(url);
          label = uri.host;
          if (label.startsWith('www.')) label = label.substring(4);
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
          // Check if titles match or one contains the other
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

    // Pattern 1: **Memory Title**: Title (Type, Date) — allow newlines between title and (Type)
    final labelRegex = RegExp(
      r'\*\*(?:Memory\s+)?Title\*\*:\s*(.{1,250}?)\s*\((Photo|Screenshot|Voice|Text|TEXT|PHOTO|SCREENSHOT|VOICE),\s*[^)]+\)',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in labelRegex.allMatches(response)) {
      final title = (match.group(1) ?? '').replaceAll('\n', ' ');
      final typeStr = match.group(2) ?? '';
      addMemoryIfMatch(title, typeStr);
    }

    // Pattern 2: **Title** (Type, Date) — allow newlines between ** and (
    final citationRegex = RegExp(
      r'\*\*([^*]+)\*\*\s*\((Photo|Screenshot|Voice|Text|TEXT|PHOTO|SCREENSHOT|VOICE),\s*[^)]+\)',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in citationRegex.allMatches(response)) {
      final title = (match.group(1) ?? '').replaceAll('\n', ' ');
      final typeStr = match.group(2) ?? '';
      // Avoid matching "Memory Title" as standard title
      if (title.trim().toLowerCase() != 'memory title') {
        addMemoryIfMatch(title, typeStr);
      }
    }

    // Pattern 3: Line-based generic fallback with previous-line lookup
    final genericCitationRegex = RegExp(
      r'\((Photo|Screenshot|Voice|Text|TEXT|PHOTO|SCREENSHOT|VOICE),\s*[^)]+\)',
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

        // If 'before' is empty, the (Type, Date) is at the start of this line —
        // look at the previous non-empty line for the title text
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

    // Pattern 4: Broad fallback — check if any photo/screenshot memory title
    // appears in the response text (handles all unusual citation formats)
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
          // Strip trailing "..." for better matching against partial titles
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

  void _showImageDialog(BuildContext context, Memory memory) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: memory.mediaPaths.length <= 1
                  ? InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.file(
                        File(memory.mediaPaths.isNotEmpty
                            ? memory.mediaPaths.first
                            : memory.mediaPath!),
                        fit: BoxFit.contain,
                      ),
                    )
                  : SizedBox(
                      height: 280,
                      child: PageView.builder(
                        itemCount: memory.mediaPaths.length,
                        itemBuilder: (ctx, i) => InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: Image.file(
                            File(memory.mediaPaths[i]),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memory.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (memory.aiAnalysis != null &&
                      memory.aiAnalysis!.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      memory.aiAnalysis!.description,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferencedMemoryCard(Memory memory) {
    final color = AppTheme.getMemoryTypeColor(memory.type.name);
    final imagePaths = memory.mediaPaths;
    final hasImage =
        imagePaths.isNotEmpty &&
        (memory.type == MemoryType.photo ||
            memory.type == MemoryType.screenshot);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (hasImage) {
                _showImageDialog(context, memory);
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasImage)
                  Image.file(
                    File(imagePaths.first),
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 60,
                      color: AppTheme.surface,
                      child: const Center(
                        child: Icon(
                          Icons.broken_image_rounded,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          AppTheme.getMemoryTypeIcon(memory.type.name),
                          size: 14,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              memory.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (hasImage) ...[
                              const SizedBox(height: 2),
                              const Text(
                                'Tap to view full image',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
