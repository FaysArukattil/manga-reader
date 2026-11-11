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
import 'discover_page.dart';
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
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${s.host} · Category: ${s.category ?? s.status.label}',
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.drive_file_move_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Move to Category'),
              subtitle: Text(s.category ?? s.status.label),
              onTap: () => Navigator.pop(sheetContext, 'move'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove from shelf'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'move') {
      _showMoveCategorySheet(s);
    } else if (action == 'edit') {
      _openForm(existing: s);
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Remove from shelf?'),
          content: Text('"${s.title}" and its saved progress will be deleted.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) {
        bloc.add(LibraryDeleteRequested(s));
      }
    }
  }

  void _showMoveCategorySheet(Series s) {
    final bloc = context.read<LibraryBloc>();
    final categories = bloc.state.categories;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Move "${s.title}" to Category',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(),
            ...categories.map((cat) {
              final isCurrent = (s.category ?? s.status.label).toLowerCase() ==
                  cat.toLowerCase();
              return ListTile(
                leading: Icon(
                  isCurrent ? Icons.check_circle : Icons.folder_outlined,
                  color: isCurrent
                      ? AppColors.primary
                      : sheetContext.tokens.textSecondary,
                ),
                title: Text(
                  cat,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent
                        ? AppColors.primary
                        : sheetContext.tokens.textPrimary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  bloc.add(LibraryMoveSeriesRequested(s, cat));
                  _snack('Moved to "$cat"');
                },
              );
            }),
            ListTile(
              leading: const Icon(Icons.add, color: AppColors.primary),
              title: const Text(
                'Create New Category',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _showAddCategoryDialog(moveSeries: s);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showCategoryOptions(String cat) {
    final bloc = context.read<LibraryBloc>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                cat,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text('Category Options'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename Category'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showRenameCategoryDialog(cat);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text(
                'Delete Category',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dContext) => AlertDialog(
                    title: Text('Delete "$cat"?'),
                    content: const Text(
                      'Books in this category will not be deleted, they will simply lose this category label.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dContext, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dContext, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
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
  }

  void _showAddCategoryDialog({Series? moveSeries}) {
    final bloc = context.read<LibraryBloc>();
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dContext) => AlertDialog(
        title: const Text('New Category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Favorites, Shonen, Webtoons',
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dContext),
            child: const Text('Cancel'),
          ),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameCategoryDialog(String oldName) {
    final bloc = context.read<LibraryBloc>();
    final controller = TextEditingController(text: oldName);
    showDialog<void>(
      context: context,
      builder: (dContext) => AlertDialog(
        title: const Text('Rename Category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'New category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dContext),
            child: const Text('Cancel'),
          ),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your shelf, reading progress and your '
          'Manga Reader account. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
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

  void _checkUpdates() {
    context.read<LibraryBloc>().add(const LibraryUpdatesRequested(force: true));
    _snack('Checking for new chapters…');
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

  Widget _buildHeader(LibraryState state, int newCount) {
    final t = context.tokens;
    final user = context.read<AuthBloc>().state.user;
    final headline = state.all.isEmpty
        ? 'Welcome to your shelf'
        : newCount > 0
            ? (newCount == 1
                ? '1 new chapter waiting'
                : '$newCount new chapters waiting')
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
          _RoundButton(
            icon: Icons.explore_outlined,
            tooltip: 'Discover',
            onTap: () async {
              await DiscoverPage.open(context);
              if (mounted) {
                context
                    .read<LibraryBloc>()
                    .add(const LibraryUpdatesRequested());
              }
            },
          ),
          const SizedBox(width: 8),
          _RoundButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Check for new chapters',
            badge: newCount,
            onTap: _checkUpdates,
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

  Widget _buildNewStrip(List<Series> fresh) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            children: [
              Text(
                'New chapters',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 8),
              _CountBadge(count: fresh.length, accent: true),
            ],
          ),
        ),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: fresh.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _MiniCover(
              series: fresh[i],
              onTap: () => _open(fresh[i]),
            ),
          ),
        ),
        const SizedBox(height: 22),
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
            final fresh = state.all.where((s) => s.hasNew).toList();
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
                    child: _buildHeader(state, fresh.length),
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
                  if (showHighlights && fresh.isNotEmpty)
                    SliverToBoxAdapter(child: _buildNewStrip(fresh)),
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
                            return _EntranceFade(
                              key: ValueKey('fade_${s.id}'),
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

class _MiniCover extends StatelessWidget {
  const _MiniCover({required this.series, required this.onTap});

  final Series series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PressableScale(
      onTap: onTap,
      scaleDown: 0.95,
      child: SizedBox(
        width: 104,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.accent.withValues(alpha: 0.8), width: 1.4),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SeriesCover(series: series, memCacheWidth: 280),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    stops: [0.0, 0.5, 1.0],
                    colors: [
                      Color(0xE6000000),
                      Color(0x66000000),
                      Color(0x00000000),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      color: Color(0xFF04130C),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Text(
                  series.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uniform circular header button with an optional count badge.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onTap,
        scaleDown: 0.9,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: t.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.border),
                ),
                child: Icon(icon, size: 21, color: t.textPrimary),
              ),
              if (badge > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: t.accent,
                      shape: badge > 9 ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius:
                          badge > 9 ? BorderRadius.circular(9) : null,
                      border: Border.all(color: t.bg, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                        color: Color(0xFF04130C),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.accent = false});

  final int count;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accent ? t.accent.withValues(alpha: 0.16) : t.surfaceCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: accent ? t.accent : t.textSecondary,
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

/// Fades + slides a grid tile in the first time it is built, with a small
/// stagger so the shelf "settles" instead of popping in.
class _EntranceFade extends StatelessWidget {
  const _EntranceFade({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ms = 280 + (index % 8) * 55;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: child),
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
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => DiscoverPage.open(context),
            icon: Icon(Icons.explore_outlined, size: 18, color: t.accent),
            label: Text(
              'Or browse MangaDex',
              style: TextStyle(color: t.accent, fontWeight: FontWeight.w700),
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
