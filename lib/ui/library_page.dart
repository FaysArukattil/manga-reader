import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show HapticFeedback;
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
import '../theme/components/shimmer_box.dart';
import 'components/brand_logo.dart';
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
    final result = await showModalBottomSheet<SeriesFormResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) =>
          SeriesForm(existing: existing, initialUrl: url, initialTitle: title),
    );
    if (result == null || !mounted) return;
    final bloc = context.read<LibraryBloc>();
    if (existing == null) {
      final series = Series.create(
        id: context.read<LibraryRepository>().newId(),
        url: result.url,
        title: result.title,
        status: result.status,
      ).copyWith(category: result.category ?? bloc.state.categoryFilter);
      bloc.add(LibraryAddRequested(series));
      if (result.openAfter) UnifiedReaderPage.openSeries(context, series);
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
      );
      bloc.add(
        LibraryEditRequested(updated, refetchCover: newTitle != existing.title),
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

  Future<void> _deleteAccount() async {
    final ok = await _showConfirmDialog(
      title: 'Delete All Data?',
      content:
          'This will permanently delete your library, reading progress, and settings from this device and the cloud. This action cannot be undone.',
      confirmLabel: 'Delete All Data',
      isDestructive: true,
      icon: Icons.warning_amber_rounded,
    );
    if (ok != true || !mounted) return;
    final repo = context.read<LibraryRepository>();
    final thumbs = context.read<ThumbnailStore>();
    final auth = context.read<AuthBloc>();
    _snack('Deleting account...');
    try {
      await repo.deleteAll().timeout(const Duration(seconds: 20));
    } catch (_) {
      if (mounted) {
        _snack('Could not delete your data. Check your connection and retry.');
      }
      return;
    }
    await thumbs.clear();
    auth.add(const AuthDeleteRequested());
    final result = await auth.stream.firstWhere((s) => !s.busy);
    if (mounted && result.error != null) _snack(result.error!);
  }
  // ---------------------------------------------------------------------------
  // Category manager (themed)
  // ---------------------------------------------------------------------------

  void _showCategoryManagerSheet() {
    final bloc = context.read<LibraryBloc>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final t = sheetContext.tokens;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Categories',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _showAddCategoryDialog();
                      },
                      icon: Icon(Icons.add, size: 16, color: t.accent),
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
                const SizedBox(height: 4),
                Text(
                  'Tap to filter your shelf. Long-press a chip on the home '
                  'screen to rename or delete it.',
                  style: TextStyle(color: t.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                BlocBuilder<LibraryBloc, LibraryState>(
                  builder: (context, state) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CategoryChip(
                        label: 'All',
                        selected: state.categoryFilter == null,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          bloc.add(const LibraryCategoryFilterChanged(null));
                        },
                      ),
                      for (final cat in state.categories)
                        _CategoryChip(
                          label: cat,
                          selected: state.categoryFilter == cat,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            bloc.add(LibraryCategoryFilterChanged(cat));
                          },
                          onLongPress: () {
                            Navigator.pop(sheetContext);
                            _showCategoryOptions(cat);
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
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
  /// "reading" entry, else whatever is on the shelf.
  Series _pickHero(List<Series> all) {
    final opened = all.where((s) => s.lastReadAt != null).toList()
      ..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
    if (opened.isNotEmpty) return opened.first;
    final reading = all.where((s) => s.status == ReadStatus.reading);
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

  Widget _buildHeader(LibraryState state) {
    final t = context.tokens;
    final user = context.read<AuthBloc>().state.user;
    final headline = state.all.isEmpty
        ? 'Welcome to your shelf'
        : "What's next to read?";

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    headline,
                    key: ValueKey(headline),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildAccountMenu(user?.photoURL, user?.email),
        ],
      ),
    );
  }

  Widget _buildAccountMenu(String? photoUrl, String? email) {
    final t = context.tokens;
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      color: t.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: t.border),
      ),
      padding: EdgeInsets.zero,
      onSelected: (v) {
        if (v == 'out') {
          context.read<AuthBloc>().add(const AuthSignOutRequested());
        } else if (v == 'delete') {
          _deleteAccount();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            email ?? 'Signed in as Guest',
            style: TextStyle(color: t.textSecondary, fontSize: 12),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'out',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 18, color: t.textPrimary),
              const SizedBox(width: 10),
              Text('Sign out', style: TextStyle(color: t.textPrimary)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
              SizedBox(width: 10),
              Text('Delete data', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
      child: Container(
        width: 42,
        height: 42,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: t.accent, width: 1.5),
        ),
        child: CircleAvatar(
          backgroundColor: t.surfaceCard,
          backgroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
          child: photoUrl == null
              ? Icon(Icons.person, size: 18, color: t.textSecondary)
              : null,
        ),
      ),
    );
  }

  /// Search + sort + category chips in ONE pinned block, so filtering is always
  /// one thumb-reach away instead of scrolling past three stacked sections.
  Widget _buildStickyControls(LibraryState state) {
    final t = context.tokens;
    final bloc = context.read<LibraryBloc>();
    final focused = _searchFocus.hasFocus;

    final search = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 46,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(
          color: focused ? t.accent.withValues(alpha: 0.7) : t.border,
          width: focused ? 1.4 : 1,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: t.accent.withValues(alpha: 0.18),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 20,
            color: focused ? t.accent : t.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: t.textPrimary, fontSize: 14.5),
              cursorColor: t.accent,
              decoration: InputDecoration(
                hintText: 'Search your shelf',
                hintStyle: TextStyle(color: t.textTertiary, fontSize: 14.5),
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
              icon: Icon(Icons.close_rounded, size: 18, color: t.textSecondary),
              onPressed: () {
                _search.clear();
                bloc.add(const LibraryQueryChanged(''));
                setState(() {});
              },
            ),
        ],
      ),
    );

    final sort = PopupMenuButton<LibrarySort>(
      tooltip: 'Sort',
      color: t.surfaceCard,
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: t.border),
      ),
      initialValue: state.sort,
      onSelected: (v) => bloc.add(LibrarySortChanged(v)),
      itemBuilder: (_) => [
        for (final entry in const {
          LibrarySort.lastRead: 'Last read',
          LibrarySort.title: 'Title A–Z',
          LibrarySort.added: 'Recently added',
        }.entries)
          PopupMenuItem(
            value: entry.key,
            child: Row(
              children: [
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: state.sort == entry.key
                      ? t.accent
                      : Colors.transparent,
                ),
                const SizedBox(width: 8),
                Text(entry.value, style: TextStyle(color: t.textPrimary)),
              ],
            ),
          ),
      ],
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: t.surface,
          shape: BoxShape.circle,
          border: Border.all(color: t.border),
        ),
        child: Icon(Icons.swap_vert_rounded, size: 22, color: t.textSecondary),
      ),
    );

    final chips = SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _CategoryChip(
            label: 'All',
            selected: state.categoryFilter == null,
            onTap: () => bloc.add(const LibraryCategoryFilterChanged(null)),
          ),
          for (final cat in state.categories)
            _CategoryChip(
              label: cat,
              selected: state.categoryFilter == cat,
              onTap: () => bloc.add(LibraryCategoryFilterChanged(cat)),
              onLongPress: () => _showCategoryOptions(cat),
            ),
          _CategoryChip(
            icon: Icons.tune_rounded,
            label: 'Manage',
            selected: false,
            onTap: _showCategoryManagerSheet,
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 10),
              sort,
            ],
          ),
        ),
        chips,
        const SizedBox(height: 10),
      ],
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

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<LibraryBloc, LibraryState>(
          builder: (context, state) {
            final width = MediaQuery.sizeOf(context).width;
            final columns = (width / 170).floor().clamp(2, 6);
            final hasShelf = state.all.isNotEmpty;
            final showHighlights = !state.loading &&
                hasShelf &&
                state.query.trim().isEmpty &&
                state.categoryFilter == null;

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
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildHeader(state),
                  ),
                  if (showHighlights)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
                        child: _ContinueHero(
                          series: _pickHero(state.all),
                          onTap: _open,
                        ),
                      ),
                    ),
                  if (hasShelf)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _PinnedBarDelegate(
                        height: 4 + 46 + 10 + 36 + 10,
                        background: t.bg,
                        child: _buildStickyControls(state),
                      ),
                    ),
                  if (hasShelf) SliverToBoxAdapter(child: _buildShelfTitle(state)),
                  if (state.loading)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      sliver: SliverGrid(
                        gridDelegate: gridDelegate,
                        delegate: SliverChildBuilderDelegate(
                          (_, __) => const ShimmerBox(
                            width: double.infinity,
                            height: double.infinity,
                            borderRadius: 18,
                          ),
                          childCount: 6,
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                      sliver: SliverGrid(
                        gridDelegate: gridDelegate,
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final s = state.visible[i];
                            return _AnimatedGridTile(
                              key: ValueKey('tile_${s.id}'),
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
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        isExtended: _fabExtended,
        backgroundColor: t.accent,
        foregroundColor: const Color(0xFF04130C),
        elevation: 4,
        tooltip: 'Paste a link',
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_link_rounded, size: 22),
        label: const Text(
          'Add link',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2),
        ),
      ),
    );
  }
}

