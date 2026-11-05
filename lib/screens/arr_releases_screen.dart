import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_providers.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/ui_common.dart';

/// What an interactive search is for: a movie, a season, or one episode.
class ArrReleaseTarget {
  final ArrKind kind;
  final int? movieId;
  final int? seriesId;
  final int? seasonNumber;
  final int? episodeId;

  const ArrReleaseTarget.movie(int id)
    : kind = ArrKind.radarr,
      movieId = id,
      seriesId = null,
      seasonNumber = null,
      episodeId = null;

  const ArrReleaseTarget.season(int series, int season)
    : kind = ArrKind.sonarr,
      movieId = null,
      seriesId = series,
      seasonNumber = season,
      episodeId = null;

  const ArrReleaseTarget.episode(int series, int episode)
    : kind = ArrKind.sonarr,
      movieId = null,
      seriesId = series,
      seasonNumber = null,
      episodeId = episode;

  /// The route to the search, its target in the query.
  String get location {
    final q = <String, String>{
      if (movieId != null) 'movie': '$movieId',
      if (seriesId != null) 'series': '$seriesId',
      if (seasonNumber != null) 'season': '$seasonNumber',
      if (episodeId != null) 'episode': '$episodeId',
    };
    return Uri(path: '/arr/releases', queryParameters: q).toString();
  }

  /// Reads the target back from the route's query, or null if it names none.
  static ArrReleaseTarget? fromQuery(Map<String, String> q) {
    int? n(String k) => int.tryParse(q[k] ?? '');
    final movie = n('movie'), series = n('series');
    final season = n('season'), episode = n('episode');
    if (movie != null) return ArrReleaseTarget.movie(movie);
    if (series != null && episode != null) {
      return ArrReleaseTarget.episode(series, episode);
    }
    if (series != null && season != null) {
      return ArrReleaseTarget.season(series, season);
    }
    return null;
  }

  Future<List<ArrSearchResult>> load(ArrClient c) {
    if (c is RadarrClient) return c.releasesForMovie(movieId!);
    final s = c as SonarrClient;
    return episodeId != null
        ? s.releasesForEpisode(episodeId!)
        : s.releasesForSeason(seriesId!, seasonNumber!);
  }
}

enum _Sort { best, quality, size, age, seeders }

/// Every release the indexers offer for one movie, season or episode, with
/// the app's verdict, to pick one by hand.
class ArrReleasesScreen extends ConsumerStatefulWidget {
  final ArrReleaseTarget? target;
  const ArrReleasesScreen({super.key, required this.target});

  @override
  ConsumerState<ArrReleasesScreen> createState() => _ArrReleasesScreenState();
}

class _ArrReleasesScreenState extends ConsumerState<ArrReleasesScreen> {
  Future<List<ArrSearchResult>>? _results;
  _Sort _sort = _Sort.best;
  bool _hideRejected = false;
  final _grabbing = <String>{};
  final _grabbed = <String>{};

  ArrClient? get _client {
    final t = widget.target;
    if (t == null) return null;
    return t.kind == ArrKind.sonarr
        ? ref.read(sonarrClientProvider)
        : ref.read(radarrClientProvider);
  }

  @override
  void initState() {
    super.initState();
    _search();
  }

  void _search() {
    final c = _client;
    final t = widget.target;
    if (c == null || t == null) return;
    setState(() {
      _results = t.load(c);
    });
  }

  List<ArrSearchResult> _apply(List<ArrSearchResult> all) {
    final list = [
      for (final r in all)
        if (!_hideRejected || !r.rejected) r,
    ];
    // Best Match keeps the app's own order: it already ranks releases the
    // way it would choose between them.
    switch (_sort) {
      case _Sort.best:
        break;
      case _Sort.quality:
        list.sort((a, b) {
          final q = b.qualityWeight.compareTo(a.qualityWeight);
          return q != 0
              ? q
              : b.customFormatScore.compareTo(a.customFormatScore);
        });
      case _Sort.size:
        list.sort((a, b) => b.size.compareTo(a.size));
      case _Sort.age:
        list.sort(
          (a, b) => (a.ageHours ?? double.infinity).compareTo(
            b.ageHours ?? double.infinity,
          ),
        );
      case _Sort.seeders:
        list.sort((a, b) => (b.seeders ?? -1).compareTo(a.seeders ?? -1));
    }
    return list;
  }

