import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import '../state/downloads.dart';
import '../state/library_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'cached_image.dart';
import '../api/jellyfin_client.dart';

/// Loads the best image for an item (portrait poster, or landscape art for
/// continue-watching / library tiles), with correct auth headers and a
/// graceful placeholder when there's no image or it fails to load.
class MediaImage extends ConsumerWidget {
  final BaseItemDto item;
  final bool landscape;
  /// The icon when there's no picture. Unset, it follows the item's kind (a
  /// person, music, a show, a playlist), so a song isn't shown as a film.
  final IconData? placeholderIcon;

  /// What to show when there is no picture, in place of the icon on a
  /// tinted box: for a large surface (the Home banner) where a small icon
  /// adrift in the middle reads as a mistake.
  final Widget? placeholder;

  /// Requested image dimensions. Defaults suit small cards; pass a larger
  /// [maxWidth] for full-width art (e.g. the Home hero) so it isn't upscaled.
  final int? maxWidth;
  final int? maxHeight;

  /// How the image is aligned when [BoxFit.cover] crops it. Biasing toward the
  /// top keeps faces/action visible when a wide band crops a 16:9 backdrop.
  final Alignment alignment;

  /// Sampling quality. Bump to medium for art that animates (e.g. the hero's
  /// Ken Burns zoom), where the default low sampling shimmers as it scales.
  final FilterQuality filterQuality;

  const MediaImage({
    super.key,
    required this.item,
    this.landscape = false,
    this.placeholderIcon,
    this.placeholder,
    this.maxWidth,
    this.maxHeight,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
  });

  ({String itemId, String type, String? tag})? _pick() {
    if (landscape) {
      // Episode "Primary" is a landscape still — ideal for Continue Watching.
      // The tag is optional: Jellyfin serves the still by id, so a downloaded
      // episode whose tag we didn't capture still loads it online (a missing
      // image just 404s to the placeholder).
      if (item.isEpisode) {
        return (itemId: item.id, type: 'Primary', tag: item.primaryImageTag);
      }
      if (item.backdropImageTags.isNotEmpty) {
        return (
          itemId: item.id,
          type: 'Backdrop',
          tag: item.backdropImageTags.first
        );
      }
      if (item.primaryImageTag != null) {
        return (itemId: item.id, type: 'Primary', tag: item.primaryImageTag!);
      }
      return null;
    }
    // Portrait / poster. An episode's own Primary is a landscape still, so for
    // a poster use the SERIES poster instead (tag optional — the series
    // Primary is served without one too).
    if (item.isEpisode && item.seriesId != null) {
      return (
        itemId: item.seriesId!,
        type: 'Primary',
        tag: item.seriesPrimaryImageTag
      );
    }
    if (item.primaryImageTag != null) {
      return (itemId: item.id, type: 'Primary', tag: item.primaryImageTag!);
    }
    // Audio tracks often carry only the album's cover.
    if (item.albumPrimaryImageTag != null && item.albumId != null) {
      return (
        itemId: item.albumId!,
        type: 'Primary',
        tag: item.albumPrimaryImageTag!
      );
    }
    return null;
  }

  /// The relative path of a locally cached copy of this art, when the item is
  /// downloaded (poster / backdrop / episode still). Consulted offline and as a
  /// fallback when the network image fails.
  String? _localRel() {
    if (landscape) {
      if (item.isEpisode) return 'episodes/${item.id}.jpg';
      return 'backdrops/${item.id}.jpg';
    }
    // A track's cover is its album art, cached under the album id.
    if ((item.type == 'Audio' || item.type == 'MusicVideo') &&
        item.albumId != null) {
      return 'posters/${item.albumId}.jpg';
    }
    final key =
        (item.isEpisode && item.seriesId != null) ? item.seriesId! : item.id;
    return 'posters/$key.jpg';
  }

  // Artwork is decorative: the card or header it sits in carries the title,
  // so the image itself is kept out of the screen-reader order (otherwise it
  // reads as "unlabeled image" before every title).
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ExcludeSemantics(child: _image(context, ref));

  Widget _image(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final client = ref.watch(jellyfinClientProvider);
    final headers = ref.watch(imageHeadersProvider);
    final cache = ref.watch(downloadImageCacheProvider);
    final rel = _localRel();
    final File? local = rel == null ? null : cache?.file(rel);

    Widget fileOrPlaceholder(BuildContext context) => local != null
        ? Image.file(
            local,
            fit: BoxFit.cover,
            alignment: alignment,
            filterQuality: filterQuality,
            errorBuilder: (context, _, _) => _placeholder(context),
          )
        : _placeholder(context);

    final pick = _pick();
    // Offline (or no server-side image known): use the downloaded copy if we
    // cached one, else the placeholder.
    if (session == null || pick == null) return fileOrPlaceholder(context);

    final url = client.imageUrl(
      baseUrl: session.baseUrl,
      itemId: pick.itemId,
      type: pick.type,
      tag: pick.tag,
      maxWidth: maxWidth,
      maxHeight: maxWidth == null ? (maxHeight ?? 480) : maxHeight,
    );

    return CachedImage(
      url: url,
      fit: BoxFit.cover,
      alignment: alignment,
      headers: headers,
      filterQuality: filterQuality,
      errorBuilder: fileOrPlaceholder,
    );
  }

  Widget _placeholder(BuildContext context) {
    if (placeholder != null) return placeholder!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(placeholderIcon ?? placeholderIconFor(item),
          color: scheme.onSurfaceVariant, size: 32),
    );
  }
}

/// The placeholder icon for an item with no picture, by what it is.
IconData placeholderIconFor(BaseItemDto item) => switch (item.type) {
      'Person' => Icons.person_rounded,
      'MusicArtist' => Icons.mic_rounded,
      'MusicAlbum' => Icons.album_rounded,
      'Audio' => Icons.music_note_rounded,
      'Series' || 'Season' || 'Episode' => Icons.tv_rounded,
      'Playlist' => Icons.playlist_play_rounded,
      'BoxSet' => Icons.video_library_rounded,
      _ => Icons.movie_rounded,
    };
