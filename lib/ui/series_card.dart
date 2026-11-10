import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/series.dart';
import '../services/thumbnail_store.dart';

class SeriesCard extends StatelessWidget {
  const SeriesCard({
    super.key,
    required this.series,
    required this.onTap,
    required this.onLongPress,
  });

  final Series series;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = series.title.isEmpty
        ? '?'
        : String.fromCharCode(series.title.runes.first).toUpperCase();
    return ColoredBox(
      color: scheme.secondaryContainer,
      child: Center(
        child: Text(
          letter,
          style: Theme.of(context).textTheme.displayMedium
              ?.copyWith(color: scheme.onSecondaryContainer),
        ),
      ),
    );
  }

  Widget _fallbackImage(BuildContext context) {
    final file = context.read<ThumbnailStore>().fileFor(series.id);
    if (file == null) return _placeholder(context);
    return Image.file(
      file,
      key: ValueKey(series.updatedAt.millisecondsSinceEpoch),
      fit: BoxFit.cover,
      cacheWidth: 420,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _placeholder(context),
    );
  }

  Widget _image(BuildContext context) {
    final cover = series.coverUrl;
    if (cover == null || cover.isEmpty) return _fallbackImage(context);
    return CachedNetworkImage(
      imageUrl: cover,
      fit: BoxFit.cover,
      memCacheWidth: 420,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => _placeholder(context),
      errorWidget: (_, __, ___) => _fallbackImage(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Material(
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _image(context),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [Color(0xE6000000), Color(0x00000000)],
                  ),
                ),
              ),
              if (series.chapter.isNotEmpty)
                Positioned(top: 8, left: 8, child: _Pill(text: series.chapter)),
              if (series.status != ReadStatus.reading)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _Pill(text: series.status.label),
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
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        CachedNetworkImage(
                          imageUrl:
                              'https://www.google.com/s2/favicons?domain=${series.host}&sz=64',
                          width: 14,
                          height: 14,
                          memCacheWidth: 64,
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.public,
                            size: 14,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            series.host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.play_arrow_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }
}
