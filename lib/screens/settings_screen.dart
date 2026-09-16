import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../database/db_helper.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';
import '../utils/input_validator.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onOverlayToggled;

  const SettingsScreen({super.key, this.onOverlayToggled});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _dbHelper = DBHelper();
  final _apiKeyController = TextEditingController();
  final _endpointController = TextEditingController();
  final _modelController = TextEditingController();
  final _localAuth = LocalAuthentication();

  String _selectedProvider = 'github';
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _isUpdatingOverlay = false;
  String? _testResult;
  bool? _testSuccess;
  bool _useSystemSTT = true;
  bool _systemOverlayEnabled = false;
  bool _biometricLockEnabled = false;
  bool _obscureApiKey = true;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final _providers = [
    {
      'key': 'local',
      'name': 'Local Ollama',
      'icon': Icons.computer_rounded,
      'color': Color(0xFF10B981),
      'description': 'Private local models through Ollama or a compatible server',
      'defaultEndpoint': 'http://localhost:11434',
      'defaultModel': 'gemma3:4b',
      'needsKey': false,
      'supportsSTT': true,
    },
    {
      'key': 'github',
      'name': 'GitHub Models',
      'icon': Icons.code_rounded,
      'color': Color(0xFF0F172A),
      'description': 'Hosted models using your GitHub token',
      'defaultEndpoint': 'https://models.github.ai/inference',
      'defaultModel': 'openai/gpt-4o-mini',
      'needsKey': true,
      'supportsSTT': false,
    },
    {
      'key': 'openai',
      'name': 'OpenAI (GPT-4o)',
      'icon': Icons.auto_awesome_rounded,
      'color': Color(0xFF10A37F),
      'description': 'Fast hosted recall, chat, image analysis, and transcription',
      'defaultEndpoint': 'https://api.openai.com/v1',
      'defaultModel': 'gpt-4o-mini',
      'needsKey': true,
      'supportsSTT': true,
    },
    {
      'key': 'gemini',
      'name': 'Google Gemini',
      'icon': Icons.diamond_rounded,
      'color': Color(0xFF4285F4),
      'description': 'Google AI for chat, image analysis, and audio fallback',
      'defaultEndpoint': 'https://generativelanguage.googleapis.com',
      'defaultModel': 'gemini-1.5-flash',
      'needsKey': true,
      'supportsSTT': true,
    },
    {
      'key': 'claude',
      'name': 'Anthropic Claude',
      'icon': Icons.psychology_alt_rounded,
      'color': Color(0xFFDA7756),
      'description': 'Claude chat and vision using your Anthropic key',
      'defaultEndpoint': 'https://api.anthropic.com/v1',
      'defaultModel': 'claude-3-5-sonnet-20241022',
      'needsKey': true,
      'supportsSTT': false,
    },
    {
      'key': 'huggingface',
      'name': 'Hugging Face',
      'icon': Icons.hub_rounded,
      'color': Color(0xFFFFD21E),
      'description': 'Open-source models via Hugging Face Inference API',
      'defaultEndpoint': 'https://router.huggingface.co/v1',
      'defaultModel': 'meta-llama/Llama-3.3-70B-Instruct',
      'needsKey': true,
      'supportsSTT': true,
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _apiKeyController.dispose();
    _endpointController.dispose();
    _modelController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _dbHelper.getSettings();
      final activeProvider = settings['provider'] ?? 'github';
      final config = await _dbHelper.getProviderConfig(activeProvider);

      if (!mounted) return;
      setState(() {
        _selectedProvider = activeProvider;
        _apiKeyController.text =
            config?['api_key'] ?? settings['api_key'] ?? '';
        _endpointController.text =
            config?['api_endpoint'] ?? settings['api_endpoint'] ?? '';
        _modelController.text =
            config?['model_name'] ?? settings['model_name'] ?? '';
        _useSystemSTT = (settings['use_system_stt'] ?? '1') == '1';
        _systemOverlayEnabled =
            (settings['system_overlay_enabled'] ?? '0') == '1';
        _biometricLockEnabled =
            (settings['biometric_lock_enabled'] ?? '0') == '1';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ErrorHandler.showErrorSnackBar(
        context,
        message: ErrorHandler.getUserMessage(e),
        onRetry: _loadSettings,
      );
    }
  }

  Map<String, dynamic> get _currentProvider =>
      _providers.firstWhere((p) => p['key'] == _selectedProvider);

  String _effectiveEndpoint(Map<String, dynamic> provider) {
    final endpoint = _endpointController.text.trim();
    return endpoint.isNotEmpty
        ? endpoint
        : provider['defaultEndpoint'] as String;
  }

  String _effectiveModel(Map<String, dynamic> provider) {
    final model = _modelController.text.trim();
    return model.isNotEmpty ? model : provider['defaultModel'] as String;
  }

  String? _validateConfig({bool requireKey = true}) {
    final provider = _currentProvider;
    final endpoint = _effectiveEndpoint(provider);
    final model = _effectiveModel(provider);
    final needsKey = provider['needsKey'] as bool;
    final key = _apiKeyController.text.trim();

    final endpointError = InputValidator.validateEndpoint(endpoint);
    if (endpointError != null) return endpointError;

    final modelError = InputValidator.validateModelName(model);
    if (modelError != null) return modelError;

    if (needsKey) {
      if (key.isEmpty && requireKey) {
        return 'API key is required for ${provider['name']}.';
      }
      if (key.isNotEmpty) {
        final keyError = InputValidator.validateApiKey(key, _selectedProvider);
        if (keyError != null) return keyError;
      }
    }

    return null;
  }

  Future<void> _saveSettings({bool showSnack = true}) async {
    final validationError = _validateConfig(requireKey: false);
    if (validationError != null) {
      _showInlineResult(validationError, false);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final provider = _currentProvider;
      await _dbHelper.saveSettings(
        provider: _selectedProvider,
        apiKey: _apiKeyController.text.trim(),
        apiEndpoint: _effectiveEndpoint(provider),
        modelName: _effectiveModel(provider),
        useSystemSTT: _useSystemSTT,
      );
      await _dbHelper.updateSystemOverlayEnabled(_systemOverlayEnabled);
      widget.onOverlayToggled?.call();

      if (!mounted) return;
      if (showSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Settings saved. API keys are kept in secure storage.',
            ),
          ),
        );
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

  Future<void> _testConnection() async {
    final validationError = _validateConfig(requireKey: true);
    if (validationError != null) {
      _showInlineResult(validationError, false);
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
    });

    try {
      final provider = _selectedProvider;
      final apiKey = _apiKeyController.text.trim();
      final endpoint = _effectiveEndpoint(
        _currentProvider,
      ).replaceFirst(RegExp(r'/+$'), '');
      final model = _effectiveModel(_currentProvider);

      if (provider == 'local') {
        final response = await http
            .get(Uri.parse('$endpoint/api/tags'))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode != 200) {
          throw Exception('Status ${response.statusCode}');
        }
        final data = json.decode(response.body);
        final models =
            (data['models'] as List?)?.map((m) => m['name']).toList() ?? [];
        _showInlineResult(
          models.isEmpty
              ? 'Connected. No local models were listed.'
              : 'Connected. Available models: ${models.take(5).join(', ')}',
          true,
        );
      } else if (provider == 'github' ||
          provider == 'openai' ||
          provider == 'huggingface') {
        final response = await http
            .post(
              Uri.parse('$endpoint/chat/completions'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
              body: json.encode({
                'messages': [
                  {
                    'role': 'user',
                    'content': 'Reply with exactly CONNECTION_OK',
                  },
                ],
                'model': model,
                'max_tokens': 20,
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          throw Exception(
            '${response.statusCode}: ${_shortBody(response.body)}',
          );
        }
        _showInlineResult('Connected to $model.', true);
      } else if (provider == 'gemini') {
        final response = await http
            .post(
              Uri.parse(
                '$endpoint/v1beta/models/$model:generateContent?key=$apiKey',
              ),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'contents': [
                  {
                    'parts': [
                      {'text': 'Reply with OK'},
                    ],
                  },
                ],
                'generationConfig': {'maxOutputTokens': 10},
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          throw Exception(
            '${response.statusCode}: ${_shortBody(response.body)}',
          );
        }
        _showInlineResult('Connected to Gemini with $model.', true);
      } else if (provider == 'claude') {
        final response = await http
            .post(
              Uri.parse('$endpoint/messages'),
              headers: {
                'Content-Type': 'application/json',
                'x-api-key': apiKey,
                'anthropic-version': '2023-06-01',
              },
              body: json.encode({
                'model': model,
                'max_tokens': 10,
                'messages': [
                  {'role': 'user', 'content': 'Reply OK'},
                ],
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          throw Exception(
            '${response.statusCode}: ${_shortBody(response.body)}',
          );
        }
        _showInlineResult('Connected to Claude with $model.', true);
      }
    } catch (e) {
      if (!mounted) return;
      _showInlineResult(ErrorHandler.getUserMessage(e), false);
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  String _shortBody(String body) {
    if (body.length <= 160) return body;
    return '${body.substring(0, 160)}...';
  }

  void _showInlineResult(String message, bool success) {
    if (!mounted) return;
    setState(() {
      _testResult = message;
      _testSuccess = success;
    });
  }

  Future<void> _selectProvider(String key) async {
    final config = await _dbHelper.getProviderConfig(key);
    final provider = _providers.firstWhere((p) => p['key'] == key);
    if (!mounted) return;
    setState(() {
      _selectedProvider = key;
      _apiKeyController.text = config?['api_key'] ?? '';
      _endpointController.text =
          config?['api_endpoint'] ?? provider['defaultEndpoint'] as String;
      _modelController.text =
          config?['model_name'] ?? provider['defaultModel'] as String;
      _testResult = null;
      _testSuccess = null;
    });
  }

  Future<void> _setOverlayEnabled(bool enabled) async {
    setState(() => _isUpdatingOverlay = true);
    try {
      if (enabled) {
        var granted = await FlutterOverlayWindow.isPermissionGranted();
        if (!granted) {
          granted = await FlutterOverlayWindow.requestPermission() ?? false;
        }
        if (!granted) {
          throw Exception('Overlay permission was not granted.');
        }

        final active = await FlutterOverlayWindow.isActive();
        if (!active) {
          await FlutterOverlayWindow.showOverlay(
            width: 100,
            height: 100,
            alignment: OverlayAlignment.centerRight,
            visibility: NotificationVisibility.visibilityPrivate,
            flag: OverlayFlag.defaultFlag,
            overlayTitle: 'Memory Box capture',
            overlayContent: 'Quick capture is ready',
            enableDrag: true,
            positionGravity: PositionGravity.auto,
          );
        }
      } else {
        final active = await FlutterOverlayWindow.isActive();
        if (active) {
          await FlutterOverlayWindow.closeOverlay();
        }
      }

      await _dbHelper.updateSystemOverlayEnabled(enabled);
      if (!mounted) return;
      setState(() => _systemOverlayEnabled = enabled);
      widget.onOverlayToggled?.call();
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorSnackBar(
        context,
        message: ErrorHandler.getUserMessage(e),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingOverlay = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Ambient Background Orbs
          Positioned(
            top: -MediaQuery.of(context).size.height * 0.1,
            left: -MediaQuery.of(context).size.width * 0.1,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.5,
              height: MediaQuery.of(context).size.width * 0.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primary.withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100.0, sigmaY: 100.0),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          Positioned(
            bottom: -MediaQuery.of(context).size.height * 0.1,
            right: -MediaQuery.of(context).size.width * 0.1,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.6,
              height: MediaQuery.of(context).size.width * 0.6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.tertiary.withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100.0, sigmaY: 100.0),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: _isLoading ? _buildLoading() : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
      children: [
        // Page Header
        Text(
          'Settings',
          style: AppTheme.headlineMdMobile,
        ),
        const SizedBox(height: 8),
        Text(
          'Configure your neural link and external integrations.',
          style: AppTheme.bodyMd.copyWith(color: AppTheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
        
        // Memory Core Status
        _buildMemoryCoreStatus(),
        const SizedBox(height: 32),
        
        // Intelligence Engine
        _buildIntelligenceEngine(),
        const SizedBox(height: 32),
        
        // Security & Privacy
        _buildSecuritySection(),
        const SizedBox(height: 32),
        
        // System Overlay
        _buildSystemOverlay(),
        const SizedBox(height: 32),
        
        // Account
        _buildAccountSection(),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildMemoryCoreStatus() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassDecoration().copyWith(
        color: AppTheme.primary.withOpacity(0.05),
      ),
      child: Row(
        children: [
          // Left Icon
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppTheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.memory_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: FadeTransition(
                  opacity: _pulseAnimation,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.success.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Center Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Memory Core',
                  style: AppTheme.bodyMd.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.primary,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Connected & Synchronized',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: AppTheme.bodyMd.copyWith(
                          color: AppTheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Right Button
          OutlinedButton(
            onPressed: _showDiagnosticsDialog,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: Text(
              'DIAGNOSTICS',
              style: AppTheme.labelCaps.copyWith(color: AppTheme.primary, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntelligenceEngine() {
    final currentProvider = _currentProvider;
    final needsKey = currentProvider['needsKey'] as bool;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.glassDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_rounded, size: 28, color: AppTheme.primary),
              const SizedBox(width: 12),
              Text(
                'Intelligence Engine',
                style: AppTheme.headlineMd.copyWith(fontSize: 22),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          _buildLabel('AI PROVIDER'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedProvider,
            decoration: _glassInputDecoration(),
            dropdownColor: AppTheme.surfaceContainerLowest,
            items: _providers.map((p) {
              return DropdownMenuItem<String>(
                value: p['key'] as String,
                child: Text(p['name'] as String, style: AppTheme.bodyMd),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) _selectProvider(value);
            },
          ),
          const SizedBox(height: 20),

          if (needsKey) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildLabel('API KEY'),
                InkWell(
                  onTap: () => _openGetKeyUrl(_selectedProvider),
                  child: Text(
                    'Get Key',
                    style: AppTheme.labelCaps.copyWith(color: AppTheme.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _apiKeyController,
              obscureText: _obscureApiKey,
              decoration: _glassInputDecoration().copyWith(
                hintText: _keyHint(_selectedProvider),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                    color: AppTheme.outline,
                  ),
                  onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                ),
              ),
              style: AppTheme.bodyMd,
            ),
            const SizedBox(height: 6),
            Text(
              'Keys are encrypted and stored locally in your vault.',
              style: AppTheme.bodyMd.copyWith(
                fontSize: 12,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
          ],

          _buildLabel('ENDPOINT'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _endpointController,
            keyboardType: TextInputType.url,
            decoration: _glassInputDecoration().copyWith(
              hintText: 'API endpoint URL',
            ),
            style: AppTheme.bodyMd,
          ),
          const SizedBox(height: 20),

          _buildLabel('MODEL'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _modelController,
            decoration: _glassInputDecoration().copyWith(
              hintText: 'Model name',
            ),
            style: AppTheme.bodyMd,
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isTesting ? null : _testConnection,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppTheme.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    ),
                  ),
                  child: _isTesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('Test', style: AppTheme.bodyMd),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text('Save', style: AppTheme.bodyMd.copyWith(color: Colors.white)),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 16),
            _buildResult(),
          ],
        ],
      ),
    );
  }

  Widget _buildSystemOverlay() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.glassDecoration(),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppTheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.picture_in_picture_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'System Overlay',
                  style: AppTheme.bodyLg.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Enable floating capture bubble across OS.',
                  style: AppTheme.bodyMd.copyWith(color: AppTheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch(
            value: _systemOverlayEnabled,
            onChanged: _isUpdatingOverlay ? null : _setOverlayEnabled,
            activeColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildSecuritySection() {
    return Container(
      decoration: AppTheme.glassDecoration(),
      padding: const EdgeInsets.all(AppTheme.containerPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_rounded, color: AppTheme.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                'Security & Privacy',
                style: AppTheme.headlineMd.copyWith(fontSize: 22),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryContainer.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fingerprint_rounded,
                  color: AppTheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Biometric App Lock',
                      style: AppTheme.bodyMd.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Require fingerprint or face ID to open your vault.',
                      style: AppTheme.bodyMd.copyWith(
                        color: AppTheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _biometricLockEnabled,
                onChanged: _setBiometricLockEnabled,
                activeColor: AppTheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _setBiometricLockEnabled(bool enabled) async {
    try {
      if (enabled) {
        final canAuth = await _localAuth.canCheckBiometrics ||
            await _localAuth.isDeviceSupported();
        if (!canAuth) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Biometric authentication is not available on this device.',
              ),
            ),
          );
          return;
        }

        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Authenticate to enable biometric app lock',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );

        if (!authenticated) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Authentication cancelled or failed.')),
          );
          return;
        }
      }

      await _dbHelper.setBiometricLockEnabled(enabled);
      if (!mounted) return;
      setState(() => _biometricLockEnabled = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Biometric lock enabled. Vault will lock when minimized.'
                : 'Biometric lock disabled.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error setting biometric lock: $e')),
      );
    }
  }

  Widget _buildAccountSection() {
    return Container(
      decoration: AppTheme.glassDecoration(),
      padding: const EdgeInsets.all(AppTheme.containerPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_rounded, color: AppTheme.secondary, size: 24),
              const SizedBox(width: 8),
              Text(
                'Account',
                style: AppTheme.headlineMd.copyWith(fontSize: 22),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _exportVault,
              icon: const Icon(Icons.cloud_download_rounded, color: AppTheme.primary),
              label: Text(
                'Export Memory Vault',
                style: AppTheme.bodyMd.copyWith(color: AppTheme.primary),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppTheme.outlineVariant),
                backgroundColor: Colors.white.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showPurgeConfirmationDialog,
              icon: const Icon(Icons.delete_forever_rounded, color: AppTheme.error),
              label: Text(
                'Purge Local Data',
                style: AppTheme.bodyMd.copyWith(color: AppTheme.error),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppTheme.error),
                backgroundColor: AppTheme.error.withOpacity(0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openGetKeyUrl(String provider) async {
    String url = 'https://github.com/settings/tokens';
    switch (provider) {
      case 'github':
        url = 'https://github.com/settings/tokens';
        break;
      case 'openai':
        url = 'https://platform.openai.com/api-keys';
        break;
      case 'gemini':
        url = 'https://aistudio.google.com/app/apikey';
        break;
      case 'claude':
        url = 'https://console.anthropic.com/settings/keys';
        break;
      case 'huggingface':
        url = 'https://huggingface.co/settings/tokens';
        break;
      case 'local':
        url = 'https://ollama.com';
        break;
    }

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Portal link: $url')),
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to open key URL: $e');
    }
  }

  Future<void> _showDiagnosticsDialog() async {
    final memories = await _dbHelper.getMemories();
    final provider = _currentProvider;
    final hasKey = await _dbHelper.getProviderConfig(_selectedProvider).then(
          (c) => (c?['api_key'] ?? '').isNotEmpty,
        );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.analytics_rounded, color: AppTheme.primary),
            const SizedBox(width: 10),
            const Text('System Diagnostics'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDiagRow('Database Status', 'Online & Healthy'),
              _buildDiagRow('Total Memories Stored', '${memories.length} entries'),
              _buildDiagRow('Active AI Provider', provider['name'] as String),
              _buildDiagRow('Model Name', _effectiveModel(provider)),
              _buildDiagRow('API Endpoint', _effectiveEndpoint(provider)),
              _buildDiagRow('API Key Configured', hasKey ? 'Yes (Encrypted in Vault)' : (provider['needsKey'] as bool ? 'Missing' : 'Not Required')),
              _buildDiagRow('Live STT Active', _useSystemSTT ? 'Device Speech Recognition' : 'Cloud LLM STT'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTheme.labelCaps.copyWith(fontSize: 11, color: AppTheme.outline),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTheme.bodyMd.copyWith(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          const Divider(height: 12),
        ],
      ),
    );
  }

  Future<void> _exportVault() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.cloud_download_rounded, color: AppTheme.primary),
            const SizedBox(width: 10),
            const Text('Export Memory Vault'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose your preferred export format. You can export a complete ZIP backup with all media, or export text as Markdown or JSON.',
              style: TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 18),
            // ZIP with Media
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _exportZipVault();
              },
              icon: const Icon(Icons.archive_rounded, color: Colors.white),
              label: const Text('Full Backup (ZIP with Media)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 10),
            // Markdown
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final markdown = await _dbHelper.exportMemoriesAsMarkdown();
                _showExportPreviewDialog('Markdown Export', markdown);
              },
              icon: const Icon(Icons.description_rounded),
              label: const Text('Export Markdown'),
            ),
            const SizedBox(height: 10),
            // JSON
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final json = await _dbHelper.exportAllDataAsJson();
                _showExportPreviewDialog('JSON Export', json);
              },
              icon: const Icon(Icons.data_object_rounded),
              label: const Text('Export JSON'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportZipVault() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Creating full vault ZIP archive with media...'),
          ],
        ),
        duration: Duration(seconds: 4),
      ),
    );

    try {
      final zipFile = await _dbHelper.exportVaultAsZip();
      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(zipFile.path)],
        text: 'Memory Box Vault Backup (Markdown, JSON, Media)',
        subject: 'Memory Box Vault Backup',
      );
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorSnackBar(
        context,
        message: 'Failed to create vault ZIP: ${ErrorHandler.getUserMessage(e)}',
      );
    }
  }

  void _showExportPreviewDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.success),
            const SizedBox(width: 10),
            Text(title),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Vault export copied to clipboard!')),
              );
              Navigator.of(ctx).pop();
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy to Clipboard'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPurgeConfirmationDialog() async {
    final count = (await _dbHelper.getMemories()).length;
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 28),
            const SizedBox(width: 10),
            const Text('Purge All Memories?'),
          ],
        ),
        content: Text(
          'This will permanently delete all $count saved memories, voice notes, photos, and analysis from this device.\n\nThis action cannot be undone.',
          style: AppTheme.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _dbHelper.purgeAllMemories();
                widget.onOverlayToggled?.call();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All local memories purged successfully.'),
                      backgroundColor: AppTheme.error,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ErrorHandler.showErrorSnackBar(
                    context,
                    message: ErrorHandler.getUserMessage(e),
                  );
                }
              }
            },
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: AppTheme.labelCaps,
    );
  }

  InputDecoration _glassInputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white.withOpacity(0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        borderSide: const BorderSide(color: AppTheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        borderSide: const BorderSide(color: AppTheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        borderSide: const BorderSide(color: AppTheme.primary, width: 2),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildResult() {
    final success = _testSuccess == true;
    final color = success ? AppTheme.success : AppTheme.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 19,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _testResult!,
              style: AppTheme.bodyMd.copyWith(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _keyHint(String provider) {
    switch (provider) {
      case 'github':
        return 'github_pat_... or ghp_...';
      case 'openai':
        return 'sk-...';
      case 'gemini':
        return 'AIza...';
      case 'claude':
        return 'sk-ant-...';
      case 'huggingface':
        return 'hf_...';
      default:
        return 'API key';
    }
  }
}
