import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/download_clients.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/download_client.dart';
import '../state/download_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_queue_poll.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/context_menu.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_keyboard.dart';

/// Rows of a list, each a sliver.
List<Widget> _boxes(List<Widget> rows) => [
  for (final r in rows) SliverToBoxAdapter(child: r),
];

/// What the page shows: the clients' lists, or SABnzbd's history.
enum DownloadClientsView { downloads, history }

/// Which downloads the list keeps to.
enum DownloadFilter { all, active, paused, finished, failed }

bool _matches(DownloadFilter f, DownloadState s) => switch (f) {
  DownloadFilter.all => true,
  DownloadFilter.active => const {
    DownloadState.downloading,
    DownloadState.fetching,
    DownloadState.stalled,
    DownloadState.queued,
    DownloadState.checking,
    DownloadState.moving,
  }.contains(s),
  DownloadFilter.paused => s == DownloadState.paused,
  DownloadFilter.finished =>
    s == DownloadState.seeding || s == DownloadState.done,
  DownloadFilter.failed => s == DownloadState.failed,
};

/// A download's state in a word, and its color.
(String, Color) downloadStanding(
  AppLocalizations l,
  ColorScheme scheme,
  DownloadState s,
) => switch (s) {
  DownloadState.downloading => (l.arrDownloading, arrUnreleasedColor),
  DownloadState.fetching => (l.dlFetching, arrQueuedColor),
  DownloadState.stalled => (l.dlStalled, arrWarningColor),
  DownloadState.queued => (l.arrQueued, arrQueuedColor),
  DownloadState.paused => (l.arrPaused, scheme.outline),
  DownloadState.checking => (l.dlChecking, arrQueuedColor),
  DownloadState.moving => (l.dlMoving, arrQueuedColor),
  DownloadState.seeding => (l.dlSeeding, arrDownloadedColor),
  DownloadState.done => (l.dlDone, arrDownloadedColor),
  DownloadState.failed => (l.arrFailed, arrMissingColor),
};

/// A release name ("Show.S01E01.1080p.WEB") as shown: free to wrap after
/// each dot, as it has no spaces to wrap at.
String downloadShownName(String name) => name.replaceAll('.', '.\u200B');

IconData downloadClientIcon(DownloadClientKind k) => switch (k) {
  DownloadClientKind.qbittorrent => Icons.hub_rounded,
  DownloadClientKind.sabnzbd => Icons.dns_rounded,
};

/// qBittorrent and SABnzbd, in the Manage section: what each is
/// downloading, its speed, pausing and removing, and adding a link.
class DownloadClientsScreen extends ConsumerStatefulWidget {
  const DownloadClientsScreen({super.key});

  @override
  ConsumerState<DownloadClientsScreen> createState() =>
      _DownloadClientsScreenState();
}

class _DownloadClientsScreenState extends ConsumerState<DownloadClientsScreen> {
  DownloadClientsView _view = DownloadClientsView.downloads;
  DownloadFilter _filter = DownloadFilter.all;

  /// What a pause or resume was asked to do, by client and id: shown at once,
  /// as qBittorrent takes a second or two to say so itself. The client's
  /// own word takes over once it agrees, or after a while regardless.
  final Map<String, DownloadState> _asked = {};
  final Map<String, Timer> _askedTimers = {};

  static String _key(DownloadItem i) => '${i.client.name}:${i.id}';

  /// The second asks after an action, one per client.
  final Map<DownloadClientKind, Timer> _again = {};

  @override
  void dispose() {
    for (final t in [..._askedTimers.values, ..._again.values]) {
      t.cancel();
    }
    super.dispose();
  }

