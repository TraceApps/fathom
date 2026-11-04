import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../services/tv_mode.dart';
import '../state/arr_providers.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/detail_header.dart';
import '../widgets/error_view.dart';
import '../widgets/hover_pill_button.dart';
import '../widgets/meta_pill.dart';

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
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (client != null)
                          _OpenIn(client: client, slug: m.titleSlug),
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
                        if (m.movieFile != null)
                          ArrFileCard(file: m.movieFile!)
                        else
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
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (client != null)
                          _OpenIn(client: client, slug: s.titleSlug),
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

  const _Header({
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
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the title in the app's own web page, for what Fathom doesn't do
/// yet. Not on TV, which has no browser to open it in.
class _OpenIn extends StatelessWidget {
  final ArrClient client;
  final String? slug;
  const _OpenIn({required this.client, required this.slug});

  @override
  Widget build(BuildContext context) {
    if (isTvDevice || slug == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return HoverPillButton(
      icon: Icons.open_in_new_rounded,
      label: l.arrOpenIn(client.kind.appName),
      onTap: () => launchUrl(
        Uri.parse(client.webUrl(slug)),
        mode: LaunchMode.externalApplication,
      ),
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
        hasScrollBody: false,
        child: ErrorView(message: message, onRetry: onRetry),
      ),
    ],
  );
}

/// A season of a show, opening into its episodes.
class _SeasonTile extends StatelessWidget {
  final ArrSeason season;
  final List<ArrEpisode> episodes;
  final Map<int, ArrFile> files;
  final bool initiallyExpanded;

  const _SeasonTile({
    required this.season,
    required this.episodes,
    required this.files,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
          leading: Icon(
            season.monitored
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            color: season.monitored ? scheme.primary : scheme.outline,
          ),
          title: Text(
            season.seasonNumber == 0
                ? l.arrSpecials
                : l.arrSeason(season.seasonNumber),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              l.arrEpisodesOf(season.episodeFileCount, season.episodeCount),
              if (season.sizeOnDisk > 0) arrSize(season.sizeOnDisk),
            ].join(' · '),
          ),
          trailing: SizedBox(
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
          children: [
            for (final e in episodes)
              _EpisodeRow(
                episode: e,
                file: e.episodeFileId == null ? null : files[e.episodeFileId],
              ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  final ArrEpisode episode;
  final ArrFile? file;
  const _EpisodeRow({required this.episode, required this.file});

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
      onTap: () => _showEpisode(context, episode, file),
    );
  }
}

void _showEpisode(BuildContext context, ArrEpisode e, ArrFile? file) {
  final l = AppLocalizations.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
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
            const SizedBox(height: 18),
            ArrFact(
              label: l.arrMonitored,
              value: e.monitored ? l.arrYes : l.arrNo,
            ),
            const SizedBox(height: 14),
            Text(l.arrFile, style: arrSectionStyle(theme)),
            const SizedBox(height: 8),
            if (file != null)
              ArrFileCard(file: file)
            else
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
    final (String label, IconData icon, Color color) = switch (item.eventType) {
      'grabbed' => (
        l.arrEventGrabbed,
        Icons.cloud_download_rounded,
        arrUnreleasedColor,
      ),
      'downloadFolderImported' ||
      'seriesFolderImported' ||
      'movieFolderImported' => (
        l.arrEventImported,
        Icons.download_done_rounded,
        arrDownloadedColor,
      ),
      'downloadFailed' => (
        l.arrEventFailed,
        Icons.error_rounded,
        arrMissingColor,
      ),
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
      'downloadIgnored' => (
        l.arrEventIgnored,
        Icons.block_rounded,
        scheme.outline,
      ),
      _ => (l.arrEventOther, Icons.history_rounded, scheme.outline),
    };
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
