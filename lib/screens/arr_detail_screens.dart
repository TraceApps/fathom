import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../models/base_item.dart';
import '../services/tv_mode.dart';
import '../state/arr_providers.dart';
import '../state/session_controller.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_delete_files.dart';
import '../widgets/arr_file_edit.dart';
import '../widgets/arr_monitoring.dart';
import '../widgets/arr_pane.dart';
import '../widgets/arr_skeletons.dart';
import '../widgets/context_menu.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/detail_header.dart';
import '../widgets/error_view.dart';
import '../widgets/hover_pill_button.dart';
import '../widgets/meta_pill.dart';
import '../widgets/shimmer.dart';
import '../widgets/tv_focus.dart';
import '../widgets/ui_common.dart';
import 'arr_import_screen.dart';
import 'arr_releases_screen.dart';

part 'arr_artist_screen.dart';

/// A refresh of a movie's page, by a pull or a key: Radarr is asked for it
/// again.
void _askMovieAgain(WidgetRef ref, int id) {
  ref.invalidate(radarrMovieHistoryProvider(id));
  ref.invalidate(radarrMovieProvider(id));
  // And whether it can be watched: the library may have it now.
  ref.invalidate(arrLibraryItemProvider);
}

/// The same of a show's page.
void _askSeriesAgain(WidgetRef ref, int id) {
  ref.invalidate(sonarrEpisodesProvider(id));
  ref.invalidate(sonarrEpisodeFilesProvider(id));
  ref.invalidate(sonarrSeriesHistoryProvider(id));
  ref.invalidate(sonarrSeriesProvider(id));
  ref.invalidate(arrLibraryItemProvider);
}

/// A movie in Radarr: where it stands, its file and its history.
class ArrMovieScreen extends ConsumerWidget {
  final int id;
  const ArrMovieScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final client = ref.watch(radarrClientProvider);
    final async = ref.watch(radarrMovieProvider(id));
    final page = Scaffold(
      body: async.when(
        loading: () => const _LoadingPage(),
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
              _askMovieAgain(ref, id);
              await ref.read(radarrMovieProvider(id).future);
            },
            child: TvPageEnds(child: CustomScrollView(
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
                    onArt: true,
                  ),
                  placeholderIcon: Icons.movie_rounded,
                  actions: wide ? actions(true) : null,
                ),
                SliverToBoxAdapter(
                  child: _Body(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!wide) actions(false),
                        SizedBox(
                          height: (m.overview?.isNotEmpty ?? false) ? 16 : 20,
                        ),
                        // One stop for a TV's remote: the page moves on a
                        // part at a time.
                        ..._tvRead([
                          if (m.overview?.isNotEmpty ?? false) ...[
                            Text(
                              m.overview!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
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
                        ]),
                        const SizedBox(height: 20),
                        Text(l.arrFile, style: arrSectionStyle(theme)),
                        const SizedBox(height: 8),
                        if (m.movieFile != null) ...[
                          TvReadStop(child: ArrFileCard(file: m.movieFile!)),
                          // Changing or deleting a file is for a phone or a
                          // desktop, not a remote.
                          if (client != null && !isTvDevice)
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
            )),
          );
        },
      ),
    );
    return ArrRefreshKeys(
      // Beside a list, the section's own keys ask again.
      onRefresh: ArrPaneHost.of(context) != null
          ? null
          : () => _askMovieAgain(ref, id),
      child: page,
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
    final page = Scaffold(
      body: async.when(
        loading: () => const _LoadingPage(),
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
              _askSeriesAgain(ref, id);
              await ref.read(sonarrSeriesProvider(id).future);
            },
            child: TvPageEnds(child: CustomScrollView(
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
                        onArt: true,
                      ),
                      if (!s.monitored)
                        ArrChip(
                          label: l.arrUnmonitored,
                          color: theme.colorScheme.outline,
                          onArt: true,
                        ),
                      if (s.monitored && s.missingEpisodes > 0)
                        ArrChip(
                          label: l.arrMissingEpisodes(s.missingEpisodes),
                          color: arrMissingColor,
                          onArt: true,
                        ),
                    ],
                  ),
                  placeholderIcon: Icons.live_tv_rounded,
                  actions: wide ? actions(true) : null,
                ),
                SliverToBoxAdapter(
                  child: _Body(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!wide) actions(false),
                        SizedBox(
                          height: (s.overview?.isNotEmpty ?? false) ? 16 : 20,
                        ),
                        // One stop for a TV's remote, before the seasons.
                        ..._tvRead([
                          if (s.overview?.isNotEmpty ?? false) ...[
                            Text(
                              s.overview!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
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
                        ]),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                if (episodes.hasError)
                  SliverToBoxAdapter(
                    child: _Body(
                      child: ErrorView(
                        message: episodes.error.toString(),
                        onRetry: () =>
                            ref.invalidate(sonarrEpisodesProvider(id)),
                      ),
                    ),
                  )
                else if (!episodes.hasValue)
                  const SliverToBoxAdapter(
                    child: _Body(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: _BlocksSkeleton(height: 52),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: seasons.length,
                    itemBuilder: (context, i) => _Body(
                      child: _SeasonTile(
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
                  ),
                SliverToBoxAdapter(
                  child: _Body(
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
            )),
          );
        },
      ),
    );
    return ArrRefreshKeys(
      // Beside a list, the section's own keys ask again.
      onRefresh: ArrPaneHost.of(context) != null
          ? null
          : () => _askSeriesAgain(ref, id),
      child: page,
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
    final host = ArrPaneHost.of(context);
    return SliverAppBar(
      expandedHeight: _headerHeight(context),
      pinned: true,
      // Solid once closed: the page scrolls beneath it, and the title's name
      // can't be read over the page's own words through a see-through bar.
      backgroundColor: theme.colorScheme.surface,
      automaticallyImplyLeading: host == null,
      leading: host == null ? null : _PaneClose(host: host),
      title: _BarTitle(title: title),
      actions: host == null
          ? null
          : [
              IconButton(
                tooltip: AppLocalizations.of(context).arrOpenFullPage,
                icon: const Icon(Icons.open_in_full_rounded),
                onPressed: host.openPage,
              ),
            ],
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
                  // Dark at the top for the bar's buttons, and at the foot
                  // for the title: bright art would swallow both.
                  colors: [
                    Colors.black54,
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black87,
                  ],
                  stops: [0.0, 0.28, 0.4, 1.0],
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
                // Beside the buttons a TV keeps in the header, a long name
                // would otherwise run down over the art.
                maxLines: isTvDevice ? 3 : null,
                overflow: isTvDevice ? TextOverflow.ellipsis : null,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
                ),
              ),
              cert: (cert?.isNotEmpty ?? false) ? CertBadge(text: cert!) : null,
              metaLine: meta,
              // Beside the buttons there's too little room on a TV for the
              // year, the length and the studio on one line.
              metaMaxLines: isTvDevice ? 2 : 1,
              // Scrolled shut, the header's buttons are still laid out under
              // the page: a remote mustn't stop on what can't be seen.
              actions: actions == null
                  ? null
                  : TvOpenHeaderOnly(child: actions!),
            ),
          ],
        ),
      ),
    );
  }
}