  void _ask(DownloadItem i, DownloadState want) {
    final key = _key(i);
    _askedTimers[key]?.cancel();
    _askedTimers[key] = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _asked.remove(key));
      _askedTimers.remove(key);
    });
    setState(() => _asked[key] = want);
  }

  DownloadState _shown(DownloadItem i) {
    final want = _asked[_key(i)];
    if (want == null) return i.state;
    final settled = want == DownloadState.paused ? i.paused : !i.paused;
    if (settled) {
      _asked.remove(_key(i));
      _askedTimers.remove(_key(i))?.cancel();
      return i.state;
    }
    return want;
  }

  void _reload(DownloadClientKind k) =>
      ref.invalidate(downloadClientStateProvider(k));

  /// Asks again now, and once more when the client has had time to act.
  void _reloadSoon(DownloadClientKind k) {
    _reload(k);
    _again[k]?.cancel();
    _again[k] = Timer(const Duration(seconds: 2), () {
      _again.remove(k);
      if (mounted) _reload(k);
    });
  }

  Future<void> _pause(DownloadClient c, DownloadItem i, bool pause) async {
    final l = AppLocalizations.of(context);
    if (await arrRun(
      context,
      () => pause ? c.pause(i) : c.resume(i),
      done: pause ? l.dlPausedName(i.name) : l.dlResumedName(i.name),
    )) {
      if (!mounted) return;
      _ask(i, pause ? DownloadState.paused : DownloadState.queued);
      _reloadSoon(c.kind);
    }
  }

  Future<void> _remove(DownloadClient c, DownloadItem i) async {
    final l = AppLocalizations.of(context);
    final files = await showDialog<bool>(
      context: context,
      builder: (_) => _RemoveDialog(name: i.name, app: c.appName),
    );
    if (files == null || !mounted) return;
    if (await arrRun(
      context,
      () => c.remove(i, deleteFiles: files),
      done: l.dlRemoved(i.name),
    )) {
      _reloadSoon(c.kind);
    }
  }

  Future<void> _all(
    DownloadClient c,
    bool pause,
    List<DownloadItem> items,
  ) async {
    final l = AppLocalizations.of(context);
    // qBittorrent's Resume All starts what was stopped part way, not the
    // finished torrents a ratio limit stopped: those would seed again.
    final stopped = [
      for (final i in items)
        if (i.state == DownloadState.paused) i,
    ];
    if (await arrRun(
      context,
      pause
          ? c.pauseAll
          : c is QbitClient
          ? () => c.resumeItems(stopped)
          : c.resumeAll,
      done: pause ? l.dlPausedAll(c.appName) : l.dlResumedAll(c.appName),
    )) {
      _reloadSoon(c.kind);
    }
  }

  Future<void> _add() async {
    final added = await showDialog<DownloadClientKind>(
      context: context,
      builder: (_) => const _AddDialog(),
    );
    if (added != null && mounted) _reloadSoon(added);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final clients = ref.watch(downloadClientsProvider);
    final sab = ref.watch(sabClientProvider);
    if (clients.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l.dlClients)),
        body: EmptyState(
          icon: Icons.download_rounded,
          title: l.dlNotConnected,
          message: l.dlNotConnectedHint,
          action: FilledButton(
            onPressed: () => context.push('/arr-settings'),
            child: Text(l.browseSetUp),
          ),
        ),
      );
    }
    final view = sab == null ? DownloadClientsView.downloads : _view;
    final loading = [
      for (final c in clients)
        ref.watch(
          downloadClientStateProvider(c.kind).select((a) => a.isLoading),
        ),
    ].any((b) => b);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.dlClients),
        actions: [
          IconButton(
            tooltip: l.dlAdd,
            icon: const Icon(Icons.add_link_rounded),
            onPressed: _add,
          ),
        ],
      ),
      body: ArrPoll(
        every: const Duration(seconds: 3),
        waiting: loading,
        onPoll: () {
          // History asks for its own; the lists behind it wait.
          if (view != DownloadClientsView.downloads) return;
          for (final c in clients) {
            _reload(c.kind);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ArrListColumn(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                // A TV opens the page on its list, not the switches above it.
                child: TvChrome(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (sab != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ArrSwitch<DownloadClientsView>(
                            options: [
                              (DownloadClientsView.downloads, l.dlDownloads),
                              (DownloadClientsView.history, l.arrHistory),
                            ],
                            value: view,
                            onChanged: (v) => setState(() => _view = v),
                          ),
                        ),
                      if (view == DownloadClientsView.downloads)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final (f, name) in [
                              (DownloadFilter.all, l.browseAll),
                              (DownloadFilter.active, l.dlActive),
                              (DownloadFilter.paused, l.arrPaused),
                              (DownloadFilter.finished, l.dlFinished),
                              (DownloadFilter.failed, l.arrFailed),
                            ])
                              ChoiceChip(
                                label: Text(name),
                                selected: _filter == f,
                                onSelected: (_) => setState(() => _filter = f),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: switch (view) {
                DownloadClientsView.downloads => RefreshIndicator(
                  onRefresh: () => Future.wait([
                    for (final c in clients)
                      ref.refresh(downloadClientStateProvider(c.kind).future),
                  ]),
                  child: ArrListView(
                    slivers: [for (final c in clients) ..._client(context, c)],
                  ),
                ),
                DownloadClientsView.history => _History(client: sab!),
              },
            ),
          ],
        ),
      ),
    );
  }

  /// One client: its header, then its downloads.
  List<Widget> _client(BuildContext context, DownloadClient c) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(downloadClientStateProvider(c.kind));
    // The last answer stays while the next is asked for.
    final state = async.asData?.value ?? async.unwrapPrevious().asData?.value;
    if (state == null) {
      return _boxes([
        ArrListColumn(child: _ClientTitle(kind: c.kind)),
        ArrListColumn(
          child: async.hasError
              ? ErrorView(
                  message: async.error.toString(),
                  onRetry: () => _reload(c.kind),
                )
              : const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: AppSpinner()),
                ),
        ),
      ]);
    }
    final items = [
      for (final i in state.items)
        if (_matches(_filter, _shown(i))) i,
    ];
    return _boxes([
      ArrListColumn(
        child: _ClientHeader(
          client: c,
          state: state,
          error: async.hasError ? async.error.toString() : null,
          onAll: (pause) => _all(c, pause, state.items),
          onChanged: () => _reloadSoon(c.kind),
        ),
      ),
      if (items.isEmpty)
        ArrListColumn(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Text(
              state.items.isEmpty ? l.dlEmpty : l.dlEmptyFilter,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      for (final i in items)
        _DownloadRow(
          key: ValueKey(_key(i)),
          item: i,
          state: _shown(i),
          onPause: (pause) => _pause(c, i, pause),
          onRemove: () => _remove(c, i),
          onTop: c is SabClient && _shown(i) != DownloadState.paused
              ? () async {
                  if (await arrRun(
                    context,
                    () => c.moveToTop(i),
                    done: l.dlMovedToTop(i.name),
                  )) {
                    _reloadSoon(c.kind);
                  }
                }
              : null,
        ),
    ]);
  }
}

