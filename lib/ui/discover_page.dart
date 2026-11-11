import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/md_blocs.dart';
import '../services/mangadex_service.dart';
import '../theme/components/pressable_scale.dart';
import '../theme/components/shimmer_box.dart';
import 'md_detail_page.dart';

/// Browse and search MangaDex (official API) and read chapters natively.
class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const DiscoverPage()));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => DiscoverCubit(c.read<MangaDexService>()),
      child: const _DiscoverView(),
    );
  }
}

class _DiscoverView extends StatefulWidget {
  const _DiscoverView();

  @override
  State<_DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<_DiscoverView> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) context.read<DiscoverCubit>().search(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 150).floor().clamp(2, 6);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search MangaDex',
            border: InputBorder.none,
          ),
        ),
      ),
      body: BlocBuilder<DiscoverCubit, DiscoverState>(
        builder: (context, state) {
          if (state.loading) {
            return GridView.builder(
              padding: const EdgeInsets.all(14),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: 0.66,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
              ),
              itemCount: 8,
              itemBuilder: (_, __) => const ShimmerBox(
                width: double.infinity,
                height: double.infinity,
                borderRadius: 14,
              ),
            );
          }
          if (state.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () =>
                          context.read<DiscoverCubit>().search(state.query),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (state.results.isEmpty) {
            return const Center(child: Text('No results'));
          }
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
                context.read<DiscoverCubit>().loadMore();
              }
              return false;
            },
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: 0.66,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: state.results.length,
              itemBuilder: (context, i) => _CoverTile(manga: state.results[i]),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'Content provided by MangaDex',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    );
  }
}

class _CoverTile extends StatelessWidget {
  const _CoverTile({required this.manga});
  final MdManga manga;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () => MdDetailPage.open(context, manga),
      scaleDown: 0.95,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF22242B),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (manga.coverUrl != null)
              CachedNetworkImage(
                imageUrl: manga.coverUrl!,
                fit: BoxFit.cover,
                memCacheWidth: 360,
                fadeInDuration: const Duration(milliseconds: 140),
                placeholder: (_, __) => const ShimmerBox(
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: [0.0, 0.45, 1.0],
                  colors: [
                    Color(0xF0000000),
                    Color(0x8A000000),
                    Color(0x00000000),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(
                manga.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