  Future<void> _grab(ArrSearchResult r) async {
    final l = AppLocalizations.of(context);
    final c = _client;
    if (c == null) return;
    if (r.rejected) {
      final go = await confirm(
        context,
        title: l.arrGrabAnyway,
        message: l.arrGrabAnywayMessage(
          c.kind.appName,
          r.rejections.map((x) => '• $x').join('\n'),
        ),
        confirmLabel: l.arrGrab,
      );
      if (!go || !mounted) return;
    }
    setState(() => _grabbing.add(r.guid));
    final ok = await arrRun(context, () => c.grab(r), done: l.arrGrabbed);
    if (!mounted) return;
    setState(() {
      _grabbing.remove(r.guid);
      if (ok) _grabbed.add(r.guid);
    });
    if (ok) ref.invalidate(arrQueueProvider);
  }

  String _subtitle(AppLocalizations l) {
    final t = widget.target!;
    if (t.movieId != null) {
      return ref.watch(radarrMovieProvider(t.movieId!)).asData?.value.title ??
          '';
    }
    final show =
        ref.watch(sonarrSeriesProvider(t.seriesId!)).asData?.value.title ?? '';
    if (t.seasonNumber != null) {
      return '$show · ${t.seasonNumber == 0 ? l.arrSpecials : l.arrSeason(t.seasonNumber!)}';
    }
    final eps = ref.watch(sonarrEpisodesProvider(t.seriesId!)).asData?.value;
    final ep = eps?.where((e) => e.id == t.episodeId).firstOrNull;
    return [show, ?ep?.code].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (widget.target == null || _client == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.arrInteractiveSearch)),
        body: EmptyState(
          icon: Icons.manage_search_rounded,
          title: l.arrNothingToSearch,
        ),
      );
    }
    String sortLabel(_Sort s) => switch (s) {
      _Sort.best => l.arrSortBestMatch,
      _Sort.quality => l.arrSortQuality,
      _Sort.size => l.arrSortSize,
      _Sort.age => l.arrSortAge,
      _Sort.seeders => l.arrSortSeeders,
    };
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.arrInteractiveSearch),
            Text(
              _subtitle(l),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _hideRejected ? l.arrShowRejected : l.arrHideRejected,
            icon: Icon(
              _hideRejected
                  ? Icons.filter_alt_rounded
                  : Icons.filter_alt_off_rounded,
            ),
            onPressed: () => setState(() => _hideRejected = !_hideRejected),
          ),
          PopupMenuButton<_Sort>(
            tooltip: l.arrSort,
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => [
              for (final s in _Sort.values)
                CheckedPopupMenuItem(
                  value: s,
                  checked: s == _sort,
                  child: Text(sortLabel(s)),
                ),
            ],
          ),
          IconButton(
            tooltip: l.arrSearchAgain,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _search,
          ),
        ],
      ),
      body: FutureBuilder<List<ArrSearchResult>>(
        future: _results,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppSpinner(),
                  const SizedBox(height: 16),
                  Text(
                    l.arrAskingIndexers,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }
          if (snap.hasError) {
            return ErrorView(message: snap.error.toString(), onRetry: _search);
          }
          final all = snap.data ?? const [];
          final list = _apply(all);
          final rejected = all.where((r) => r.rejected).length;
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.search_off_rounded,
              title: l.arrNoReleases,
              message: l.arrNoReleasesHint,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length + 1,
            separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 4 : 10),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Text(
                  l.arrReleaseCount(all.length, rejected),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              final r = list[i - 1];
              return _ReleaseCard(
                key: ValueKey(r.guid),
                release: r,
                busy: _grabbing.contains(r.guid),
                grabbed: _grabbed.contains(r.guid),
                onGrab: () => _grab(r),
              );
            },
          );
        },
      ),
    );
  }
}

