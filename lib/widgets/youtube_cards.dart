import 'cached_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/youtube_video.dart';
import '../services/youtube_thumbnails.dart';
import '../services/tv_mode.dart';
import '../state/preferences.dart';
import 'context_menu.dart';
import 'tv_focus.dart';
import 'youtube_actions.dart';

/// The channel name as its own tap target, opening that channel's page.
class _ChannelLink extends StatefulWidget {
  final String name;
  final String channelId;
  const _ChannelLink({required this.name, required this.channelId});

  @override
  State<_ChannelLink> createState() => _ChannelLinkState();
}

class _ChannelLinkState extends State<_ChannelLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => context.push('/youtube/channel',
              extra: (channelId: widget.channelId, title: widget.name)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _hover ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        // A quiet hint that the name goes somewhere.
                        decoration:
                            _hover ? TextDecoration.underline : null,
                        decorationColor: scheme.primary,
                      ),
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.chevron_right_rounded,
                  size: 13,
                  color: _hover ? scheme.primary : scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// A YouTube video row: thumbnail with a duration (or LIVE) badge, title, and a
/// metadata line. Shared by search results, channel uploads, and the feed.
class YoutubeVideoRow extends ConsumerStatefulWidget {
  final YoutubeVideo video;

  /// The channel is omitted on channel pages, where it would repeat the header.
  final bool showAuthor;

  /// Smaller thumbnail for narrow columns (the watch page's Up Next rail).
  final bool compact;

  /// Defaults to opening the watch page; the watch page overrides this to
  /// replace itself rather than stack another route.
  final VoidCallback? onTap;

  /// How far through the video the viewer got, 0..1. Draws a resume bar across
  /// the bottom of the thumbnail. Null hides it.
  final double? progress;

  /// Shows the overflow menu with Add to Playlist. Off inside a playlist, where
  /// the useful action is Remove and the screen supplies its own.
  final bool showMenu;

  /// Extra entries for the overflow menu, e.g. Remove from this playlist.
  final List<ContextMenuAction> extraMenuItems;

  /// A one-tap remove action (e.g. History). When set, an X sits inline to the
  /// left of the overflow menu, not overlaid on top of it. [removeTooltip]
  /// labels it.
  final VoidCallback? onRemove;

  /// Defaults to the shared "Remove" label when null.
  final String? removeTooltip;

  const YoutubeVideoRow({
    super.key,
    required this.video,
    this.showAuthor = true,
    this.compact = false,
    this.onTap,
    this.progress,
    this.showMenu = true,
    this.extraMenuItems = const [],
    this.onRemove,
    this.removeTooltip,
  });

  @override
  ConsumerState<YoutubeVideoRow> createState() => _YoutubeVideoRowState();
}

class _YoutubeVideoRowState extends ConsumerState<YoutubeVideoRow> {
  bool _hover = false;

  /// Opens the item menu where the pointer is.
  Future<void> _showContextMenu(Offset at) => showContextMenu(
        context,
        at: at,
        actions: YoutubeActions.menuItems(
          context,
          ref,
          widget.video,
          includePlaylist: widget.showMenu,
          extra: widget.extraMenuItems,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final v = widget.video;
    final thumbQuality = thumbQualityFrom(
        ref.watch(preferencesProvider).asData?.value.youtubeThumbnailQuality);
    // The channel is a separate tap target, so it isn't part of this line.
    final meta = [
      v.viewsLabel(l),
      v.uploadedText(l, DateTime.now()),
    ].where((s) => s.isNotEmpty).join('  ·  ');

    void effectiveTap() {
      final t = widget.onTap;
      if (t != null) {
        t();
      } else {
        context.push('/youtube/watch', extra: (videoId: v.id, title: v.title));
      }
    }

    final row = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        // Opaque, not the default deferToChild: without this only the thumbnail
        // and the text respond, and the padding and the gaps between them are
        // dead. Clicking a row "somewhere near the middle" then does nothing,
        // which reads as the feature being broken.
        behavior: HitTestBehavior.opaque,
        onTap: effectiveTap,
        // NewPipe's long-press-to-enqueue, in the shape desktop expects.
        // Same menu as the overflow button, so the two can't diverge.
        onSecondaryTapUp: (d) => _showContextMenu(d.globalPosition),
        onLongPressStart: (d) => _showContextMenu(d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _hover
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    SizedBox(
                      width: widget.compact ? 140 : 178,
                      height: widget.compact ? 79 : 100,
                      child: CachedImage(
                        url: youtubeThumbnail(v.thumbnailUrl, thumbQuality),
                        errorBuilder: (_) => Container(
                          color: scheme.surfaceContainerHigh,
                          child: const Icon(Icons.smart_display_rounded),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: v.isLive ? Colors.red : Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          v.durationLabel(l),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    // How far through the viewer got, for history rows.
                    if (widget.progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: widget.progress,
                          minHeight: 3,
                          backgroundColor: Colors.black54,
                          valueColor:
                              AlwaysStoppedAnimation(scheme.primary),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (widget.showAuthor && v.channelId != null) ...[
                      const SizedBox(height: 6),
                      _ChannelLink(
                          name: v.author, channelId: v.channelId!),
                    ] else if (widget.showAuthor) ...[
                      const SizedBox(height: 6),
                      Text(v.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.onRemove != null)
                IconButton(
                  tooltip: widget.removeTooltip ?? l.commonRemove,
                  iconSize: 18,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: widget.onRemove,
                  // Reads as neutral, but goes red on hover/press so removal
                  // signals itself.
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      final active = states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.pressed) ||
                          states.contains(WidgetState.focused);
                      return active ? Colors.redAccent : scheme.onSurfaceVariant;
                    }),
                    overlayColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.hovered) ||
                                states.contains(WidgetState.pressed)
                            ? Colors.redAccent.withValues(alpha: 0.12)
                            : null),
                  ),
                ),
              // The inline 3-dot is unreachable on TV (the whole card is one
              // D-pad target), so hide it there; its actions live in the sheet
              // that selecting the card opens instead. Same menu as a
              // right-click/long-press on the row (_showContextMenu), just
              // anchored to the button's own position rather than the pointer.
              if ((widget.showMenu || widget.extraMenuItems.isNotEmpty) &&
                  !isTvDevice)
                Builder(builder: (btnContext) {
                  return IconButton(
                    tooltip: l.commonMore,
                    icon: Icon(Icons.more_vert_rounded,
                        size: 18, color: scheme.onSurfaceVariant),
                    onPressed: () {
                      final box =
                          btnContext.findRenderObject() as RenderBox?;
                      _showContextMenu(box == null
                          ? Offset.zero
                          : box.localToGlobal(box.size.center(Offset.zero)));
                    },
                  );
                }),
            ],
          ),
        ),
      ),
    );
    // On TV a remote needs a visible focus target; the hover-only highlight is
    // invisible to a D-pad. Wrap the row so Select opens it and it rings on focus.
    if (!isTvDevice) return row;
    // On TV, selecting the card opens an action sheet (Play first, then the
    // same actions the 3-dot held) since a remote can't reach the inline menu.
    return TvFocusable(
      onTap: () => YoutubeActions.showTvActionSheet(
        context,
        ref,
        v,
        includePlaylist: widget.showMenu,
        onPlay: effectiveTap,
      ),
      borderRadius: BorderRadius.circular(12),
      scale: 1.02,
      child: row,
    );
  }
}
