import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../services/tv_mode.dart';
import '../theme/app_theme.dart';
import 'arr_pane.dart';
import 'cached_image.dart';
import 'context_menu.dart';
import 'tv_focus.dart';
import 'window_frame.dart';

/// The Manage section's icon, in the navigation and on its empty state.
const kManageIcon = Icons.video_settings_rounded;

// The colors Sonarr and Radarr use on their poster bars and chips.
const arrDownloadedColor = Color(0xFF27C24C);
const arrMissingColor = Color(0xFFF05050);
const arrUnreleasedColor = Color(0xFF5D9CEC);
const arrContinuingColor = Color(0xFF5D9CEC);
const arrQueuedColor = Color(0xFF7A43B6);
const arrWarningColor = Color(0xFFFFA500);

Color arrStateColor(ArrState s, ColorScheme scheme) => switch (s) {
  ArrState.downloaded => arrDownloadedColor,
  ArrState.missing => arrMissingColor,
  ArrState.unreleased => arrUnreleasedColor,
  ArrState.continuing => arrContinuingColor,
  ArrState.ended => arrDownloadedColor,
  ArrState.unmonitored => scheme.outline,
};

String arrStateLabel(AppLocalizations l, ArrState s) => switch (s) {
  ArrState.downloaded => l.arrDownloaded,
  ArrState.missing => l.arrMissing,
  ArrState.unreleased => l.arrNotReleased,
  ArrState.continuing => l.arrContinuing,
  ArrState.ended => l.arrEnded,
  ArrState.unmonitored => l.arrUnmonitored,
};

/// "4.3 GB", "812 MB". Sonarr and Radarr count in powers of 1024.
String arrSize(num bytes) {
  const k = 1024;
  if (bytes >= k * k * k * k) {
    return '${(bytes / (k * k * k * k)).toStringAsFixed(2)} TB';
  }
  if (bytes >= k * k * k) {
    return '${(bytes / (k * k * k)).toStringAsFixed(1)} GB';
  }
  if (bytes >= k * k) return '${(bytes / (k * k)).toStringAsFixed(0)} MB';
  if (bytes >= k) return '${(bytes / k).toStringAsFixed(0)} KB';
  return '${bytes.toInt()} B';
}

String arrDate(BuildContext context, DateTime d) =>
    DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(d);

String arrTime(BuildContext context, DateTime d) =>
    DateFormat.jm(Localizations.localeOf(context).toString()).format(d);

/// "2h 14m", "47m".
String arrDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}

/// How a download in the queue is doing, in a word, and the color that
/// says so across the section.
(String, Color) arrQueueStanding(
  AppLocalizations l,
  ColorScheme scheme,
  ArrQueueItem item,
) => switch (item.state) {
  ArrQueueState.failed => (l.arrFailed, arrMissingColor),
  ArrQueueState.importBlocked => (l.arrImportBlocked, arrWarningColor),
  ArrQueueState.importFailed => (l.arrImportFailed, arrWarningColor),
  ArrQueueState.needsAttention => (l.arrNeedsAttention, arrWarningColor),
  ArrQueueState.waitingToImport => (l.arrWaitingToImport, arrDownloadedColor),
  ArrQueueState.importing => (l.arrImporting, arrDownloadedColor),
  ArrQueueState.paused => (l.arrPaused, scheme.outline),
  ArrQueueState.queued => (l.arrQueued, arrQueuedColor),
  ArrQueueState.delayed => (l.arrDelayed, scheme.outline),
  ArrQueueState.downloading => (l.arrDownloading, arrUnreleasedColor),
};

/// A picture of a title from Sonarr or Radarr. Their own copies need the API
/// key; pictures from TMDB or TheTVDB don't, but get it harmlessly anyway.
class ArrArt extends StatelessWidget {
  final ArrClient? client;
  final List<ArrImage> images;
  final String type; // poster, fanart
  final int width;
  final IconData placeholderIcon;
  final Alignment alignment;

  /// How wide it's drawn, where that's far less than the picture itself (a
  /// wide picture behind a card): it's kept in memory at that size, not at
  /// the size it comes in. A poster is kept at [width] without it.
  final double? decodeWidth;

  /// Nothing at all where there's no picture, or while it loads: for a
  /// picture behind something, that a gray box would only spoil.
  final bool bare;

  const ArrArt({
    super.key,
    required this.client,
    required this.images,
    this.type = 'poster',
    this.width = 342,
    this.placeholderIcon = Icons.movie_rounded,
    this.alignment = Alignment.center,
    this.decodeWidth,
    this.bare = false,
  });

