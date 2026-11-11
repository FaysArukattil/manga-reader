import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/auth_bloc.dart';
import '../blocs/library_bloc.dart';
import '../core/url_tools.dart';
import '../data/library_repository.dart';
import '../models/series.dart';
import '../services/category_store.dart';
import '../services/share_service.dart';
import '../services/thumbnail_store.dart';
import '../theme/app_colors.dart';
import '../theme/components/pressable_scale.dart';
import 'components/brand_logo.dart';
import 'components/mini_book_loader.dart';
import 'md_detail_page.dart';
import 'series_card.dart';
import 'series_form.dart';
import 'unified_reader_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  bool _fabExtended = true;
  bool _isScrolled = false;
  bool _showCompactSearch = false;
  late final ShareService _share;

  @override
  void initState() {
    super.initState();
    _share = context.read<ShareService>();
    _share.addListener(_onShare);
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onShare());
  }

  @override
  void dispose() {
    _share.removeListener(_onShare);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Collapse the FAB to an icon while scrolling down, expand when scrolling
  /// back up, so it never covers the last row of covers.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final dir = _scroll.position.userScrollDirection;
    if (dir == ScrollDirection.reverse && _fabExtended) {
      setState(() => _fabExtended = false);
    } else if (dir == ScrollDirection.forward && !_fabExtended) {
      setState(() => _fabExtended = true);
    }
    final scrolled = _scroll.offset > 40;
    if (scrolled != _isScrolled) {
      setState(() => _isScrolled = scrolled);
    }
  }

  void _snack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  void _onShare() {
    final raw = _share.take();
    if (raw == null || !mounted) return;
    final link = UrlTools.parseShare(raw);
    if (link == null) {
      _snack('No link found in the shared text');
      return;
    }
    final existing = context
        .read<LibraryBloc>()
        .state
        .all
        .where((s) => UrlTools.normalize(s.url) == UrlTools.normalize(link.url))
        .firstOrNull;
    if (existing != null) {
      _snack(
        'Already on your shelf',
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => UnifiedReaderPage.openSeries(context, existing),
        ),
      );
      return;
    }
    _openForm(url: link.url, title: link.title);
  }

  Future<void> _openForm({Series? existing, String? url, String? title}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final bloc = context.read<LibraryBloc>();
    final result = await showModalBottomSheet<SeriesFormResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SeriesForm(
        existing: existing,
        initialUrl: url,
        initialTitle: title,
        availableCategories: bloc.state.categories,
        initialCategory: bloc.state.categoryFilter,
      ),
    );
    if (result == null || !mounted) return;
    if (result.category != null &&
        result.category!.isNotEmpty &&
        !bloc.state.categories.contains(result.category!)) {
      bloc.add(LibraryCategoryAdded(result.category!));
    }
    if (existing == null) {
      final series = Series.create(
        id: context.read<LibraryRepository>().newId(),
        url: result.url,
        title: result.title,
        status: result.status,
      ).copyWith(
        category: result.category ?? bloc.state.categoryFilter,
        coverUrl: result.customCoverUrl,
      );
      if (result.customCoverBytes != null) {
        await context
            .read<ThumbnailStore>()
            .save(series.id, result.customCoverBytes!);
      }
      bloc.add(LibraryAddRequested(series));
      if (mounted && result.openAfter) {
        UnifiedReaderPage.openSeries(context, series);
      }
    } else {
      final urlChanged =
          UrlTools.normalize(result.url) != UrlTools.normalize(existing.url);
      final newTitle = result.title.isEmpty ? existing.title : result.title;
      final updated = existing.copyWith(
        title: newTitle,
        url: result.url,
        host: UrlTools.hostOf(result.url),
        chapter: result.chapter,
        status: result.status,
        category: result.category ?? existing.category,
        scroll: urlChanged ? 0 : existing.scroll,
        coverUrl: result.customCoverUrl ?? existing.coverUrl,
      );
      if (result.customCoverBytes != null) {
        await context
            .read<ThumbnailStore>()
            .save(existing.id, result.customCoverBytes!);
      }
      bloc.add(
        LibraryEditRequested(
          updated,
          refetchCover: result.customCoverBytes == null &&
              result.customCoverUrl == null &&
              newTitle != existing.title,
        ),
      );
    }
  }

  Future<void> _showActions(Series s) async {
    final bloc = context.read<LibraryBloc>();
    final t = context.tokens;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with cover artwork, title, and metadata
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 48,
                      height: 66,
                      child: SeriesCover(series: s, memCacheWidth: 160),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: t.surfaceCard,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: t.border),
                              ),
                              child: Text(
                                s.category ?? s.status.label,
                                style: TextStyle(
                                  color: t.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.host,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.textSecondary,
                                  fontSize: 12,
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
              const SizedBox(height: 20),
              _SheetActionTile(
                icon: Icons.drive_file_move_rounded,
                iconColor: t.accent,
                title: 'Move to Category',
                subtitle: 'Organize into a custom category',
                onTap: () => Navigator.pop(sheetContext, 'move'),
              ),
              const SizedBox(height: 8),
              _SheetActionTile(
                icon: Icons.edit_rounded,
                iconColor: Colors.blueAccent,
                title: 'Edit Details',
                subtitle: 'Update title, chapter or status',
                onTap: () => Navigator.pop(sheetContext, 'edit'),
              ),
              const SizedBox(height: 8),
              _SheetActionTile(
                icon: Icons.delete_outline_rounded,
                iconColor: Colors.redAccent,
                title: 'Remove from shelf',
                subtitle: 'Delete series and saved progress',
                destructive: true,
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'move') {
      _showMoveCategorySheet(s);
    } else if (action == 'edit') {
      _openForm(existing: s);
    } else if (action == 'delete') {
      final ok = await _showConfirmDialog(
        title: 'Remove from shelf?',
        content: '"${s.title}" and its saved reading progress will be removed from your shelf.',
        confirmLabel: 'Remove',
        isDestructive: true,
        icon: Icons.delete_sweep_rounded,
      );
      if (ok == true && mounted) {
        bloc.add(LibraryDeleteRequested(s));
      }
    }
  }

  void _showMoveCategorySheet(Series s) {
    final bloc = context.read<LibraryBloc>();
    final categories = bloc.state.categories;
    final t = context.tokens;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Move to Category',
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _showAddCategoryDialog(moveSeries: s);
                    },
                    icon: Icon(Icons.add_rounded, size: 16, color: t.accent),
                    label: Text(
                      'New',
                      style: TextStyle(
                        color: t.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...categories.map((cat) {
                final isCurrent =
                    (s.category ?? s.status.label).toLowerCase() ==
                        cat.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: PressableScale(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(sheetContext);
                      bloc.add(LibraryMoveSeriesRequested(s, cat));
                      _snack('Moved to "$cat"');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? t.accent.withValues(alpha: 0.12)
                            : t.surfaceCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isCurrent ? t.accent : t.border,
                          width: isCurrent ? 1.4 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isCurrent
                                ? Icons.check_circle_rounded
                                : Icons.folder_outlined,
                            size: 20,
                            color: isCurrent ? t.accent : t.textSecondary,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              cat,
                              style: TextStyle(
                                color: isCurrent ? t.accent : t.textPrimary,
                                fontSize: 14.5,
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (isCurrent)
                            Text(
                              'Current',
                              style: TextStyle(
                                color: t.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showCategoryOptions(String cat) {
    final bloc = context.read<LibraryBloc>();
    final t = context.tokens;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cat,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Category options',
                style: TextStyle(color: t.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              _SheetActionTile(
                icon: Icons.edit_rounded,
                iconColor: t.accent,
                title: 'Rename Category',
                subtitle: 'Change name on your shelf',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRenameCategoryDialog(cat);
                },
              ),
              const SizedBox(height: 8),
              _SheetActionTile(
                icon: Icons.delete_outline_rounded,
                iconColor: Colors.redAccent,
                title: 'Delete Category',
                subtitle: 'Books in this category will keep their series',
                destructive: true,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final ok = await _showConfirmDialog(
                    title: 'Delete "$cat"?',
                    content:
                        'Books in this category will not be deleted, they will simply lose this category label.',
                    confirmLabel: 'Delete',
                    isDestructive: true,
                    icon: Icons.folder_delete_rounded,
                  );
                  if (ok == true && mounted) {
                    bloc.add(LibraryCategoryRemoved(cat));
                    _snack('Deleted category "$cat"');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddCategoryDialog({Series? moveSeries}) {
    final bloc = context.read<LibraryBloc>();
    final controller = TextEditingController();
    final t = context.tokens;
    showDialog<void>(
      context: context,
      builder: (dContext) => Dialog(
        backgroundColor: t.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: t.border),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.create_new_folder_rounded, size: 22, color: t.accent),
              ),
              const SizedBox(height: 16),
              Text(
                'New Category',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Create a shelf category to organize your manga collection.',
                style: TextStyle(color: t.textSecondary, fontSize: 13.5),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(color: t.textPrimary, fontSize: 15),
                cursorColor: t.accent,
                decoration: InputDecoration(
                  hintText: 'e.g. Favorites, Shonen, Webtoons',
                  hintStyle: TextStyle(color: t.textTertiary, fontSize: 14),
                  filled: true,
                  fillColor: t.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: t.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: t.accent, width: 1.5),
                  ),
                ),
                onSubmitted: (val) {
                  final name = val.trim();
                  if (name.isNotEmpty) {
                    Navigator.pop(dContext);
                    bloc.add(LibraryCategoryAdded(name));
                    if (moveSeries != null) {
                      bloc.add(LibraryMoveSeriesRequested(moveSeries, name));
                      _snack('Created "$name" and moved series');
                    } else {
                      _snack('Created category "$name"');
                    }
                  }
                },
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dContext),
                    style: TextButton.styleFrom(foregroundColor: t.textSecondary),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final name = controller.text.trim();
                      if (name.isNotEmpty) {
                        Navigator.pop(dContext);
                        bloc.add(LibraryCategoryAdded(name));
                        if (moveSeries != null) {
                          bloc.add(LibraryMoveSeriesRequested(moveSeries, name));
                          _snack('Created "$name" and moved series');
                        } else {
                          _snack('Created category "$name"');
                        }
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: t.accent,
                      foregroundColor: const Color(0xFF04130C),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Create', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameCategoryDialog(String oldName) {
    final bloc = context.read<LibraryBloc>();
    final controller = TextEditingController(text: oldName);
    final t = context.tokens;
    showDialog<void>(
      context: context,
      builder: (dContext) => Dialog(
        backgroundColor: t.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: t.border),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.drive_file_rename_outline_rounded,
                    size: 22, color: Colors.blueAccent),
              ),
              const SizedBox(height: 16),
              Text(
                'Rename Category',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose a new name for "$oldName".',
                style: TextStyle(color: t.textSecondary, fontSize: 13.5),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(color: t.textPrimary, fontSize: 15),
                cursorColor: t.accent,
                decoration: InputDecoration(
                  hintText: 'Category name',
                  hintStyle: TextStyle(color: t.textTertiary, fontSize: 14),
                  filled: true,
                  fillColor: t.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: t.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: t.accent, width: 1.5),
                  ),
                ),
                onSubmitted: (val) async {
                  final newName = val.trim();
                  if (newName.isNotEmpty && newName != oldName) {
                    Navigator.pop(dContext);
                    await CategoryStore.renameCategory(oldName, newName);
                    final updated = await CategoryStore.getCategories();
                    bloc.add(LibraryCategoriesLoaded(updated));
                    if (bloc.state.categoryFilter == oldName) {
                      bloc.add(LibraryCategoryFilterChanged(newName));
                    }
                    _snack('Renamed to "$newName"');
                  }
                },
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dContext),
                    style: TextButton.styleFrom(foregroundColor: t.textSecondary),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final newName = controller.text.trim();
                      if (newName.isNotEmpty && newName != oldName) {
                        Navigator.pop(dContext);
                        await CategoryStore.renameCategory(oldName, newName);
                        final updated = await CategoryStore.getCategories();
                        bloc.add(LibraryCategoriesLoaded(updated));
                        if (bloc.state.categoryFilter == oldName) {
                          bloc.add(LibraryCategoryFilterChanged(newName));
                        }
                        _snack('Renamed to "$newName"');
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: t.accent,
                      foregroundColor: const Color(0xFF04130C),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String content,
    required String confirmLabel,
    bool isDestructive = false,
    IconData? icon,
  }) {
    final t = context.tokens;
    return showDialog<bool>(
      context: context,
      builder: (dContext) => Dialog(
        backgroundColor: t.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: t.border),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: (isDestructive ? Colors.redAccent : t.accent)
                        .withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: isDestructive ? Colors.redAccent : t.accent,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Text(
                title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                content,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dContext, false),
                    style: TextButton.styleFrom(
                      foregroundColor: t.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(dContext, true),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isDestructive ? Colors.redAccent : t.accent,
                      foregroundColor:
                          isDestructive ? Colors.white : const Color(0xFF04130C),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      confirmLabel,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Category manager (themed)
  // ---------------------------------------------------------------------------

  void _showCategoryManagerSheet() {
    FocusManager.instance.primaryFocus?.unfocus();
    final bloc = context.read<LibraryBloc>();
    final t = context.tokens;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return BlocBuilder<LibraryBloc, LibraryState>(
          builder: (context, state) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Manage Categories',
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Filter your shelf or edit categories',
                              style: TextStyle(
                                  color: t.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _showAddCategoryDialog();
                          },
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('New'),
                          style: FilledButton.styleFrom(
                            backgroundColor: t.accent,
                            foregroundColor: const Color(0xFF04130C),
                            textStyle:
                                const TextStyle(fontWeight: FontWeight.w800),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (state.categories.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No custom categories yet. Tap "New" above to add one!',
                            style: TextStyle(
                                color: t.textTertiary, fontSize: 13.5),
                          ),
                        ),
                      )
                    else
                      ...state.categories.map((cat) {
                        final count = state.all
                            .where((s) =>
                                (s.category ?? s.status.label).toLowerCase() ==
                                cat.toLowerCase())
                            .length;
                        final isFiltered = state.categoryFilter == cat;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isFiltered
                                  ? t.accent.withValues(alpha: 0.12)
                                  : t.surfaceCard,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: isFiltered ? t.accent : t.border),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.folder_rounded,
                                  size: 20,
                                  color: isFiltered ? t.accent : t.textSecondary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cat,
                                        style: TextStyle(
                                          color: isFiltered
                                              ? t.accent
                                              : t.textPrimary,
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '$count ${count == 1 ? "manga" : "mangas"}',
                                        style: TextStyle(
                                            color: t.textSecondary,
                                            fontSize: 11.5),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.edit_outlined,
                                      size: 18, color: t.textSecondary),
                                  tooltip: 'Rename',
                                  onPressed: () {
                                    Navigator.pop(sheetContext);
                                    _showRenameCategoryDialog(cat);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      size: 18, color: Colors.redAccent),
                                  tooltip: 'Delete',
                                  onPressed: () async {
                                    Navigator.pop(sheetContext);
                                    final ok = await _showConfirmDialog(
                                      title: 'Delete "$cat"?',
                                      content:
                                          'Books in this category will not be deleted, they will simply lose this label.',
                                      confirmLabel: 'Delete',
                                      isDestructive: true,
                                      icon: Icons.folder_delete_rounded,
                                    );
                                    if (ok == true && mounted) {
                                      bloc.add(LibraryCategoryRemoved(cat));
                                      _snack('Deleted category "$cat"');
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _open(Series s) {
    context.read<LibraryBloc>().add(LibraryMarkSeriesRead(s.id));
    s.isMangaDex
        ? MdDetailPage.openSeries(context, s)
        : UnifiedReaderPage.openSeries(context, s);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Still up?';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 22) return 'Good evening';
    return 'Good night';
  }

  /// The series most worth resuming: last one actually opened, else the first
  /// "reading" entry, else whatever is on the shelf, or null if library is empty.
  Series? _pickHero(List<Series> all) {
    if (all.isEmpty) return null;
    final opened = all.where((s) => s.lastReadAt != null).toList()
      ..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
    if (opened.isNotEmpty) return opened.first;
    final reading = all.where((s) => s.status == ReadStatus.reading).toList();
    return reading.isNotEmpty ? reading.first : all.first;
  }

  void _clearFilters() {
    _search.clear();
    _searchFocus.unfocus();
    final bloc = context.read<LibraryBloc>();
    bloc
      ..add(const LibraryQueryChanged(''))
      ..add(const LibraryCategoryFilterChanged(null));
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------------

  Widget _buildTopPortion(LibraryState state) {
    final user = context.read<AuthBloc>().state.user;
    final topPadding = MediaQuery.paddingOf(context).top;
    final hero = _pickHero(state.all);
    final showContinue = hero != null &&
        state.all.isNotEmpty &&
        state.query.trim().isEmpty &&
        state.categoryFilter == null;

    final displayName = user?.displayName?.trim();
    final welcomeTitle = displayName != null && displayName.isNotEmpty
        ? 'Welcome,\n$displayName!'
        : 'Welcome\nto Shelfmark!';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF031218), // deep status bar teal
            Color(0xFF072430), // rich ambient teal
            Color(0xFF0C3A4B), // vibrant cyan/teal luminous glow
            Color(0xFF051C25), // deep base teal
          ],
          stops: [0.0, 0.30, 0.72, 1.0],
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C3A4B).withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, topPadding + 10, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Row: Headline + Profile Avatar
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: const TextStyle(
                        color: Color(0xFF8BA5B5),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      welcomeTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "What's next to read?",
                      style: TextStyle(
                        color: Color(0xFF8BA5B5),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Profile button / avatar
              GestureDetector(
                onTap: _showProfileSheet,
                child: Container(
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF2C7D99).withValues(alpha: 0.7),
                      width: 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0C3A4B).withValues(alpha: 0.45),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    backgroundColor: const Color(0xFF051C25),
                    backgroundImage: user?.photoURL != null
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: user?.photoURL == null
                        ? const Icon(Icons.person, size: 22, color: Colors.white70)
                        : null,
                  ),
                ),
              ),
            ],
          ),

          // Continue Reading Card (if reading hero available)
          if (showContinue) ...[
            const SizedBox(height: 16),
            _CompactContinueCard(
              series: hero,
              onTap: _open,
            ),
          ],

          const SizedBox(height: 18),

          // Search Bar & Circular Action Button
          _buildTopSearchRow(state),
        ],
      ),
    );
  }

  Widget _buildTopSearchRow(LibraryState state) {
    final focused = _searchFocus.hasFocus;
    final bloc = context.read<LibraryBloc>();

    return Row(
      children: [
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 48,
            padding: const EdgeInsets.only(left: 16, right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF031218).withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: focused
                    ? const Color(0xFF38B2AC)
                    : Colors.white.withValues(alpha: 0.12),
                width: focused ? 1.4 : 1,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: const Color(0xFF38B2AC).withValues(alpha: 0.22),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: Color(0xFF7FA8B8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5),
                    cursorColor: const Color(0xFF38B2AC),
                    decoration: const InputDecoration(
                      hintText: 'Search title, author, genre...',
                      hintStyle: TextStyle(
                        color: Color(0xFF6B8A99),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (v) {
                      bloc.add(LibraryQueryChanged(v));
                      setState(() {});
                    },
                  ),
                ),
                if (_search.text.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                    onPressed: () {
                      _search.clear();
                      bloc.add(const LibraryQueryChanged(''));
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Circular search / filter action button
        Tooltip(
          message: 'Sort: ${_sortShortLabel(state.sort)}',
          child: GestureDetector(
            onTap: () => _showSortAndFilterSheet(state),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF144658),
                border: Border.all(
                  color: state.sort != LibrarySort.lastRead
                      ? const Color(0xFF38B2AC)
                      : const Color(0xFF2C7D99).withValues(alpha: 0.5),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0C3A4B).withValues(alpha: 0.45),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                Icons.tune_rounded,
                color: state.sort != LibrarySort.lastRead
                    ? const Color(0xFF38B2AC)
                    : Colors.white,
                size: 21,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showProfileSheet() {
    FocusManager.instance.primaryFocus?.unfocus();
    final t = context.tokens;
    final user = context.read<AuthBloc>().state.user;
    final bloc = context.read<LibraryBloc>();
    final all = bloc.state.all;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [t.accent, t.accent.withValues(alpha: 0.3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: CircleAvatar(
                  backgroundColor: t.surfaceCard,
                  backgroundImage: user?.photoURL != null
                      ? NetworkImage(user!.photoURL!)
                      : null,
                  child: user?.photoURL == null
                      ? Icon(Icons.person, size: 34, color: t.textSecondary)
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                user?.displayName ?? 'Manga Reader',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                user?.email ?? 'Guest Profile (Local Storage)',
                style: TextStyle(color: t.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: t.surfaceCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: t.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: t.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.auto_stories_rounded, color: t.accent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Books Added',
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${all.length} ${all.length == 1 ? "manga" : "manga series"}',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SheetActionTile(
                icon: Icons.logout_rounded,
                iconColor: t.textPrimary,
                title: 'Sign Out',
                subtitle: 'Switch accounts or read offline',
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.read<AuthBloc>().add(const AuthSignOutRequested());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Category chips in a pinned block with "Categories" header (matching reference design).
  Widget _buildStickyControls(LibraryState state, {required bool needsTopPad}) {
    final t = context.tokens;
    final bloc = context.read<LibraryBloc>();
    final isHomeAll = state.categoryFilter == null && state.query.trim().isEmpty;
    final topPadding = MediaQuery.paddingOf(context).top;

    final chips = _WaterBubbleCategoryBar(
      categories: [null, ...state.categories],
      selected: state.categoryFilter,
      onSelect: (cat) => bloc.add(LibraryCategoryFilterChanged(cat)),
      onManage: _showCategoryManagerSheet,
      onLongPress: (cat) => _showCategoryOptions(cat),
    );

    return Container(
      color: t.bg,
      padding: EdgeInsets.only(
        top: needsTopPad ? (topPadding + 6) : 6,
        bottom: 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Categories Header Row (matches reference design: "Categories" + "See All >")
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Categories',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isHomeAll) ...[
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showCompactSearch = !_showCompactSearch;
                            if (_showCompactSearch) {
                              _searchFocus.requestFocus();
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _showCompactSearch || _search.text.isNotEmpty
                                ? t.accent.withValues(alpha: 0.2)
                                : t.surfaceCard,
                            border: Border.all(
                              color: _showCompactSearch || _search.text.isNotEmpty
                                  ? t.accent
                                  : t.border,
                            ),
                          ),
                          child: Icon(
                            Icons.search_rounded,
                            size: 16,
                            color: _showCompactSearch || _search.text.isNotEmpty
                                ? t.accent
                                : t.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _showSortAndFilterSheet(state),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: state.sort != LibrarySort.lastRead
                                ? t.accent.withValues(alpha: 0.2)
                                : t.surfaceCard,
                            border: Border.all(
                              color: state.sort != LibrarySort.lastRead
                                  ? t.accent
                                  : t.border,
                            ),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 16,
                            color: state.sort != LibrarySort.lastRead
                                ? t.accent
                                : t.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    GestureDetector(
                      onTap: _showCategoryManagerSheet,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        child: Row(
                          children: [
                            Text(
                              'See All',
                              style: TextStyle(
                                color: t.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded, size: 16, color: t.accent),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Inline search field when searching on a category view
          if (!isHomeAll && (_showCompactSearch || _search.text.isNotEmpty))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _buildCompactSearchField(state),
            ),

          // Liquid Water Bubble Category Pills
          chips,
        ],
      ),
    );
  }

  Widget _buildCompactSearchField(LibraryState state) {
    final t = context.tokens;
    final bloc = context.read<LibraryBloc>();
    final focused = _searchFocus.hasFocus;

    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: t.surfaceCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: focused ? t.accent : t.border,
          width: focused ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: focused ? t.accent : t.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: t.textPrimary, fontSize: 13.5),
              cursorColor: t.accent,
              decoration: InputDecoration(
                hintText: 'Search in ${state.categoryFilter ?? "shelf"}...',
                hintStyle: TextStyle(color: t.textTertiary, fontSize: 13.5),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (v) {
                bloc.add(LibraryQueryChanged(v));
                setState(() {});
              },
            ),
          ),
          if (_search.text.isNotEmpty)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 16, color: t.textSecondary),
              onPressed: () {
                _search.clear();
                bloc.add(const LibraryQueryChanged(''));
                setState(() {});
              },
            ),
        ],
      ),
    );
  }

  static String _sortShortLabel(LibrarySort sort) {
    switch (sort) {
      case LibrarySort.lastRead:
        return 'Recent';
      case LibrarySort.title:
        return 'A–Z';
      case LibrarySort.added:
        return 'Added';
    }
  }

  void _showSortAndFilterSheet(LibraryState state) {
    FocusManager.instance.primaryFocus?.unfocus();
    final t = context.tokens;
    final bloc = context.read<LibraryBloc>();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sort Library',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose how manga series appear on your shelf.',
                style: TextStyle(color: t.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 18),
              _buildSortOptionCard(
                t: t,
                label: 'Last Read',
                description: 'Recently read chapters appear first',
                icon: Icons.history_rounded,
                selected: state.sort == LibrarySort.lastRead,
                onTap: () {
                  Navigator.pop(sheetContext);
                  bloc.add(const LibrarySortChanged(LibrarySort.lastRead));
                },
              ),
              const SizedBox(height: 10),
              _buildSortOptionCard(
                t: t,
                label: 'Title A–Z',
                description: 'Organize series alphabetically by title',
                icon: Icons.sort_by_alpha_rounded,
                selected: state.sort == LibrarySort.title,
                onTap: () {
                  Navigator.pop(sheetContext);
                  bloc.add(const LibrarySortChanged(LibrarySort.title));
                },
              ),
              const SizedBox(height: 10),
              _buildSortOptionCard(
                t: t,
                label: 'Recently Added',
                description: 'New additions appear at the top',
                icon: Icons.calendar_today_rounded,
                selected: state.sort == LibrarySort.added,
                onTap: () {
                  Navigator.pop(sheetContext);
                  bloc.add(const LibrarySortChanged(LibrarySort.added));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortOptionCard({
    required AppThemeTokens t,
    required String label,
    required String description,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? t.accent.withValues(alpha: 0.12) : t.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? t.accent : t.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected
                    ? t.accent.withValues(alpha: 0.2)
                    : t.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: selected ? t.accent : t.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? t.textPrimary : t.textSecondary,
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(color: t.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: t.accent, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildShelfTitle(LibraryState state) {
    final t = context.tokens;
    final filtering = state.query.trim().isNotEmpty || state.categoryFilter != null;
    final title = state.categoryFilter ?? (filtering ? 'Results' : 'Your shelf');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _CountBadge(count: state.visible.length),
          const Spacer(),
          if (filtering)
            TextButton(
              onPressed: _clearFilters,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: t.accent,
              ),
              child: const Text(
                'Clear',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bloc = context.read<LibraryBloc>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: t.bg,
        resizeToAvoidBottomInset: false,
        body: BlocBuilder<LibraryBloc, LibraryState>(
          builder: (context, state) {
            final width = MediaQuery.sizeOf(context).width;
            final columns = (width / 170).floor().clamp(2, 6);
            final hasShelf = state.all.isNotEmpty;
            final isHomeAll = state.categoryFilter == null && state.query.trim().isEmpty;
            final topPadding = MediaQuery.paddingOf(context).top;
            final needsTopPad = _isScrolled || !isHomeAll;
            final hasActiveCompactSearch = !isHomeAll && (_showCompactSearch || state.query.isNotEmpty);
            final controlsHeight = (needsTopPad ? (topPadding + 6.0) : 6.0) +
                32.0 + 10.0 + 40.0 + 8.0 +
                (hasActiveCompactSearch ? 54.0 : 0.0);

            final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: 0.68,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
            );

            return RefreshIndicator(
              color: t.accent,
              backgroundColor: t.surfaceCard,
              onRefresh: () async {
                bloc.add(const LibraryUpdatesRequested(force: true));
                await Future<void>.delayed(const Duration(milliseconds: 700));
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_searchFocus.hasFocus) {
                    _searchFocus.unfocus();
                  }
                },
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v.abs() < 240) return;
                  final filters = <String?>[null, ...state.categories];
                  final currentIndex = filters.indexOf(state.categoryFilter);
                  if (currentIndex == -1) return;
                  if (v < 0 && currentIndex < filters.length - 1) {
                    HapticFeedback.selectionClick();
                    bloc.add(LibraryCategoryFilterChanged(filters[currentIndex + 1]));
                  } else if (v > 0 && currentIndex > 0) {
                    HapticFeedback.selectionClick();
                    bloc.add(LibraryCategoryFilterChanged(filters[currentIndex - 1]));
                  }
                },
                child: CustomScrollView(
                  controller: _scroll,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverToBoxAdapter(
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeInOutCubic,
                        child: isHomeAll
                            ? _buildTopPortion(state)
                            : const SizedBox.shrink(),
                      ),
                    ),
                    if (hasShelf)
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _PinnedBarDelegate(
                          height: controlsHeight,
                          background: t.bg,
                          child: _buildStickyControls(state, needsTopPad: needsTopPad),
                        ),
                      ),
                    if (hasShelf) SliverToBoxAdapter(child: _buildShelfTitle(state)),
                    if (state.loading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MiniBookLoader(size: 42),
                              SizedBox(height: 14),
                              Text(
                                'Loading your shelf...',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (!hasShelf)
                      SliverToBoxAdapter(
                        child: _EmptyState(onAdd: () => _openForm()),
                      )
                    else if (state.visible.isEmpty)
                      SliverToBoxAdapter(
                        child: _NoResults(onClear: _clearFilters),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          120 + MediaQuery.paddingOf(context).bottom,
                        ),
                        sliver: SliverGrid(
                          gridDelegate: gridDelegate,
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final s = state.visible[i];
                              return _AnimatedGridTile(
                                key: ValueKey('tile_${s.id}_${state.categoryFilter}_${state.sort}'),
                                index: i,
                                child: SeriesCard(
                                  key: ValueKey(s.id),
                                  series: s,
                                  onTap: () => _open(s),
                                  onLongPress: () => _showActions(s),
                                ),
                              );
                            },
                            childCount: state.visible.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        floatingActionButton: PressableScale(
        onTap: () {
          HapticFeedback.lightImpact();
          _openForm();
        },
        scaleDown: 0.94,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 52,
          padding: EdgeInsets.symmetric(
            horizontal: _fabExtended ? 20 : 16,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00FFA3), Color(0xFF00D486)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00FFA3).withValues(alpha: 0.40),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.add_rounded,
                size: 24,
                color: Color(0xFF04130C),
              ),
              if (_fabExtended) ...[
                const SizedBox(width: 8),
                const Text(
                  'Add Manga',
                  style: TextStyle(
                    color: Color(0xFF04130C),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
}

// =============================================================================
// Pieces
// =============================================================================

class _SheetActionTile extends StatelessWidget {
  const _SheetActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PressableScale(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: destructive ? Colors.redAccent : t.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: t.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: t.surfaceCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: t.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CompactContinueCard extends StatelessWidget {
  const _CompactContinueCard({
    required this.series,
    required this.onTap,
  });

  final Series series;
  final void Function(Series) onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final resume = series.resumeLabel;

    return PressableScale(
      onTap: () => onTap(series),
      scaleDown: 0.98,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: t.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border.withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail
            AspectRatio(
              aspectRatio: 0.72,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SeriesCover(series: series, memCacheWidth: 200),
              ),
            ),
            const SizedBox(width: 12),
            // Title & Progress
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'CONTINUE READING',
                        style: TextStyle(
                          color: t.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    series.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    resume.isNotEmpty ? resume : series.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Mini Resume Button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 16,
                    color: Color(0xFF04130C),
                  ),
                  SizedBox(width: 2),
                  Text(
                    'Resume',
                    style: TextStyle(
                      color: Color(0xFF04130C),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaterBubbleCategoryBar extends StatefulWidget {
  const _WaterBubbleCategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelect,
    required this.onManage,
    this.onLongPress,
  });

  final List<String?> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final VoidCallback onManage;
  final ValueChanged<String>? onLongPress;

  @override
  State<_WaterBubbleCategoryBar> createState() => _WaterBubbleCategoryBarState();
}

class _WaterBubbleCategoryBarState extends State<_WaterBubbleCategoryBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morphController;

  @override
  void initState() {
    super.initState();
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
  }

  @override
  void didUpdateWidget(covariant _WaterBubbleCategoryBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _morphController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _morphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: widget.categories.length + 1, // +1 for Manage
        itemBuilder: (context, index) {
          if (index == widget.categories.length) {
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onManage();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: t.surfaceCard,
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: t.border),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, size: 14, color: t.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Manage',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final cat = widget.categories[index];
          final label = cat ?? 'All';
          final isSelected = widget.selected == cat;
          final isFav = cat?.toLowerCase() == 'favorites' || cat?.toLowerCase() == 'favourite';

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onSelect(cat);
              },
              onLongPress: cat != null && !isFav
                  ? () => widget.onLongPress?.call(cat)
                  : null,
              child: AnimatedBuilder(
                animation: _morphController,
                builder: (context, child) {
                  // Morphing water bubble scaling: when active, dynamically animates width & squish
                  double scaleX = 1.0;
                  double scaleY = 1.0;
                  if (isSelected && _morphController.isAnimating) {
                    final progress = _morphController.value;
                    // Squish & stretch like a dividing liquid droplet
                    scaleX = 1.0 + (math.sin(progress * math.pi) * 0.14);
                    scaleY = 1.0 - (math.sin(progress * math.pi) * 0.08);
                  }

                  return Transform.scale(
                    scaleX: scaleX,
                    scaleY: scaleY,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isFav ? Colors.redAccent : t.accent)
                            : t.surfaceCard,
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(
                          color: isSelected
                              ? (isFav ? Colors.redAccent : t.accent)
                              : t.border,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: (isFav ? Colors.redAccent : t.accent)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isFav) ...[
                            Icon(
                              isSelected
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 13,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.redAccent,
                            ),
                            const SizedBox(width: 5),
                          ],
                          Text(
                            label,
                            style: TextStyle(
                              color: isSelected
                                  ? (isFav ? Colors.white : const Color(0xFF04130C))
                                  : t.textSecondary,
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Animated entry for grid tiles as the user scrolls or reveals the shelf:
/// smooth scale + slide up + opacity with an index-staggered spring curve.
class _AnimatedGridTile extends StatelessWidget {
  const _AnimatedGridTile({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delayMs = (index % 6) * 45;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, v, animChild) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 24),
          child: Transform.scale(
            scale: 0.90 + 0.10 * v,
            alignment: Alignment.center,
            child: animChild,
          ),
        ),
      ),
      child: child,
    );
  }
}

class _PinnedBarDelegate extends SliverPersistentHeaderDelegate {
  _PinnedBarDelegate({
    required this.height,
    required this.background,
    required this.child,
  });

  final double height;
  final Color background;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: background,
      elevation: 0,
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: 0,
        maxHeight: height,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedBarDelegate old) => true;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Ambient Glowing Logo
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: t.accent.withValues(alpha: 0.16),
                      blurRadius: 40,
                      spreadRadius: 8,
                    ),
                  ],
                ),
              ),
              const BrandLogo(size: 88, withGlow: true),
            ],
          ),
          const SizedBox(height: 24),

          // Headline
          Text(
            'Your shelf is empty',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 8),

          // Explanatory subtitle
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              'Paste a link to any manga or webtoon chapter. Shelfmark removes every ad and bookmarks your reading progress automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Primary Paste Button
          PressableScale(
            onTap: () {
              HapticFeedback.mediumImpact();
              onAdd();
            },
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: t.accent,
                boxShadow: [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_link_rounded,
                    size: 20,
                    color: Color(0xFF04130C),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Paste Manga Link',
                    style: TextStyle(
                      color: Color(0xFF04130C),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 44, color: t.textTertiary),
          const SizedBox(height: 12),
          Text(
            'Nothing matches that',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try a different word or clear your filters.',
            style: TextStyle(color: t.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onClear,
            style: OutlinedButton.styleFrom(
              foregroundColor: t.accent,
              side: BorderSide(color: t.accent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }
}
