import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../theme/app_theme.dart';
import 'arr_pane.dart';
import 'cached_image.dart';
import 'context_menu.dart';

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
) {
  if (item.status == 'failed' || item.trackedDownloadState == 'failed') {
    return (l.arrFailed, arrMissingColor);
  }
  switch (item.trackedDownloadState) {
    case 'importBlocked':
      return (l.arrImportBlocked, arrWarningColor);
    case 'importPending':
      return (l.arrWaitingToImport, arrDownloadedColor);
    case 'importing':
      return (l.arrImporting, arrDownloadedColor);
    case 'failedPending':
      return (l.arrFailed, arrMissingColor);
  }
  if (item.trackedDownloadStatus == 'warning' ||
      item.trackedDownloadStatus == 'error' ||
      item.status == 'warning') {
    return (l.arrNeedsAttention, arrWarningColor);
  }
  return switch (item.status) {
    'paused' => (l.arrPaused, scheme.outline),
    'queued' => (l.arrQueued, arrQueuedColor),
    'delay' => (l.arrDelayed, scheme.outline),
    'completed' => (l.arrWaitingToImport, arrDownloadedColor),
    _ => (l.arrDownloading, arrUnreleasedColor),
  };
}

/// A picture of a title from Sonarr or Radarr. Their own copies need the API
/// key; pictures from TMDB or TheTVDB don't, but get it harmlessly anyway.
class ArrArt extends StatelessWidget {
  final ArrClient? client;
  final List<ArrImage> images;
  final String type; // poster, fanart
  final int width;
  final IconData placeholderIcon;
  final Alignment alignment;

  const ArrArt({
    super.key,
    required this.client,
    required this.images,
    this.type = 'poster',
    this.width = 342,
    this.placeholderIcon = Icons.movie_rounded,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final url = client?.imageUrl(images, type, width: width);
    final scheme = Theme.of(context).colorScheme;
    final ph = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(placeholderIcon, color: scheme.onSurfaceVariant),
    );
    if (url == null) return ph;
    final local = !url.startsWith('http') || url.startsWith(client!.baseUrl);
    return CachedImage(
      url: url,
      alignment: alignment,
      cacheWidth: type == 'poster' ? width.toDouble() : null,
      headers: local ? client!.imageHeaders : null,
      errorBuilder: (_) => ph,
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
  /// to where the names don't fit.
  static const _pad = 12.0;
  static const _tightPad = 8.0;

  /// A toolbar's own button beside the switch, with the gap between the two.
  static const _beside = 60.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        theme.segmentedButtonTheme.style?.textStyle?.resolve(const {}) ??
        theme.textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
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
            options.length * (widest + _pad * 2) + _beside > c.maxWidth;
        return SegmentedButton<T>(
          showSelectedIcon: false,
          style: tight
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
                          Text(brief),
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
                  _ => Text(label),
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: _padding,
      child: LayoutBuilder(
        builder: (context, c) {
          final fold = c.maxWidth + _padding.horizontal < foldBelow;
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

/// Section heading on Arr pages.
TextStyle? arrSectionStyle(ThemeData theme) =>
    theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

/// Opens a show or movie: in the pane beside the list where the Manage
/// section has one, otherwise on its own page.
void arrOpenTitle(BuildContext context, ArrKind kind, int? id) {
  if (id == null) return;
  final scope = ArrPaneScope.read(context);
  final open = scope?.open;
  if (open != null) return open(kind, id);
  scope?.onPage?.call();
  arrOpenTitlePage(context, kind, id);
}

/// Opens a show or movie on its own page.
void arrOpenTitlePage(BuildContext context, ArrKind kind, int id) =>
    context.push(kind == ArrKind.sonarr ? '/arr/series/$id' : '/arr/movie/$id');

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
  'downloadFolderImported' || 'seriesFolderImported' || 'movieFolderImported' =>
    (l.arrEventImported, Icons.download_done_rounded, arrDownloadedColor),
  'downloadFailed' => (l.arrEventFailed, Icons.error_rounded, arrMissingColor),
  'episodeFileDeleted' || 'movieFileDeleted' => (
    l.arrEventDeleted,
    Icons.delete_rounded,
    arrMissingColor,
  ),
  'episodeFileRenamed' || 'movieFileRenamed' => (
    l.arrEventRenamed,
    Icons.drive_file_rename_outline_rounded,
    scheme.outline,
  ),
  'downloadIgnored' => (l.arrEventIgnored, Icons.block_rounded, scheme.outline),
  _ => (l.arrEventOther, Icons.history_rounded, scheme.outline),
};