  @override
  Widget build(BuildContext context) {
    final url = client?.imageUrl(images, type, width: width);
    final scheme = Theme.of(context).colorScheme;
    final ph = bare
        ? const SizedBox.shrink()
        : Container(
            color: scheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Icon(placeholderIcon, color: scheme.onSurfaceVariant),
          );
    if (url == null) return ph;
    final local = !url.startsWith('http') || url.startsWith(client!.baseUrl);
    return CachedImage(
      url: url,
      alignment: alignment,
      cacheWidth: decodeWidth ?? (type == 'poster' ? width.toDouble() : null),
      headers: local ? client!.imageHeaders : null,
      placeholder: bare ? ph : null,
      errorBuilder: (_) => ph,
    );
  }
}

/// A card with its title's wide picture behind what it says. The picture
/// sits at the card's far end, washed with the card's own color: plain
/// where the words start, showing through more toward the edge, and never
/// so much that they're hard to read. Without a picture, the card alone.
class ArrCardWash extends StatelessWidget {
  /// The picture, filling the space it's given, told how wide to keep it in
  /// memory (see [decodeWidth]). Null: there's none.
  final Widget Function(double decodeWidth)? picture;

  /// The card's own color.
  final Color color;

  /// Less of the picture: for a narrow card, whose words run across it.
  final bool quiet;
  final Widget child;

  const ArrCardWash({
    super.key,
    required this.picture,
    required this.color,
    this.quiet = false,
    required this.child,
  });

  /// How much of the card's width the picture takes, from its far end.
  static const double share = 0.6;

  /// How wide a picture is kept in memory to fill [space]: as wide as it's
  /// drawn there, which is a fraction of what a wide picture comes in at
  /// (TheTVDB's are 1920 across, and a list has one on every card). In
  /// steps, so a window being dragged doesn't read it again at every width.
  static double decodeWidth(Size space) {
    const step = 160.0;
    // Wide pictures are 16:9, and cover the space: a tall one is filled by
    // the picture's height, with its sides cut off.
    final drawn = math.max(space.width, space.height * 16 / 9);
    return math.max(1, (drawn / step).ceil()) * step;
  }

