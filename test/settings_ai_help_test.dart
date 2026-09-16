import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memorybox/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AiProviderHelpSheet renders correctly and supports interactions',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    String? selectedProvider;
    String? openedPortalProvider;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiProviderHelpSheet(
            initialProvider: 'github',
            onSelectProvider: (provider) {
              selectedProvider = provider;
            },
            onOpenPortal: (provider) {
              openedPortalProvider = provider;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify header and titles
    expect(find.text('AI Provider Setup Guide'), findsOneWidget);
    expect(find.text('How to get API keys & connect models'), findsOneWidget);
    expect(find.text('Step-by-Step Setup'), findsOneWidget);
    expect(find.text('Recommended Models (Tap to copy)'), findsOneWidget);

    // 2. Verify all 6 providers are available in tabs
    expect(find.text('GitHub Models'), findsWidgets);
    expect(find.text('Google Gemini'), findsWidgets);
    expect(find.text('Local Ollama'), findsWidgets);
    expect(find.text('OpenAI'), findsWidgets);
    expect(find.text('Anthropic Claude'), findsWidgets);
    expect(find.text('Hugging Face'), findsWidgets);

    // 3. Test portal button callback
    final portalBtn = find.text('Open GitHub Models Portal');
    expect(portalBtn, findsOneWidget);
    await tester.tap(portalBtn);
    expect(openedPortalProvider, 'github');

    // 4. Switch tab to Local Ollama
    final localTab = find.widgetWithText(FilterChip, 'Local Ollama');
    expect(localTab, findsOneWidget);
    await tester.ensureVisible(localTab);
    await tester.pumpAndSettle();
    await tester.tap(localTab);
    await tester.pumpAndSettle();

    // Verify Ollama setup steps and Wi-Fi tips appear
    expect(find.textContaining('OLLAMA_HOST=0.0.0.0:11434'), findsOneWidget);
    expect(find.textContaining('IMPORTANT FOR PHONES'), findsOneWidget);

    // 5. Test Select & Use button callback
    final selectBtn = find.text('Select & Use');
    expect(selectBtn, findsOneWidget);
    await tester.tap(selectBtn);
    expect(selectedProvider, 'local');

    // 6. Test Model chip copy interaction
    final llamaModelChip = find.text('llama3.2');
    expect(llamaModelChip, findsOneWidget);
    await tester.ensureVisible(llamaModelChip);
    await tester.pumpAndSettle();
    await tester.tap(llamaModelChip);
    await tester.pump();
    expect(find.textContaining('Copied "llama3.2" to clipboard'), findsOneWidget);
  });

  testWidgets('AiProviderHelpSheet bottom buttons and layout do not overflow on narrow screens',
      (WidgetTester tester) async {
    // Test on a narrow 320px screen
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiProviderHelpSheet(
            initialProvider: 'local',
            onSelectProvider: (_) {},
            onOpenPortal: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify buttons render cleanly without throwing RenderFlex overflow
    expect(find.text('Select & Use'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
  });
}
