import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/url_tools.dart';
import '../models/series.dart';
import '../services/scrape/scrape_service.dart';
import '../theme/app_colors.dart';
import '../theme/components/pressable_scale.dart';
import 'components/mini_book_loader.dart';

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

/// Interactive 3-step bottom sheet wizard to add or edit a manga series:
/// Step 1: Paste Link (focused, paste chip only when clipboard has link)
/// Step 2: Title & Category (auto-detected title with single-back/x clear, unselected favorites)
/// Step 3: Thumbnail & Finish (sample cover art preview + Start Reading / Save to Shelf)
class SeriesForm extends StatefulWidget {
  const SeriesForm({
    super.key,
    this.existing,
    this.initialUrl,
    this.initialTitle,
    this.availableCategories,
    this.initialCategory,
  });

  final Series? existing;
  final String? initialUrl;
  final String? initialTitle;
  final List<String>? availableCategories;
  final String? initialCategory;

  @override
  State<SeriesForm> createState() => _SeriesFormState();
}

class _SeriesFormState extends State<SeriesForm> {
  int _step = 0; // 0: Link, 1: Title & Category, 2: Cover & Action

  late final TextEditingController _url;
  late final TextEditingController _title;
  late final TextEditingController _chapter;
  late final TextEditingController _coverUrlController;
  final TextEditingController _newCategoryController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();

  final ScrapeService _scrape = ScrapeService();
  bool _isAddingCategory = false;
  late final List<String> _categories;
  late String _selectedCategory;

  bool _isAutoDetectedTitle = false;
  bool _hasClipboardUrl = false;
  String _clipboardUrl = '';
  bool _hasClipboardTitle = false;
  String _clipboardTitle = '';

  String? _scrapedCoverUrl;
  Uint8List? _customCoverBytes;
  bool _showCoverUrlField = false;
  bool _isFetchingMeta = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _url = TextEditingController(text: e?.url ?? widget.initialUrl ?? '');
    _title = TextEditingController(text: e?.title ?? widget.initialTitle ?? '');
    _chapter = TextEditingController(text: e?.chapter ?? '');
    _coverUrlController = TextEditingController(text: e?.coverUrl ?? '');

    // Setup categories - Ensure Favorites is available, but NOT preselected by default
    final rawCats = widget.availableCategories?.where((c) => c != 'All').toList() ?? [];
    if (rawCats.isEmpty) {
      rawCats.addAll(const ['Reading', 'Favorites', 'Plan to Read', 'Completed']);
    } else if (!rawCats.any((c) => c.toLowerCase() == 'favorites' || c.toLowerCase() == 'favourite')) {
      rawCats.insert(1, 'Favorites');
    }
    _categories = List<String>.from(rawCats);

    final initCat = e?.category ?? widget.initialCategory;
    if (initCat != null &&
        initCat != 'All' &&
        initCat.toLowerCase() != 'favorites' &&
        _categories.contains(initCat)) {
      _selectedCategory = initCat;
    } else {
      // "the ability to select favorite while adding make it as not preselected"
      // Default to "Reading" or first non-favorite category!
      _selectedCategory = _categories.firstWhere(
        (c) => c.toLowerCase() != 'favorites' && c.toLowerCase() != 'favourite',
        orElse: () => _categories.isNotEmpty ? _categories.first : 'Reading',
      );
    }

    _checkClipboard();

    if (_editing) {
      _step = 1; // Start at title/category when editing existing series
    } else if (_url.text.isNotEmpty) {
      _autoPrefillFromUrl(_url.text);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    _chapter.dispose();
    _coverUrlController.dispose();
    _newCategoryController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  static bool _isValidWebUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    final startsLikeUrl = t.startsWith('http://') ||
        t.startsWith('https://') ||
        t.startsWith('www.');
    if (!startsLikeUrl && !t.contains('://')) {
      return false;
    }
    final uri = Uri.tryParse(t.startsWith('http://') || t.startsWith('https://') ? t : 'https://$t');
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return host.contains('.') && host.split('.').last.length >= 2;
  }

