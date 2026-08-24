import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../database/db_helper.dart';
import 'memory_feed.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'add_memory_sheet.dart';
import 'floating_assistant.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _currentIndex = 0;
  final GlobalKey<MemoryFeedState> _feedKey = GlobalKey<MemoryFeedState>();
  final GlobalKey _screenshotKey = GlobalKey();
  final GlobalKey<FloatingAssistantOverlayState> _assistantKey =
      GlobalKey<FloatingAssistantOverlayState>();
  final DBHelper _dbHelper = DBHelper();
  late AnimationController _fabController;
  bool _systemOverlayEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _initSystemOverlay();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshOverlayState();
      _checkAndProcessPendingOverlayAction();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshOverlayState();
      _checkAndProcessPendingOverlayAction();
    }
  }

  Future<void> _checkAndProcessPendingOverlayAction() async {
    try {
      final action = await _dbHelper.getPendingOverlayAction();
      if (action == null || action.isEmpty) return;

      await _dbHelper.updatePendingOverlayAction(null);
      debugPrint('Processing pending overlay action in home screen: $action');

      if (!mounted) return;

      switch (action) {
        case 'open_text':
          _openAddMemory(initialType: 'text');
          break;
        case 'open_photo':
          _openAddMemory(initialType: 'photo');
          break;
        case 'open_voice':
          _openAddMemory(initialType: 'voice');
          break;
        case 'open_screenshot':
          final path = await _captureScreenshot();
          if (path != null) {
            _assistantKey.currentState?.openScreenshotWithFile(File(path));
          }
          break;
        case 'open_voice_assistant':
          _selectTab(1);
          Future.delayed(const Duration(milliseconds: 350), () {
            _assistantKey.currentState?.startVoiceAssistant();
          });
          break;
        case 'open_app':
          break;
      }
    } catch (e) {
      debugPrint('Error checking or processing pending overlay action: $e');
    }
  }

  Future<String?> _captureScreenshot() async {
    try {
      if (WidgetsBinding.instance.schedulerPhase != SchedulerPhase.idle) {
        await WidgetsBinding.instance.endOfFrame;
      }
      await Future.delayed(const Duration(milliseconds: 50));

      RenderRepaintBoundary? boundary;
      for (int i = 0; i < 5; i++) {
        boundary =
            _screenshotKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary != null && !boundary.debugNeedsPaint) {
          break;
        }
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
      debugPrint('Failed to capture screenshot in home screen: $e');
      return null;
    }
  }

  Future<void> _refreshOverlayState() async {
    try {
      final settings = await _dbHelper.getSettings();
      final enabled = (settings['system_overlay_enabled'] ?? '0') == '1';
      if (mounted && enabled != _systemOverlayEnabled) {
        setState(() => _systemOverlayEnabled = enabled);
      }
    } catch (_) {}
  }

  static const _appLauncherChannel = MethodChannel(
    'com.memorybox.memorybox/app_launcher',
  );

  Future<void> _bringAppToForeground() async {
    try {
      await _appLauncherChannel.invokeMethod('bringToForeground');
    } catch (e) {
      debugPrint('Failed to bring app to foreground: $e');
    }
  }

  Future<void> _initSystemOverlay() async {
    FlutterOverlayWindow.overlayListener.listen((data) {
      debugPrint('Overlay event received in main app: $data');
      if (data == 'open_text') {
        _bringAppToForeground().then(
          (_) => _openAddMemory(initialType: 'text'),
        );
      } else if (data == 'open_photo') {
        _bringAppToForeground().then(
          (_) => _openAddMemory(initialType: 'photo'),
        );
      } else if (data == 'open_voice') {
        _bringAppToForeground().then(
          (_) => _openAddMemory(initialType: 'voice'),
        );
      } else if (data == 'open_screenshot') {
        _bringAppToForeground().then((_) async {
          final path = await _captureScreenshot();
          if (path != null) {
            _assistantKey.currentState?.openScreenshotWithFile(File(path));
          }
        });
      } else if (data == 'open_voice_assistant') {
        _bringAppToForeground().then((_) {
          _selectTab(1);
          Future.delayed(const Duration(milliseconds: 300), () {
            _assistantKey.currentState?.startVoiceAssistant();
          });
        });
      } else if (data == 'open_app') {
        _bringAppToForeground();
      } else if (data == 'close_bubble') {
        _dbHelper.updateSystemOverlayEnabled(false).then((_) {
          _refreshOverlayState();
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fabController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (!mounted) return;
    setState(() => _currentIndex = index);
    if (index == 0) {
      _fabController.forward();
    } else {
      _fabController.reverse();
    }
  }

  void _openAddMemory({String? initialType}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddMemorySheet(
        initialType: initialType,
        onMemoryAdded: () {
          _feedKey.currentState?.loadMemories();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RepaintBoundary(
          key: _screenshotKey,
          child: Scaffold(
            extendBody: true,
            body: Stack(
              children: [
                SafeArea(
                  bottom: false,
                  child: IndexedStack(
                    index: _currentIndex,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 64.0),
                        child: MemoryFeed(
                          key: _feedKey,
                          onMemoriesChanged: () {
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 64.0),
                        child: ChatScreen(),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 64.0),
                        child: SettingsScreen(onOverlayToggled: _refreshOverlayState),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildHeader(),
                ),
              ],
            ),
            floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
            floatingActionButton: Padding(
              padding: const EdgeInsets.only(bottom: 12.0, right: 6.0),
              child: (_currentIndex == 0 && (_feedKey.currentState?.hasMemories ?? false))
                  ? ScaleTransition(
                      scale: CurvedAnimation(
                        parent: _fabController,
                        curve: Curves.easeOutBack,
                      ),
                      child: Semantics(
                        button: true,
                        label: 'Capture a new memory',
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppTheme.fabGradient,
                            boxShadow: AppTheme.fabShadow,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _openAddMemory,
                              child: const Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
            bottomNavigationBar: _buildBottomNav(),
          ),
        ),
        Positioned.fill(
          child: FloatingAssistantOverlay(
            key: _assistantKey,
            screenshotKey: _screenshotKey,
            showBubble: false,
            onMemoryAdded: () {
              _feedKey.currentState?.loadMemories();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64 + MediaQuery.of(context).padding.top,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top,
            left: 20,
            right: 20,
          ),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: 0.6),
          ),
          child: Row(
            children: [
              Image.asset(
                'assets/images/logo.png',
                width: 34,
                height: 34,
              ),
              const SizedBox(width: 10),
              Text(
                'Memory Box',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: AppTheme.navShadow,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.timeline, 'Feed'),
              _buildNavItem(1, Icons.psychology, 'Recall'),
              _buildNavItem(2, Icons.settings, 'Settings'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _selectTab(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.secondaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: Icon(
              icon,
              color: isSelected ? Colors.white : AppTheme.onSurfaceVariant,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTheme.labelCaps.copyWith(
              color: isSelected ? AppTheme.secondaryContainer : AppTheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
