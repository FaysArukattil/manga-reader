import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/library_bloc.dart';
import '../blocs/md_blocs.dart';
import '../data/library_repository.dart';
import '../models/series.dart';
import '../services/mangadex_service.dart';
import '../services/page_cache.dart';
import 'unified_reader_page.dart';
import '../services/reader/chapter_source.dart';

class MdDetailPage extends StatelessWidget {
  const MdDetailPage({super.key, required this.manga});

  final MdManga manga;

  static Future<void> open(BuildContext context, MdManga manga) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => MdDetailPage(manga: manga)));
  }

  static Future<void> openSeries(BuildContext context, Series s) {
    return open(
      context,
      MdManga(
        id: s.mdId!,
        title: s.title,
        description: '',
        coverUrl: s.coverUrl,
        latestChapterId: s.mdNewest,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => MdDetailCubit(
        c.read<MangaDexService>(),
        c.read<ChapterStore>(),
        manga.id,
      ),
      child: _DetailView(manga: manga),
    );
  }
}

class _DetailView extends StatefulWidget {
  const _DetailView({required this.manga});
  final MdManga manga;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView> {
  @override
  void initState() {
    super.initState();
    // Opening the series clears its NEW badge.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shelf = _shelfEntry(context);
      if (shelf != null && shelf.hasNew) {
        context.read<LibraryRepository>().update(
            shelf.id,
            {
              'mdSeen': shelf.mdNewest,
            },
            touch: false);
      }
    });
  }

  Series? _shelfEntry(BuildContext context) => context
      .read<LibraryBloc>()
      .state
      .all
      .where((s) => s.mdId == widget.manga.id)
      .firstOrNull;

  void _toggleShelf(Series? shelf) {
    final bloc = context.read<LibraryBloc>();
    if (shelf != null) {
      bloc.add(LibraryDeleteRequested(shelf));
      return;
    }
    final m = widget.manga;
    bloc.add(
      LibraryAddRequested(
        Series.md(
          id: context.read<LibraryRepository>().newId(),
          mdId: m.id,
          title: m.title,
          coverUrl: m.coverUrl,
          newest: m.latestChapterId,
        ),
      ),
    );
  }

  void _read(
    List<MdChapter> chapters,
    int index,
    Series? shelf, {
    int page = 0,
  }) {
    final source = MangaDexSource(
      service: context.read<MangaDexService>(),
      store: context.read<ChapterStore>(),
      chapters: chapters,
    );
    final series = shelf ??
        Series.md(
          id: context.read<LibraryRepository>().newId(),
          mdId: widget.manga.id,
          title: widget.manga.title,
          coverUrl: widget.manga.coverUrl,
        );
    UnifiedReaderPage.open(
      context,
      series: series,
      source: source,
      startChapterId: chapters[index].id,
      startPageIndex: page,
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.manga;
    final shelf = context.select<LibraryBloc, Series?>(
      (b) => b.state.all.where((s) => s.mdId == m.id).firstOrNull,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: BlocBuilder<MdDetailCubit, MdDetailState>(
        builder: (context, state) {
          final resumeIndex = shelf?.mdChapterId == null
              ? -1
              : state.chapters.indexWhere((c) => c.id == shelf!.mdChapterId);
          final newestFirst = state.chapters.reversed.toList();
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 110,
                              height: 160,
                              child: m.coverUrl == null
                                  ? const ColoredBox(color: Colors.black12)
                                  : CachedNetworkImage(
                                      imageUrl: m.coverUrl!,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 330,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.title,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                if (m.status.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      m.status,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                FilledButton.tonalIcon(
                                  onPressed: () => _toggleShelf(shelf),
                                  icon: Icon(
                                    shelf == null ? Icons.add : Icons.check,
                                  ),
                                  label: Text(
                                    shelf == null
                                        ? 'Add to shelf'
                                        : 'On shelf (tap to remove)',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: state.chapters.isEmpty
                                      ? null
                                      : () => resumeIndex >= 0
                                          ? _read(
                                              state.chapters,
                                              resumeIndex,
                                              shelf,
                                              page: shelf?.mdPage ?? 0,
                                            )
                                          : _read(state.chapters, 0, shelf),
                                  icon: const Icon(Icons.play_arrow),
                                  label: Text(
                                    resumeIndex >= 0
                                        ? 'Continue ${state.chapters[resumeIndex].label}'
                                        : 'Start reading',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (m.description.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          m.description,
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'Provided by MangaDex. Chapters are uploaded by '
                        'scanlation groups, who are credited in the reader.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (state.offlineList)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Offline - showing the last saved chapter list.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (state.loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.error!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => context.read<MdDetailCubit>().load(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (state.chapters.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No chapters readable here. This series may be '
                        'hosted by its official publisher instead.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final c = newestFirst[i];
                    final ascIndex = state.chapters.length - 1 - i;
                    final read = resumeIndex >= 0 && ascIndex < resumeIndex;
                    return ListTile(
                      title: Text(
                        c.number.isNotEmpty && c.title.isNotEmpty
                            ? '${c.label} - ${c.title}'
                            : c.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: c.group.isEmpty ? null : Text(c.group),
                      trailing: read
                          ? const Icon(Icons.check_circle_outline, size: 18)
                          : null,
                      onTap: () => _read(state.chapters, ascIndex, shelf),
                    );
                  }, childCount: newestFirst.length),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }
}
