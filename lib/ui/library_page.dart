import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/auth_bloc.dart';
import '../blocs/library_bloc.dart';
import '../core/url_tools.dart';
import '../data/library_repository.dart';
import '../models/series.dart';
import '../services/share_service.dart';
import 'reader_page.dart';
import 'series_card.dart';
import 'series_form.dart';

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
          onPressed: () => ReaderPage.open(context, existing),
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
      );
      bloc.add(LibraryAddRequested(series));
      if (result.openAfter) ReaderPage.open(context, series);
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
        scroll: urlChanged ? 0 : existing.scroll,
      );
      bloc.add(
        LibraryEditRequested(updated, refetchCover: newTitle != existing.title),
      );
    }
  }

  Future<void> _showActions(Series s) async {
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
              subtitle: Text(s.host),
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
    if (action == 'edit') {
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
        context.read<LibraryBloc>().add(LibraryDeleteRequested(s));
      }
    }
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
            : const Text('Shelfmark'),
        actions: [
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
              backgroundImage: user?.photoURL == null
                  ? null
                  : NetworkImage(user!.photoURL!),
              child: user?.photoURL == null
                  ? const Icon(Icons.person, size: 16)
                  : null,
            ),
            onSelected: (v) {
              if (v == 'out') {
                context.read<AuthBloc>().add(const AuthSignOutRequested());
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
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: BlocSelector<LibraryBloc, LibraryState, ReadStatus?>(
              selector: (s) => s.filter,
              builder: (context, filter) => ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: filter == null,
                    onTap: () => bloc.add(const LibraryFilterChanged(null)),
                  ),
                  for (final s in ReadStatus.values)
                    _FilterChip(
                      label: s.label,
                      selected: filter == s,
                      onTap: () => bloc.add(LibraryFilterChanged(s)),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: BlocBuilder<LibraryBloc, LibraryState>(
              builder: (context, state) {
                if (state.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.all.isEmpty) {
                  return const _EmptyState();
                }
                if (state.visible.isEmpty) {
                  return const Center(child: Text('No matches'));
                }
                final width = MediaQuery.sizeOf(context).width;
                final columns = (width / 180).floor().clamp(2, 6);
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: 0.68,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: state.visible.length,
                  itemBuilder: (context, i) {
                    final s = state.visible[i];
                    return SeriesCard(
                      key: ValueKey(s.id),
                      series: s,
                      onTap: () => ReaderPage.open(context, s),
                      onLongPress: () => _showActions(s),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.collections_bookmark_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Your shelf is empty',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Open a chapter in Chrome, tap Share, and choose Shelfmark.\n'
              'Or tap Add and paste a link.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
