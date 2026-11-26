import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/error_text.dart';
import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../services/tv_mode.dart';
import '../state/arr_providers.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_pane.dart';
import '../widgets/arr_skeletons.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/context_menu.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/tv_focus.dart';

/// What's coming up, and what just came out: the days one under another
/// (Agenda), or on a window wide enough for seven columns, a month's grid.
class ArrCalendarTab extends ConsumerStatefulWidget {
  const ArrCalendarTab({super.key});

  /// A month's grid needs seven columns a title can be read in. The lists
  /// keep more than this beside the pane, so opening a title never turns
  /// the month back into an agenda.
  static const gridMinWidth = 600.0;

  @override
  ConsumerState<ArrCalendarTab> createState() => _ArrCalendarTabState();
}

class _ArrCalendarTabState extends ConsumerState<ArrCalendarTab> {
  /// The day the Calendar was last drawn for. When it turns, "today", the
  /// days on show, and what's out and what isn't are drawn again.
  late DateTime _today = _dayOf(arrCalendarNow());
  Timer? _midnight;
  late final AppLifecycleListener _resumed;

  @override
  void initState() {
    super.initState();
    _arm();
    // A sleeping device's timers run late: look again when the app is back.
    _resumed = AppLifecycleListener(onResume: _arm);
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _resumed.dispose();
    super.dispose();
  }

  void _arm() {
    _midnight?.cancel();
    final now = arrCalendarNow();
    final today = _dayOf(now);
    if (today != _today) setState(() => _today = today);
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), _arm);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final picked = ref.watch(arrCalendarViewProvider);
    final unmonitored = ref.watch(arrCalendarUnmonitoredProvider);
    return LayoutBuilder(
      builder: (_, box) {
        // A remote steps through a list far more easily than a grid.
        final canGrid =
            !isTvDevice && box.maxWidth >= ArrCalendarTab.gridMinWidth;
        final view = !canGrid
            ? ArrCalendarView.agenda
            : picked ?? ArrCalendarView.month;
        final row = Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (canGrid)
                ArrSwitch<ArrCalendarView>(
                  options: [
                    (ArrCalendarView.agenda, l.arrAgenda),
                    (ArrCalendarView.month, l.arrMonth),
                  ],
                  value: view,
                  onChanged: ref.read(arrCalendarViewProvider.notifier).set,
                )
              else
                const SizedBox.shrink(),
              // Monitored only by default, as in the apps; unmonitored ones
              // then show greyed. On a small phone with large text its name
              // is cut short rather than run off the edge.
              Flexible(
                child: FilterChip(
                  label: Text(
                    l.arrShowUnmonitored,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: unmonitored,
                  onSelected: ref
                      .read(arrCalendarUnmonitoredProvider.notifier)
                      .set,
                ),
              ),
            ],
          ),
        );
        // A TV opens the Calendar on its first day, not on the switch.
        final bar = TvChrome(child: row);
        // The tab itself outlives the month's cells (a narrower window
        // swaps them for the agenda): what a cell opens over the Calendar
        // acts from here.
        return view == ArrCalendarView.month
            ? _Month(bar: bar, host: context)
            : _Agenda(bar: bar);
      },
    );
  }
}

/// The time, as the Calendar reads it. Tests set the clock.
@visibleForTesting
DateTime Function() arrCalendarNow = DateTime.now;

/// The day a week starts on where the device is set up for, 0 for Sunday.
/// The app speaks English everywhere, and that language's own answer
/// (Sunday) is wrong for most of the world: the region decides, as in the
/// Unicode CLDR's week data, where Monday is the rule and these the
/// exceptions.
int arrFirstWeekday(BuildContext context) {
  final region = WidgetsBinding.instance.platformDispatcher.locale.countryCode
      ?.toUpperCase();
  if (region == null || region.isEmpty) {
    return MaterialLocalizations.of(context).firstDayOfWeekIndex;
  }
  if (_sundayFirst.contains(region)) return 0;
  if (_saturdayFirst.contains(region)) return 6;
  return region == 'MV' ? 5 : 1;
}