/// "3h", "5d", "2y": how old a release is.
String arrAge(double hours) {
  if (hours < 1) return '${(hours * 60).round()}m';
  if (hours < 48) return '${hours.round()}h';
  final days = hours / 24;
  if (days < 730) return '${days.round()}d';
  return '${(days / 365).floor()}y';
}

class _ReleaseCard extends StatefulWidget {
  final ArrSearchResult release;
  final bool busy;
  final bool grabbed;
  final VoidCallback onGrab;

  const _ReleaseCard({
    super.key,
    required this.release,
    required this.busy,
    required this.grabbed,
    required this.onGrab,
  });

  @override
  State<_ReleaseCard> createState() => _ReleaseCardState();
}

class _ReleaseCardState extends State<_ReleaseCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = widget.release;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final facts = [
      arrSize(r.size),
      if (r.ageHours != null) arrAge(r.ageHours!),
      ?r.indexer,
    ].join(' · ');
    return Opacity(
      opacity: r.rejected ? 0.78 : 1,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title,
                        maxLines: _open ? null : 2,
                        overflow: _open ? null : TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (r.quality != null)
                            ArrChip(
                              label: r.quality!,
                              color: r.rejected
                                  ? arrMissingColor
                                  : arrDownloadedColor,
                            ),
                          ArrChip(
                            label: r.isTorrent ? l.arrTorrent : l.arrUsenet,
                            color: r.isTorrent
                                ? arrQueuedColor
                                : arrUnreleasedColor,
                          ),
                          if (r.customFormatScore != 0)
                            ArrChip(
                              label: r.customFormatScore > 0
                                  ? '+${r.customFormatScore}'
                                  : '${r.customFormatScore}',
                              color: r.customFormatScore > 0
                                  ? arrDownloadedColor
                                  : arrWarningColor,
                            ),
                          if (r.isTorrent && r.seeders != null)
                            _Peers(seeders: r.seeders!, leechers: r.leechers),
                          Text(facts, style: muted),
                        ],
                      ),
                      if (r.rejected && r.rejections.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.block_rounded,
                                size: 16,
                                color: arrMissingColor,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _open
                                      ? r.rejections.join('\n')
                                      : r.rejections.length == 1
                                      ? r.rejections.first
                                      : l.arrRejectionsMore(
                                          r.rejections.first,
                                          r.rejections.length - 1,
                                        ),
                                  maxLines: _open ? null : 2,
                                  overflow: _open
                                      ? null
                                      : TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: arrMissingColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_open) ...[
                        const SizedBox(height: 8),
                        if (r.customFormats.isNotEmpty)
                          ArrFact(
                            label: l.arrCustomFormats,
                            value: r.customFormats.join(', '),
                          ),
                        if (r.languages.isNotEmpty)
                          ArrFact(
                            label: l.arrLanguages,
                            value: r.languages.join(', '),
                          ),
                        if (r.releaseGroup?.isNotEmpty ?? false)
                          ArrFact(
                            label: l.arrReleaseGroup,
                            value: r.releaseGroup!,
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: widget.busy
                      ? const Center(child: AppSpinner.inline())
                      : widget.grabbed
                      ? Tooltip(
                          message: l.arrGrabbed,
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: arrDownloadedColor,
                          ),
                        )
                      : IconButton(
                          tooltip: l.arrGrab,
                          icon: Icon(
                            Icons.download_rounded,
                            color: r.rejected
                                ? scheme.onSurfaceVariant
                                : scheme.primary,
                          ),
                          onPressed: r.downloadAllowed ? widget.onGrab : null,
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

class _Peers extends StatelessWidget {
  final int seeders;
  final int? leechers;
  const _Peers({required this.seeders, this.leechers});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = seeders == 0
        ? arrMissingColor
        : seeders < 5
        ? arrWarningColor
        : arrDownloadedColor;
    return Tooltip(
      message: l.arrPeers(seeders, leechers ?? 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_upward_rounded, size: 14, color: color),
          Text(
            '$seeders',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (leechers != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_downward_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            Text(
              '$leechers',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
