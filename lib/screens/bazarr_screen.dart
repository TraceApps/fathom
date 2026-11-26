import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/error_text.dart';
import '../api/bazarr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../state/arr_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/context_menu.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/tv_focus.dart';

/// Rows of a list, each a sliver.
List<Widget> _boxes(List<Widget> rows) => [
  for (final r in rows) SliverToBoxAdapter(child: r),
];

/// What the Subtitles page shows.
enum BazarrView { wanted, history, providers }

/// A language as a chip says it: "English", "English HI", "English Forced".
String bazarrLanguageLabel(AppLocalizations l, BazarrLanguage lang) => [
  lang.name.isEmpty ? lang.code.toUpperCase() : lang.name,
  if (lang.hi) l.bzHi,
  if (lang.forced) l.bzForced,
].join(' ');

/// The title of an episode or a movie: "Show S01E02 · Title", "Movie".
String bazarrTitle(String title, String? code, String? episodeTitle) => [
  if (code == null) title else '$title $code',
  if (episodeTitle != null && episodeTitle.isNotEmpty) episodeTitle,
].join(' · ');

/// Bazarr, in the Manage section: episodes and movies missing subtitles,
/// with a search (Bazarr picks) or a manual one (every provider's, scored);
/// what it did; and how its providers are doing.
class BazarrScreen extends ConsumerStatefulWidget {
  const BazarrScreen({super.key});

  @override
  ConsumerState<BazarrScreen> createState() => _BazarrScreenState();
}