const _sundayFirst = {
  'AG', 'AS', 'BD', 'BR', 'BS', 'BT', 'BW', 'BZ', 'CA', 'CO', 'DM', 'DO',
  'ET', 'GT', 'GU', 'HK', 'HN', 'ID', 'IL', 'IN', 'JM', 'JP', 'KE', 'KH',
  'KR', 'LA', 'MH', 'MM', 'MO', 'MT', 'MX', 'MZ', 'NI', 'NP', 'PA', 'PE',
  'PH', 'PK', 'PR', 'PT', 'PY', 'SA', 'SG', 'SV', 'TH', 'TT', 'TW', 'UM',
  'US', 'VE', 'VI', 'WS', 'YE', 'ZA', 'ZW',
};

const _saturdayFirst = {
  'AF', 'BH', 'DJ', 'DZ', 'EG', 'IQ', 'IR', 'JO', 'KW', 'LY', 'OM', 'QA',
  'SD', 'SY',
};

/// How much bigger than usual the device draws text: the month's cells grow
/// with it, so a line of a day is never cut through.
double _cellScale(BuildContext context) =>
    math.max(1.0, MediaQuery.textScalerOf(context).scale(12) / 12);

/// Where a release stands, and the color that says so across the section.
(String, Color) _standing(
  AppLocalizations l,
  ColorScheme scheme,
  ArrCalendarEntry e,
) => e.hasFile
    ? (l.arrDownloaded, arrDownloadedColor)
    : !e.monitored
    ? (l.arrUnmonitored, scheme.outline)
    : !e.date.isAfter(arrCalendarNow())
    ? (l.arrMissing, arrMissingColor)
    : e.kind == ArrKind.sonarr
    ? (l.arrUnaired, arrUnreleasedColor)
    : (l.arrNotReleased, arrUnreleasedColor);

/// The line under a release's title: the episode, the album, or which of a
/// movie's releases this is.
String _about(AppLocalizations l, ArrCalendarEntry e) =>
    e.kind == ArrKind.lidarr
    ? e.albumTitle ?? ''
    : e.kind == ArrKind.sonarr
    ? [
        e.episodeCode,
        e.episodeTitle,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' · ')
    : switch (e.release) {
        ArrRelease.cinemas => l.arrInCinemas,
        ArrRelease.digital => l.arrDigitalRelease,
        ArrRelease.physical => l.arrPhysicalRelease,
        null => '',
      };

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

Map<DateTime, List<ArrCalendarEntry>> _byDay(List<ArrCalendarEntry> items) {
  final out = <DateTime, List<ArrCalendarEntry>>{};
  for (final e in items) {
    (out[_dayOf(e.date)] ??= []).add(e);
  }
  return out;
}

String _dayLabel(BuildContext context, AppLocalizations l, DateTime d) {
  final today = _dayOf(arrCalendarNow());
  if (d == today) return l.arrToday;
  if (d == DateTime(today.year, today.month, today.day + 1)) {
    return l.arrTomorrow;
  }
  if (d == DateTime(today.year, today.month, today.day - 1)) {
    return l.arrYesterday;
  }
  return DateFormat.MMMEd(Localizations.localeOf(context).toString()).format(d);
}

/// Where something shown over the Calendar acts from: the Calendar itself
/// ([pane]) while it's there, so a title opens in the pane beside it, and
/// otherwise wherever it was pressed.
BuildContext _hostOf(BuildContext context, BuildContext? pane) =>
    pane != null && pane.mounted ? pane : context;

