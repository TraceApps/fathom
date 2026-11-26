import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../services/tv_mode.dart';
import '../state/preferences.dart';
import 'item_actions.dart';
import 'media_image.dart';
import 'meta_pill.dart';
import 'motion.dart';
import 'tv_focus.dart';

/// Poster artwork with a tactile hover: it scales up, gains an accent ring, and
/// reveals a play button. Fills its parent's constraints (wrap in AspectRatio
/// or Expanded).
class HoverPosterArt extends ConsumerStatefulWidget {
  final BaseItemDto? item;
  final Widget? art; // custom artwork (e.g. a network poster) instead of [item]
  final Widget? overlay; // e.g. status badges, drawn above the art
  final Widget? hoverOverlay; // revealed on hover and clickable (e.g. a button)
  final VoidCallback? onTap;
  final double borderRadius;
  // Overrides the shared-element hero tag. Defaults to `art-<id>`, which the
  // detail header flies to. Rows that can show the SAME item more than once on
  // one screen (Home's Continue Watching vs Next Up) pass a row-scoped tag so
  // the two don't collide into a duplicate-tag error.
  final String? heroTag;

  /// Grabs focus on mount — used on TV so the remote lands on a grid's first
  /// card as soon as it appears (Flutter's autofocus only fires when nothing
  /// else in the scope holds focus, so it never steals focus later).
  final bool autofocus;

  /// Whether the poster exposes the shared item context menu (long-press /
  /// right-click / hover hamburger). Off for non-item art and library-view
  /// cards, which aren't playable/deletable.
  final bool contextActions;

  /// A custom menu opener that replaces the shared item menu (used by the
  /// offline Downloads library, whose actions are Play / Remove download rather
  /// than the server-side ones). When set, the poster shows the menu affordance
  /// and calls this instead of [showItemActionsMenu]. Receives the tap/click's
  /// global position, to anchor a desktop dropdown the same way the shared menu does.
  final void Function(Offset at)? onMenu;

  /// What the menu's "Show Details" runs. Defaults to [onTap]; the Downloads
  /// library sets it to open the detail page while [onTap] plays/drills in.
  final VoidCallback? onOpenDetails;

  /// Adds a "Select" row to this card's menu, which puts the grid into
  /// multi-select with this item already ticked.
  final VoidCallback? onSelect;
  const HoverPosterArt(
      {super.key,
      this.item,
      this.art,
      this.overlay,
      this.hoverOverlay,
      this.onTap,
      this.borderRadius = 12,
      this.heroTag,
      this.autofocus = false,
      this.contextActions = true,
      this.onMenu,
      this.onOpenDetails,
      this.onSelect})
      : assert(item != null || art != null);

  @override
  ConsumerState<HoverPosterArt> createState() => _HoverPosterArtState();
}

class _HoverPosterArtState extends ConsumerState<HoverPosterArt> {
  bool _hover = false;
  // Set when a D-pad/keyboard focus lands on the card (TV remotes). Reuses the
  // exact hover visuals (scale, accent ring, revealed overlay) so a focused
  // card on a TV reads the same as a moused-over one on desktop.
  bool _focused = false;
  // The focus ring/scale is a TV (D-pad) affordance; off TV only hover drives
  // it, so desktop/mobile are unchanged.
  bool get _active => _hover || (_focused && isTvDevice);

  // Context menu is an off-TV affordance (long-press / right-click / hover
  // hamburger); on TV a card opens detail and the menu lives on the detail
  // overflow, so the card's D-pad path is left untouched. Only real media items
  // get it, not library-view tiles or bare artwork.
  bool get _canMenu =>
      !isTvDevice &&
      (widget.onMenu != null ||
          (widget.contextActions &&
              widget.item != null &&
              widget.item!.collectionType == null));