class _BazarrScreenState extends ConsumerState<BazarrScreen> {
  BazarrView _view = BazarrView.wanted;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final client = ref.watch(bazarrClientProvider);
    if (client == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.bzSubtitles)),
        body: EmptyState(
          icon: Icons.subtitles_rounded,
          title: l.bzNotConnected,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.bzSubtitles)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArrListColumn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              // A TV opens the page on its list, not the switch above it.
              child: TvChrome(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ArrSwitch<BazarrView>(
                      options: [
                        (BazarrView.wanted, l.bzWanted),
                        (BazarrView.history, l.arrHistory),
                        (BazarrView.providers, l.bzProviders),
                      ],
                      value: _view,
                      onChanged: (v) => setState(() => _view = v),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: switch (_view) {
              BazarrView.wanted => _Wanted(client: client),
              BazarrView.history => const _History(),
              BazarrView.providers => _Providers(client: client),
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Wanted

class _Wanted extends ConsumerStatefulWidget {
  final BazarrClient client;
  const _Wanted({required this.client});

  @override
  ConsumerState<_Wanted> createState() => _WantedState();
}

class _WantedState extends ConsumerState<_Wanted> {
  int _length = arrPageSize;

  /// The last list shown: it stays while Load More asks for a longer one.
  ({List<BazarrWanted> items, int total})? _last;

  /// Asked for, not yet done: Bazarr queues searches and downloads.
  final Set<String> _asked = {};
  final List<Timer> _later = [];

  @override
  void dispose() {
    for (final t in _later) {
      t.cancel();
    }
    super.dispose();
  }

  /// Bazarr does it a moment later: the list is asked for again then. By
  /// the last look it's done, found or not: the rows say Searching no more.
  void _soon() {
    for (final s in const [4, 12]) {
      _later.add(
        Timer(Duration(seconds: s), () {
          if (!mounted) return;
          if (s == 12) setState(_asked.clear);
          ref.invalidate(bazarrWantedProvider);
        }),
      );
    }
  }

  Future<void> _search(BazarrWanted w) async {
    final l = AppLocalizations.of(context);
    final title = bazarrTitle(w.title, w.episodeCode, null);
    final languages = w.missing.map((x) => bazarrLanguageLabel(l, x)).join(', ');
    if (await arrRun(
      context,
      () async {
        for (final lang in w.missing) {
          await widget.client.search(w, lang);
        }
      },
      done: l.bzSearching(languages, title),
    )) {
      if (!mounted) return;
      setState(() => _asked.add(w.key));
      _soon();
    }
  }

  Future<void> _manual(BazarrWanted w) async {
    final picked = await showDialog<bool>(
      context: context,
      builder: (_) => _ManualSearch(client: widget.client, wanted: w),
    );
    if (picked == true && mounted) {
      setState(() => _asked.add(w.key));
      _soon();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(bazarrWantedProvider(_length));
    final page = async.asData?.value ?? _last;
    if (async.hasValue) _last = async.value;
    if (page == null) {
      return async.hasError
          ? ErrorView(
              message: errorText(async.error!),
              onRetry: () => ref.invalidate(bazarrWantedProvider),
            )
          : const Center(child: AppSpinner());
    }
    if (page.items.isEmpty) {
      return EmptyState(
        icon: Icons.subtitles_rounded,
        title: l.bzNothingWanted,
        message: l.bzNothingWantedHint,
      );
    }
    final bar = ArrToolbar(
      lead: Text(
        l.bzMissing(page.total),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      tools: [
        ArrTool(Icons.manage_search_rounded, l.bzSearchAll, () async {
          if (await arrRun(
            context,
            widget.client.searchAllWanted,
            done: l.bzSearchingAll,
          )) {
            _soon();
          }
        }, labeled: true),
      ],
    );
    return RefreshIndicator(
      onRefresh: () => ref.refresh(bazarrWantedProvider(_length).future),
      child: ArrListView(
        slivers: _boxes([
          ArrListColumn(child: bar),
          for (final w in page.items)
            _WantedRow(
              key: ValueKey(w.key),
              wanted: w,
              asked: _asked.contains(w.key),
              onSearch: () => _search(w),
              onManual: () => _manual(w),
            ),
          if (page.items.length < page.total)
            ArrListColumn(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: TextButton(
                    onPressed: () => setState(() => _length += arrPageSize),
                    child: Text(l.arrLoadMore),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _WantedRow extends StatelessWidget {
  final BazarrWanted wanted;

  /// A search or download was just asked for.
  final bool asked;
  final VoidCallback onSearch;
  final VoidCallback onManual;

  const _WantedRow({
    super.key,
    required this.wanted,
    required this.asked,
    required this.onSearch,
    required this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final w = wanted;
    // Its buttons, by name: pressing the row (OK on a TV), a right-click or
    // a long press.
    void menu(Offset at) => showContextMenu(
      context,
      at: at,
      title: bazarrTitle(w.title, w.episodeCode, null),
      actions: [
        ContextMenuAction(
          icon: Icons.search_rounded,
          label: l.bzSearch,
          onTap: onSearch,
        ),
        ContextMenuAction(
          icon: Icons.manage_search_rounded,
          label: l.bzManualSearch,
          onTap: onManual,
        ),
      ],
    );
    return ArrListColumn(
      child: Builder(
        builder: (row) => ArrRowInk(
          onTap: () => menu(contextMenuAnchor(row)),
          onMenu: menu,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    w.isEpisode ? Icons.live_tv_rounded : Icons.movie_rounded,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bazarrTitle(w.title, w.episodeCode, w.episodeTitle),
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
                          for (final lang in w.missing)
                            ArrChip(
                              label: bazarrLanguageLabel(l, lang),
                              color: arrMissingColor,
                            ),
                          if (asked)
                            ArrChip(label: l.bzAsked, color: arrQueuedColor),
                        ],
                      ),
                    ],
                  ),
                ),
                TvRowActions(
                  child: IconButton(
                    tooltip: l.bzSearch,
                    icon: const Icon(Icons.search_rounded),
                    onPressed: onSearch,
                  ),
                ),
                TvRowActions(
                  child: IconButton(
                    tooltip: l.bzManualSearch,
                    icon: const Icon(Icons.manage_search_rounded),
                    onPressed: onManual,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Manual Search: every provider's subtitles for one episode or movie, the
/// best first, and Download. Pops true once one is downloading.
class _ManualSearch extends StatefulWidget {
  final BazarrClient client;
  final BazarrWanted wanted;
  const _ManualSearch({required this.client, required this.wanted});

  @override
  State<_ManualSearch> createState() => _ManualSearchState();
}

class _ManualSearchState extends State<_ManualSearch> {
  late Future<List<BazarrRelease>> _results = widget.client.manualSearch(
    widget.wanted,
  );
  String? _busy;

  Future<void> _download(BazarrRelease r) async {
    final l = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = r.subtitle);
    final ok = await arrRun(
      context,
      () => widget.client.download(widget.wanted, r),
      done: l.bzDownloading,
    );
    if (!mounted) return;
    setState(() => _busy = null);
    if (ok) nav.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final w = widget.wanted;
    return AlertDialog(
      title: Text(bazarrTitle(w.title, w.episodeCode, null)),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 640,
        height: 520,
        child: FutureBuilder<List<BazarrRelease>>(
          future: _results,
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorView(
                message: errorText(snap.error!),
                onRetry: () => setState(() {
                  _results = widget.client.manualSearch(widget.wanted);
                }),
              );
            }
            final list = snap.data;
            if (list == null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppSpinner(),
                    const SizedBox(height: 12),
                    Text(l.bzAskingProviders),
                  ],
                ),
              );
            }
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.subtitles_off_rounded,
                title: l.bzNoResults,
              );
            }
            return ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final r = list[i];
                return ListTile(
                  key: ValueKey(r.subtitle),
                  title: Text(
                    r.releaseInfo.isEmpty ? r.provider : r.releaseInfo.first,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ArrChip(
                          label: l.bzScore(r.score),
                          color: r.score >= 80
                              ? arrDownloadedColor
                              : r.score >= 50
                              ? arrWarningColor
                              : arrMissingColor,
                        ),
                        ArrChip(label: r.provider, color: scheme.outline),
                        if (r.hi) ArrChip(label: l.bzHi, color: scheme.outline),
                        if (r.forced)
                          ArrChip(label: l.bzForced, color: scheme.outline),
                        if (r.uploader != null)
                          Text(
                            r.uploader!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  trailing: _busy == r.subtitle
                      ? AppSpinner.inline()
                      : IconButton(
                          tooltip: l.bzDownload,
                          icon: const Icon(Icons.download_rounded),
                          onPressed: _busy == null ? () => _download(r) : null,
                        ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- History

class _History extends ConsumerStatefulWidget {
  const _History();

  @override
  ConsumerState<_History> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<_History> {
  int _length = arrPageSize;
  ({List<BazarrHistoryItem> items, int total})? _last;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final async = ref.watch(bazarrHistoryProvider(_length));
    final page = async.asData?.value ?? _last;
    if (async.hasValue) _last = async.value;
    if (page == null) {
      return async.hasError
          ? ErrorView(
              message: errorText(async.error!),
              onRetry: () => ref.invalidate(bazarrHistoryProvider),
            )
          : const Center(child: AppSpinner());
    }
    final list = page.items;
    if (list.isEmpty) {
      return EmptyState(icon: Icons.history_rounded, title: l.arrNoHistory);
    }
    return RefreshIndicator(
      onRefresh: () => ref.refresh(bazarrHistoryProvider(_length).future),
      child: ArrListView(
        slivers: _boxes([
          for (final h in list)
            ArrListColumn(
              child: TvReadStop(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        switch (h.action) {
                          BazarrAction.deleted => Icons.delete_outline_rounded,
                          BazarrAction.upgraded => Icons.upgrade_rounded,
                          BazarrAction.uploaded => Icons.upload_rounded,
                          BazarrAction.synced => Icons.sync_rounded,
                          BazarrAction.translated => Icons.translate_rounded,
                          BazarrAction.extracted => Icons.unarchive_rounded,
                          _ => Icons.download_done_rounded,
                        },
                        size: 20,
                        color: h.action == BazarrAction.deleted
                            ? arrMissingColor
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bazarrTitle(
                                h.title,
                                h.episodeCode,
                                h.episodeTitle,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              [
                                bazarrActionLabel(l, h),
                                if (h.language != null)
                                  bazarrLanguageLabel(l, h.language!),
                                ?h.provider,
                                ?h.score,
                                if (h.time != null)
                                  '${arrDate(context, h.time!)} ${arrTime(context, h.time!)}',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (list.length < page.total)
            ArrListColumn(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: TextButton(
                    onPressed: () => setState(() => _length += arrPageSize),
                    child: Text(l.arrLoadMore),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// What Bazarr did, in a word; Bazarr's own words for what this doesn't
/// know.
String bazarrActionLabel(AppLocalizations l, BazarrHistoryItem h) =>
    switch (h.action) {
      BazarrAction.deleted => l.bzDeleted,
      BazarrAction.downloaded => l.bzDownloaded,
      BazarrAction.manual => l.bzManualDownloaded,
      BazarrAction.upgraded => l.bzUpgraded,
      BazarrAction.uploaded => l.bzUploaded,
      BazarrAction.synced => l.bzSynced,
      BazarrAction.translated => l.bzTranslated,
      BazarrAction.extracted => l.bzExtracted,
      BazarrAction.other => h.description ?? l.bzDownloaded,
    };

// --------------------------------------------------------------- Providers

class _Providers extends ConsumerWidget {
  final BazarrClient client;
  const _Providers({required this.client});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final async = ref.watch(bazarrProvidersProvider);
    return async.when(
      loading: () => const Center(child: AppSpinner()),
      error: (e, _) => ErrorView(
        message: errorText(e),
        onRetry: () => ref.invalidate(bazarrProvidersProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.subtitles_off_rounded,
            title: l.bzNoProviders,
            message: l.bzNoProvidersHint,
          );
        }
        final bar = ArrToolbar(
          lead: const SizedBox.shrink(),
          tools: [
            ArrTool(Icons.restart_alt_rounded, l.bzResetProviders, () async {
              if (await arrRun(
                context,
                client.resetProviders,
                done: l.bzProvidersReset,
              )) {
                ref.invalidate(bazarrProvidersProvider);
              }
            }, labeled: true),
          ],
        );
        return RefreshIndicator(
          onRefresh: () => ref.refresh(bazarrProvidersProvider.future),
          child: ArrListView(
            slivers: _boxes([
              ArrListColumn(child: bar),
              for (final p in list)
                ArrListColumn(
                  child: TvReadStop(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            p.good
                                ? Icons.check_circle_rounded
                                : Icons.warning_rounded,
                            color: p.good ? arrDownloadedColor : arrWarningColor,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  p.good
                                      ? l.bzProviderGood
                                      : [
                                          p.status,
                                          if (p.retry != null)
                                            l.bzRetry(p.retry!),
                                        ].join(' · '),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: p.good
                                        ? scheme.onSurfaceVariant
                                        : arrWarningColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}