/// What a release offers on a right-click or a long press. [pane] is where
/// its title opens: the Calendar itself, for a row shown in a dialog over
/// it, which [before] then closes. [details] is what a pointer reads in the
/// release's tooltip, for a finger's menu to say.
void _entryMenu(
  BuildContext context,
  WidgetRef ref,
  Offset at,
  ArrCalendarEntry e, {
  BuildContext? pane,
  VoidCallback? before,
  String? details,
}) {
  final l = AppLocalizations.of(context);
  final id = e.titleId;
  final client = arrClient(ref, e.kind);
  final episode = e.episodeId;
  final album = e.albumId;
  // What the menu was opened on may be gone by the time a line is picked
  // (the window resized, the month redrawn): each acts from what's there
  // then, or not at all.
  void act(void Function(BuildContext host) run) {
    final host = _hostOf(context, pane);
    if (!host.mounted) return;
    before?.call();
    run(host);
  }

  showContextMenu(
    context,
    at: at,
    title: e.title,
    subtitle: details,
    actions: [
      if (id != null)
        ContextMenuAction(
          icon: Icons.info_outline_rounded,
          label: l.arrOpenTitle,
          onTap: () => act((host) => arrOpenTitle(host, e.kind, id)),
        ),
      if (id != null &&
          ArrPaneScope.read(_hostOf(context, pane))?.open != null)
        ContextMenuAction(
          icon: Icons.open_in_full_rounded,
          label: l.arrOpenFullPage,
          onTap: () => act((host) => arrOpenTitlePage(host, e.kind, id)),
        ),
      if (client is SonarrClient && episode != null)
        ContextMenuAction(
          icon: Icons.search_rounded,
          label: l.arrSearchEpisode,
          onTap: () => act(
            (host) => arrRun(
              host,
              () => client.searchEpisodes([episode]),
              done: l.arrSearchStarted(client.kind.appName),
            ),
          ),
        ),
      if (client is LidarrClient && album != null)
        ContextMenuAction(
          icon: Icons.search_rounded,
          label: l.arrSearchAlbum,
          onTap: () => act(
            (host) => arrRun(
              host,
              () => client.searchAlbums([album]),
              done: l.arrSearchStarted(client.kind.appName),
            ),
          ),
        ),
      if (client is RadarrClient && id != null)
        ContextMenuAction(
          icon: Icons.search_rounded,
          label: l.arrSearchMovie,
          onTap: () => act(
            (host) => arrRun(
              host,
              () => client.searchMovie(id),
              done: l.arrSearchStarted(client.kind.appName),
            ),
          ),
        ),
    ],
  );
}

// ------------------------------------------------------------------ Agenda