/// A title's name in its bar, once the header that says it has scrolled
/// away: there's nothing else left on the page to say whose page this is.
class _BarTitle extends StatelessWidget {
  final String title;
  const _BarTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final bar = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    if (bar == null) return const SizedBox.shrink();
    // Comes in as the header's picture goes out: over its last stretch, a
    // bar's height from closed, which is where the header fades its own.
    final open = bar.currentExtent - bar.minExtent;
    final shown = (1 - open / kToolbarHeight).clamp(0.0, 1.0);
    if (shown == 0) return const SizedBox.shrink();
    return Opacity(
      opacity: shown,
      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// How tall a title's header is, for the width it has.
double _headerHeight(BuildContext context) =>
    (MediaQuery.sizeOf(context).width / 2.35).clamp(320.0, 620.0);

/// Closes the pane a title's page is shown in.
class _PaneClose extends StatelessWidget {
  final ArrPaneHost host;
  const _PaneClose({required this.host});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: AppLocalizations.of(context).commonClose,
    icon: const Icon(Icons.close_rounded),
    onPressed: host.close,
  );
}

/// Leaves a title's page once the title is gone: closes the pane it's in, or
/// goes back.
void _leave(BuildContext context) {
  final host = ArrPaneHost.of(context);
  host != null ? host.close() : context.pop();
}

/// A stretch of a title's page. On a wide window it keeps to a width that
/// reads well, at the start, under the header's own title.
class _Body extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final Widget child;
  const _Body({
    super.key,
    this.padding = EdgeInsets.zero,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: arrListMaxWidth),
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// On a TV, a stretch of the page that's only read (the overview and the
/// facts under it) is one stop for the remote, so UP and DOWN move the page a
/// part at a time. Anywhere else the widgets are just themselves.
List<Widget> _tvRead(List<Widget> children) => !isTvDevice
    ? children
    : [
        TvReadStop(
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ];

/// A few blocks standing in for rows that are on their way.
class _BlocksSkeleton extends StatelessWidget {
  final double height;
  const _BlocksSkeleton({required this.height});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ShimmerBox(height: height),
          ),
      ],
    ),
  );
}

/// A title's page before the title has arrived.
class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    final host = ArrPaneHost.of(context);
    // Filling the page: left to itself the stack is only as big as the
    // button, and the shapes behind it are squeezed into that.
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: ArrDetailSkeleton(
              headerHeight:
                  _headerHeight(context) + MediaQuery.paddingOf(context).top,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: host != null
                  ? _PaneClose(host: host)
                  : (Navigator.of(context).canPop()
                        ? const BackButton()
                        : null),
            ),
          ),
        ],
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

