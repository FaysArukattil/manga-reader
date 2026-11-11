import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/series.dart';
import '../services/thumbnail_store.dart';
import '../theme/app_colors.dart';
import '../theme/components/pressable_scale.dart';

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
    final letter = series.title.isEmpty
        ? '?'
        : String.fromCharCode(series.title.runes.first).toUpperCase();
    return Container(
      color: const Color(0xFF23252E),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white38,
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
      fadeInDuration: const Duration(milliseconds: 140),
      placeholder: (_, __) => _placeholder(context),
      errorWidget: (_, __, ___) => _fallbackImage(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      onLongPress: onLongPress,
      scaleDown: 0.95,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _image(context),
            // Bottom gradient backdrop
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
            // Top Pills: Chapter Resume and NEW Badge
            if (series.resumeLabel.isNotEmpty)
              Positioned(
                top: 8,
                left: 8,
                child: _Pill(text: series.resumeLabel),
              ),
            if (series.hasNew)
              const Positioned(
                top: 8,
                right: 8,
                child: _Pill(text: 'NEW', isAccent: true),
              )
            else if (series.status != ReadStatus.reading)
              Positioned(
                top: 8,
                right: 8,
                child: _Pill(text: series.status.label),
              ),
            // Bottom Information
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
                      fontSize: 13,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      CachedNetworkImage(
                        imageUrl:
                            'https://www.google.com/s2/favicons?domain=${series.host}&sz=64',
                        width: 13,
                        height: 13,
                        memCacheWidth: 64,
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.public,
                          size: 13,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 5),
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
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        size: 18,
                        color: AppColors.primary,
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

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.isAccent = false});
  final String text;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:
            isAccent ? AppColors.primary : Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        boxShadow: isAccent
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      child: Text(
        text,
        style: TextStyle(
          color: isAccent ? Colors.black : Colors.white,
          fontSize: 10,
          fontWeight: isAccent ? FontWeight.w800 : FontWeight.w500,
          letterSpacing: isAccent ? 0.4 : 0,
        ),
      ),
    );
  }
}