class _ClientTitle extends StatelessWidget {
  final DownloadClientKind kind;
  const _ClientTitle({required this.kind});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Icon(downloadClientIcon(kind), color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(
            kind.appName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A client's name, speeds and space, and what it does as a whole: pause
/// or resume everything, and its speed limit.
class _ClientHeader extends ConsumerWidget {
  final DownloadClient client;
  final DownloadClientState state;

  /// The last ask failed, though an earlier answer is still shown.
  final String? error;
  final ValueChanged<bool> onAll;
  final VoidCallback onChanged;

  const _ClientHeader({
    required this.client,
    required this.state,
    required this.error,
    required this.onAll,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = state.summary;
    final c = client;
    // SABnzbd pauses its queue; qBittorrent has no such switch, so "all
    // paused" is every torrent stopped.
    // For qBittorrent: nothing running, and something stopped part way
    // (finished torrents stopped at their ratio don't count).
    final allPaused = c is SabClient
        ? s.paused
        : state.items.any((i) => i.state == DownloadState.paused) &&
              state.items.every((i) => i.paused);
    final facts = [
      '↓ ${l.dlSpeed(arrSize(s.downSpeed))}',
      if (c is QbitClient) '↑ ${l.dlSpeed(arrSize(s.upSpeed))}',
      if (s.speedLimit > 0) l.dlLimited(l.dlSpeed(arrSize(s.speedLimit))),
      if (s.freeSpace != null) l.dlFree(arrSize(s.freeSpace!)),
    ].join(' · ');
    final warning = switch (s.connection) {
      'firewalled' => l.dlFirewalled,
      'disconnected' => l.dlDisconnected,
      _ => null,
    };
    Future<void> slow() async {
      if (c is! QbitClient) return;
      if (await arrRun(
        context,
        c.toggleSlowMode,
        done: s.slowMode ? l.dlSlowOff : l.dlSlowOn,
      )) {
        onChanged();
      }
    }

    Future<void> limit(int mb) async {
      if (c is! SabClient) return;
      final bytes = mb * 1024 * 1024;
      if (await arrRun(
        context,
        () => c.setSpeedLimit(bytes),
        done: mb == 0 ? l.dlLimitOff : l.dlLimitSet(l.dlSpeed(arrSize(bytes))),
      )) {
        onChanged();
      }
    }

    final limitMb = (s.speedLimit / (1024 * 1024)).round();
    // The client's own buttons, by name: pressing the header (OK on a TV),
    // a right-click or a long press.
    void menu(Offset at) => showContextMenu(
      context,
      at: at,
      title: c.appName,
      actions: [
        ContextMenuAction(
          icon: allPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          label: allPaused ? l.dlResumeAll : l.dlPauseAll,
          onTap: () => onAll(!allPaused),
        ),
        if (c is QbitClient)
          ContextMenuAction(
            icon: s.slowMode
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            label: l.dlSlowMode,
            onTap: slow,
          ),
        if (c is SabClient)
          for (final mb in sabSpeedLimits)
            ContextMenuAction(
              icon: mb == limitMb
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              label: mb == 0
                  ? l.dlNoLimit
                  : l.dlLimitSet(l.dlSpeed(arrSize(mb * 1024 * 1024))),
              onTap: () => limit(mb),
            ),
      ],
    );
    return Builder(
      builder: (row) => ArrRowInk(
        onTap: () => menu(contextMenuAnchor(row)),
        onMenu: menu,
        child: _header(
          context,
          l,
          theme,
          scheme,
          s,
          allPaused,
          facts,
          warning,
          slow,
          limit,
          limitMb,
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l,
    ThemeData theme,
    ColorScheme scheme,
    DownloadClientSummary s,
    bool allPaused,
    String facts,
    String? warning,
    Future<void> Function() slow,
    Future<void> Function(int) limit,
    int limitMb,
  ) {
    final c = client;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(downloadClientIcon(c.kind), color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.appName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  facts,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (warning != null || allPaused)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (allPaused)
                          ArrChip(label: l.arrPaused, color: scheme.outline),
                        if (warning != null)
                          ArrChip(label: warning, color: arrWarningColor),
                      ],
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: arrMissingColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (c is QbitClient)
            TvRowActions(
              child: IconButton(
                tooltip: l.dlSlowMode,
                isSelected: s.slowMode,
                icon: const Icon(Icons.speed_rounded),
                selectedIcon: const Icon(Icons.slow_motion_video_rounded),
                onPressed: slow,
              ),
            ),
          if (c is SabClient)
            TvRowActions(
              child: PopupMenuButton<int>(
                tooltip: l.dlSpeedLimit,
                icon: Icon(
                  s.speedLimit > 0
                      ? Icons.slow_motion_video_rounded
                      : Icons.speed_rounded,
                  color: s.speedLimit > 0 ? scheme.primary : null,
                ),
                onSelected: limit,
                itemBuilder: (_) => [
                  for (final mb in sabSpeedLimits)
                    CheckedPopupMenuItem(
                      value: mb,
                      checked: limitMb == mb,
                      child: Text(
                        mb == 0
                            ? l.dlNoLimit
                            : l.dlSpeed(arrSize(mb * 1024 * 1024)),
                      ),
                    ),
                ],
              ),
            ),
          TvRowActions(
            child: IconButton(
              tooltip: allPaused ? l.dlResumeAll : l.dlPauseAll,
              icon: Icon(
                allPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              ),
              onPressed: () => onAll(!allPaused),
            ),
          ),
        ],
      ),
    );
  }
}

/// SABnzbd's speed limits on offer, in MB a second (0: none).
const sabSpeedLimits = [0, 1, 2, 5, 10, 25, 50];

class _DownloadRow extends StatelessWidget {
  final DownloadItem item;

  /// Its state as shown: what was just asked for, until the client says so.
  final DownloadState state;
  final ValueChanged<bool> onPause;
  final VoidCallback onRemove;
  final VoidCallback? onTop;

  const _DownloadRow({
    super.key,
    required this.item,
    required this.state,
    required this.onPause,
    required this.onRemove,
    required this.onTop,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final i = item;
    final (standing, color) = downloadStanding(l, scheme, state);
    final paused = state == DownloadState.paused || state == DownloadState.done;
    final moving = !paused && state != DownloadState.failed;
    final meta = [
      if (i.size > 0)
        i.progress < 1
            ? l.dlOfSize(arrSize(i.size - i.left), arrSize(i.size))
            : arrSize(i.size),
      if (moving && (i.downSpeed ?? 0) > 0)
        '↓ ${l.dlSpeed(arrSize(i.downSpeed!))}',
      if (moving && (i.upSpeed ?? 0) > 0) '↑ ${l.dlSpeed(arrSize(i.upSpeed!))}',
      if (moving && i.eta != null) l.arrTimeLeft(arrDuration(i.eta!)),
      if (i.ratio != null && i.progress >= 1)
        l.dlRatio(i.ratio!.toStringAsFixed(2)),
      if (i.seeds != null && i.progress < 1 && moving)
        l.dlPeers(i.seeds!, i.peers ?? 0),
    ].join(' · ');
    final problem = switch (i.problem) {
      'missingFiles' => l.dlMissingFiles,
      'error' => l.dlErrored,
      _ => null,
    };
    // Its buttons, by name: pressing the row (OK on a TV), a right-click or
    // a long press.
    void menu(Offset at) => showContextMenu(
      context,
      at: at,
      title: i.name,
      actions: [
        ContextMenuAction(
          icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          label: paused ? l.dlResume : l.dlPause,
          onTap: () => onPause(!paused),
        ),
        if (onTop != null)
          ContextMenuAction(
            icon: Icons.vertical_align_top_rounded,
            label: l.dlMoveToTop,
            onTap: onTop!,
          ),
        ContextMenuAction(
          icon: Icons.close_rounded,
          label: l.arrRemove,
          color: scheme.error,
          onTap: onRemove,
        ),
      ],
    );
    return ArrListColumn(
      child: Builder(
        builder: (row) => ArrRowInk(
          onTap: () => menu(contextMenuAnchor(row)),
          onMenu: menu,
          child: _row(
            context,
            l,
            theme,
            scheme,
            standing,
            color,
            paused,
            meta,
            problem,
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l,
    ThemeData theme,
    ColorScheme scheme,
    String standing,
    Color color,
    bool paused,
    String meta,
    String? problem,
  ) {
    final i = item;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  downloadShownName(i.name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: i.progress,
                    minHeight: 5,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ArrChip(label: standing, color: color),
                    if (i.category != null)
                      ArrChip(label: i.category!, color: scheme.outline),
                    if (i.priority != null &&
                        i.priority != 'Normal' &&
                        i.priority!.isNotEmpty)
                      ArrChip(label: i.priority!, color: scheme.outline),
                  ],
                ),
                if (meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      meta,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (problem != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      problem,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: arrMissingColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onTop != null)
            TvRowActions(
              child: IconButton(
                tooltip: l.dlMoveToTop,
                icon: const Icon(Icons.vertical_align_top_rounded),
                onPressed: onTop,
              ),
            ),
          TvRowActions(
            child: IconButton(
              tooltip: paused ? l.dlResume : l.dlPause,
              icon: Icon(
                paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              ),
              onPressed: () => onPause(!paused),
            ),
          ),
          TvRowActions(
            child: IconButton(
              tooltip: l.arrRemove,
              icon: const Icon(Icons.close_rounded),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Remove it?", with whether its files go too. Pops with that, or null.
class _RemoveDialog extends StatefulWidget {
  final String name;
  final String app;

  /// Whether its files can go too. SABnzbd deletes the files of a failed
  /// job from its history, never a finished one's.
  final bool files;
  const _RemoveDialog({
    required this.name,
    required this.app,
    this.files = true,
  });

  @override
  State<_RemoveDialog> createState() => _RemoveDialogState();
}

class _RemoveDialogState extends State<_RemoveDialog> {
  bool _files = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.dlRemoveTitle(widget.name)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.dlRemoveBody(widget.app)),
          if (widget.files) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _files,
              onChanged: (v) => setState(() => _files = v ?? false),
              title: Text(l.dlDeleteFiles),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          style: kInlineButtonStyle.merge(
            FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
          ),
          onPressed: () => Navigator.pop(context, _files),
          child: Text(l.arrRemove),
        ),
      ],
    );
  }
}

/// Which client a link goes to by its look: a magnet or a .torrent to
/// qBittorrent, an NZB to SABnzbd; null when it doesn't say.
DownloadClientKind? downloadClientForLink(String link) {
  final s = link.trim().toLowerCase();
  if (s.startsWith('magnet:')) return DownloadClientKind.qbittorrent;
  final path = Uri.tryParse(s)?.path ?? s;
  if (path.endsWith('.torrent')) return DownloadClientKind.qbittorrent;
  if (path.endsWith('.nzb') || s.contains('t=get') || s.contains('/getnzb')) {
    return DownloadClientKind.sabnzbd;
  }
  return null;
}

/// Add Download: a link, the client it goes to, and its category. Pops
/// with the client it was added to.
class _AddDialog extends ConsumerStatefulWidget {
  const _AddDialog();

  @override
  ConsumerState<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends ConsumerState<_AddDialog> {
  final _link = TextEditingController();
  DownloadClientKind? _picked;
  String? _category;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _link.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  DownloadClientKind _kind(List<DownloadClient> clients) {
    final kinds = [for (final c in clients) c.kind];
    final picked = _picked;
    if (picked != null && kinds.contains(picked)) return picked;
    final byLink = downloadClientForLink(_link.text);
    if (byLink != null && kinds.contains(byLink)) return byLink;
    return kinds.first;
  }

  Future<void> _add(DownloadClient c) async {
    final l = AppLocalizations.of(context);
    final link = _link.text.trim();
    if (link.isEmpty) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final ok = await arrRun(
      context,
      () => c.add(link, category: _category),
      done: l.dlAdded(c.appName),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) nav.pop(c.kind);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final clients = ref.watch(downloadClientsProvider);
    if (clients.isEmpty) return const SizedBox.shrink();
    final kind = _kind(clients);
    final client = clients.firstWhere((c) => c.kind == kind);
    final categories =
        ref.watch(downloadCategoriesProvider(kind)).asData?.value ??
        const <String>[];
    final category = categories.contains(_category) ? _category : null;
    return AlertDialog(
      title: Text(l.dlAdd),
      // A short window (a phone on its side) scrolls it rather than cutting
      // it off.
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TvTextField(
                controller: _link,
                keyboardType: TextInputType.url,
                label: l.dlLink,
                helperText: l.dlLinkHint,
                icon: Icons.link_rounded,
                autofocus: true,
                onSubmitted: (_) => _busy ? null : _add(client),
              ),
              if (clients.length > 1) ...[
                const SizedBox(height: 16),
                ArrDropdownField<DownloadClientKind>(
                  label: l.dlClient,
                  value: kind,
                  options: {for (final c in clients) c.kind: c.appName},
                  onChanged: (k) => setState(() {
                    _picked = k;
                    _category = null;
                  }),
                ),
              ],
              if (categories.isNotEmpty) ...[
                const SizedBox(height: 16),
                ArrDropdownField<String>(
                  label: l.dlCategory,
                  value: category ?? '',
                  options: {
                    '': l.dlNoCategory,
                    for (final c in categories) c: c,
                  },
                  onChanged: (c) => setState(
                    () => _category = (c?.isEmpty ?? true) ? null : c,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: _busy || _link.text.trim().isEmpty
              ? null
              : () => _add(client),
          child: _busy ? AppSpinner.inline() : Text(l.dlAddButton),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- History

class _History extends ConsumerStatefulWidget {
  final SabClient client;
  const _History({required this.client});

  @override
  ConsumerState<_History> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<_History> {
  int _limit = 50;
  List<DownloadHistoryItem>? _last;

  Future<void> _retry(DownloadHistoryItem h) async {
    final l = AppLocalizations.of(context);
    if (await arrRun(
      context,
      () => widget.client.retry(h),
      done: l.dlRetried(h.name),
    )) {
      ref.invalidate(sabHistoryProvider);
      ref.invalidate(downloadClientStateProvider(DownloadClientKind.sabnzbd));
    }
  }

  Future<void> _remove(DownloadHistoryItem h) async {
    final l = AppLocalizations.of(context);
    final files = await showDialog<bool>(
      context: context,
      builder: (_) => _RemoveDialog(
        name: h.name,
        app: widget.client.appName,
        files: h.failed,
      ),
    );
    if (files == null || !mounted) return;
    if (await arrRun(
      context,
      () => widget.client.removeHistory(h, deleteFiles: files),
      done: l.dlRemoved(h.name),
    )) {
      ref.invalidate(sabHistoryProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(sabHistoryProvider(_limit));
    final list = async.asData?.value ?? _last;
    if (async.hasValue) _last = async.value;
    if (list == null) {
      return async.hasError
          ? ErrorView(
              message: async.error.toString(),
              onRetry: () => ref.invalidate(sabHistoryProvider),
            )
          : const Center(child: AppSpinner());
    }
    // Finished jobs come in as the queue works: asked again now and then.
    final poll = ArrPoll(
      every: const Duration(seconds: 10),
      waiting: async.isLoading,
      onPoll: () => ref.invalidate(sabHistoryProvider(_limit)),
      child: const SizedBox.shrink(),
    );
    if (list.isEmpty) {
      return Stack(
        children: [
          poll,
          EmptyState(icon: Icons.history_rounded, title: l.arrNoHistory),
        ],
      );
    }
    return Stack(children: [poll, _list(context, list)]);
  }

  Widget _list(BuildContext context, List<DownloadHistoryItem> list) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(sabHistoryProvider(_limit).future),
      child: ArrListView(
        slivers: _boxes([
          for (final h in list)
            ArrListColumn(
              key: ValueKey(h.id),
              child: Builder(
                builder: (row) {
                  // Its buttons, by name: pressing the row (OK on a TV), a
                  // right-click or a long press.
                  void menu(Offset at) => showContextMenu(
                    context,
                    at: at,
                    title: h.name,
                    actions: [
                      if (h.failed && h.canRetry)
                        ContextMenuAction(
                          icon: Icons.replay_rounded,
                          label: l.dlRetry,
                          onTap: () => _retry(h),
                        ),
                      ContextMenuAction(
                        icon: Icons.close_rounded,
                        label: l.arrRemove,
                        color: scheme.error,
                        onTap: () => _remove(h),
                      ),
                    ],
                  );
                  return ArrRowInk(
                    onTap: () => menu(contextMenuAnchor(row)),
                    onMenu: menu,
                    child: _historyRow(context, h),
                  );
                },
              ),
            ),
          if (list.length >= _limit)
            ArrListColumn(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: TextButton(
                    onPressed: () => setState(() => _limit += 50),
                    child: Text(l.arrLoadMore),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _historyRow(BuildContext context, DownloadHistoryItem h) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  downloadShownName(h.name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    () {
                      final (label, color) = h.state == DownloadState.queued
                          // A step SABnzbd names itself.
                          ? (h.status, arrQueuedColor)
                          : downloadStanding(l, scheme, h.state);
                      return ArrChip(label: label, color: color);
                    }(),
                    if (h.category != null)
                      ArrChip(label: h.category!, color: scheme.outline),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    [
                      if (h.size > 0) arrSize(h.size),
                      if (h.completed != null)
                        '${arrDate(context, h.completed!)} ${arrTime(context, h.completed!)}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (h.failed && h.problem != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      h.problem!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: arrMissingColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (h.failed && h.canRetry)
            TvRowActions(
              child: IconButton(
                tooltip: l.dlRetry,
                icon: const Icon(Icons.replay_rounded),
                onPressed: () => _retry(h),
              ),
            ),
          TvRowActions(
            child: IconButton(
              tooltip: l.arrRemove,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _remove(h),
            ),
          ),
        ],
      ),
    );
  }
}