/// Watch, for a title the Jellyfin library has (Play, for an artist): it
/// opens the title there, to play it. The main action then, ahead of
/// searching for a release.
ArrAction? _watchAction(BuildContext context, WidgetRef ref, ArrLibraryKey k) {
  final l = AppLocalizations.of(context);
  final label = k.kind == ArrKind.lidarr ? l.commonPlay : l.detailWatch;
  final asked = ref.watch(arrLibraryItemProvider(k));
  final itemId = asked.value;
  if (itemId == null) {
    // A title on disk is most likely in the library: its button holds its
    // place while the library is first asked, so the others don't move
    // over when the answer comes.
    final likely =
        k.onDisk &&
        asked.isLoading &&
        !asked.hasValue &&
        ref.watch(sessionControllerProvider).value != null;
    if (!likely) return null;
    return ArrAction(
      icon: Icons.play_arrow_rounded,
      label: label,
      primary: true,
      onTap: null,
    );
  }
  return ArrAction(
    icon: Icons.play_arrow_rounded,
    label: label,
    primary: true,
    // An artist opens on its albums, as the Music library opens one.
    onTap: () => context.push(
      k.kind == ArrKind.lidarr ? '/artist' : '/item',
      extra: BaseItemDto(id: itemId, name: k.title),
    ),
  );
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
  final watch = _watchAction(context, ref, arrLibraryKeyOfMovie(m));
  final main = [
    ?watch,
    ArrAction(
      icon: Icons.search_rounded,
      label: l.arrSearchMovie,
      primary: watch == null,
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
      pinned: true,
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
    if (!isTvDevice && m.path != null && m.path!.isNotEmpty)
      ArrAction(
        icon: Icons.drive_folder_upload_rounded,
        label: l.arrManualImport,
        onTap: () => context.push(
          ArrImportTarget.folder(ArrKind.radarr, m.path!).location,
        ),
      ),
    if (!isTvDevice && m.hasFile)
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
          _leave(context);
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
  final watch = _watchAction(context, ref, arrLibraryKeyOfSeries(s));
  final main = [
    ?watch,
    ArrAction(
      icon: Icons.search_rounded,
      label: l.arrSearchMonitored,
      primary: watch == null,
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
      pinned: true,
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
    // Files, folders and renaming are for a phone or a desktop, not a
    // remote.
    if (!isTvDevice && s.episodeFileCount > 0)
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
    if (!isTvDevice && s.path != null && s.path!.isNotEmpty)
      ArrAction(
        icon: Icons.drive_folder_upload_rounded,
        label: l.arrManualImport,
        onTap: () => context.push(
          ArrImportTarget.folder(ArrKind.sonarr, s.path!).location,
        ),
      ),
    if (!isTvDevice && s.episodeFileCount > 0)
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
          _leave(context);
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
  Widget build(BuildContext context) {
    final host = ArrPaneHost.of(context);
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          automaticallyImplyLeading: host == null,
          leading: host == null ? null : _PaneClose(host: host),
        ),
        SliverFillRemaining(
          hasScrollBody: true,
          child: ErrorView(message: message, onRetry: onRetry),
        ),
      ],
    );
  }
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
          // On a TV the remote goes season to season, and RIGHT steps onto
          // a season's own buttons.
          leading: TvRowActions(child: IconButton(
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
          )),
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
                TvRowActions(child: IconButton(
                  tooltip: l.arrSearchSeason,
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => arrRun(
                    context,
                    () => c.searchSeason(seriesId, season.seasonNumber),
                    done: l.arrSearchStarted(c.kind.appName),
                  ),
                )),
                TvRowActions(child: Builder(
                  builder: (anchor) => IconButton(
                    tooltip: l.arrSeasonActions,
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => _openMenu(context, ref, anchor, c, name),
                  ),
                )),
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
        if (!isTvDevice && seasonFiles.isNotEmpty)
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
    // A remote has nothing to drag: on a TV the sheet opens tall, with the
    // remote on its first button.
    showDragHandle: !isTvDevice,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final theme = Theme.of(context);
        final c = client;
        void changed() => arrSeriesChanged(ref, e.seriesId);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: isTvDevice ? 0.92 : 0.6,
          maxChildSize: 0.92,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(20, isTvDevice ? 24 : 0, 20, 28),
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
                      autofocus: isTvDevice,
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
                TvReadStop(child: ArrFileCard(file: file)),
                // Deleting a file is for a phone or a desktop.
                if (c != null && !isTvDevice)
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
            // Lidarr's: "16bit", "44.1kHz", "1411 kbps", set the way the
            // video's bit depth is.
            mi.audioBits?.replaceFirstMapped(
              RegExp(r'(\d)\s*bit$'),
              (m) => '${m[1]}-bit',
            ),
            mi.audioSampleRate?.replaceFirstMapped(
              RegExp(r'(\d)\s*kHz$'),
              (m) => '${m[1]} kHz',
            ),
            mi.audioBitRate,
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
          const _BlocksSkeleton(height: 40)
        else if (items.isEmpty)
          Text(
            l.arrNoHistory,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          for (final h in items.take(50))
            // Each a stop on a TV, so the remote can read down the list.
            TvReadStop(
              child: _HistoryRow(item: h, episode: episodeLabel[h.episodeId]),
            ),
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
    // Lidarr's events are a track's: its title stands where an episode's
    // code would.
    final heading = [
      ?(episode ?? item.trackTitle),
      label,
      ?item.quality,
    ].join(' · ');
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
