import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/series.dart';
import '../theme/app_colors.dart';
import '../theme/components/pressable_scale.dart';

class SeriesFormResult {
  const SeriesFormResult({
    required this.url,
    required this.title,
    required this.chapter,
    required this.status,
    required this.openAfter,
    this.category,
    this.customCoverUrl,
    this.customCoverBytes,
  });

  final String url;
  final String title;
  final String chapter;
  final ReadStatus status;
  final bool openAfter;
  final String? category;
  final String? customCoverUrl;
  final Uint8List? customCoverBytes;
}

/// Bottom sheet used both to add (optionally pre-filled from a share) and to
/// edit a series.
class SeriesForm extends StatefulWidget {
  const SeriesForm({
    super.key,
    this.existing,
    this.initialUrl,
    this.initialTitle,
  });

  final Series? existing;
  final String? initialUrl;
  final String? initialTitle;

  @override
  State<SeriesForm> createState() => _SeriesFormState();
}

class _SeriesFormState extends State<SeriesForm>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _url;
  late final TextEditingController _title;
  late final TextEditingController _chapter;
  late final TextEditingController _coverUrlController;
  late ReadStatus _status;

  Uint8List? _customCoverBytes;
  bool _showCoverUrlField = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _url = TextEditingController(text: e?.url ?? widget.initialUrl ?? '');
    _title = TextEditingController(text: e?.title ?? widget.initialTitle ?? '');
    _chapter = TextEditingController(text: e?.chapter ?? '');
    _coverUrlController = TextEditingController(text: e?.coverUrl ?? '');
    _status = e?.status ?? ReadStatus.reading;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _url.dispose();
    _title.dispose();
    _chapter.dispose();
    _coverUrlController.dispose();
    super.dispose();
  }

  static String _normalizeUrl(String raw) {
    final t = raw.trim();
    return t.contains('://') ? t : 'https://$t';
  }

  String? _validateUrl(String? v) {
    final u = Uri.tryParse(_normalizeUrl(v ?? ''));
    final ok = u != null &&
        (u.scheme == 'http' || u.scheme == 'https') &&
        u.host.contains('.');
    return ok ? null : 'Enter a valid chapter or series URL';
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      HapticFeedback.mediumImpact();
      setState(() {
        _url.text = text;
      });
      _formKey.currentState?.validate();
    } else {
      HapticFeedback.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clipboard is empty. Copy a manga chapter URL first!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 900,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        HapticFeedback.selectionClick();
        setState(() {
          _customCoverBytes = bytes;
          _showCoverUrlField = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load image: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _submit(bool open) {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      SeriesFormResult(
        url: _normalizeUrl(_url.text),
        title: _title.text.trim(),
        chapter: _chapter.text.trim(),
        status: _status,
        openAfter: open,
        category: widget.existing?.category ?? _status.label,
        customCoverUrl: _coverUrlController.text.trim().isNotEmpty
            ? _normalizeUrl(_coverUrlController.text)
            : null,
        customCoverBytes: _customCoverBytes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomInset),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _editing ? 'Edit Manga' : 'Add to Shelf',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _editing
                                ? 'Update details, chapter or cover art'
                                : 'Paste any chapter URL to start reading',
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.close_rounded, color: t.textSecondary),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Initial animated guidance banner
                  if (!_editing) ...[
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, _) {
                        final glow = _pulseAnimation.value;
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: t.surfaceCard,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: t.accent.withValues(alpha: 0.35 + 0.35 * glow),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: t.accent.withValues(alpha: 0.08 + 0.08 * glow),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: t.accent.withValues(alpha: 0.16),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.auto_stories_rounded,
                                  size: 18,
                                  color: t.accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Instant Universal Reader',
                                      style: TextStyle(
                                        color: t.textPrimary,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Copy the link of your current chapter from any site (Asura, MangaDex, etc.). Shelfmark auto-strips ads, syncs your page, and detects next chapters!',
                                      style: TextStyle(
                                        color: t.textSecondary,
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Chapter / Series Link Field with Paste button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CHAPTER OR SERIES LINK',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      GestureDetector(
                        onTap: _pasteFromClipboard,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: t.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.content_paste_rounded,
                                size: 13,
                                color: t.accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Paste Clipboard',
                                style: TextStyle(
                                  color: t.accent,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    style: TextStyle(color: t.textPrimary, fontSize: 14.5),
                    cursorColor: t.accent,
                    decoration: InputDecoration(
                      hintText: 'https://site.com/series/title/chapter-1',
                      hintStyle: TextStyle(color: t.textTertiary, fontSize: 13.5),
                      filled: true,
                      fillColor: t.surfaceCard,
                      prefixIcon: Icon(Icons.link_rounded, color: t.accent, size: 20),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: t.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: t.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: t.accent, width: 1.5),
                      ),
                    ),
                    validator: _validateUrl,
                  ),
                  const SizedBox(height: 16),

                  // Title Field
                  Text(
                    'MANGA TITLE (OPTIONAL)',
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _title,
                    textCapitalization: TextCapitalization.words,
                    style: TextStyle(color: t.textPrimary, fontSize: 14.5),
                    cursorColor: t.accent,
                    decoration: InputDecoration(
                      hintText: _editing ? 'Title' : 'Auto-detected from webpage if empty',
                      hintStyle: TextStyle(color: t.textTertiary, fontSize: 13.5),
                      filled: true,
                      fillColor: t.surfaceCard,
                      prefixIcon:
                          Icon(Icons.title_rounded, color: t.textSecondary, size: 20),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: t.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: t.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: t.accent, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Chapter field (for editing)
                  if (_editing) ...[
                    Text(
                      'CURRENT CHAPTER',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _chapter,
                      style: TextStyle(color: t.textPrimary, fontSize: 14.5),
                      cursorColor: t.accent,
                      decoration: InputDecoration(
                        hintText: 'e.g. Chapter 42',
                        hintStyle: TextStyle(color: t.textTertiary, fontSize: 13.5),
                        filled: true,
                        fillColor: t.surfaceCard,
                        prefixIcon: Icon(Icons.bookmark_outline_rounded,
                            color: t.textSecondary, size: 20),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: t.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: t.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: t.accent, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Custom Thumbnail Section
                  Text(
                    'COVER THUMBNAIL',
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.surfaceCard,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: t.border),
                    ),
                    child: Row(
                      children: [
                        // Thumbnail Preview
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 58,
                            height: 80,
                            color: t.surface,
                            child: _buildCoverPreview(t),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _customCoverBytes != null
                                    ? 'Custom image selected'
                                    : _coverUrlController.text.isNotEmpty
                                        ? 'Custom cover link set'
                                        : 'Auto-fetched from website',
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  PressableScale(
                                    onTap: _pickImage,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: t.surface,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: t.border),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.photo_library_outlined,
                                            size: 14,
                                            color: t.accent,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'Upload',
                                            style: TextStyle(
                                              color: t.textPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  PressableScale(
                                    onTap: () {
                                      setState(() {
                                        _showCoverUrlField = !_showCoverUrlField;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: t.surface,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: t.border),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.link_rounded,
                                            size: 14,
                                            color: t.textSecondary,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'Link URL',
                                            style: TextStyle(
                                              color: t.textPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_customCoverBytes != null ||
                                      _coverUrlController.text.isNotEmpty)
                                    PressableScale(
                                      onTap: () {
                                        setState(() {
                                          _customCoverBytes = null;
                                          _coverUrlController.clear();
                                          _showCoverUrlField = false;
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent
                                              .withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 14,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_showCoverUrlField) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _coverUrlController,
                      style: TextStyle(color: t.textPrimary, fontSize: 13.5),
                      cursorColor: t.accent,
                      decoration: InputDecoration(
                        hintText: 'Paste direct image URL (jpg, png, webp)',
                        hintStyle:
                            TextStyle(color: t.textTertiary, fontSize: 12.5),
                        filled: true,
                        fillColor: t.surfaceCard,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: t.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: t.accent),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // Reading Status Chips
                  Text(
                    'READING STATUS',
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in ReadStatus.values)
                        _StatusPill(
                          label: s.label,
                          selected: _status == s,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _status = s);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 26),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _submit(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: t.textPrimary,
                            side: BorderSide(color: t.border, width: 1.2),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            _editing ? 'Save Changes' : 'Save to Shelf',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (!_editing) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: t.accent,
                              foregroundColor: const Color(0xFF04130C),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 2,
                            ),
                            onPressed: () => _submit(true),
                            child: const Text(
                              'Save & Read',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverPreview(AppThemeTokens t) {
    if (_customCoverBytes != null) {
      return Image.memory(
        _customCoverBytes!,
        fit: BoxFit.cover,
      );
    }
    final customUrl = _coverUrlController.text.trim();
    if (customUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: customUrl,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Center(
          child: Icon(Icons.broken_image_rounded, size: 22, color: t.textTertiary),
        ),
      );
    }
    final existingCover = widget.existing?.coverUrl;
    if (existingCover != null && existingCover.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: existingCover,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Center(
          child: Icon(Icons.book_rounded, size: 22, color: t.textTertiary),
        ),
      );
    }
    return Center(
      child: Icon(Icons.image_outlined, size: 24, color: t.textTertiary),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PressableScale(
      onTap: onTap,
      scaleDown: 0.95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? t.accent : t.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? t.accent : t.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF04130C) : t.textSecondary,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
