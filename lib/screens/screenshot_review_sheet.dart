import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../theme/app_theme.dart';
import '../models/memory.dart';
import '../database/db_helper.dart';
import '../services/llm_service.dart';
import '../utils/error_handler.dart';
import '../utils/input_validator.dart';

/// A dedicated bottom sheet for reviewing auto-detected screenshots.
/// Shows the screenshot preview, runs AI analysis automatically,
/// asks for additional context, and saves with one tap.
class ScreenshotReviewSheet extends StatefulWidget {
  final File screenshotFile;
  final VoidCallback onMemoryAdded;

  const ScreenshotReviewSheet({
    super.key,
    required this.screenshotFile,
    required this.onMemoryAdded,
  });

  @override
  State<ScreenshotReviewSheet> createState() => _ScreenshotReviewSheetState();
}

class _ScreenshotReviewSheetState extends State<ScreenshotReviewSheet>
    with SingleTickerProviderStateMixin {
  final _contextController = TextEditingController();
  final _titleController = TextEditingController();
  final _dbHelper = DBHelper();
  final _llmService = LLMService();

  bool _isAnalyzing = true;
  bool _isSaving = false;
  AIAnalysis? _aiAnalysis;
  final List<String> _tags = ['screenshot', 'auto-captured'];
  late AnimationController _pulseController;
  String? _analysisError;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // Auto-analyze immediately
    _autoAnalyze();
  }

  @override
  void dispose() {
    _contextController.dispose();
    _titleController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _autoAnalyze() async {
    setState(() {
      _isAnalyzing = true;
      _analysisError = null;
    });
    _pulseController.repeat(reverse: true);

    try {
      final analysis = await _llmService.analyzeImage(
        widget.screenshotFile,
        'screenshot',
      );
      if (!mounted) return;
      setState(() {
        _aiAnalysis = analysis;
        _isAnalyzing = false;
        // Auto-fill title from AI description
        if (analysis.description.isNotEmpty) {
          _titleController.text = _compactTitle(analysis.description);
        }
        // Merge AI tags
        for (final tag in analysis.tags) {
          final clean = InputValidator.sanitizeTag(tag);
          if (clean.isNotEmpty && !_tags.contains(clean)) {
            _tags.add(clean);
          }
        }
      });
      _pulseController.stop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _analysisError = ErrorHandler.getUserMessage(e);
      });
      _pulseController.stop();
    }
  }

  Future<void> _saveScreenshot() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final title = InputValidator.sanitizeTitle(_titleController.text);
      final userContext = InputValidator.sanitizeContent(_contextController.text);

      // Combine AI description + user context
      String content = '';
      if (_aiAnalysis != null) {
        if (_aiAnalysis!.description.isNotEmpty) {
          content = _aiAnalysis!.description;
        }
        if (_aiAnalysis!.extractedText.isNotEmpty) {
          content += content.isNotEmpty ? '\n\n---\n\n' : '';
          content += _aiAnalysis!.extractedText;
        }
      }
      if (userContext.isNotEmpty) {
        content += content.isNotEmpty ? '\n\n' : '';
        content += '📝 Context: $userContext';
      }

      final memory = Memory(
        id: const Uuid().v4(),
        type: MemoryType.screenshot,
        title: title.isNotEmpty ? title : 'Auto-captured Screenshot',
        content: content,
        mediaPath: widget.screenshotFile.path,
        aiAnalysis: _aiAnalysis,
        tags: _tags
            .map(InputValidator.sanitizeTag)
            .where((t) => t.isNotEmpty)
            .toSet()
            .toList(),
        createdAt: DateTime.now(),
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

  String _compactTitle(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= 60) return clean;
    return '${clean.substring(0, 57).trim()}...';
  }

  @override
  Widget build(BuildContext ctx) {
    final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.15),
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
                        _buildScreenshotPreview(),
                        const SizedBox(height: 16),
                        _buildAnalysisSection(),
                        const SizedBox(height: 16),
                        _buildTitleField(),
                        const SizedBox(height: 16),
                        _buildContextField(),
                        const SizedBox(height: 12),
                        _buildTagChips(),
                        const SizedBox(height: 24),
                        _buildActions(),
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
          color: AppTheme.outlineVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Screenshot Detected', style: AppTheme.titleSm),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: _isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(Icons.close, size: 24, color: AppTheme.onSurface),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.screenshot_monitor_rounded,
                    size: 14, color: AppTheme.warning),
                const SizedBox(width: 6),
                Text(
                  'Auto-captured · AI analyzing',
                  style: AppTheme.labelCaps.copyWith(
                    color: AppTheme.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshotPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 240),
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Image.file(
          widget.screenshotFile,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Icon(Icons.broken_image_rounded,
                  size: 48, color: AppTheme.outline),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalysisSection() {
    if (_isAnalyzing) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(
                  alpha: 0.05 + (_pulseController.value * 0.05)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.secondary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AI is analyzing your screenshot...',
                    style: AppTheme.bodyMd.copyWith(
                      color: AppTheme.secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    if (_analysisError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 20, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _analysisError!,
                style: AppTheme.bodyMd.copyWith(color: Colors.red),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _autoAnalyze,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_aiAnalysis != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.success.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: AppTheme.success),
                const SizedBox(width: 8),
                Text(
                  'AI Analysis Complete',
                  style: AppTheme.labelCaps.copyWith(
                    color: AppTheme.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (_aiAnalysis!.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _aiAnalysis!.description,
                style: AppTheme.bodyMd.copyWith(
                  color: AppTheme.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (_aiAnalysis!.extractedText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.text_snippet_rounded,
                        size: 16, color: AppTheme.outline),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _aiAnalysis!.extractedText,
                        style: AppTheme.bodyMd.copyWith(
                          fontSize: 13,
                          color: AppTheme.onSurfaceVariant,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_aiAnalysis!.extractedUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: _aiAnalysis!.extractedUrls.map((url) {
                  return Chip(
                    avatar: const Icon(Icons.link, size: 14),
                    label: Text(
                      url.length > 30 ? '${url.substring(0, 30)}...' : url,
                      style: const TextStyle(fontSize: 11),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildTitleField() {
    return TextField(
      controller: _titleController,
      textInputAction: TextInputAction.next,
      style: AppTheme.titleSm,
      decoration: InputDecoration(
        hintText: 'Title',
        hintStyle: AppTheme.titleSm.copyWith(
          color: AppTheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildContextField() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _contextController,
        minLines: 2,
        maxLines: 4,
        style: AppTheme.bodyMd,
        decoration: InputDecoration(
          hintText: 'Add context — what\'s this about? (optional)',
          hintStyle: AppTheme.bodyMd.copyWith(
            color: AppTheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(Icons.edit_note_rounded,
                size: 22, color: AppTheme.onSurfaceVariant.withValues(alpha: 0.5)),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 20),
        ),
      ),
    );
  }

  Widget _buildTagChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _tags.map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primaryContainer.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '#$tag',
            style: AppTheme.labelCaps.copyWith(
              color: AppTheme.primary,
              fontSize: 11,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: AppTheme.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Dismiss'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: (_isSaving || _isAnalyzing) ? null : _saveScreenshot,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded, size: 20),
            label: Text(_isSaving ? 'Saving...' : 'Save to Memory Box'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.surfaceContainerHigh,
              disabledForegroundColor: AppTheme.outline,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
