import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../services/image_cache.dart';
import 'shimmer.dart';

/// A disk-cached [ImageProvider], for the few places that need a provider (e.g.
/// CircleAvatar.foregroundImage) rather than a widget.
ImageProvider cachedImageProvider(String url) =>
    CachedNetworkImageProvider(url, cacheManager: fathomImageCache);

/// A network image backed by a persistent disk cache, so artwork survives an
/// app restart instead of re-downloading every launch. A drop-in for
/// `Image.network` across the app (Seerr TMDB art, Jellyfin art).
class CachedImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;

  /// Logical width to decode the image at. The bitmap is downsampled to about
  /// this many device pixels instead of the source's full resolution, which
  /// cuts memory and GPU upload for the many small poster/card images. Leave
  /// null for full-bleed art that fills the window.
  final double? cacheWidth;
  final Map<String, String>? headers;

  /// Sampling quality. Low is fine for static cards; use medium for art that
  /// animates (e.g. a Ken Burns zoom), where low sampling shimmers as it scales.
  final FilterQuality filterQuality;

  /// Shown while loading. Defaults to a shimmer.
  final Widget? placeholder;

  /// Shown when the image fails. Defaults to an empty box.
  final Widget Function(BuildContext context)? errorBuilder;

  const CachedImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.cacheWidth,
    this.headers,
    this.filterQuality = FilterQuality.low,
    this.placeholder,
    this.errorBuilder,
  });

  @override
  State<CachedImage> createState() => _CachedImageState();
}

/// Throws a saved picture away so the next look fetches it afresh.
///
/// A download cut short (the app killed, the battery gone, a crash) leaves a
/// file that is empty or half there. The cache still lists it, so the same
/// poster failed to draw at every launch until its entry aged out, three
/// weeks later. A picture that can't be read is not worth keeping.
Future<void> forgetBrokenImage(String url, {BaseCacheManager? cache}) async {
  try {
    await (cache ?? fathomImageCache).removeFile(url);
  } catch (_) {
    // Nothing saved under it, or the store is busy: the retry fetches anyway.
  }
  await CachedNetworkImageProvider(url, cacheManager: cache ?? fathomImageCache)
      .evict();
}

class _CachedImageState extends State<CachedImage> {
  /// Bumped to build the picture again after a broken copy was thrown out.
  int _attempt = 0;

  /// One fresh fetch per picture: one that fails twice is really not there.
  bool _retried = false;

  @override
  void didUpdateWidget(CachedImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _attempt = 0;
      _retried = false;
    }
  }

  void _failed() {
    if (_retried) return;
    _retried = true;
    final url = widget.url;
    forgetBrokenImage(url).then((_) {
      if (mounted && widget.url == url) setState(() => _attempt++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final memW =
        widget.cacheWidth != null ? (widget.cacheWidth! * dpr).round() : null;
    return CachedNetworkImage(
      key: ValueKey(_attempt),
      imageUrl: widget.url,
      cacheManager: fathomImageCache,
      fit: widget.fit,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      filterQuality: widget.filterQuality,
      memCacheWidth: memW,
      httpHeaders: widget.headers,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 120),
      placeholder: (context, _) =>
          widget.placeholder ??
          const ShimmerBox(borderRadius: BorderRadius.zero),
      errorListener: (_) => _failed(),
      errorWidget: (context, _, _) =>
          widget.errorBuilder?.call(context) ?? const SizedBox.shrink(),
    );
  }
}
