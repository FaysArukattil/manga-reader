import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/series.dart';
import '../services/page_cache.dart';
import '../services/scrape/cf_session.dart';
import '../services/thumbnail_store.dart';
import '../theme/app_colors.dart';
import '../theme/components/pressable_scale.dart';

/// Cover artwork for a [Series] with the same loading pipeline the reader
/// uses (cookie/UA headers, cached file fallback, letter placeholder).
/// Shared by the shelf grid, the "Continue reading" hero and the
/// "New chapters" strip so covers behave identically everywhere.
class SeriesCover extends StatelessWidget {
  const SeriesCover({super.key, required this.series, this.memCacheWidth = 420});

  final Series series;
  final int memCacheWidth;

  Widget _placeholder(BuildContext context) {
    final t = context.tokens;
    final letter = series.title.isEmpty
        ? '?'
        : String.fromCharCode(series.title.runes.first).toUpperCase();
    return Container(
      color: t.surfaceCard,
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: t.textTertiary,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
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
      cacheWidth: memCacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _placeholder(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cover = series.coverUrl;
    if (cover == null || cover.isEmpty) return _fallbackImage(context);
    return CachedNetworkImage(
      imageUrl: cover,
      cacheKey: cover,
      cacheManager: PageCache.instance,
      httpHeaders: CfSession.imageHeaders(
        cover,
        series.url.isNotEmpty ? series.url : null,
      ),
      fit: BoxFit.cover,
      memCacheWidth: memCacheWidth,
      fadeInDuration: const Duration(milliseconds: 160),
      placeholder: (_, __) => _placeholder(context),
      errorWidget: (_, __, ___) => _fallbackImage(context),
    );
  }
}

/// A shelf tile. Intentionally quiet: cover, title, one line of context.
/// (The old card also fired a favicon network request per tile and stacked
/// three pills + a play icon on top of the art, which read as noise.)
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

  @override
  Widget build(BuildContext context) {
    final subtitle =
        series.resumeLabel.isNotEmpty ? series.resumeLabel : series.host;
    final showStatus = !series.hasNew && series.status != ReadStatus.reading;

    return PressableScale(
      onTap: onTap,
      onLongPress: onLongPress,
      scaleDown: 0.96,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        foregroundDecoration: series.hasNew
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.85),
                  width: 1.6,
                ),
              )
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SeriesCover(series: series),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: [0.0, 0.42, 0.75],
                  colors: [
                    Color(0xF2000000),
                    Color(0x80000000),
                    Color(0x00000000),
                  ],
                ),
              ),
            ),
            if (series.hasNew)
              const Positioned(
                top: 10,
                right: 10,
                child: _Pill(text: 'NEW', accent: true),
              )
            else if (showStatus)
              Positioned(
                top: 10,
                right: 10,
                child: _Pill(text: series.status.label),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
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
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
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

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.accent = false});
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent ? AppColors.primary : Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: accent ? const Color(0xFF04130C) : Colors.white,
          fontSize: 10,
          fontWeight: accent ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: accent ? 0.5 : 0,
        ),
      ),
    );
  }
}
