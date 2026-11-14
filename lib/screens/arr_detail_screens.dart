import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../services/tv_mode.dart';
import '../state/arr_providers.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_delete_files.dart';
import '../widgets/arr_file_edit.dart';
import '../widgets/arr_monitoring.dart';
import '../widgets/context_menu.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/detail_header.dart';
import '../widgets/error_view.dart';
import '../widgets/hover_pill_button.dart';
import '../widgets/meta_pill.dart';
import '../widgets/ui_common.dart';
import 'arr_import_screen.dart';
import 'arr_releases_screen.dart';

/// A movie in Radarr: where it stands, its file and its history.
class ArrMovieScreen extends ConsumerWidget {
  final int id;
  const ArrMovieScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final client = ref.watch(radarrClientProvider);
    final async = ref.watch(radarrMovieProvider(id));
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => _ErrorPage(
          message: e.toString(),
          onRetry: () => ref.invalidate(radarrMovieProvider(id)),
        ),
        data: (m) {
          final theme = Theme.of(context);
          final profiles =
              ref
                  .watch(arrQualityProfilesProvider(ArrKind.radarr))
                  .asData
                  ?.value ??
              const {};
          final history = ref.watch(radarrMovieHistoryProvider(id));
          final wide = MediaQuery.sizeOf(context).width >= 620;
          final actions = _movieActions(context, ref, client, m);
          final meta = [
            if (m.year != null) '${m.year}',
            if ((m.runtime ?? 0) > 0)
              arrDuration(Duration(minutes: m.runtime!)),
            if (m.studio?.isNotEmpty ?? false) m.studio!,
          ].join(' · ');
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(radarrMovieHistoryProvider(id));
              ref.invalidate(radarrMovieProvider(id));
              await ref.read(radarrMovieProvider(id).future);
            },
            child: CustomScrollView(
              slivers: [
                _Header(
                  client: client,
                  images: m.images,
                  title: m.title,
                  meta: meta,
                  cert: m.certification,
                  status: ArrChip(
                    label: arrStateLabel(l, m.state),
                    color: arrStateColor(m.state, theme.colorScheme),
                  ),
                  placeholderIcon: Icons.movie_rounded,
                  actions: wide ? actions(true) : null,
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!wide) actions(false),
                        if (m.overview?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 16),
                          Text(
                            m.overview!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        ArrFact(
                          label: l.arrQualityProfile,
                          value: profiles[m.qualityProfileId] ?? '-',
                        ),
                        ArrFact(
                          label: l.arrMonitored,
                          value: m.monitored ? l.arrYes : l.arrNo,
                        ),
                        if (m.path != null)
                          ArrFact(label: l.arrPath, value: m.path!),
                        ArrFact(
                          label: l.arrSizeOnDisk,
                          value: arrSize(m.sizeOnDisk),
                        ),
                        if (m.added != null && m.added!.year > 1)
                          ArrFact(
                            label: l.arrAdded,
                            value: arrDate(context, m.added!),
                          ),
                        if (m.inCinemas != null ||
                            m.digitalRelease != null ||
                            m.physicalRelease != null) ...[
                          const SizedBox(height: 20),
                          Text(l.arrReleases, style: arrSectionStyle(theme)),
                          const SizedBox(height: 6),
                          if (m.inCinemas != null)
                            ArrFact(
                              label: l.arrInCinemas,
                              value: arrDate(context, m.inCinemas!),
                            ),
                          if (m.digitalRelease != null)
                            ArrFact(
                              label: l.arrDigitalRelease,
                              value: arrDate(context, m.digitalRelease!),
                            ),
                          if (m.physicalRelease != null)
                            ArrFact(
                              label: l.arrPhysicalRelease,
                              value: arrDate(context, m.physicalRelease!),
                            ),
                        ],
                        const SizedBox(height: 20),
                        Text(l.arrFile, style: arrSectionStyle(theme)),
                        const SizedBox(height: 8),
                        if (m.movieFile != null) ...[
                          ArrFileCard(file: m.movieFile!),
                          if (client != null)
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 4,
                              children: [
                                TextButton.icon(
                                  icon: const Icon(Icons.edit_rounded, size: 18),
                                  label: Text(l.arrEditFile),
                                  onPressed: () =>
                                      _editMovieFile(context, ref, client, m),
                                ),
                                _DeleteFileButton(
                                fileName:
                                    m.movieFile!.relativePath ??
                                    m.movieFile!.path ??
                                    '',
                                app: client.kind.appName,
                                  delete: () =>
                                      client.deleteMovieFile(m.movieFile!.id),
                                  after: () => arrMovieChanged(ref, id),
                                ),
                              ],
                            ),
                        ] else
                          Text(
                            l.arrNoFile,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 24),
                        _HistorySection(history: history),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A show in Sonarr: its seasons and episodes, files and history.
class ArrSeriesScreen extends ConsumerWidget {
  final int id;
  const ArrSeriesScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final client = ref.watch(sonarrClientProvider);
    final async = ref.watch(sonarrSeriesProvider(id));
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => _ErrorPage(
          message: e.toString(),
          onRetry: () => ref.invalidate(sonarrSeriesProvider(id)),
        ),
        data: (s) {
          final theme = Theme.of(context);
          final profiles =
              ref
                  .watch(arrQualityProfilesProvider(ArrKind.sonarr))
                  .asData
                  ?.value ??
              const {};
          final episodes = ref.watch(sonarrEpisodesProvider(id));
          final files =
              ref.watch(sonarrEpisodeFilesProvider(id)).asData?.value ??
              const {};
          final history = ref.watch(sonarrSeriesHistoryProvider(id));
          final meta = [
            if (s.year != null) '${s.year}',
            if (s.network?.isNotEmpty ?? false) s.network!,
            if ((s.runtime ?? 0) > 0)
              arrDuration(Duration(minutes: s.runtime!)),
          ].join(' · ');
          final state = s.ended ? ArrState.ended : ArrState.continuing;
          final wide = MediaQuery.sizeOf(context).width >= 620;
          final actions = _seriesActions(
            context,
            ref,
            client,
            s,
            episodes.asData?.value,
          );
          // Newest season first, specials at the end, as Sonarr lists them.
          final seasons = [
            ...s.seasons.where((x) => x.seasonNumber > 0),
            ...s.seasons.where((x) => x.seasonNumber == 0),
          ];
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(sonarrEpisodesProvider(id));
              ref.invalidate(sonarrEpisodeFilesProvider(id));
              ref.invalidate(sonarrSeriesHistoryProvider(id));
              ref.invalidate(sonarrSeriesProvider(id));
              await ref.read(sonarrSeriesProvider(id).future);
            },
            child: CustomScrollView(
              slivers: [
                _Header(
                  client: client,
                  images: s.images,
                  title: s.title,
                  meta: meta,
                  cert: s.certification,
                  status: Wrap(
                    spacing: 6,
                    children: [
                      ArrChip(
                        label: arrStateLabel(l, state),
                        color: arrStateColor(state, theme.colorScheme),
                      ),
                      if (!s.monitored)
                        ArrChip(
                          label: l.arrUnmonitored,
                          color: theme.colorScheme.outline,
                        ),
                      if (s.monitored && s.missingEpisodes > 0)
                        ArrChip(
                          label: l.arrMissingEpisodes(s.missingEpisodes),
                          color: arrMissingColor,
                        ),
                    ],
                  ),
                  placeholderIcon: Icons.live_tv_rounded,
                  actions: wide ? actions(true) : null,
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!wide) actions(false),
                        if (s.overview?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 16),
                          Text(
                            s.overview!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        ArrFact(
                          label: l.arrQualityProfile,
                          value: profiles[s.qualityProfileId] ?? '-',
                        ),
                        ArrFact(
                          label: l.arrMonitored,
                          value: s.monitored ? l.arrYes : l.arrNo,
                        ),
                        ArrFact(
                          label: l.arrFiles,
                          value: l.arrEpisodesOf(
                            s.episodeFileCount,
                            s.episodeCount,
                          ),
                        ),
                        if (s.path != null)
                          ArrFact(label: l.arrPath, value: s.path!),
                        ArrFact(
                          label: l.arrSizeOnDisk,
                          value: arrSize(s.sizeOnDisk),
                        ),
                        if (s.added != null && s.added!.year > 1)
                          ArrFact(
                            label: l.arrAdded,
                            value: arrDate(context, s.added!),
                          ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                if (episodes.hasError)
                  SliverToBoxAdapter(
                    child: ErrorView(
                      message: episodes.error.toString(),
                      onRetry: () => ref.invalidate(sonarrEpisodesProvider(id)),
                    ),
                  )
                else if (!episodes.hasValue)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: AppSpinner()),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: seasons.length,
                    itemBuilder: (context, i) => _SeasonTile(
                      client: client,
                      series: s,
                      seriesId: id,
                      season: seasons[i],
                      episodes:
                          [
                            for (final e in episodes.value!)
                              if (e.seasonNumber == seasons[i].seasonNumber) e,
                          ]..sort(
                            (a, b) =>
                                b.episodeNumber.compareTo(a.episodeNumber),
                          ),
                      files: files,
                      initiallyExpanded: i == 0,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                    child: _HistorySection(
                      history: history,
                      episodeLabel: {
                        for (final e
                            in episodes.asData?.value ?? const <ArrEpisode>[])
                          e.id: e.code,
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ArrClient? client;
  final List<ArrImage> images;
  final String title;
  final String meta;
  final String? cert;
  final Widget status;
  final IconData placeholderIcon;
  final Widget? actions;

  const _Header({
    this.actions,
    required this.client,
    required this.images,
    required this.title,
    required this.meta,
    required this.status,
    required this.placeholderIcon,
    this.cert,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = (MediaQuery.sizeOf(context).width / 2.35).clamp(
      320.0,
      620.0,
    );
    return SliverAppBar(
      expandedHeight: height,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            ArrArt(
              client: client,
              images: images,
              type: 'fanart',
              width: 1280,
              placeholderIcon: placeholderIcon,
              alignment: const Alignment(0, -0.35),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.4, 1.0],
                ),
              ),
            ),
            DetailHeaderOverlay(
              poster: ArrArt(
                client: client,
                images: images,
                width: 342,
                placeholderIcon: placeholderIcon,
              ),
              status: status,
              title: Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
                ),
              ),
              cert: (cert?.isNotEmpty ?? false) ? CertBadge(text: cert!) : null,
              metaLine: meta,
              actions: actions,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openIn(ArrClient client, String? slug) => launchUrl(
  Uri.parse(client.webUrl(slug)),
  mode: LaunchMode.externalApplication,
);

/// Corrects the movie file's quality, languages or release group, as on
/// Radarr's Manage Files.
Future<void> _editMovieFile(
  BuildContext context,
  WidgetRef ref,
  RadarrClient client,
  ArrMovie m,
) async {
  final f = m.movieFile;
  if (f == null) return;
  final l = AppLocalizations.of(context);
  final changes = await showArrFileEditDialog(
    context,
    kind: ArrKind.radarr,
    subtitle: (f.relativePath ?? f.path ?? '').split('/').last,
    qualityId: arrQualityId(f.qualityModel),
    languages: f.languageItems,
    releaseGroup: f.releaseGroup,
  );
  if (changes == null || changes.isEmpty || !context.mounted) return;
  if (await arrRun(
    context,
    () => client.updateFiles([
      {
        'id': f.id,
        if (changes.quality != null)
          'quality': arrQualityModel(changes.quality!, f.qualityModel),
        if (changes.languages != null)
          'languages': [for (final x in changes.languages!) x.toJson()],
        if (changes.releaseGroup != null) 'releaseGroup': changes.releaseGroup,
      },
    ]),
    done: l.arrSaved,
  )) {
    arrMovieChanged(ref, m.id);
  }
}

/// A movie's actions; call with true for the header's round buttons.
Widget Function(bool header) _movieActions(
  BuildContext context,
  WidgetRef ref,
  RadarrClient? client,
  ArrMovie m,
) {
  final l = AppLocalizations.of(context);
  if (client == null) return (_) => const SizedBox.shrink();
  void changed() => arrMovieChanged(ref, m.id);
  final main = [
    ArrAction(
      icon: Icons.search_rounded,
      label: l.arrSearchMovie,
      primary: true,
      onTap: () => arrRun(
        context,
        () => client.searchMovie(m.id),
        done: l.arrSearchStarted(client.kind.appName),
      ),
    ),
    ArrAction(
      icon: Icons.manage_search_rounded,
      label: l.arrInteractiveSearch,
      onTap: () => context.push(ArrReleaseTarget.movie(m.id).location),
    ),
    ArrAction(
      icon: m.monitored
          ? Icons.bookmark_rounded
          : Icons.bookmark_border_rounded,
      label: m.monitored ? l.arrUnmonitor : l.arrMonitor,
      onTap: () async {
        if (await arrRun(
          context,
          () => client.setMovieMonitored(m.id, !m.monitored),
          done: m.monitored ? l.arrNowUnmonitored : l.arrNowMonitored,
        )) {
          changed();
        }
      },
    ),
    ArrAction(
      icon: Icons.edit_rounded,
      label: l.arrEdit,
      onTap: () async {
        if (await showArrEditDialog(
          context,
          client: client,
          id: m.id,
          title: m.title,
          images: m.images,
        )) {
          changed();
        }
      },
    ),
  ];
  final more = [
    ArrAction(
      icon: Icons.sync_rounded,
      label: l.arrRefreshScan,
      onTap: () async {
        if (await arrRun(
          context,
          () => client.refreshMovie(m.id),
          done: l.arrRefreshStarted(client.kind.appName),
        )) {
          Future.delayed(const Duration(seconds: 4), changed);
        }
      },
    ),
    // Files dropped in the movie's folder that Radarr hasn't taken in.
    if (m.path != null && m.path!.isNotEmpty)
      ArrAction(
        icon: Icons.drive_folder_upload_rounded,
        label: l.arrManualImport,
        onTap: () => context.push(
          ArrImportTarget.folder(ArrKind.radarr, m.path!).location,
        ),
      ),
    if (m.hasFile)
      ArrAction(
        icon: Icons.drive_file_rename_outline_rounded,
        label: l.arrRenameFiles,
        onTap: () async {
          if (await showArrRenameDialog(
            context,
            client: client,
            id: m.id,
            title: m.title,
            images: m.images,
          )) {
            Future.delayed(const Duration(seconds: 3), changed);
          }
        },
      ),
    if (!isTvDevice && m.titleSlug != null)
      ArrAction(
        icon: Icons.open_in_new_rounded,
        label: l.arrOpenIn(client.kind.appName),
        onTap: () => _openIn(client, m.titleSlug),
      ),
    ArrAction(
      icon: Icons.delete_rounded,
      label: l.commonDelete,
      destructive: true,
      onTap: () async {
        if (await showArrDeleteDialog(
              context,
              client: client,
              id: m.id,
              title: m.title,
              images: m.images,
              sizeOnDisk: m.sizeOnDisk,
            ) &&
            context.mounted) {
          ref.invalidate(radarrMoviesProvider);
          ref.invalidate(arrCalendarProvider);
          context.pop();
        }
      },
    ),
  ];
  return (header) =>
      ArrActionBar(main: main, more: more, header: header, title: m.title);
}

/// A show's actions; call with true for the header's round buttons.
Widget Function(bool header) _seriesActions(
  BuildContext context,
  WidgetRef ref,
  SonarrClient? client,
  ArrSeries s,
  List<ArrEpisode>? episodes,
) {
  final l = AppLocalizations.of(context);
  if (client == null) return (_) => const SizedBox.shrink();
  void changed() => arrSeriesChanged(ref, s.id);
  final main = [
    ArrAction(
      icon: Icons.search_rounded,
      label: l.arrSearchMonitored,
      primary: true,
      onTap: () => arrRun(
        context,
        () => client.searchSeries(s.id),
        done: l.arrSearchStarted(client.kind.appName),
      ),
    ),
    // Sonarr's show toggle and its Monitoring options in one place: the
    // show's switch, which episodes, specials and new seasons.
    ArrAction(
      icon: s.monitored
          ? Icons.bookmark_rounded
          : Icons.bookmark_border_rounded,
      label: l.arrMonitoring,
      onTap: () async {
        if (await showArrMonitoringDialog(
          context,
          client: client,
          series: s,
          episodes: episodes,
        )) {
          changed();
        }
      },
    ),
    ArrAction(
      icon: Icons.edit_rounded,
      label: l.arrEdit,
      onTap: () async {
        if (await showArrEditDialog(
          context,
          client: client,
          id: s.id,
          title: s.title,
          images: s.images,
        )) {
          changed();
        }
      },
    ),
  ];
  final more = [
    if (s.episodeFileCount > 0)
      ArrAction(
        icon: Icons.folder_open_rounded,
        label: l.arrManageFiles,
        onTap: () => context.push('/arr/series/${s.id}/files'),
      ),
    ArrAction(
      icon: Icons.sync_rounded,
      label: l.arrRefreshScan,
      onTap: () async {
        if (await arrRun(
          context,
          () => client.refreshSeries(s.id),
          done: l.arrRefreshStarted(client.kind.appName),
        )) {
          Future.delayed(const Duration(seconds: 4), changed);
        }
      },
    ),
    if (s.path != null && s.path!.isNotEmpty)
      ArrAction(
        icon: Icons.drive_folder_upload_rounded,
        label: l.arrManualImport,
        onTap: () => context.push(
          ArrImportTarget.folder(ArrKind.sonarr, s.path!).location,
        ),
      ),
    if (s.episodeFileCount > 0)
      ArrAction(
        icon: Icons.drive_file_rename_outline_rounded,
        label: l.arrRenameFiles,
        onTap: () async {
          if (await showArrRenameDialog(
            context,
            client: client,
            id: s.id,
            title: s.title,
            images: s.images,
          )) {
            Future.delayed(const Duration(seconds: 3), changed);
          }
        },
      ),
    if (!isTvDevice && s.titleSlug != null)
      ArrAction(
        icon: Icons.open_in_new_rounded,
        label: l.arrOpenIn(client.kind.appName),
        onTap: () => _openIn(client, s.titleSlug),
      ),
    ArrAction(
      icon: Icons.delete_rounded,
      label: l.commonDelete,
      destructive: true,
      onTap: () async {
        if (await showArrDeleteDialog(
              context,
              client: client,
              id: s.id,
              title: s.title,
              images: s.images,
              sizeOnDisk: s.sizeOnDisk,
            ) &&
            context.mounted) {
          ref.invalidate(sonarrSeriesListProvider);
          ref.invalidate(arrCalendarProvider);
          context.pop();
        }
      },
    ),
  ];
  return (header) =>
      ArrActionBar(main: main, more: more, header: header, title: s.title);
}

/// Deletes one file from disk after asking.
class _DeleteFileButton extends StatelessWidget {
  final String fileName;
  final String app;
  final Future<void> Function() delete;
  final VoidCallback after;
  const _DeleteFileButton({
    required this.fileName,
    required this.app,
    required this.delete,
    required this.after,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: scheme.error),
      icon: const Icon(Icons.delete_outline_rounded, size: 18),
      label: Text(l.arrDeleteFile),
      onPressed: () async {
        final go = await confirm(
          context,
          title: l.arrDeleteFileTitle,
          message: l.arrDeleteFileMessage(fileName, app),
          confirmLabel: l.commonDelete,
          destructive: true,
        );
        if (!go || !context.mounted) return;
        if (await arrRun(context, delete, done: l.arrFileDeleted)) after();
      },
    );
  }
}

class _ErrorPage extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorPage({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      const SliverAppBar(pinned: true),
      SliverFillRemaining(
        hasScrollBody: true,
        child: ErrorView(message: message, onRetry: onRetry),
      ),
    ],
  );
}

/// A season of a show, opening into its episodes.
class _SeasonTile extends ConsumerWidget {
  final SonarrClient? client;
  final ArrSeries series;
  final int seriesId;
  final ArrSeason season;
  final List<ArrEpisode> episodes;
  final Map<int, ArrFile> files;
  final bool initiallyExpanded;

  const _SeasonTile({
    required this.client,
    required this.series,
    required this.seriesId,
    required this.season,
    required this.episodes,
    required this.files,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = client;
    final name = season.seasonNumber == 0
        ? l.arrSpecials
        : l.arrSeason(season.seasonNumber);
    final complete =
        season.episodeCount > 0 &&
        season.episodeFileCount >= season.episodeCount;
    final color = !season.monitored
        ? scheme.outline
        : complete
        ? arrDownloadedColor
        : season.episodeFileCount == 0 && season.episodeCount == 0
        ? arrUnreleasedColor
        : arrMissingColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          shape: const Border(),
          leading: IconButton(
            tooltip: season.monitored ? l.arrUnmonitor : l.arrMonitor,
            icon: Icon(
              season.monitored
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              color: season.monitored ? scheme.primary : scheme.outline,
            ),
            onPressed: c == null
                ? null
                : () async {
                    if (await arrRun(
                      context,
                      () => c.setSeasonMonitored(
                        seriesId,
                        season.seasonNumber,
                        !season.monitored,
                      ),
                      done: season.monitored
                          ? l.arrNowUnmonitored
                          : l.arrNowMonitored,
                    )) {
                      arrSeriesChanged(ref, seriesId);
                    }
                  },
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              l.arrEpisodesOf(season.episodeFileCount, season.episodeCount),
              if (season.sizeOnDisk > 0) arrSize(season.sizeOnDisk),
            ].join(' · '),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: season.episodeCount == 0
                        ? 0
                        : season.episodeFileCount / season.episodeCount,
                    minHeight: 5,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              if (c != null) ...[
                IconButton(
                  tooltip: l.arrSearchSeason,
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => arrRun(
                    context,
                    () => c.searchSeason(seriesId, season.seasonNumber),
                    done: l.arrSearchStarted(c.kind.appName),
                  ),
                ),
                Builder(
                  builder: (anchor) => IconButton(
                    tooltip: l.arrSeasonActions,
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => _openMenu(context, ref, anchor, c, name),
                  ),
                ),
              ],
            ],
          ),
          children: [
            for (final e in episodes)
              _EpisodeRow(
                client: c,
                episode: e,
                file: e.episodeFileId == null ? null : files[e.episodeFileId],
              ),
          ],
        ),
      ),
    );
  }
}

extension on _SeasonTile {
  /// The season's other actions: Interactive Search, and deleting all of its
  /// files (Sonarr has no season delete; its Manage Episodes does this).
  void _openMenu(
    BuildContext context,
    WidgetRef ref,
    BuildContext anchor,
    SonarrClient c,
    String name,
  ) {
    final l = AppLocalizations.of(context);
    final box = anchor.findRenderObject() as RenderBox?;
    final at = box == null
        ? Offset.zero
        : box.localToGlobal(box.size.bottomCenter(Offset.zero));
    final seasonFiles = [
      for (final f in files.values)
        if ((f.seasonNumber ??
                episodes
                    .where((e) => e.episodeFileId == f.id)
                    .firstOrNull
                    ?.seasonNumber) ==
            season.seasonNumber)
          f,
    ];
    showContextMenu(
      context,
      at: at,
      title: name,
      actions: [
        ContextMenuAction(
          icon: Icons.manage_search_rounded,
          label: l.arrInteractiveSearch,
          onTap: () => context.push(
            ArrReleaseTarget.season(seriesId, season.seasonNumber).location,
          ),
        ),
        if (seasonFiles.isNotEmpty)
          ContextMenuAction(
            icon: Icons.delete_sweep_rounded,
            label: l.arrDeleteSeasonFiles,
            color: Theme.of(context).colorScheme.error,
            onTap: () async {
              if (await showArrDeleteFilesDialog(
                context,
                client: c,
                series: series,
                files: seasonFiles,
                episodeIds: [
                  for (final e in episodes)
                    if (e.episodeFileId != null) e.id,
                ],
              )) {
                arrSeriesChanged(ref, seriesId);
              }
            },
          ),
      ],
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  final SonarrClient? client;
  final ArrEpisode episode;
  final ArrFile? file;
  const _EpisodeRow({
    required this.client,
    required this.episode,
    required this.file,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final aired = episode.aired(now);
    final (String label, Color color) = episode.hasFile
        ? (file?.quality ?? l.arrDownloaded, arrDownloadedColor)
        : !episode.monitored
        ? (l.arrUnmonitored, scheme.outline)
        : aired
        ? (l.arrMissing, arrMissingColor)
        : (l.arrUnaired, arrUnreleasedColor);
    final date = episode.airDate;
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 34,
        child: Text(
          '${episode.episodeNumber}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(
        episode.title ?? episode.code,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: date == null
          ? null
          : Text(
              aired
                  ? l.arrAired(arrDate(context, date))
                  : l.arrAirs(arrDate(context, date)),
            ),
      trailing: ArrChip(label: label, color: color),
      onTap: () => _showEpisode(context, client, episode, file),
    );
  }
}

void _showEpisode(
  BuildContext context,
  SonarrClient? client,
  ArrEpisode e,
  ArrFile? file,
) {
  final l = AppLocalizations.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final theme = Theme.of(context);
        final c = client;
        void changed() => arrSeriesChanged(ref, e.seriesId);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              Text(
                e.code,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                e.title ?? '',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (e.airDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${arrDate(context, e.airDate!)} · ${arrTime(context, e.airDate!)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (e.overview?.isNotEmpty ?? false) ...[
                const SizedBox(height: 14),
                Text(
                  e.overview!,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
              if (c != null) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    HoverPillButton(
                      primary: true,
                      icon: Icons.search_rounded,
                      label: l.arrSearchEpisode,
                      onTap: () => arrRun(
                        context,
                        () => c.searchEpisodes([e.id]),
                        done: l.arrSearchStarted(c.kind.appName),
                      ),
                    ),
                    HoverPillButton(
                      icon: Icons.manage_search_rounded,
                      label: l.arrInteractiveSearch,
                      onTap: () {
                        final target = ArrReleaseTarget.episode(
                          e.seriesId,
                          e.id,
                        ).location;
                        final router = GoRouter.of(context);
                        Navigator.pop(context);
                        router.push(target);
                      },
                    ),
                    HoverPillButton(
                      icon: e.monitored
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      label: e.monitored ? l.arrUnmonitor : l.arrMonitor,
                      onTap: () async {
                        if (await arrRun(
                              context,
                              () =>
                                  c.setEpisodesMonitored([e.id], !e.monitored),
                              done: e.monitored
                                  ? l.arrNowUnmonitored
                                  : l.arrNowMonitored,
                            ) &&
                            context.mounted) {
                          changed();
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              ArrFact(
                label: l.arrMonitored,
                value: e.monitored ? l.arrYes : l.arrNo,
              ),
              const SizedBox(height: 14),
              Text(l.arrFile, style: arrSectionStyle(theme)),
              const SizedBox(height: 8),
              if (file != null) ...[
                ArrFileCard(file: file),
                if (c != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: _DeleteFileButton(
                      fileName: file.relativePath ?? file.path ?? '',
                      app: c.kind.appName,
                      delete: () => c.deleteEpisodeFile(file.id),
                      after: () {
                        changed();
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
              ] else
                Text(
                  l.arrNoFile,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

/// What a file is: name, quality, size and what's inside it.
class ArrFileCard extends StatelessWidget {
  final ArrFile file;
  const ArrFileCard({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mi = file.mediaInfo;
    final video = mi == null
        ? null
        : [
            mi.resolution,
            mi.videoCodec,
            if (mi.videoDynamicRangeType?.isNotEmpty ?? false)
              mi.videoDynamicRangeType,
            if ((mi.videoBitDepth ?? 0) > 8) '${mi.videoBitDepth}-bit',
          ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final audio = mi == null
        ? null
        : [
            mi.audioCodec,
            mi.channels,
            mi.audioLanguages,
          ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              file.relativePath ?? file.path ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (file.quality != null)
                  ArrChip(label: file.quality!, color: arrDownloadedColor),
                ArrChip(
                  label: arrSize(file.size),
                  color: theme.colorScheme.outline,
                ),
                if (file.qualityCutoffNotMet)
                  ArrChip(label: l.arrUpgradeWanted, color: arrWarningColor),
              ],
            ),
            const SizedBox(height: 8),
            if (video?.isNotEmpty ?? false)
              ArrFact(label: l.arrVideo, value: video!),
            if (audio?.isNotEmpty ?? false)
              ArrFact(label: l.arrAudio, value: audio!),
            if (mi?.subtitles?.isNotEmpty ?? false)
              ArrFact(label: l.arrSubtitles, value: mi!.subtitles!),
            if (file.languages.isNotEmpty)
              ArrFact(label: l.arrLanguages, value: file.languages.join(', ')),
            if (file.releaseGroup?.isNotEmpty ?? false)
              ArrFact(label: l.arrReleaseGroup, value: file.releaseGroup!),
            if (file.dateAdded != null)
              ArrFact(
                label: l.arrAdded,
                value: arrDate(context, file.dateAdded!),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  final AsyncValue<List<ArrHistoryItem>> history;
  final Map<int, String> episodeLabel;
  const _HistorySection({required this.history, this.episodeLabel = const {}});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = history.asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.arrHistory, style: arrSectionStyle(theme)),
        const SizedBox(height: 8),
        if (history.hasError)
          Text(history.error.toString(), style: TextStyle(color: scheme.error))
        else if (items == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: AppSpinner()),
          )
        else if (items.isEmpty)
          Text(
            l.arrNoHistory,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          for (final h in items.take(50))
            _HistoryRow(item: h, episode: episodeLabel[h.episodeId]),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final ArrHistoryItem item;
  final String? episode;
  const _HistoryRow({required this.item, this.episode});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (label, icon, color) = arrHistoryEvent(l, scheme, item.eventType);
    final heading = [?episode, label, ?item.quality].join(' · ');
    final sub = [
      ?item.sourceTitle,
      if (item.date != null)
        '${arrDate(context, item.date!)} ${arrTime(context, item.date!)}',
      ?item.detail,
    ].join('\n');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heading,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  sub,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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
