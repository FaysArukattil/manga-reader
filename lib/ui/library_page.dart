import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/auth_bloc.dart';
import '../blocs/library_bloc.dart';
import '../core/url_tools.dart';
import '../data/library_repository.dart';
import '../models/series.dart';
import '../services/category_store.dart';
import '../services/page_cache.dart';
import '../services/scrape/cf_session.dart';
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

  void _showCategoryManagerSheet() {
    final bloc = context.read<LibraryBloc>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF13151D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Categories',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _showAddCategoryDialog();
                    },
                    icon: const Icon(Icons.add, size: 16, color: Color(0xFF00FFA3)),
                    label: const Text(
                      'New',
                      style: TextStyle(
                        color: Color(0xFF00FFA3),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              BlocBuilder<LibraryBloc, LibraryState>(
                builder: (context, state) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('All'),
                      backgroundColor: state.categoryFilter == null
                          ? const Color(0xFF00FFA3).withValues(alpha: 0.15)
                          : const Color(0xFF1E202A),
                      labelStyle: TextStyle(
                        color: state.categoryFilter == null
                            ? const Color(0xFF00FFA3)
                            : Colors.white,
                        fontWeight: state.categoryFilter == null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: state.categoryFilter == null
                            ? const Color(0xFF00FFA3)
                            : Colors.white12,
                      ),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        bloc.add(const LibraryCategoryFilterChanged(null));
                      },
                    ),
                    for (final cat in state.categories)
                      ActionChip(
                        label: Text(cat),
                        backgroundColor: state.categoryFilter == cat
                            ? const Color(0xFF00FFA3).withValues(alpha: 0.15)
                            : const Color(0xFF1E202A),
                        labelStyle: TextStyle(
                          color: state.categoryFilter == cat
                              ? const Color(0xFF00FFA3)
                              : Colors.white,
                          fontWeight: state.categoryFilter == cat
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: state.categoryFilter == cat
                              ? const Color(0xFF00FFA3)
                              : Colors.white12,
                        ),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          bloc.add(LibraryCategoryFilterChanged(cat));
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpotlightSearchBar(LibraryBloc bloc) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0C2233),
            Color(0xFF09141F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: const Color(0xFF00FFA3).withValues(alpha: 0.25),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00B4D8).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Fantasy, Solo Leveling, Stephen King..',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
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
            GestureDetector(
              onTap: () {
                _search.clear();
                bloc.add(const LibraryQueryChanged(''));
                setState(() {});
              },
              child: const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.close_rounded, size: 18, color: Colors.white60),
              ),
            ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF16324A),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: const Icon(
              Icons.search_rounded,
              size: 18,
              color: Color(0xFF00FFA3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesSection(LibraryBloc bloc, LibraryState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Categories',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            GestureDetector(
              onTap: _showCategoryManagerSheet,
              child: const Text(
                'See All >',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _FilterChip(
                label: 'All',
                selected: state.categoryFilter == null,
                onTap: () => bloc.add(const LibraryCategoryFilterChanged(null)),
              ),
              for (final cat in state.categories)
                _FilterChip(
                  label: cat,
                  selected: state.categoryFilter == cat,
                  onTap: () => bloc.add(LibraryCategoryFilterChanged(cat)),
                  onLongPress: () => _showCategoryOptions(cat),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildForYouSection(List<Series> topPicks, LibraryBloc bloc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'For you',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            GestureDetector(
              onTap: () {},
              child: const Text(
                'See All >',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 205,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: topPicks.length,
            itemBuilder: (context, i) {
              final s = topPicks[i];
              return _ContinueReadingCard(
                series: s,
                onTap: () {
                  bloc.add(LibraryMarkSeriesRead(s.id));
                  s.isMangaDex
                      ? MdDetailPage.openSeries(context, s)
                      : UnifiedReaderPage.openSeries(context, s);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<LibraryBloc>();
    final user = context.read<AuthBloc>().state.user;

    return Scaffold(
      backgroundColor: const Color(0xFF090A0E),
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<LibraryBloc, LibraryState>(
          builder: (context, state) {
            final width = MediaQuery.sizeOf(context).width;
            final columns = (width / 180).floor().clamp(2, 6);

            final forYouList = state.all
                .where((s) => s.status == ReadStatus.reading)
                .toList();
            final topPicks = forYouList.isNotEmpty
                ? forYouList
                : state.all.take(6).toList();

            return RefreshIndicator(
              color: const Color(0xFF00FFA3),
              backgroundColor: const Color(0xFF13151D),
              onRefresh: () async {
                bloc.add(const LibraryUpdatesRequested(force: true));
                await Future<void>.delayed(const Duration(milliseconds: 600));
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Header Row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const BrandLogo(size: 44, withGlow: true),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Welcome to Manga Reader',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.4,
                                        height: 1.2,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      "What's next to read?",
                                      style: TextStyle(
                                        color: Color(0xFFA0A4B2),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Header action buttons
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.explore_outlined,
                                      color: Colors.white70,
                                      size: 22,
                                    ),
                                    tooltip: 'Browse MangaDex',
                                    onPressed: () async {
                                      await DiscoverPage.open(context);
                                      if (mounted) {
                                        bloc.add(const LibraryUpdatesRequested());
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.notifications_none_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                    tooltip: 'Check Updates',
                                    onPressed: () {
                                      bloc.add(
                                        const LibraryUpdatesRequested(
                                          force: true,
                                        ),
                                      );
                                      _snack(
                                        'Checking chapters for new releases...',
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  PopupMenuButton<String>(
                                    tooltip: 'Account',
                                    offset: const Offset(0, 42),
                                    color: const Color(0xFF1E2028),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: const BorderSide(
                                        color: Colors.white12,
                                      ),
                                    ),
                                    icon: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFF00FFA3),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: CircleAvatar(
                                        radius: 14,
                                        backgroundImage: user?.photoURL == null
                                            ? null
                                            : NetworkImage(user!.photoURL!),
                                        child: user?.photoURL == null
                                            ? const Icon(
                                                Icons.person,
                                                size: 16,
                                                color: Colors.white70,
                                              )
                                            : null,
                                      ),
                                    ),
                                    onSelected: (v) {
                                      if (v == 'out') {
                                        context
                                            .read<AuthBloc>()
                                            .add(const AuthSignOutRequested());
                                      } else if (v == 'delete') {
                                        _deleteAccount();
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      PopupMenuItem<String>(
                                        enabled: false,
                                        child: Text(
                                          user?.email ?? 'Signed in as Guest',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const PopupMenuDivider(),
                                      const PopupMenuItem<String>(
                                        value: 'out',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.logout_rounded,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Sign out',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.delete_outline,
                                              size: 16,
                                              color: Colors.redAccent,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Delete data',
                                              style: TextStyle(
                                                color: Colors.redAccent,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Spotlight Search Container
                          _buildSpotlightSearchBar(bloc),
                          const SizedBox(height: 24),

                          // Categories Header & Chips
                          _buildCategoriesSection(bloc, state),
                          const SizedBox(height: 24),

                          // For You Carousel
                          if (_search.text.isEmpty && topPicks.isNotEmpty) ...[
                            _buildForYouSection(topPicks, bloc),
                            const SizedBox(height: 24),
                          ],

                          // "Your Shelf" Section Header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Your Shelf',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E202A),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${state.visible.length}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              PopupMenuButton<LibrarySort>(
                                tooltip: 'Sort',
                                color: const Color(0xFF1E2028),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(
                                    color: Colors.white12,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.swap_vert_rounded,
                                  color: Colors.white70,
                                  size: 22,
                                ),
                                onSelected: (v) =>
                                    bloc.add(LibrarySortChanged(v)),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: LibrarySort.lastRead,
                                    child: Text(
                                      'Last read',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: LibrarySort.title,
                                    child: Text(
                                      'Title',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: LibrarySort.added,
                                    child: Text(
                                      'Recently added',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),

                  // Main Grid / Empty / Loading State
                  if (state.loading)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          childAspectRatio: 0.68,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, __) => const ShimmerBox(
                            width: double.infinity,
                            height: double.infinity,
                            borderRadius: 16,
                          ),
                          childCount: 6,
                        ),
                      ),
                    )
                  else if (state.all.isEmpty)
                    const SliverToBoxAdapter(
                      child: _EmptyState(),
                    )
                  else if (state.visible.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'No matching manga found',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          childAspectRatio: 0.68,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
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
        backgroundColor: const Color(0xFF00FFA3),
        foregroundColor: const Color(0xFF090A0E),
        elevation: 6,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text(
          'Add Link',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
      ),
    );
  }
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({
    required this.series,
    required this.onTap,
  });

  final Series series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = series.coverUrl;
    final thumb = context.read<ThumbnailStore>().fileFor(series.id);

    Widget imageWidget;
    if (cover != null && cover.isNotEmpty) {
      imageWidget = CachedNetworkImage(
        imageUrl: cover,
        cacheKey: cover,
        cacheManager: PageCache.instance,
        httpHeaders: CfSession.imageHeaders(
          cover,
          series.url.isNotEmpty ? series.url : null,
        ),
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => thumb != null
            ? Image.file(thumb, fit: BoxFit.cover)
            : Container(
                color: const Color(0xFF1F222E),
                child: Center(
                  child: Text(
                    series.title.isEmpty ? '?' : series.title[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
      );
    } else if (thumb != null) {
      imageWidget = Image.file(thumb, fit: BoxFit.cover);
    } else {
      imageWidget = Container(
        color: const Color(0xFF1F222E),
        child: Center(
          child: Text(
            series.title.isEmpty ? '?' : series.title[0].toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return PressableScale(
      onTap: onTap,
      scaleDown: 0.95,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            imageWidget,
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: [0.0, 0.55, 1.0],
                  colors: [
                    Color(0xF5000000),
                    Color(0x99000000),
                    Color(0x00000000),
                  ],
                ),
              ),
            ),
            if (series.resumeLabel.isNotEmpty)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    series.resumeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    series.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          series.host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF00FFA3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00FFA3)
                                  .withValues(alpha: 0.4),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 16,
                          color: Colors.black,
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
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF00FFA3).withValues(alpha: 0.15)
                : const Color(0xFF13151D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? const Color(0xFF00FFA3).withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.1),
              width: selected ? 1.2 : 0.8,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF00FFA3).withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFF00FFA3) : Colors.white70,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(size: 76, withGlow: true),
            const SizedBox(height: 20),
            const Text(
              'Your shelf is waiting',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Share any chapter link from Chrome to Manga Reader, or tap "+ Add Link" to paste a manga, webtoon, or novel URL.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => DiscoverPage.open(context),
              icon: const Icon(Icons.explore_rounded, size: 18),
              label: const Text('Explore MangaDex Titles'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00FFA3),
                side: const BorderSide(color: Color(0xFF00FFA3)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
