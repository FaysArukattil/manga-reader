import 'package:flutter/material.dart';
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
  bool _searching = false;
  late final ShareService _share;

  @override
  void initState() {
    super.initState();
    _share = context.read<ShareService>();
    _share.addListener(_onShare);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onShare());
  }

  @override
  void dispose() {
    _share.removeListener(_onShare);
    _search.dispose();
    super.dispose();
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
                  color: isCurrent ? AppColors.primary : Colors.white60,
                ),
                title: Text(
                  cat,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? AppColors.primary : Colors.white,
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
          'Shelfmark account. It cannot be undone.',
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

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<LibraryBloc>();
    final user = context.read<AuthBloc>().state.user;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search shelf',
                  border: InputBorder.none,
                ),
                onChanged: (v) => bloc.add(LibraryQueryChanged(v)),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandLogo(size: 28, withGlow: true),
                  SizedBox(width: 10),
                  Text('Shelfmark'),
                ],
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.explore_outlined),
            tooltip: 'Read on MangaDex',
            onPressed: () async {
              await DiscoverPage.open(context);
              if (mounted) bloc.add(const LibraryUpdatesRequested());
            },
          ),
          BlocSelector<LibraryBloc, LibraryState, bool>(
            selector: (s) => s.fromCache,
            builder: (context, fromCache) => fromCache
                ? const Tooltip(
                    message: 'Offline or syncing - changes will sync later',
                    child: Icon(Icons.cloud_off_outlined),
                  )
                : const SizedBox.shrink(),
          ),
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _search.clear();
                bloc.add(const LibraryQueryChanged(''));
              }
            },
          ),
          PopupMenuButton<LibrarySort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: (v) => bloc.add(LibrarySortChanged(v)),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: LibrarySort.lastRead,
                child: Text('Last read'),
              ),
              PopupMenuItem(value: LibrarySort.title, child: Text('Title')),
              PopupMenuItem(
                value: LibrarySort.added,
                child: Text('Recently added'),
              ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: CircleAvatar(
              radius: 14,
              backgroundImage:
                  user?.photoURL == null ? null : NetworkImage(user!.photoURL!),
              child: user?.photoURL == null
                  ? const Icon(Icons.person, size: 16)
                  : null,
            ),
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
                child: Text(user?.email ?? 'Signed in'),
              ),
              const PopupMenuItem<String>(
                value: 'out',
                child: Text('Sign out'),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: Text('Delete account & data'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: BlocBuilder<LibraryBloc, LibraryState>(
              buildWhen: (a, b) =>
                  a.categoryFilter != b.categoryFilter ||
                  a.categories != b.categories,
              builder: (context, state) => ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: state.categoryFilter == null,
                    onTap: () =>
                        bloc.add(const LibraryCategoryFilterChanged(null)),
                  ),
                  for (final cat in state.categories)
                    _FilterChip(
                      label: cat,
                      selected: state.categoryFilter == cat,
                      onTap: () => bloc.add(LibraryCategoryFilterChanged(cat)),
                      onLongPress: () => _showCategoryOptions(cat),
                    ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.add,
                          size: 16, color: AppColors.primary),
                      label: const Text(
                        'New Category',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      onPressed: _showAddCategoryDialog,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: BlocBuilder<LibraryBloc, LibraryState>(
              builder: (context, state) {
                final width = MediaQuery.sizeOf(context).width;
                final columns = (width / 180).floor().clamp(2, 6);

                if (state.loading) {
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      childAspectRatio: 0.68,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                    ),
                    itemCount: 6,
                    itemBuilder: (_, __) => const ShimmerBox(
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: 16,
                    ),
                  );
                }
                if (state.all.isEmpty) {
                  return const _EmptyState();
                }
                if (state.visible.isEmpty) {
                  return const Center(
                    child: Text(
                      'No matching manga found',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }
                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    bloc.add(const LibraryUpdatesRequested(force: true));
                    await Future<void>.delayed(
                      const Duration(milliseconds: 600),
                    );
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      childAspectRatio: 0.68,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                    ),
                    itemCount: state.visible.length,
                    itemBuilder: (context, i) {
                      final s = state.visible[i];
                      return SeriesCard(
                        key: ValueKey(s.id),
                        series: s,
                        onTap: () {
                          bloc.add(LibraryMarkSeriesRead(s.id));
                          s.isMangaDex
                              ? MdDetailPage.openSeries(context, s)
                              : UnifiedReaderPage.openSeries(context, s);
                        },
                        onLongPress: () => _showActions(s),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        elevation: 4,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text(
          'Add Link',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: AppColors.primary.withValues(alpha: 0.2),
          checkmarkColor: AppColors.primary,
          side: BorderSide(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.5)
                : Colors.white12,
            width: 0.8,
          ),
          labelStyle: TextStyle(
            color: selected ? AppColors.primary : Colors.white70,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandLogo(size: 80, withGlow: true),
            SizedBox(height: 24),
            Text(
              'Your shelf is empty',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Open a chapter in Chrome, tap Share, and choose Shelfmark.\n'
              'Or tap "Add Link" below to paste any manga URL.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