  @override
  Widget build(BuildContext context) {
    final picture = this.picture;
    if (picture == null) return child;
    return Stack(
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerEnd,
              widthFactor: share,
              child: LayoutBuilder(
                builder: (context, box) => picture(decodeWidth(box.biggest)),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                // Plain past the picture's near edge, so it has no edge.
                stops: const [0, 1 - share + 0.04, 0.72, 1],
                colors: [
                  color,
                  color,
                  color.withValues(alpha: quiet ? 0.93 : 0.86),
                  color.withValues(alpha: quiet ? 0.82 : 0.66),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// The thin colored bar across a poster's foot, as on Sonarr's and Radarr's
/// posters: how much of a show is there, or where a movie stands.
class ArrPosterBar extends StatelessWidget {
  final Color color;
  final double fraction; // 0 to 1, how much of the bar is filled
  const ArrPosterBar({super.key, required this.color, this.fraction = 1});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: 5,
        width: double.infinity,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.55),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction.clamp(0, 1).toDouble(),
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}

/// A small rounded status label, tinted by its color.
class ArrChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  /// Over a picture: the tint alone disappears into art of its own color,
  /// so the label gets something dark to stand on.
  final bool onArt;

  const ArrChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.onArt = false,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color.withValues(alpha: 0.16);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onArt
            ? Color.alphaBlend(tint, Colors.black.withValues(alpha: 0.72))
            : tint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          // A long label (a long quality name, a translation) shortens
          // instead of spilling out of a narrow row.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A label and its value, one row of a detail page's facts.
class ArrFact extends StatelessWidget {
  final String label;
  final String value;
  const ArrFact({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// A banner for an app that didn't answer, shown above what the other did.
class ArrErrorBanner extends StatelessWidget {
  final Map<ArrKind, String> errors;
  const ArrErrorBanner({super.key, required this.errors});

  @override
  Widget build(BuildContext context) {
    if (errors.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          for (final e in errors.entries)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: scheme.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      e.value,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The switch between the lists of one tab: Movies and Shows in the Library,
/// Queue, History and Blocklist under Activity, Missing and Cutoff Unmet under
/// Wanted.
class ArrSwitch<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Shorter names for a phone too narrow for the full ones: there an option
  /// with one shows it, and a dot for what the full name said besides (a
  /// count). A screen reader still hears the full name.
  final Map<T, String> short;

  const ArrSwitch({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.short = const {},
  });

  /// The space a segment keeps at each side of its name, and what that's cut
  /// to where the names don't fit: first with the short names, then, on the
  /// narrowest phones, with those set a little smaller as well.
  static const _pad = 12.0;
  static const _tightPad = 8.0;
  static const _snugPad = 5.0;
  static const _snugScale = 0.9;

  /// A toolbar's own button beside the switch, with the gap between the two.
  /// A toolbar with more buttons than one says so: see [_ArrBeside].
  static const _beside = 60.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        theme.segmentedButtonTheme.style?.textStyle?.resolve(const {}) ??
        theme.textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final beside = math.max(
      _beside,
      context.dependOnInheritedWidgetOfExactType<_ArrBeside>()?.width ?? 0,
    );
    double width(String name) {
      final p = TextPainter(
        text: TextSpan(text: name, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = p.width;
      p.dispose();
      return w;
    }

    return LayoutBuilder(
      builder: (context, c) {
        // Every segment is as wide as the widest, so one long name (a count
        // after it) costs that much on each.
        var widest = 0.0;
        for (final (_, label) in options) {
          widest = math.max(widest, width(label));
        }
        final tight =
            options.length * (widest + _pad * 2) + beside > c.maxWidth;
        var widestShort = 0.0;
        if (tight) {
          for (final (v, label) in options) {
            widestShort = math.max(widestShort, width(short[v] ?? label));
          }
        }
        final snug =
            tight &&
            options.length * (widestShort + _tightPad * 2) + beside >
                c.maxWidth;
        // One line always: a name that still doesn't fit fades at its end
        // rather than breaking in two.
        Widget name(String text) => Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
        );
        return SegmentedButton<T>(
          showSelectedIcon: false,
          style: snug
              ? SegmentedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: _snugPad),
                  textStyle: style?.copyWith(
                    fontSize: (style.fontSize ?? 14) * _snugScale,
                  ),
                )
              : tight
              ? SegmentedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: _tightPad),
                )
              : null,
          segments: [
            for (final (v, label) in options)
              ButtonSegment(
                value: v,
                label: switch (tight ? short[v] : null) {
                  final brief? when brief != label => Semantics(
                    label: label,
                    child: ExcludeSemantics(
                      // Above the name's last letter, clear of it and of
                      // the switch's rounded end.
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          name(brief),
                          PositionedDirectional(
                            top: -3,
                            end: -1,
                            child: Badge(
                              smallSize: 6,
                              backgroundColor: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _ => name(label),
                },
              ),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        );
      },
    );
  }
}

/// What a phone's toolbar keeps beside its switch: the width of its buttons
/// and the gap before them, for the switch to make room.
class _ArrBeside extends InheritedWidget {
  final double width;
  const _ArrBeside({required this.width, required super.child});

  @override
  bool updateShouldNotify(_ArrBeside old) => old.width != width;
}

/// Something a list's toolbar offers (Select, Manual Import, Clear): a button
/// on a wide window, a line of the More menu on a phone, where the switch
/// beside it leaves no room for a row of buttons.
class ArrTool {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Shown with its name on a wide window, not only its icon.
  final bool labeled;
  final bool danger;
  const ArrTool(
    this.icon,
    this.label,
    this.onTap, {
    this.labeled = false,
    this.danger = false,
  });
}

/// The keyboard's refresh for a page that stands alone, on a desktop
/// window: F5, and Ctrl or Cmd with R. Nothing at all without [onRefresh],
/// anywhere else, and in TV mode (which a desktop can be put in).
class ArrRefreshKeys extends StatelessWidget {
  final VoidCallback? onRefresh;
  final Widget child;
  const ArrRefreshKeys({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final refresh = onRefresh;
    if (refresh == null || !isDesktopWindowFrame || isTvDevice) return child;
    const keyR = LogicalKeyboardKey.keyR;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): refresh,
        const SingleActivator(keyR, control: true): refresh,
        const SingleActivator(keyR, meta: true): refresh,
      },
      // Where the keys are heard from until something on the page has the
      // keyboard. Never a stop for Tab: nothing would show it's there.
      child: Focus(autofocus: true, skipTraversal: true, child: child),
    );
  }
}

/// The row above a list: its switch on the left, what can be done with the
/// list on the right. [actions] always show; [tools] are buttons with room
/// for them and fold under More without, so a phone keeps it to one line.
class ArrToolbar extends StatelessWidget {
  final Widget lead;
  final List<Widget> actions;
  final List<ArrTool> tools;

  const ArrToolbar({
    super.key,
    required this.lead,
    this.actions = const [],
    this.tools = const [],
  });

  /// Below this the tools fold under More: the width of the list the
  /// toolbar is above, its own padding included.
  static const foldBelow = 600.0;

  static const _padding = EdgeInsets.fromLTRB(16, 12, 8, 4);

  // A TV opens a list on its first row, not on the buttons above it.
  @override
  Widget build(BuildContext context) => TvChrome(child: _bar(context));

  Widget _bar(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: _padding,
      child: LayoutBuilder(
        builder: (context, c) {
          final fold = c.maxWidth + _padding.horizontal < foldBelow;
          // Folded, every button is an icon of a known size.
          final buttons = actions.length + (tools.isEmpty ? 0 : 1);
          final lead = fold
              ? _ArrBeside(width: buttons * 48.0 + 12, child: this.lead)
              : this.lead;
          return Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              lead,
              // As tall as a button even with none, so the row doesn't jump
              // between lists.
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!fold)
                      for (final t in tools)
                        t.labeled
                            ? TextButton.icon(
                                style: kInlineButtonStyle,
                                onPressed: t.onTap,
                                icon: Icon(t.icon),
                                label: Text(t.label),
                              )
                            : IconButton(
                                tooltip: t.label,
                                icon: Icon(t.icon),
                                onPressed: t.onTap,
                              ),
                    ...actions,
                    if (fold && tools.isNotEmpty)
                      PopupMenuButton<ArrTool>(
                        tooltip: l.arrMore,
                        icon: const Icon(Icons.more_vert_rounded),
                        onSelected: (t) => t.onTap?.call(),
                        itemBuilder: (_) => [
                          for (final t in tools)
                            PopupMenuItem(
                              value: t,
                              enabled: t.onTap != null,
                              child: Row(
                                children: [
                                  Icon(
                                    t.icon,
                                    size: 20,
                                    color: t.danger ? scheme.error : null,
                                  ),
                                  const SizedBox(width: 14),
                                  Flexible(child: Text(t.label)),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// How wide a list of rows gets on a big window: past this a row's title and
/// its button drift too far apart to read as one line.
const arrListMaxWidth = 960.0;

/// The space each side of a list [width] wide that keeps its rows within
/// [arrListMaxWidth].
double arrListInset(double width, [double maxWidth = arrListMaxWidth]) =>
    width > maxWidth ? (width - maxWidth) / 2 : 0;

/// A scrolling list that keeps a readable width on a wide window: its rows
/// stay in a centered column while the whole width still scrolls.
class ArrListView extends StatelessWidget {
  final List<Widget> slivers;
  final double maxWidth;
  final ScrollPhysics? physics;

  const ArrListView({
    super.key,
    required this.slivers,
    this.maxWidth = arrListMaxWidth,
    this.physics,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final side = arrListInset(c.maxWidth, maxWidth);
      return CustomScrollView(
        physics: physics,
        slivers: [
          for (final s in slivers)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: side),
              sliver: s,
            ),
        ],
      );
    },
  );
}

/// The same column for what sits above or in place of a list (its toolbar
/// while it loads, an error).
class ArrListColumn extends StatelessWidget {
  final Widget child;
  const ArrListColumn({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: arrListMaxWidth),
      // The column's whole width, as a row of the list gets: a toolbar left to
      // its own width would sit in the middle until the list arrived.
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

/// A kind of title as the section names its library: Movies, Shows, Music.
String arrKindName(AppLocalizations l, ArrKind kind) => switch (kind) {
  ArrKind.radarr => l.arrMovies,
  ArrKind.sonarr => l.arrShows,
  ArrKind.lidarr => l.arrMusic,
};

/// What stands for a title of [kind] where it has no picture.
IconData arrKindIcon(ArrKind kind) => switch (kind) {
  ArrKind.sonarr => Icons.live_tv_rounded,
  ArrKind.radarr => Icons.movie_rounded,
  ArrKind.lidarr => Icons.library_music_rounded,
};

/// Section heading on Arr pages.
TextStyle? arrSectionStyle(ThemeData theme) =>
    theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

/// Opens a show, movie or artist: in the pane beside the list where the
/// Manage section has one, otherwise on its own page.
void arrOpenTitle(BuildContext context, ArrKind kind, int? id) {
  if (id == null) return;
  final scope = ArrPaneScope.read(context);
  final open = scope?.open;
  if (open != null) return open(kind, id);
  scope?.onPage?.call();
  arrOpenTitlePage(context, kind, id);
}

/// Opens a show, movie or artist on its own page.
void arrOpenTitlePage(BuildContext context, ArrKind kind, int id) =>
    context.push(switch (kind) {
      ArrKind.sonarr => '/arr/series/$id',
      ArrKind.radarr => '/arr/movie/$id',
      ArrKind.lidarr => '/arr/artist/$id',
    });

/// The first lines of a row's or a poster's menu: open the title, and where
/// that opens it in the pane beside the lists, open its own page as well.
List<ContextMenuAction> arrOpenActions(
  BuildContext context,
  ArrKind kind,
  int? id,
) {
  if (id == null) return const [];
  final l = AppLocalizations.of(context);
  return [
    ContextMenuAction(
      icon: Icons.info_outline_rounded,
      label: l.arrOpenTitle,
      onTap: () => arrOpenTitle(context, kind, id),
    ),
    if (ArrPaneScope.read(context)?.open != null)
      ContextMenuAction(
        icon: Icons.open_in_full_rounded,
        label: l.arrOpenFullPage,
        onTap: () => arrOpenTitlePage(context, kind, id),
      ),
  ];
}

/// A row of one of the section's lists. Under a pointer it lights up as a
/// rounded shape set in from the list's edges, and it stays tinted while
/// the pane beside the list shows its title. [onMenu] opens on a right-click
/// or a long press, where they happened.
class ArrRowInk extends StatelessWidget {
  final ArrKind? kind;
  final int? titleId;
  final VoidCallback? onTap;
  final void Function(Offset at)? onMenu;
  final Widget child;

  const ArrRowInk({
    super.key,
    this.kind,
    this.titleId,
    this.onTap,
    this.onMenu,
    required this.child,
  });

  /// What the row is set in by on each side; its content keeps its place by
  /// taking this off its own side padding.
  static const inset = 6.0;

  @override
  Widget build(BuildContext context) {
    final shown = kind != null && ArrPaneScope.shows(context, kind!, titleId);
    Widget row = Material(
      color: shown
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );
    final menu = onMenu;
    if (menu != null) {
      row = GestureDetector(
        onSecondaryTapUp: (d) => menu(d.globalPosition),
        onLongPressStart: (d) => menu(d.globalPosition),
        child: row,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: inset),
      child: row,
    );
  }
}

/// How a history event reads: its name, icon and color, the way the apps
/// show them.
(String, IconData, Color) arrHistoryEvent(
  AppLocalizations l,
  ColorScheme scheme,
  String eventType,
) => switch (eventType) {
  'grabbed' => (
    l.arrEventGrabbed,
    Icons.cloud_download_rounded,
    arrUnreleasedColor,
  ),
  'downloadFolderImported' ||
  'seriesFolderImported' ||
  'movieFolderImported' ||
  // Lidarr's: one for each track, and one for a whole download.
  'trackFileImported' ||
  'artistFolderImported' ||
  'downloadImported' => (
    l.arrEventImported,
    Icons.download_done_rounded,
    arrDownloadedColor,
  ),
  // Lidarr took some of an album's tracks, not all of them.
  'albumImportIncomplete' => (
    l.arrEventImportIncomplete,
    Icons.rule_rounded,
    arrWarningColor,
  ),
  'downloadFailed' => (l.arrEventFailed, Icons.error_rounded, arrMissingColor),
  'episodeFileDeleted' || 'movieFileDeleted' || 'trackFileDeleted' => (
    l.arrEventDeleted,
    Icons.delete_rounded,
    arrMissingColor,
  ),
  'episodeFileRenamed' || 'movieFileRenamed' || 'trackFileRenamed' => (
    l.arrEventRenamed,
    Icons.drive_file_rename_outline_rounded,
    scheme.outline,
  ),
  'downloadIgnored' => (l.arrEventIgnored, Icons.block_rounded, scheme.outline),
  // Lidarr wrote its tags into a track's file.
  'trackFileRetagged' => (
    l.arrEventRetagged,
    Icons.sell_rounded,
    scheme.outline,
  ),
  _ => (l.arrEventOther, Icons.history_rounded, scheme.outline),
};
