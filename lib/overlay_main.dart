import 'package:flutter/material.dart';
import 'screens/overlay_bubble.dart';

/// This is the entry point for the system overlay window.
/// It runs in a separate Flutter engine from the main app.
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayBubbleWidget(),
    ),
  );
}