  Future<void> _checkClipboard() async {
    try {
      final has = await Clipboard.hasStrings();
      if (!has) return;
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) return;

      if (mounted) {
        setState(() {
          if (_isValidWebUrl(text)) {
            _hasClipboardUrl = true;
            _clipboardUrl = text;
          } else if (text.length >= 2 && text.length <= 100 && !text.contains('\n')) {
            _hasClipboardTitle = true;
            _clipboardTitle = text;
          }
        });
      }
    } catch (_) {}
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
    return ok ? null : 'Please enter a valid manga or chapter URL';
  }

  void _autoPrefillFromUrl(String rawUrl) {
    if (_title.text.trim().isEmpty) {
      final detected = UrlTools.titleFromUrl(rawUrl);
      if (detected.isNotEmpty) {
        _title.text = detected;
        _isAutoDetectedTitle = true;
      }
    }
    if (_chapter.text.trim().isEmpty) {
      final ch = UrlTools.chapterLabel(rawUrl);
      if (ch != null) _chapter.text = ch;
    }
  }

  Future<void> _fetchMetadata(String rawUrl) async {
    final norm = _normalizeUrl(rawUrl);
    if (!mounted) return;
    setState(() => _isFetchingMeta = true);
    try {
      final res = await _scrape.scrapeChapter(norm);
      if (!mounted) return;
      setState(() {
        _isFetchingMeta = false;
        if (res.title != null && res.title!.isNotEmpty && (_title.text.isEmpty || _isAutoDetectedTitle)) {
          _title.text = res.title!;
        }
        if (res.coverUrl != null && res.coverUrl!.isNotEmpty && _scrapedCoverUrl == null) {
          _scrapedCoverUrl = res.coverUrl;
        }
        if (res.chapterLabel != null && res.chapterLabel!.isNotEmpty && _chapter.text.isEmpty) {
          _chapter.text = res.chapterLabel!;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _isFetchingMeta = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final text = _clipboardUrl.isNotEmpty
        ? _clipboardUrl
        : (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      HapticFeedback.mediumImpact();
      setState(() {
        _url.text = text;
      });
      _continueToStep2();
    }
  }

  void _continueToStep2() {
    final err = _validateUrl(_url.text);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    _autoPrefillFromUrl(_url.text);
    HapticFeedback.selectionClick();
    setState(() => _step = 1);
    _fetchMetadata(_url.text);
  }

  void _continueToStep3() {
    if (_title.text.trim().isEmpty) {
      _autoPrefillFromUrl(_url.text);
      if (_title.text.trim().isEmpty) {
        _title.text = 'Untitled Manga';
      }
    }
    HapticFeedback.selectionClick();
    setState(() => _step = 2);
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

  void _addNewCategory() {
    final text = _newCategoryController.text.trim();
    if (text.isNotEmpty) {
      HapticFeedback.selectionClick();
      setState(() {
        if (!_categories.contains(text)) {
          _categories.add(text);
        }
        _selectedCategory = text;
        _isAddingCategory = false;
        _newCategoryController.clear();
      });
    }
  }

  void _submit(bool openAfter) {
    final normUrl = _normalizeUrl(_url.text);
    if (_validateUrl(normUrl) != null) {
      setState(() => _step = 0);
      return;
    }

    final finalTitle = _title.text.trim().isNotEmpty
        ? _title.text.trim()
        : (UrlTools.titleFromUrl(normUrl).isNotEmpty
            ? UrlTools.titleFromUrl(normUrl)
            : 'Untitled Manga');

    final finalChapter = _chapter.text.trim().isNotEmpty
        ? _chapter.text.trim()
        : (UrlTools.chapterLabel(normUrl) ?? '');

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      SeriesFormResult(
        url: normUrl,
        title: finalTitle,
        chapter: finalChapter,
        status: widget.existing?.status ?? ReadStatus.reading,
        openAfter: openAfter,
        category: _selectedCategory,
        customCoverUrl: _coverUrlController.text.trim().isNotEmpty
            ? _normalizeUrl(_coverUrlController.text)
            : _scrapedCoverUrl,
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
          padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottomInset),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top header row with step indicator
                _buildHeader(t),
                const SizedBox(height: 18),

                // Animated step views
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.04, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<int>(_step),
                    child: _buildCurrentStep(t),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppThemeTokens t) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_step > 0 && !_editing)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.arrow_back_rounded, color: t.textPrimary),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _step--);
                },
              )
            else
              Text(
                _editing ? 'Edit Manga' : 'Add Manga',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),

            // Step Progress indicators (3 pills)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final isActive = index == _step;
                final isPassed = index < _step;
                return GestureDetector(
                  onTap: () {
                    if (isPassed || _editing) {
                      HapticFeedback.selectionClick();
                      setState(() => _step = index);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 24 : 12,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive
                          ? t.accent
                          : (isPassed
                              ? t.accent.withValues(alpha: 0.45)
                              : t.surfaceCard),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              }),
            ),

            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, color: t.textSecondary),
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCurrentStep(AppThemeTokens t) {
    switch (_step) {
      case 0:
        return _buildStep1Link(t);
      case 1:
        return _buildStep2Details(t);
      case 2:
      default:
        return _buildStep3CoverAndActions(t);
    }
  }

  // ---------------------------------------------------------------------------
  // STEP 1: Paste Link
  // ---------------------------------------------------------------------------
  Widget _buildStep1Link(AppThemeTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Paste Manga Link',
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Paste any chapter or series link from Asura, MangaDex, ThunderScans, etc.',
          style: TextStyle(
            color: t.textSecondary,
            fontSize: 13.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 22),

        // Link Input Card
        Container(
          decoration: BoxDecoration(
            color: t.surfaceCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.link_rounded, color: t.accent, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _url,
                  autofocus: true,
                  style: TextStyle(color: t.textPrimary, fontSize: 15),
                  cursorColor: t.accent,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  onChanged: (v) {
                    setState(() {});
                  },
                  onSubmitted: (_) => _continueToStep2(),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'https://site.com/series/title/chapter-1',
                    hintStyle: TextStyle(color: t.textTertiary, fontSize: 13.5),
                  ),
                ),
              ),
              if (_url.text.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.cancel_rounded, color: t.textTertiary, size: 20),
                  onPressed: () => setState(() => _url.clear()),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Paste from Clipboard Button: ONLY shown if user actually copied a valid link
        if (_hasClipboardUrl && _url.text.isEmpty) ...[
          Center(
            child: PressableScale(
              onTap: _pasteFromClipboard,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: t.accent.withValues(alpha: 0.28)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.content_paste_rounded, color: t.accent, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Paste from Clipboard',
                      style: TextStyle(
                        color: t.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        const SizedBox(height: 16),

        // Continue Button
        PressableScale(
          onTap: _continueToStep2,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.accent, t.accent.withValues(alpha: 0.85)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: t.accent.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Continue',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 19),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 2: Title & Category
  // ---------------------------------------------------------------------------
  Widget _buildStep2Details(AppThemeTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Title & Shelf',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Review detected title and select a shelf category.',
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
            if (_isFetchingMeta)
              const Padding(
                padding: EdgeInsets.all(4),
                child: MiniBookLoader(size: 24),
              ),
          ],
        ),
        const SizedBox(height: 20),

        // Manga Title Field with single-back/x clear functionality
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MANGA TITLE',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            if (_isAutoDetectedTitle)
              Text(
                'Auto-detected from URL',
                style: TextStyle(
                  color: t.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: t.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _title,
                  focusNode: _titleFocusNode,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  cursorColor: t.accent,
                  textInputAction: TextInputAction.next,
                  onTap: () {
                    // Selecting the field highlights all text so a single backspace deletes it all
                    if (_isAutoDetectedTitle) {
                      _title.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: _title.text.length,
                      );
                    }
                  },
                  onChanged: (v) {
                    setState(() {
                      _isAutoDetectedTitle = false;
                    });
                  },
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'e.g. Solo Leveling',
                    hintStyle: TextStyle(color: t.textTertiary),
                  ),
                ),
              ),
              if (_title.text.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.clear_rounded, color: t.textTertiary, size: 18),
                  tooltip: 'Clear title',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _title.clear();
                      _isAutoDetectedTitle = false;
                    });
                  },
                ),
            ],
          ),
        ),
        if (_hasClipboardTitle && _clipboardTitle.isNotEmpty && _title.text.isEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: PressableScale(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _title.text = _clipboardTitle;
                  _isAutoDetectedTitle = false;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.accent.withValues(alpha: 0.28)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.content_paste_rounded, color: t.accent, size: 14),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Paste title: "$_clipboardTitle"',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),

        // Shelf Category Header with + Add Category
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SHELF CATEGORY',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            if (!_isAddingCategory)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isAddingCategory = true);
                },
                child: Row(
                  children: [
                    Icon(Icons.add_rounded, size: 14, color: t.accent),
                    const SizedBox(width: 4),
                    Text(
                      'New Category',
                      style: TextStyle(
                        color: t.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Inline New Category Input if active
        if (_isAddingCategory) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: t.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.accent, width: 1.2),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newCategoryController,
                    autofocus: true,
                    style: TextStyle(color: t.textPrimary, fontSize: 13.5),
                    cursorColor: t.accent,
                    onSubmitted: (_) => _addNewCategory(),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Category name (e.g. Manhwa)',
                      hintStyle: TextStyle(color: t.textTertiary, fontSize: 13),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.check_rounded, color: t.accent, size: 20),
                  onPressed: _addNewCategory,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, color: t.textTertiary, size: 18),
                  onPressed: () => setState(() => _isAddingCategory = false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Categories Wrap Chips with Favorite support (Not preselected by default)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _categories.map((cat) {
            final isSelected = cat == _selectedCategory;
            final isFav = cat.toLowerCase() == 'favorites' || cat.toLowerCase() == 'favourite';

            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedCategory = cat);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isFav
                          ? Colors.redAccent.withValues(alpha: 0.25)
                          : t.accent.withValues(alpha: 0.22))
                      : t.surfaceCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? (isFav ? Colors.redAccent : t.accent) : t.border,
                    width: isSelected ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isFav) ...[
                      Icon(
                        isSelected ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        size: 14,
                        color: isSelected ? Colors.redAccent : t.textSecondary,
                      ),
                      const SizedBox(width: 6),
                    ] else if (isSelected) ...[
                      Icon(Icons.check_rounded, size: 14, color: t.accent),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      cat,
                      style: TextStyle(
                        color: isSelected
                            ? (isFav ? Colors.redAccent : t.textPrimary)
                            : t.textSecondary,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 28),

        // Navigation row (Back + Next)
        Row(
          children: [
            Expanded(
              flex: 1,
              child: PressableScale(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _step = 0);
                },
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: t.surfaceCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.border),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Back',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: PressableScale(
                onTap: _continueToStep3,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [t.accent, t.accent.withValues(alpha: 0.85)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: t.accent.withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Next: Cover Art',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 3: Cover & Finish
  // ---------------------------------------------------------------------------
  Widget _buildStep3CoverAndActions(AppThemeTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sample Cover Preview',
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'This is the cover art that will appear on your shelf.',
          style: TextStyle(
            color: t.textSecondary,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 20),

        // Centered Cover Preview
        Center(
          child: Container(
            width: 136,
            height: 195,
            decoration: BoxDecoration(
              color: t.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.border.withValues(alpha: 0.8), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.40),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: _buildCoverImage(t),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Change Cover Options
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PressableScale(
              onTap: _pickImage,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: t.surfaceCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: t.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_library_outlined, size: 15, color: t.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Upload Image',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            PressableScale(
              onTap: () {
                setState(() => _showCoverUrlField = !_showCoverUrlField);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: t.surfaceCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: t.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link_rounded, size: 15, color: t.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Image URL',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_customCoverBytes != null || _coverUrlController.text.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.restart_alt_rounded, color: t.textTertiary, size: 18),
                tooltip: 'Reset cover',
                onPressed: () {
                  setState(() {
                    _customCoverBytes = null;
                    _coverUrlController.clear();
                  });
                },
              ),
            ],
          ],
        ),

        // Expandable Image URL field
        if (_showCoverUrlField) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: t.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _coverUrlController,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                    cursorColor: t.accent,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'https://site.com/cover.jpg',
                      hintStyle: TextStyle(color: t.textTertiary, fontSize: 12.5),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.check_rounded, color: t.accent, size: 18),
                  onPressed: () {
                    setState(() => _showCoverUrlField = false);
                  },
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 26),

        // Two High-Converting Action Buttons
        // Primary: Start Reading Now
        PressableScale(
          onTap: () => _submit(true),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.accent, t.accent.withValues(alpha: 0.85)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: t.accent.withValues(alpha: 0.32),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bolt_rounded, color: Colors.white, size: 21),
                SizedBox(width: 8),
                Text(
                  'Start Reading Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Secondary: Save to Shelf
        PressableScale(
          onTap: () => _submit(false),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: t.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.border),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bookmark_add_outlined, color: t.textPrimary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Save to Shelf',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoverImage(AppThemeTokens t) {
    if (_customCoverBytes != null) {
      return Image.memory(
        _customCoverBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    final coverUrl = _coverUrlController.text.trim().isNotEmpty
        ? _coverUrlController.text.trim()
        : _scrapedCoverUrl;

    if (coverUrl != null && coverUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: coverUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, __) => Container(
          color: t.surfaceCard,
          alignment: Alignment.center,
          child: const MiniBookLoader(size: 28),
        ),
        errorWidget: (_, __, ___) => _buildFallbackCover(t),
      );
    }

    if (_isFetchingMeta) {
      return Container(
        color: t.surfaceCard,
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MiniBookLoader(size: 32),
            SizedBox(height: 8),
            Text(
              'Fetching cover...',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return _buildFallbackCover(t);
  }

  Widget _buildFallbackCover(AppThemeTokens t) {
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceCard,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            t.surfaceCard,
            t.accent.withValues(alpha: 0.15),
          ],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_stories_rounded, size: 26, color: t.accent),
          ),
          const SizedBox(height: 10),
          Text(
            _title.text.isNotEmpty ? _title.text : 'Manga Cover',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_chapter.text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _chapter.text,
              style: TextStyle(color: t.accent, fontSize: 10.5, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