// =============================================================================
// Pieces
// =============================================================================

/// Big "Continue reading" card: blurred cover backdrop, sharp cover thumb,
/// one obvious Resume action. This is the single most important element on the
/// screen, so it gets the most visual weight.
class _ContinueHero extends StatelessWidget {
  const _ContinueHero({required this.series, required this.onTap});

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
        height: 168,
        decoration: BoxDecoration(
          color: t.surfaceCard,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Transform.scale(
                scale: 1.3,
                child: SeriesCover(series: series, memCacheWidth: 300),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  AspectRatio(
                    aspectRatio: 0.68,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SeriesCover(series: series, memCacheWidth: 360),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'CONTINUE READING',
                          style: TextStyle(
                            color: t.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          series.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            height: 1.18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          resume.isNotEmpty ? resume : series.host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: t.accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                                color: Color(0xFF04130C),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Resume',
                                style: TextStyle(
                                  color: Color(0xFF04130C),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = selected ? const Color(0xFF04130C) : t.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? t.accent : t.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? t.accent : t.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BrandLogo(size: 84, withGlow: true),
          const SizedBox(height: 22),
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
          Text(
            'Paste a link to any manga or webtoon chapter and it opens here as a clean reader. '
            'You can also share a link from your browser straight to this app.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_link_rounded, size: 20),
            label: const Text('Paste a link'),
            style: FilledButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: const Color(0xFF04130C),
              minimumSize: const Size(200, 50),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
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