  void _openMenu(Offset at) {
    if (widget.onMenu != null) {
      widget.onMenu!(at);
      return;
    }
    showItemActionsMenu(
      context,
      ref,
      widget.item!,
      at: at,
      fromGrid: true,
      onOpenDetails: widget.onOpenDetails ?? widget.onTap,
      onSelect: widget.onSelect,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;
    // Resume sliver: universal, no setting. Only for real items with progress.
    final progress = item?.progressFraction;
    // Rating badge: opt-in (default off) and only from data already in the list
    // response (community/critic), so a grid never fires per-card lookups.
    final ratingMode = ref.watch(preferencesProvider
        .select((p) => p.asData?.value.cardRating ?? 'off'));
    final ratingBadge =
        item == null ? null : _cardRating(context, item, ratingMode);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _active ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          autofocus: widget.autofocus,
          // Track ACTUAL focus (not Flutter's focus-highlight mode) so the ring +
          // scale show whenever a D-pad remote lands on the card, including the
          // first one focused on a screen.
          onFocusChange: (v) => setState(() => _focused = v),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap?.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
          onTap: widget.onTap,
          onLongPressStart:
              _canMenu ? (d) => _openMenu(d.globalPosition) : null,
          onSecondaryTapDown:
              _canMenu ? (d) => _openMenu(d.globalPosition) : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _active ? 0.5 : 0.35),
                  blurRadius: _active ? 20 : 12,
                  offset: const Offset(0, 6),
                ),
                // A soft accent glow blooms on hover/focus so cards lift.
                if (_active)
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.45),
                    blurRadius: 26,
                    spreadRadius: -2,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.art ??
                      Hero(
                          tag: widget.heroTag ?? 'art-${widget.item!.id}',
                          child: MediaImage(item: widget.item!)),
                  if (widget.overlay != null) widget.overlay!,
                  if (widget.item != null) _WatchedBadge(item: widget.item!),
                  ?ratingBadge,
                  // Resume progress along the bottom, the way Jellyfin web and
                  // Plex show "how far in". Hidden by the hover-request overlay
                  // (Seerr cards pass `art`, not `item`, so they never have one).
                  if (progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(widget.borderRadius),
                          bottomRight: Radius.circular(widget.borderRadius),
                        ),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: Colors.black.withValues(alpha: 0.45),
                          valueColor: AlwaysStoppedAnimation(scheme.primary),
                        ),
                      ),
                    ),
                  // Accent ring + faint lift on hover — a "selectable" cue, not
                  // a play promise (tapping opens the detail page).
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _active ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(widget.borderRadius),
                          border: Border.all(color: scheme.primary, width: 2),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              scheme.primary.withValues(alpha: 0.0),
                              scheme.primary.withValues(alpha: 0.12),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // A hover-revealed control (the Seerr Request button). Above
                  // the ring and NOT wrapped in IgnorePointer, so it's tappable;
                  // it also swallows the card's tap so requesting doesn't also
                  // open the detail page.
                  if (widget.hoverOverlay != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedOpacity(
                        opacity: _active ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: IgnorePointer(
                          ignoring: !_active,
                          child: widget.hoverOverlay!,
                        ),
                      ),
                    ),
                  // Hover hamburger (desktop), bottom-right of the poster. On
                  // touch the same menu is a long-press; on TV it lives on the
                  // detail overflow. A card with a button of its own along
                  // the bottom (Discover's Request) keeps that edge for it;
                  // its menu is still a right-click away.
                  if (_canMenu && widget.hoverOverlay == null)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: AnimatedOpacity(
                        opacity: _hover ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: IgnorePointer(
                          ignoring: !_hover,
                          child: _CardMenuButton(onTap: _openMenu),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// The card rating badge for [mode], or null when off / unavailable. Only uses
/// [BaseItemDto.criticRating] (RT critic %) and [communityRating] (star), both
/// present in the list response, so no per-card network lookups.
Widget? _cardRating(BuildContext context, BaseItemDto item, String mode) {
  if (mode == 'off') return null;
  final critic = item.criticRating; // 0..100
  final community = item.communityRating; // 0..10
  Widget critics() => _RatingBadge(
        label: '${critic!.round()}%',
        background: const Color(0xFFFA320A), // Rotten Tomatoes red
        foreground: Colors.white,
      );
  Widget star() => _RatingBadge(
        icon: Icons.star_rounded,
        iconColor: const Color(0xFFFFC107),
        label: community!.toStringAsFixed(1),
        background: Colors.black.withValues(alpha: 0.62),
        foreground: Colors.white,
      );
  switch (mode) {
    case 'critics':
      return critic != null ? critics() : null;
    case 'community':
      return community != null ? star() : null;
    default: // auto: critic score if present, else the community star
      if (critic != null) return critics();
      if (community != null) return star();
      return null;
  }
}

/// A small top-left rating pill on a poster card.
class _RatingBadge extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String label;
  final Color background;
  final Color foreground;
  const _RatingBadge({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 6,
      left: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: iconColor ?? foreground),
              const SizedBox(width: 3),
            ],
            Text(label,
                style: TextStyle(
                    color: foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// A corner badge showing watched state: a check for fully-played items, or the
/// number of unwatched episodes for a partly-watched series.
class _WatchedBadge extends StatelessWidget {
  final BaseItemDto item;
  const _WatchedBadge({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = item.userData;
    final unplayed = data.unplayedItemCount;
    final showCheck = data.played;
    final showCount = !showCheck && item.isSeries && unplayed > 0;
    if (!showCheck && !showCount) return const SizedBox.shrink();
    return Positioned(
      top: 6,
      right: 6,
      child: Container(
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: showCount
            ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: showCount ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: showCount ? BorderRadius.circular(11) : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.35), blurRadius: 6),
          ],
        ),
        alignment: Alignment.center,
        child: showCheck
            ? Icon(Icons.check_rounded, size: 15, color: scheme.onPrimary)
            : Text('$unplayed',
                style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Portrait poster card (Recently Added, library grids).
/// Small circular hamburger drawn on a poster on hover (desktop). Opens the
/// shared item context menu.
class _CardMenuButton extends StatelessWidget {
  final void Function(Offset at) onTap;
  const _CardMenuButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: Semantics(button: true, label: AppLocalizations.of(context).commonMore, child: InkWell(
        onTap: () {
          final box = context.findRenderObject() as RenderBox?;
          onTap(box == null
              ? Offset.zero
              : box.localToGlobal(box.size.center(Offset.zero)));
        },
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.more_vert_rounded, size: 20, color: Colors.white),
        ),
      )),
    );
  }
}

class PosterCard extends StatelessWidget {
  final BaseItemDto item;
  final VoidCallback? onTap;
  // Row-scoped hero tag; see [HoverPosterArt.heroTag]. Home passes one so an
  // item that appears in several rows doesn't collide on a duplicate tag.
  final String? heroTag;

  /// A locally-cached poster to show instead of the server image (used by the
  /// offline Downloads library so covers render without the server).
  final String? localPosterPath;

  /// Whether the poster exposes the shared item context menu. Off for the
  /// Downloads library, whose reconstructed items aren't full detail items.
  final bool contextActions;

  /// A custom menu opener (replaces the shared item menu). The Downloads library
  /// passes one for its Play / Remove-download actions.
  final void Function(Offset at)? onMenu;

  /// What the menu's "Show Details" runs; defaults to [onTap].
  final VoidCallback? onOpenDetails;
  static const double width = 176;

  const PosterCard({
    super.key,
    required this.item,
    this.onTap,
    this.heroTag,
    this.localPosterPath,
    this.contextActions = true,
    this.onMenu,
    this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // One screen-reader stop that reads "Title, 2019, button", not an
    // unlabeled tap target followed by stray text.
    return _CardSemantics(
      onTap: onTap,
      child: SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flexible so the poster shrinks to fit the row instead of ever
          // overflowing (no caution-tape). Rows are sized to give it full 2:3.
          Flexible(
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: HoverPosterArt(
                item: item,
                onTap: onTap,
                heroTag: heroTag,
                contextActions: contextActions,
                onMenu: onMenu,
                onOpenDetails: onOpenDetails,
                art: localPosterPath == null
                    ? null
                    : Image.file(
                        File(localPosterPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, _, _) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(Icons.movie_rounded,
                              color: theme.colorScheme.onSurfaceVariant,
                              size: 32),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (item.productionYear != null)
            Text('${item.productionYear}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
      ),
    );
  }
}

/// Width-flexible poster tile for grids (library browse, search results).
class PosterTile extends StatelessWidget {
  final BaseItemDto item;
  final VoidCallback? onTap;

  /// Grabs focus on mount (TV): set on a grid's first tile so the remote lands
  /// on content, not the app bar.
  final bool autofocus;

  /// While the grid is selecting, a tap ticks the tile instead of opening it,
  /// and [selected] draws the tick. Null means the grid isn't selecting.
  final bool? selected;

  /// Starts multi-select from this tile's own menu.
  final VoidCallback? onSelect;

  const PosterTile({
    super.key,
    required this.item,
    this.onTap,
    this.autofocus = false,
    this.selected,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = item.isEpisode
        ? (item.seriesName ?? '')
        : (item.productionYear?.toString() ?? '');
    final selecting = selected != null;
    final ticked = selected ?? false;
    return _CardSemantics(
      onTap: onTap,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
            child: Stack(
          children: [
            Positioned.fill(
              child: HoverPosterArt(
                  item: item,
                  onTap: onTap,
                  autofocus: autofocus,
                  onSelect: onSelect,
                  // No per-card menu mid-selection: the bar above the grid is
                  // what acts on things now.
                  contextActions: !selecting),
            ),
            if (selecting)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: ticked
                          ? theme.colorScheme.primary.withValues(alpha: 0.28)
                          : Colors.black.withValues(alpha: 0.28),
                      border: ticked
                          ? Border.all(
                              color: theme.colorScheme.primary, width: 3)
                          : null,
                    ),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          ticked
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: ticked
                              ? theme.colorScheme.primary
                              : Colors.white70,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        )),
        const SizedBox(height: 6),
        Text(item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        if (subtitle.isNotEmpty)
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
      ),
    );
  }
}

/// Landscape card with a progress bar (Continue Watching).
/// A single extra (behind the scenes, a deleted scene, a trailer file): a
/// landscape thumbnail with its kind and runtime, which plays on tap.
class ExtraCard extends StatelessWidget {
  final BaseItemDto item;

  /// The localized ExtraType ("Deleted Scene"), or null for an unknown kind.
  final String? kind;
  final VoidCallback? onTap;
  static const double width = 240;

  const ExtraCard({super.key, required this.item, this.kind, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = item.runTimeTicks == null
        ? null
        : (item.runTimeTicks! / 600000000).round();
    final subtitle = [
      ?kind,
      if (minutes != null && minutes > 0) fmtRuntime(minutes),
    ].join(' · ');
    return _CardSemantics(
      onTap: onTap,
      child: HoverLift(
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: TvFocusable(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: InkWell(
                        onTap: onTap,
                        canRequestFocus: isTvDevice,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MediaImage(
                              item: item,
                              landscape: true,
                              placeholderIcon: Icons.movie_creation_outlined,
                            ),
                            Center(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(6),
                                child: const Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 22),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The landscape card used by Continue Watching and Next Up.
///
/// Carries the same item menu a poster does (long-press, right-click, or the
/// hover hamburger): without it there was nowhere to reach "Remove from
/// Continue Watching", which is the one action this row exists for.
class ContinueCard extends ConsumerStatefulWidget {
  final BaseItemDto item;
  final VoidCallback? onTap;
  /// Sits in the Continue Watching row (not Next Up), so its menu offers
  /// Remove even for a waiting episode.
  final bool inContinueWatching;
  static const double width = 304;

  const ContinueCard({
    super.key,
    required this.item,
    this.onTap,
    this.inContinueWatching = false,
  });

  @override
  ConsumerState<ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends ConsumerState<ContinueCard> {
  bool _hover = false;

  // Off TV only, exactly like the poster cards: on TV the card's D-pad path is
  // left alone and the menu lives on the detail page.
  bool get _canMenu => !isTvDevice;

  void _openMenu(Offset at) => showItemActionsMenu(
        context,
        ref,
        widget.item,
        at: at,
        fromGrid: true,
        onOpenDetails: widget.onTap,
        inContinueWatching: widget.inContinueWatching,
      );

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final onTap = widget.onTap;
    final theme = Theme.of(context);
    final title = item.isEpisode ? (item.seriesName ?? item.name) : item.name;
    final subtitle = item.isEpisode
        ? _episodeLabel(item)
        : (item.productionYear?.toString() ?? '');

    return _CardSemantics(
      onTap: onTap,
      child: MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
      onLongPressStart:
          _canMenu ? (d) => _openMenu(d.globalPosition) : null,
      onSecondaryTapDown:
          _canMenu ? (d) => _openMenu(d.globalPosition) : null,
      child: HoverLift(
      child: SizedBox(
        width: ContinueCard.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Flexible so the artwork shrinks to fit instead of overflowing.
            Flexible(
              child: TvFocusable(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: InkWell(
                onTap: onTap,
                // Off TV the wrapping TvFocusable is a no-op, so this InkWell stays
            // the (keyboard-)focusable target as it was originally.
            canRequestFocus: isTvDevice,
                borderRadius: BorderRadius.circular(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MediaImage(item: item, landscape: true),
                        if (item.progress > 0)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: LinearProgressIndicator(
                            value: item.progress,
                            minHeight: 4,
                            backgroundColor: Colors.black45,
                          ),
                        ),
                      Positioned.fill(
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(8),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                      if (_canMenu)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: AnimatedOpacity(
                            opacity: _hover ? 1 : 0,
                            duration: const Duration(milliseconds: 120),
                            child: IgnorePointer(
                              ignoring: !_hover,
                              child: _CardMenuButton(onTap: _openMenu),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ),
            ),
            const SizedBox(height: 8),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      ),
      ),
      ),
    );
  }

  static String _episodeLabel(BaseItemDto item) {
    final s = item.parentIndexNumber;
    final e = item.indexNumber;
    if (s != null && e != null) return 'S$s:E$e · ${item.name}';
    return item.name;
  }
}

/// Landscape library tile with the library name overlaid.
class LibraryCard extends StatelessWidget {
  final BaseItemDto item;
  final VoidCallback? onTap;
  static const double width = 268;

  const LibraryCard({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CardSemantics(
      onTap: onTap,
      child: HoverLift(
      child: SizedBox(
        width: width,
        child: TvFocusable(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            // Off TV the wrapping TvFocusable is a no-op, so this InkWell stays
            // the (keyboard-)focusable target as it was originally.
            canRequestFocus: isTvDevice,
            borderRadius: BorderRadius.circular(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaImage(
                      item: item,
                      landscape: true,
                      placeholderIcon: Icons.video_library_rounded,
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7)
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ),
      ),
      ),
    );
  }
}

/// Makes a card one screen-reader stop: its tap target, title, and subtitle
/// read together as a single button ("Title, 2019, button") instead of an
/// unlabeled tap target followed by stray pieces of text.
class _CardSemantics extends StatelessWidget {
  const _CardSemantics({required this.onTap, required this.child});
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Semantics(button: onTap != null, child: child),
      );
}
