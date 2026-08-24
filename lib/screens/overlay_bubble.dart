import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:url_launcher/url_launcher.dart';
import '../database/db_helper.dart';

/// A compact floating bubble widget that appears as a system overlay
/// on top of other apps. Tapping opens a menu with quick actions.
/// Long pressing opens the app in voice assistant mode.
class OverlayBubbleWidget extends StatefulWidget {
  const OverlayBubbleWidget({super.key});

  @override
  State<OverlayBubbleWidget> createState() => _OverlayBubbleWidgetState();
}

class _OverlayBubbleWidgetState extends State<OverlayBubbleWidget>
    with SingleTickerProviderStateMixin {
  bool _isMenuExpanded = false;

  static const _bubbleSize = 70.0;

  // HSL-based colors matching AppTheme
  static const Color _primary = Color(0xFF4F46E5);
  static const Color _typeText = Color(0xFF00B894);
  static const Color _typePhoto = Color(0xFFFDAC53);
  static const Color _typeVoice = Color(0xFFE17055);
  static const Color _typeScreenshot = Color(0xFF0984E3);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _border = Color(0xFFE8ECF2);
  static const Color _textPrimary = Color(0xFF1A1D26);

  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  final DBHelper _dbHelper = DBHelper();

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutBack,
    );

    // Listen for messages from the main app
    FlutterOverlayWindow.overlayListener.listen((data) {
      if (data == 'close') {
        FlutterOverlayWindow.closeOverlay();
      }
    });
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _onBubbleTap() {
    if (_isMenuExpanded) {
      _expandController.reverse().then((_) {
        setState(() => _isMenuExpanded = false);
        FlutterOverlayWindow.resizeOverlay(100, 100, true);
      });
    } else {
      FlutterOverlayWindow.resizeOverlay(220, 520, true).then((_) {
        setState(() => _isMenuExpanded = true);
        _expandController.forward();
      });
    }
  }

  Future<void> _launchAppWithAction(String action) async {
    // 1. ALWAYS fire shareData first — this works reliably for warm starts
    FlutterOverlayWindow.shareData(action);

    // 2. Try to save to SQLite (may fail in overlay isolate — that's OK)
    try {
      await _dbHelper.updatePendingOverlayAction(action);
    } catch (e) {
      debugPrint("DB write failed in overlay isolate (expected): $e");
    }

    // 3. Try to launch URL scheme to wake/resume app from cold start
    try {
      final uri = Uri.parse('memorybox://open?action=$action');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("URL launch failed in overlay isolate: $e");
    }
  }

  void _onBubbleLongPress() {
    // Send message to main app to open in voice assistant mode
    _launchAppWithAction('open_voice_assistant');
  }

  void _onMenuAction(String action) {
    // Send the action and deep link
    _launchAppWithAction(action);

    _expandController.reverse().then((_) {
      setState(() => _isMenuExpanded = false);
      FlutterOverlayWindow.resizeOverlay(100, 100, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final double width = _isMenuExpanded ? 220 : 100;
    final double height = _isMenuExpanded ? 520 : 100;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        child: _isMenuExpanded ? _buildExpandedMenu() : _buildBubble(),
      ),
    );
  }

  Widget _buildBubble() {
    return GestureDetector(
      onTap: _onBubbleTap,
      onLongPress: _onBubbleLongPress,
      child: Container(
        width: _bubbleSize,
        height: _bubbleSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6C5CE7), Color(0xFF8B7CF6)],
          ),
          boxShadow: [
            BoxShadow(
              color: _primary.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Logo centered
            Center(
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: _bubbleSize - 8,
                  height: _bubbleSize - 8,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            // Close button badge
            Positioned(
              right: -4,
              top: -4,
              child: GestureDetector(
                onTap: () {
                  FlutterOverlayWindow.shareData('close_bubble');
                  FlutterOverlayWindow.closeOverlay();
                },
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedMenu() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizeTransition(
          sizeFactor: _expandAnimation,
          axisAlignment: 1.0,
          child: Container(
            width: 180,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMenuItem(
                  icon: Icons.edit_note_rounded,
                  label: 'Text',
                  color: _typeText,
                  onTap: () => _onMenuAction('open_text'),
                ),
                const SizedBox(height: 4),
                _buildMenuItem(
                  icon: Icons.photo_library_rounded,
                  label: 'Photo',
                  color: _typePhoto,
                  onTap: () => _onMenuAction('open_photo'),
                ),
                const SizedBox(height: 4),
                _buildMenuItem(
                  icon: Icons.mic_rounded,
                  label: 'Voice',
                  color: _typeVoice,
                  onTap: () => _onMenuAction('open_voice'),
                ),
                const SizedBox(height: 4),
                _buildMenuItem(
                  icon: Icons.screenshot_monitor_rounded,
                  label: 'Screenshot',
                  color: _typeScreenshot,
                  onTap: () => _onMenuAction('open_screenshot'),
                ),
                const SizedBox(height: 4),
                _buildMenuItem(
                  icon: Icons.open_in_new_rounded,
                  label: 'Open App',
                  color: _primary,
                  onTap: () => _onMenuAction('open_app'),
                ),
                const SizedBox(height: 4),
                _buildMenuItem(
                  icon: Icons.close_rounded,
                  label: 'Close Bubble',
                  color: Colors.redAccent,
                  onTap: () {
                    FlutterOverlayWindow.shareData('close_bubble');
                    FlutterOverlayWindow.closeOverlay();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildBubble(),
      ],
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