class _Agenda extends ConsumerWidget {
  final Widget bar;
  const _Agenda({required this.bar});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final days = arrCalendarWindow(arrCalendarNow());
    final async = ref.watch(arrCalendarProvider(days));
    final top = ArrListColumn(child: bar);
    // Show Unmonitored reloads it: keep showing the list meanwhile rather
    // than blanking the tab.
    return async.when(
      skipLoadingOnReload: true,
      loading: () => Column(
        children: [
          top,
          const Expanded(child: ArrRowsSkeleton(heading: true)),
        ],
      ),
      error: (e, _) => Column(
        children: [
          top,
          Expanded(
            child: ErrorView(
              message: errorText(e),
              onRetry: () => ref.invalidate(arrCalendarProvider),
            ),
          ),
        ],
      ),
      data: (merged) {
        final byDay = _byDay(merged.items);
        return Column(
          children: [
            top,
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(arrCalendarProvider(days).future),
                child: ArrListView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: ArrErrorBanner(errors: merged.errors),
                    ),
                    if (byDay.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: true,
                        child: EmptyState(
                          icon: Icons.event_available_rounded,
                          title: l.arrCalendarEmpty,
                        ),
                      )
                    else
                      for (final day in byDay.entries) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                            child: Text(
                              _dayLabel(context, l, day.key),
                              style: arrSectionStyle(Theme.of(context)),
                            ),
                          ),
                        ),
                        SliverList.builder(
                          itemCount: day.value.length,
                          itemBuilder: (context, i) =>
                              _CalendarRow(entry: day.value[i]),
                        ),
                      ],
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CalendarRow extends ConsumerWidget {
  final ArrCalendarEntry entry;

  /// Where the title opens, for a row shown somewhere else (a dialog over
  /// the Calendar); [before] runs first, to close that.
  final BuildContext? pane;
  final VoidCallback? before;

  const _CalendarRow({required this.entry, this.pane, this.before});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final client = arrWatchClient(ref, entry.kind);
    final (status, color) = _standing(l, scheme, entry);
    final subtitle = _about(l, entry);
    return ArrRowInk(
      kind: entry.kind,
      titleId: entry.titleId,
      onTap: entry.titleId == null
          ? null
          : () {
              final host = _hostOf(context, pane);
              before?.call();
              arrOpenTitle(host, entry.kind, entry.titleId);
            },
      onMenu: (at) =>
          _entryMenu(context, ref, at, entry, pane: pane, before: before),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 46,
                height: 69,
                child: ArrArt(
                  client: client,
                  images: entry.images,
                  width: 185,
                  placeholderIcon: arrKindIcon(entry.kind),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ArrChip(label: status, color: color),
                      if (entry.finale)
                        ArrChip(label: l.arrFinale, color: arrQueuedColor),
                    ],
                  ),
                ],
              ),
            ),
            if (entry.kind == ArrKind.sonarr) ...[
              const SizedBox(width: 10),
              Text(
                arrTime(context, entry.date),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- Month

class _Month extends ConsumerWidget {
  final Widget bar;

  /// The Calendar tab, which a day's dialog is shown from and acts in.
  final BuildContext host;
  const _Month({required this.bar, required this.host});

  /// A week is never squeezed under this: room for the day's number, a
  /// release, and the line saying there are more.
  static const _minWeek = 96.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final now = arrCalendarNow();
    final month =
        ref.watch(arrCalendarMonthProvider) ?? DateTime(now.year, now.month);
    final grid = arrMonthGrid(month, arrFirstWeekday(context));
    final scale = _cellScale(context);
    DateTime cell(int n) =>
        DateTime(grid.start.year, grid.start.month, grid.start.day + n);
    final days = (start: grid.start, end: cell(grid.weeks * 7));
    final async = ref.watch(arrCalendarProvider(days));
    final merged = async.value;
    final byDay = _byDay(merged?.items ?? const []);
    final turn = ref.read(arrCalendarMonthProvider.notifier).set;
    final thisMonth = month.year == now.year && month.month == now.month;

    final head = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              DateFormat.yMMMM(locale).format(month),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (!thisMonth)
            TextButton(onPressed: () => turn(null), child: Text(l.arrToday)),
          IconButton(
            tooltip: l.arrPreviousMonth,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => turn(DateTime(month.year, month.month - 1)),
          ),
          IconButton(
            tooltip: l.arrNextMonth,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => turn(DateTime(month.year, month.month + 1)),
          ),
        ],
      ),
    );

    final line = BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6));
    final weekdays = DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: line)),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                child: Text(
                  DateFormat.E(locale).format(cell(i)),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final Widget body;
    // A reload that failed says so, as the agenda does, rather than leave
    // the last answer up as if it were this one.
    if (async.hasError && !async.isLoading) {
      body = ErrorView(
        message: errorText(async.error!),
        onRetry: () => ref.invalidate(arrCalendarProvider),
      );
    } else {
      body = LayoutBuilder(
        builder: (context, box) {
          final weekHeight = math.max(
            _minWeek * scale,
            (box.maxHeight / grid.weeks).floorToDouble(),
          );
          final today = _dayOf(now);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(arrCalendarProvider(days).future),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  for (var w = 0; w < grid.weeks; w++)
                    SizedBox(
                      height: weekHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var d = 0; d < 7; d++)
                            Expanded(
                              child: _DayCell(
                                day: cell(w * 7 + d),
                                inMonth: cell(w * 7 + d).month == month.month,
                                today: cell(w * 7 + d) == today,
                                entries: byDay[cell(w * 7 + d)] ?? const [],
                                host: host,
                                height: weekHeight,
                                scale: scale,
                                // No line down the window's own edge.
                                line: line,
                                last: d == 6,
                                // Room for an episode's number beside the
                                // show's name, not instead of it.
                                roomy: box.maxWidth / 7 >= 150,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        if (merged != null) ArrErrorBanner(errors: merged.errors),
        head,
        // The grid stays up while a month is on its way, empty at first.
        SizedBox(
          height: 2,
          child: async.isLoading
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
        weekdays,
        Expanded(child: body),
      ],
    );
  }
}

/// One day of the month's grid: its number, then as many of its releases as
/// fit, then how many more there are.
class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final bool today;
  final List<ArrCalendarEntry> entries;
  final BuildContext host;
  final double height;

  /// How much bigger than usual text is drawn: the lines grow with it.
  final double scale;
  final BorderSide line;
  final bool last;
  final bool roomy;

  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.entries,
    required this.host,
    required this.height,
    required this.scale,
    required this.line,
    required this.last,
    required this.roomy,
  });

  static const _numberHeight = 30.0;
  static const _entryHeight = 22.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final numberHeight = _numberHeight * scale;
    final entryHeight = _entryHeight * scale;
    final lines = math.max(
      1,
      ((height - numberHeight - 4) / entryHeight).floor(),
    );
    // The last line says how many more there are when they don't all fit.
    final shown = entries.length <= lines ? entries.length : lines - 1;
    final more = entries.length - shown;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: inMonth
            ? null
            : scheme.surfaceContainerHighest.withValues(alpha: 0.28),
        border: Border(
          bottom: line,
          right: last ? BorderSide.none : line,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: numberHeight,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  constraints: BoxConstraints(minWidth: 24 * scale),
                  height: 24 * scale,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: today
                      ? BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(12 * scale),
                        )
                      : null,
                  // As wide as its number, not the day: today's mark is a
                  // dot round the date.
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      '${day.day}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                        color: today
                            ? scheme.onPrimary
                            : inMonth
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            for (final e in entries.take(shown))
              _MonthEntry(
                entry: e,
                roomy: roomy,
                dim: !inMonth,
                height: entryHeight - 2,
              ),
            if (more > 0)
              SizedBox(
                height: entryHeight - 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _showDay(host, day, entries),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        l.arrMoreCount(more),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A day's releases in full, for a day with more than its cell shows.
/// [host] is the Calendar tab: the cell that was pressed may be gone before
/// a row here is.
void _showDay(BuildContext host, DateTime day, List<ArrCalendarEntry> entries) {
  if (!host.mounted) return;
  showDialog<void>(
    context: host,
    builder: (dialog) {
      final l = AppLocalizations.of(dialog);
      return AlertDialog(
        title: Text(_dayLabel(dialog, l, day)),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: SizedBox(
          width: 440,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in entries)
                // The dialog is drawn outside the Calendar, so a row's title
                // opens from the Calendar itself: in the pane when there is
                // one.
                _CalendarRow(
                  entry: e,
                  pane: host,
                  before: () => Navigator.pop(dialog),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(l.commonClose),
          ),
        ],
      );
    },
  );
}

/// A release on its day: one line, in the color of where it stands.
class _MonthEntry extends ConsumerWidget {
  final ArrCalendarEntry entry;
  final bool roomy;
  final bool dim;
  final double height;
  const _MonthEntry({
    required this.entry,
    required this.roomy,
    required this.dim,
    required this.height,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (status, color) = _standing(l, scheme, entry);
    final about = _about(l, entry);
    final id = entry.titleId;
    final open = ArrPaneScope.shows(context, entry.kind, id);
    final quiet = dim || (!entry.monitored && !entry.hasFile);
    final text = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: quiet ? scheme.onSurfaceVariant : scheme.onSurface,
    );
    // What one line has no room for: under a pointer, or heading the menu
    // a long press opens.
    final details = [
      if (about.isNotEmpty) about,
      [
        if (entry.kind == ArrKind.sonarr) arrTime(context, entry.date),
        status,
        if (entry.finale) l.arrFinale,
      ].join(' · '),
    ];
    void menu(Offset at) =>
        _entryMenu(context, ref, at, entry, details: details.join('\n'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        waitDuration: const Duration(milliseconds: 500),
        message: [entry.title, ...details].join('\n'),
        child: GestureDetector(
          onSecondaryTapUp: (d) => menu(d.globalPosition),
          onLongPressStart: (d) => menu(d.globalPosition),
          child: Material(
            color: color.withValues(alpha: open ? 0.38 : (dim ? 0.1 : 0.18)),
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: id == null
                  ? null
                  : () => arrOpenTitle(context, entry.kind, id),
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    start: BorderSide(color: color, width: 3),
                  ),
                ),
                padding: const EdgeInsetsDirectional.only(start: 5, end: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: text,
                      ),
                    ),
                    if (roomy && (entry.episodeCode?.isNotEmpty ?? false))
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 6),
                        child: Text(
                          entry.episodeCode!,
                          maxLines: 1,
                          softWrap: false,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
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
