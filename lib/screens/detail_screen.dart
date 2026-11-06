import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../services/tv_mode.dart';
import '../widgets/tv_focus.dart';
import '../state/downloads.dart';
import '../state/library_providers.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../state/seerr_providers.dart';
import '../state/arr_providers.dart';
import '../models/arr.dart';
import '../state/session_controller.dart';
import '../state/watchlist.dart';
import '../widgets/add_to_playlist.dart';
import '../widgets/context_menu.dart';
import '../widgets/item_actions.dart';
import '../widgets/score_pills.dart';
import '../widgets/series_download_sheet.dart';
import '../widgets/glass.dart';
import '../widgets/cast_button.dart';
import '../widgets/hover_pill_button.dart';
import '../widgets/motion.dart';
import '../widgets/media_cards.dart';
import '../widgets/media_image.dart';
import '../widgets/media_section.dart';
import '../widgets/detail_header.dart';
import '../widgets/meta_pill.dart';
import '../widgets/shimmer.dart';
import 'album_screen.dart';
import 'collection_view.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/ui_common.dart';
import '../api/jellyfin_client.dart';

/// Item detail: backdrop, metadata, overview, a Play/Resume action, and — for
/// series — an episode list. Tapping Play opens the media_kit player.
class DetailScreen extends ConsumerWidget {
  final BaseItemDto item;

  /// Download-local mode: the page renders from the passed (downloaded) item
  /// without hitting the server, shows ONLY downloaded episodes, and every
  /// action is download-only (Play offline, Mark Watched local, Remove
  /// download). Guards keep the normal (server) path completely unchanged.
  final bool downloadScoped;
  const DetailScreen(
      {super.key, required this.item, this.downloadScoped = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (downloadScoped) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: BackdropBackground(
          item: item,
          child: _DetailBody(item: item, downloadScoped: true),
        ),
      );
    }
    final detail = ref.watch(itemDetailProvider(item.id));
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: detail.when(
        loading: () => const _DetailSkeleton(),
        error: (e, _) => _ErrorState(message: '$e'),
        data: (full) => BackdropBackground(
          item: full,
          child: full.type == 'BoxSet'
              ? CollectionView(collection: full)
              : full.isAlbum
              ? AlbumView(album: full)
              // Preserve the opening item's kind (e.g. a recording) so a
              // download stores it, not the fetched content type.
              : _DetailBody(item: full, sourceType: item.type),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  final BaseItemDto item;
  final bool downloadScoped;
  // The kind of the item that opened this page (e.g. 'Recording'), preserved
  // for downloads because the fetched full item can report a plain video type.
  final String? sourceType;
  const _DetailBody(
      {required this.item, this.downloadScoped = false, this.sourceType});

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  BaseItemDto get item => widget.item;
  bool get downloadScoped => widget.downloadScoped;
  String? get sourceType => widget.sourceType;
  // The remote lands back here (the header Play) on UP from the top of the body.
  final FocusNode _playNode = FocusNode(debugLabel: 'detailPlay');
  final ScrollController _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    // Opened from Downloads while online: refresh the cached extra ratings so
    // the offline copy stays current (a no-op offline).
    if (downloadScoped) {
      Future.microtask(
          () => ref.read(downloadsProvider.notifier).refreshRatings(item));
    }
  }

  @override
  void dispose() {
    _playNode.dispose();
    _sc.dispose();
    super.dispose();
  }

  // UP from the top of the body scrolls the hero header back open and lands on
  // the header Play, so it stays reachable after the pinned app bar collapses
  // (whose own toolbar icons would otherwise grab UP first). Mid-content UP still
  // moves row-by-row, so this only kicks in at the top of the body. Off TV it's
  // a no-op.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!isTvDevice) return KeyEventResult.ignored;
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (e.logicalKey != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    final pf = FocusManager.instance.primaryFocus;
    if (pf == null || pf == _playNode) return KeyEventResult.ignored;
    final curTop = pf.rect.top;
    // Any focusable body row strictly above the current focus (ignoring the
    // pinned toolbar band and the header Play itself)? Then it's a normal
    // row-up move — let traversal handle it.
    const toolbarBand = 100.0;
    final scope = pf.nearestScope;
    if (scope != null) {
      for (final n in scope.traversalDescendants) {
        if (n == pf ||
            n == _playNode ||
            !n.canRequestFocus ||
            n.context == null) {
          continue;
        }
        final t = n.rect.top;
        if (t > toolbarBand && t < curTop - 8) return KeyEventResult.ignored;
      }
    }
    // Top of the body → open the header and focus Play.
    if (_sc.hasClients && _sc.offset > 0) {
      _sc
          .animateTo(
            0,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          )
          .then((_) {
            if (mounted) _playNode.requestFocus();
          });
    } else {
      _playNode.requestFocus();
    }
    return KeyEventResult.handled;
  }

  Future<void> _play(
    BuildContext context,
    WidgetRef ref,
    BaseItemDto playItem, {
    bool resume = true,
  }) async {
    await context.push(
      '/player',
      extra: resume ? playItem : (item: playItem, resume: false),
    );
    if (!context.mounted) return; // torn down while the player was open
    // Back from the player: refresh resume position + Home rows.
    ref.invalidate(itemDetailProvider(item.id));
    ref.invalidate(resumeItemsProvider);
    ref.invalidate(latestItemsProvider);
    ref.invalidate(nextUpItemsProvider);
    if (item.isSeries) {
      ref.invalidate(episodesProvider(item.id));
      ref.invalidate(nextUpProvider(item.id));
    }
  }

  // A grouped download parent: a series (episodes) or a music album (tracks).
  // Only ever a music album in download mode (albums route to AlbumView online).
  bool get _grouped => item.isSeries || item.type == 'MusicAlbum';

  // The downloaded children of this item (a series' episodes, an album's tracks)
  // or the single item, for download-local play/watched/remove actions.
  List<DownloadEntry> _downloadTargets(WidgetRef ref) {
    final map = ref.read(downloadsProvider).asData?.value ?? const {};
    final children = map.values.where((e) => e.seriesId == item.id).toList();
    if (children.isNotEmpty) return children;
    final e = map[item.id];
    return e != null ? [e] : const [];
  }

  bool _localWatched(WidgetRef ref) {
    final ctrl = ref.read(downloadsProvider.notifier);
    final targets = _downloadTargets(ref);
    return targets.isNotEmpty && targets.every(ctrl.isWatched);
  }

  Future<void> _togglePlayed(WidgetRef ref) async {
    if (downloadScoped) {
      final ctrl = ref.read(downloadsProvider.notifier);
      final targets = _downloadTargets(ref);
      final allWatched = targets.isNotEmpty && targets.every(ctrl.isWatched);
      for (final e in targets) {
        await ctrl.setWatched(e.itemId, !allWatched);
      }
      return;
    }
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    await ref
        .read(jellyfinClientProvider)
        .setPlayed(
          baseUrl: session.baseUrl,
          userId: session.userId,
          token: session.accessToken,
          itemId: item.id,
          played: !item.userData.played,
        );
    ref.invalidate(itemDetailProvider(item.id));
    ref.invalidate(resumeItemsProvider);
    ref.invalidate(latestItemsProvider);
    // Same refresh the player teardown does: Next Up and the episode list both
    // change when an episode's watched state does.
    ref.invalidate(nextUpItemsProvider);
    final seriesId = item.isSeries ? item.id : item.seriesId;
    if (seriesId != null) {
      ref.invalidate(itemDetailProvider(seriesId));
      ref.invalidate(episodesProvider(seriesId));
      ref.invalidate(nextUpProvider(seriesId));
    }
  }

  Future<void> _toggleFavorite(WidgetRef ref) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    await ref
        .read(jellyfinClientProvider)
        .setFavorite(
          baseUrl: session.baseUrl,
          userId: session.userId,
          token: session.accessToken,
          itemId: item.id,
          favorite: !item.userData.isFavorite,
        );
    ref.invalidate(itemDetailProvider(item.id));
  }

  Future<void> _toggleWatchlist(WidgetRef ref, bool inWatchlist) async {
    final watchlist = ref.read(watchlistProvider.notifier);
    if (inWatchlist) {
      await watchlist.remove(item.id);
    } else {
      await watchlist.add(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Download-local watched drives the header check when scoped; watch the
    // provider so the icon flips when it toggles.
    if (downloadScoped) ref.watch(downloadsProvider);
    final watched = downloadScoped ? _localWatched(ref) : item.userData.played;
    // Not meaningful in download-scoped mode (guarded below), but computing it
    // unconditionally keeps this a plain top-of-build value like the others.
    final inWatchlist = (ref.watch(watchlistProvider).asData?.value ?? const [])
        .any((e) => e.id == item.id);
    // Cast / Play-on stream from the server, so in download mode they only make
    // sense online. Normal mode is always "online" here (no behaviour change).
    final online = !downloadScoped ||
        ref.watch(sessionControllerProvider).asData?.value != null;
    // Scale the backdrop band with width so it keeps a consistent aspect and
    // isn't cropped into a thin sliver on wide windows. A taller band (closer
    // to the art's 16:9 shape) means less of the backdrop is cropped away.
    final headerHeight = (MediaQuery.sizeOf(context).width / 2.35).clamp(
      320.0,
      680.0,
    );

    // Ratings + meta for the header marquee, enriched with Seerr's RT audience
    // and IMDb scores when we have a TMDB id, so the header matches Seerr.
    final prefs = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final tmdb = int.tryParse(item.tmdbId ?? '');
    final seerrType = item.seerrMediaType;
    final ext = (tmdb != null && seerrType != null)
        ? ref
              .watch(
                jellyfinItemRatingsProvider((
                  mediaType: seerrType,
                  tmdbId: tmdb,
                )),
              )
              .asData
              ?.value
        : null;
    final mdb = (tmdb != null && seerrType != null)
        ? ref
              .watch(
                mdbListRatingsProvider((mediaType: seerrType, tmdbId: tmdb)),
              )
              .asData
              ?.value
        : null;
    // In download mode the live providers are empty offline, so fall back to the
    // ratings cached at download time (online, the live values win and refresh
    // the cache via initState).
    final cached = downloadScoped
        ? ref.watch(downloadRatingsProvider(item.id)).asData?.value
        : null;
    final ratingPills = scorePills(
      // Native first, then MDBList as gap-fill (never overwrites a real value),
      // then the offline cache.
      rtCritic: ext?.rtCritic ??
          item.criticRating?.round() ??
          mdb?.rtCritic ??
          cached?.rtCritic,
      rtAudience: ext?.rtAudience ?? mdb?.rtAudience ?? cached?.rtAudience,
      imdb: ext?.imdb ??
          (mdb?.imdb != null ? mdb!.imdb! / 10 : null) ??
          cached?.imdb,
      community: item.communityRating ??
          (mdb?.tmdb != null ? mdb!.tmdb! / 10 : null) ??
          cached?.community,
      letterboxd: mdb?.letterboxd ?? cached?.letterboxd,
      metacritic: mdb?.metacritic ?? cached?.metacritic,
      metacriticUser: mdb?.metacriticUser ?? cached?.metacriticUser,
      trakt: mdb?.trakt ?? cached?.trakt,
      rogerEbert: mdb?.rogerEbert ?? cached?.rogerEbert,
      myAnimeList: mdb?.myAnimeList ?? cached?.myAnimeList,
      prefs: prefs,
    );
    final metaLine = item.isEpisode
        ? _episodeLine(item)
        : [
            item.type == 'Series' ? l.detailSeries : l.detailMovie,
            if (item.productionYear != null) '${item.productionYear}',
            if (item.runtimeMinutes != null) fmtRuntime(item.runtimeMinutes!),
          ].join('  ·  ');

    // Actions as circular icons in the header on wide windows, as labelled
    // buttons in the body on narrow ones.
    final wideHeader = MediaQuery.sizeOf(context).width >= 620;
    // For a series, Play targets Next Up. When there isn't one — a recorded
    // series (which is how a recording opened from a library shows up), or
    // everything already watched — fall back to the first episode so Play is
    // never a silent dead button.
    final nextUp = item.isSeries
        ? ref.watch(nextUpProvider(item.id)).asData?.value
        : null;
    final seriesEpisodes = item.isSeries
        ? (ref.watch(episodesProvider(item.id)).asData?.value ??
              const <BaseItemDto>[])
        : const <BaseItemDto>[];
    // In download mode Play targets the first downloaded episode (a series) or
    // the downloaded item itself (a movie); the server next-up/episodes lists
    // aren't reachable offline.
    final downloadEps = downloadScoped
        ? (_downloadTargets(ref).toList()
          ..sort((a, b) {
            final s = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
            return s != 0
                ? s
                : (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
          }))
        : const <DownloadEntry>[];
    final playTarget = downloadScoped
        ? (_grouped
              ? (downloadEps.isEmpty
                    ? null
                    : _downloadEpisodeItem(downloadEps.first,
                        ref.read(downloadsProvider.notifier)
                            .isWatched(downloadEps.first)))
              : item)
        : (item.isSeries
              ? (nextUp ?? (seriesEpisodes.isEmpty ? null : seriesEpisodes.first))
              : item);
    final headerActionIcons = <Widget>[
      HeaderActionButton(
        icon: Icons.play_arrow_rounded,
        tooltip: playTarget == null
            ? l.commonPlay
            : (playTarget.canResume ? l.detailResume : l.commonPlay),
        primary: true,
        autofocus: isTvDevice,
        focusNode: isTvDevice ? _playNode : null,
        onTap: playTarget == null
            ? null
            : () => _play(context, ref, playTarget),
      ),
      if (!item.isSeries && item.canResume)
        HeaderActionButton(
          icon: Icons.replay_rounded,
          tooltip: l.detailPlayFromStart,
          onTap: () => _play(context, ref, item, resume: false),
        ),
      if (item.trailerUrl != null) _TrailerButton(item: item, header: true),
      if (!item.isAlbum) ...[
        // Play-on streams from the server, so in download mode it shows only
        // when online. The download button is dropped entirely here (the item
        // is already downloaded; removal lives in the overflow / episode menus).
        if (online) _RemoteButton(item: item, header: true),
        if (!downloadScoped)
          _DownloadButton(item: item, header: true, asType: sourceType),
      ],
    ];
    final headerActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < headerActionIcons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          headerActionIcons[i],
        ],
      ],
    );

    return Focus(
      onKeyEvent: _onKey,
      canRequestFocus: false,
      skipTraversal: true,
      child: CustomScrollView(
        controller: _sc,
        slivers: [
          SliverAppBar(
            expandedHeight: headerHeight,
            pinned: true,
            stretch: true,
            backgroundColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: watched ? l.detailMarkUnwatched : l.detailMarkWatched,
                icon: _PopIcon(
                  selected: watched,
                  icon: Icons.check_circle_rounded,
                  iconOff: Icons.check_circle_outline_rounded,
                ),
                onPressed: () => _togglePlayed(ref),
              ),
              // Favourite and Watchlist are both server writes (Watchlist via a
              // hidden playlist), so both are hidden in download-local mode.
              if (!downloadScoped) ...[
                IconButton(
                  tooltip: item.userData.isFavorite
                      ? l.detailRemoveFavorite
                      : l.detailAddFavorite,
                  icon: _PopIcon(
                    selected: item.userData.isFavorite,
                    icon: Icons.favorite_rounded,
                    iconOff: Icons.favorite_border_rounded,
                    selectedColor: Colors.redAccent,
                  ),
                  onPressed: () => _toggleFavorite(ref),
                ),
                IconButton(
                  tooltip: inWatchlist
                      ? l.detailRemoveFromWatchlist
                      : l.detailAddToWatchlist,
                  icon: _PopIcon(
                    selected: inWatchlist,
                    icon: Icons.bookmark_rounded,
                    iconOff: Icons.bookmark_border_rounded,
                    selectedColor: scheme.primary,
                  ),
                  onPressed: () => _toggleWatchlist(ref, inWatchlist),
                ),
              ],
              _ItemMenu(item: item, downloadScoped: downloadScoped),
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  MediaImage(
                    item: item,
                    landscape: true,
                    maxWidth: 1920,
                    alignment: const Alignment(0, -0.35),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                          scheme.surface.withValues(alpha: 0.6),
                        ],
                        stops: const [0, 0.45, 0.82, 1],
                      ),
                    ),
                  ),
                  DetailHeaderOverlay(
                    poster: Hero(
                      tag: 'art-${item.id}',
                      child: MediaImage(item: item),
                    ),
                    title: _DetailTitle(item: item, onDark: true),
                    cert: item.officialRating != null
                        ? CertBadge(text: item.officialRating!)
                        : null,
                    metaLine: metaLine,
                    ratings: ratingPills,
                    actions: wideHeader ? headerActions : null,
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!wideHeader) ...[
                    _ActionBar(
                      item: item,
                      downloadScoped: downloadScoped,
                      sourceType: sourceType,
                      onPlay: (playItem, {bool resume = true}) =>
                          _play(context, ref, playItem, resume: resume),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (item.overview != null && item.overview!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      item.overview!,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ],
                  if (item.genres.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: item.genres
                          .map(
                            (g) => TvFocusRing(
                              borderRadius: BorderRadius.circular(8),
                              child: ActionChip(
                                label: Text(g),
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    context.push('/genre', extra: g),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (item.people.isNotEmpty) _CastSection(people: item.people),
                ],
              ),
            ),
          ),
          // Next-up and More-Like-This are server-driven, so they're dropped in
          // download mode (only the episodes you've downloaded are shown).
          if (item.isSeries && !downloadScoped) _NextUpSection(seriesId: item.id),
          // A series' episodes, or (in download mode) an album's tracks.
          if (_grouped)
            _EpisodeList(
              seriesId: item.id,
              downloadScoped: downloadScoped,
              headerLabel: item.type == 'MusicAlbum' ? l.downloadsTracks : null,
              // A recorded series' episodes download as recordings.
              downloadAsType: sourceType == 'Recording' ? 'Recording' : null,
            ),
          if (!downloadScoped) _Extras(itemId: item.id),
          if (!item.isEpisode && !downloadScoped) _MoreLikeThis(itemId: item.id),
        ],
      ),
    );
  }

  static String _episodeLine(BaseItemDto item) {
    final s = item.parentIndexNumber, e = item.indexNumber;
    final se = (s != null && e != null) ? 'S$s:E$e · ' : '';
    return '$se${item.name}';
  }
}

class _EpisodeList extends ConsumerStatefulWidget {
  final String seriesId;
  // Download mode: show only the downloaded episodes; every row action is local.
  final bool downloadScoped;
  // Overrides the "Episodes" list header (e.g. "Tracks" for a music album).
  final String? headerLabel;
  // The kind to store when an episode is downloaded (e.g. 'Recording' when this
  // series was opened from the recordings context).
  final String? downloadAsType;
  const _EpisodeList(
      {required this.seriesId,
      this.downloadScoped = false,
      this.headerLabel,
      this.downloadAsType});

  @override
  ConsumerState<_EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends ConsumerState<_EpisodeList> {
  int? _season;

  String _seasonLabel(int n) {
    final l = AppLocalizations.of(context);
    return n == 0 ? l.detailSpecials : l.detailSeasonNumber(n);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.downloadScoped) {
      final map = ref.watch(downloadsProvider).asData?.value ??
          const <String, DownloadEntry>{};
      final ctrl = ref.read(downloadsProvider.notifier);
      final entries = map.values
          .where((e) =>
              e.status == DownloadStatus.complete &&
              e.seriesId == widget.seriesId)
          .toList();
      if (entries.isEmpty) return const SliverToBoxAdapter();
      final eps = entries
          .map((e) => _downloadEpisodeItem(e, ctrl.isWatched(e)))
          .toList()
        ..sort((a, b) {
          final s =
              (a.parentIndexNumber ?? 0).compareTo(b.parentIndexNumber ?? 0);
          return s != 0
              ? s
              : (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0);
        });
      return _buildList(eps);
    }
    final episodes = ref.watch(episodesProvider(widget.seriesId));
    return episodes.when(
      loading: () => const SliverToBoxAdapter(child: EpisodeListSkeleton()),
      error: (e, _) => SliverToBoxAdapter(child: _ErrorState(message: '$e')),
      data: (items) =>
          items.isEmpty ? const SliverToBoxAdapter() : _buildList(items),
    );
  }

  Widget _buildList(List<BaseItemDto> items) {
    final l = AppLocalizations.of(context);
    final seasons =
        items.map((e) => e.parentIndexNumber ?? 0).toSet().toList()..sort();
    final current = seasons.contains(_season) ? _season! : seasons.first;
    final shown = seasons.length > 1
        ? items.where((e) => (e.parentIndexNumber ?? 0) == current).toList()
        : items;
    return SliverList.builder(
          itemCount: shown.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: Row(
                  children: [
                    Text(
                      widget.headerLabel ?? l.detailEpisodes,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (seasons.length > 1)
                      TvFocusRing(
                        borderRadius: BorderRadius.circular(12),
                        child: DropdownButton<int>(
                          value: current,
                          underline: const SizedBox.shrink(),
                          borderRadius: BorderRadius.circular(12),
                          items: [
                            for (final s in seasons)
                              DropdownMenuItem(
                                value: s,
                                child: Text(_seasonLabel(s)),
                              ),
                          ],
                          onChanged: (v) => setState(() => _season = v),
                        ),
                      ),
                  ],
                ),
              );
            }
            final ep = shown[i - 1];
            if (widget.downloadScoped) {
              // Download-local row: tap or thumbnail plays the local file; the
              // menu offers Play / Mark Watched (local) / Remove download.
              final tile = HoverHighlight(
                child: _EpisodeTile(
                  episode: ep,
                  onPlay: () => context.push('/player', extra: ep),
                  onOpen: () => context.push('/player', extra: ep),
                ),
              );
              return Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.deferToChild,
                      onLongPressStart: isTvDevice
                          ? null
                          : (d) =>
                              _openDownloadEpisodeMenu(ep, d.globalPosition),
                      onSecondaryTapUp: isTvDevice
                          ? null
                          : (d) =>
                              _openDownloadEpisodeMenu(ep, d.globalPosition),
                      child: tile,
                    ),
                  ),
                  _EpisodeMenuButton(
                      onTap: (at) => _openDownloadEpisodeMenu(ep, at)),
                ],
              );
            }
            // Played/resume/next-up state can change whether we played the
            // episode or opened its page (and played from there), so refresh on
            // return from either.
            Future<void> refreshOnReturn() async {
              if (!mounted) return; // torn down while the pushed page was open
              ref.invalidate(episodesProvider(widget.seriesId));
              ref.invalidate(resumeItemsProvider);
              ref.invalidate(nextUpProvider(widget.seriesId));
            }

            final tile = HoverHighlight(
              child: _EpisodeTile(
                episode: ep,
                // Thumbnail (and the trailing play icon) play the episode
                // directly; the rest of the row opens its detail page — the
                // convention other Jellyfin clients use (issue #20).
                onPlay: () async {
                  await context.push('/player', extra: ep);
                  await refreshOnReturn();
                },
                onOpen: () async {
                  await context.push('/item', extra: ep);
                  await refreshOnReturn();
                },
              ),
            );
            // Per-episode context menu: a visible three-dot (a D-pad stop on TV,
            // a tap target on touch/desktop) plus long-press off TV.
            return Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.deferToChild,
                    onLongPressStart: isTvDevice
                        ? null
                        : (d) => _openEpisodeMenu(ep, d.globalPosition),
                    onSecondaryTapUp: isTvDevice
                        ? null
                        : (d) => _openEpisodeMenu(ep, d.globalPosition),
                    child: tile,
                  ),
                ),
                _EpisodeMenuButton(onTap: (at) => _openEpisodeMenu(ep, at)),
              ],
            );
          },
        );
  }

  void _openEpisodeMenu(BaseItemDto ep, Offset at) {
    // The deleted/played/favorite refresh rides on provider invalidation inside
    // the shared menu (episodesProvider + nextUp keyed off ep.seriesId).
    showItemActionsMenu(context, ref, ep,
        at: at, downloadAsType: widget.downloadAsType);
  }

  // Download-local episode menu: Play, Mark Watched (local), Remove download.
  // Nothing here touches the server copy.
  void _openDownloadEpisodeMenu(BaseItemDto ep, Offset at) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final ctrl = ref.read(downloadsProvider.notifier);
    final watched = ep.userData.played;
    showContextMenu(context, at: at, actions: [
      ContextMenuAction(
        icon: Icons.play_arrow_rounded,
        label: l.commonPlay,
        onTap: () => context.push('/player', extra: ep),
      ),
      ContextMenuAction(
        icon: watched
            ? Icons.check_circle_rounded
            : Icons.check_circle_outline_rounded,
        label: watched ? l.detailMarkUnwatched : l.detailMarkWatched,
        onTap: () => ctrl.setWatched(ep.id, !watched),
      ),
      ContextMenuAction(
        icon: Icons.delete_outline_rounded,
        label: l.detailRemoveDownload,
        color: cs.error,
        onTap: () => ctrl.delete(ep.id),
      ),
    ]);
  }
}

/// Builds a lightweight episode item from a download entry for the download
/// detail's episode list (played reflects the local watched flag).
BaseItemDto _downloadEpisodeItem(DownloadEntry e, bool watched) => BaseItemDto(
      id: e.itemId,
      name: e.name,
      type: 'Episode',
      seriesId: e.seriesId,
      seriesName: e.seriesName,
      indexNumber: e.episodeNumber,
      parentIndexNumber: e.seasonNumber,
      // Carries the episode still: loads from the server online, and matches the
      // cached copy offline (MediaImage falls back to episodes/<id>.jpg).
      primaryImageTag: e.imageTag,
      userData: UserItemData(played: watched),
    );

/// Per-episode three-dot: a D-pad focus stop on TV, an icon button off it.
class _EpisodeMenuButton extends StatelessWidget {
  final void Function(Offset at) onTap;
  const _EpisodeMenuButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (isTvDevice) {
      return TvFocusable(
        onTap: () => onTap(Offset.zero), // ignored on the TV sheet path
        scale: 1.1,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.more_vert_rounded),
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.more_vert_rounded),
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      onPressed: () {
        final box = context.findRenderObject() as RenderBox?;
        onTap(box == null
            ? Offset.zero
            : box.localToGlobal(box.size.center(Offset.zero)));
      },
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final BaseItemDto episode;
  final VoidCallback onPlay;
  final VoidCallback onOpen;
  const _EpisodeTile({
    required this.episode,
    required this.onPlay,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final played = episode.userData.played;
    final label = episode.indexNumber != null
        ? '${episode.indexNumber}. ${episode.name}'
        : episode.name;
    // On TV, TvFocusable is the single D-pad stop (ring + activate) and selecting
    // an episode plays it, unchanged. Off TV the row splits: the thumbnail and
    // trailing icon play, the rest of the row opens the episode page (issue #20).
    final thumbnail = SizedBox(
      width: 96,
      height: 54,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: MediaImage(item: episode, landscape: true),
          ),
          if (played)
            Positioned(
              top: 3,
              right: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.check_rounded,
                  size: 12,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          if (!played && episode.progress > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8),
                ),
                child: LinearProgressIndicator(
                  value: episode.progress,
                  minHeight: 3,
                ),
              ),
            ),
        ],
      ),
    );

    final playIcon = Icon(
      episode.canResume
          ? Icons.play_circle_outline_rounded
          : Icons.play_arrow_rounded,
    );

    return TvFocusable(
      onTap: onPlay,
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      scale: 1.0,
      child: ListTile(
        hoverColor: Colors.transparent, // HoverHighlight handles the hover tint
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        // Thumbnail plays the episode directly (off TV); on TV the enclosing
        // TvFocusable already plays, so leave the thumbnail as a plain image.
        leading: isTvDevice
            ? thumbnail
            : MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(onTap: onPlay, child: thumbnail),
              ),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: played ? TextStyle(color: scheme.onSurfaceVariant) : null,
        ),
        subtitle: episode.runtimeMinutes != null
            ? Text(
                l.detailRuntimeMinutes(episode.runtimeMinutes!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            : null,
        trailing: isTvDevice
            ? playIcon
            : IconButton(
                icon: playIcon,
                tooltip: l.commonPlay,
                onPressed: onPlay,
              ),
        // Off TV the row body opens the episode page; the thumbnail and trailing
        // button play. On TV the whole TvFocusable plays (unchanged).
        onTap: isTvDevice ? null : onOpen,
      ),
    );
  }
}

/// Download / offline-copy button reflecting the item's download state.
class _DownloadButton extends ConsumerWidget {
  final BaseItemDto item;
  final bool header;
  // Preserves the source item's kind (e.g. 'Recording') for the stored download,
  // since the fetched full item can report a plain content type instead.
  final String? asType;
  const _DownloadButton({required this.item, this.header = false, this.asType});

  Widget _btn({
    required IconData icon,
    required String tooltip,
    required String label,
    required VoidCallback? onTap,
    Widget? iconOverride,
  }) => header
      ? HeaderActionButton(
          icon: icon,
          tooltip: tooltip,
          label: label,
          onTap: onTap,
          iconOverride: iconOverride,
        )
      : HoverPillButton(
          icon: icon,
          label: label,
          onTap: onTap,
          iconWidget: iconOverride,
        );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // A series aggregates its episodes' states (there's no single series file):
    // download queues every episode, and the button shows the set's progress.
    if (item.isSeries) return _seriesButton(context, ref, l);
    final entry = ref.watch(downloadsProvider).asData?.value[item.id];
    if (entry == null) {
      return _btn(
        icon: Icons.download_rounded,
        tooltip: l.detailDownload,
        label: l.detailDownload,
        onTap: () => ref.read(downloadsProvider.notifier).download(item, asType: asType),
      );
    }
    switch (entry.status) {
      case DownloadStatus.downloading:
        return _btn(
          icon: Icons.download_rounded,
          tooltip: l.detailDownloadingTooltip,
          label: l.detailDownloading,
          onTap: null,
          iconOverride: AppSpinner.inline(
              value: entry.progress > 0 ? entry.progress : null,
              color: header ? Colors.white : null),
        );
      case DownloadStatus.complete:
        return _btn(
          icon: Icons.download_done_rounded,
          tooltip: l.detailDownloadedTooltip,
          label: l.detailDownloaded,
          onTap: () => _confirmDelete(context, ref),
        );
      case DownloadStatus.failed:
        return _btn(
          icon: Icons.error_outline_rounded,
          tooltip: l.detailDownloadFailedTooltip,
          label: l.commonRetry,
          onTap: () => ref.read(downloadsProvider.notifier).download(item, asType: asType),
        );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await confirm(context,
        title: l.detailRemoveDownload,
        message: l.detailRemoveOfflineCopy(item.name),
        confirmLabel: l.commonRemove);
    if (ok) ref.read(downloadsProvider.notifier).delete(item.id);
  }

  /// The series-level download button. It has no file of its own, so its state
  /// is the aggregate of its episodes: download queues the missing episodes, a
  /// spinner shows the set's combined progress, and once every episode is in it
  /// offers to remove the whole set.
  Widget _seriesButton(BuildContext context, WidgetRef ref, AppLocalizations l) {
    final episodes =
        ref.watch(episodesProvider(item.id)).asData?.value ?? const [];
    final map = ref.watch(downloadsProvider).asData?.value ?? const {};
    Widget downloadBtn() => _btn(
          icon: Icons.download_rounded,
          tooltip: l.detailDownload,
          label: l.detailDownload,
          onTap: () => showSeriesDownloadSheet(context, item, asType: asType),
        );
    if (episodes.isEmpty) return downloadBtn();

    final entries = [for (final e in episodes) map[e.id]]
        .whereType<DownloadEntry>()
        .toList();
    final done =
        entries.where((e) => e.status == DownloadStatus.complete).length;
    final inFlight =
        entries.where((e) => e.status == DownloadStatus.downloading).toList();

    if (done == episodes.length) {
      return _btn(
        icon: Icons.download_done_rounded,
        tooltip: l.detailDownloadedTooltip,
        label: l.detailDownloaded,
        onTap: () => _confirmDeleteSeries(context, ref, episodes),
      );
    }
    if (inFlight.isNotEmpty) {
      final progress =
          (done + inFlight.fold<double>(0, (a, e) => a + e.progress)) /
              episodes.length;
      return _btn(
        icon: Icons.download_rounded,
        tooltip: l.detailDownloadingTooltip,
        label: l.detailDownloading,
        onTap: null,
        iconOverride: AppSpinner.inline(
            value: progress > 0 ? progress : null,
            color: header ? Colors.white : null),
      );
    }
    return downloadBtn();
  }

  Future<void> _confirmDeleteSeries(
      BuildContext context, WidgetRef ref, List<BaseItemDto> episodes) async {
    final l = AppLocalizations.of(context);
    final ok = await confirm(context,
        title: l.detailRemoveDownload,
        message: l.detailRemoveOfflineCopy(item.name),
        confirmLabel: l.commonRemove);
    if (!ok) return;
    final notifier = ref.read(downloadsProvider.notifier);
    for (final e in episodes) {
      await notifier.delete(e.id);
    }
  }
}

/// "Play on Another Device" — casts the item to another controllable player.
class _RemoteButton extends ConsumerWidget {
  final BaseItemDto item;
  final bool header;
  const _RemoteButton({required this.item, this.header = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (header) {
      return HeaderActionButton(
        icon: Icons.settings_remote_rounded,
        tooltip: l.detailPlayOnAnotherDevice,
        label: l.detailCastAction,
        onTap: () => _showDevices(context, ref),
      );
    }
    return HoverPillButton(
      icon: Icons.settings_remote_rounded,
      label: l.detailCastAction,
      onTap: () => _showDevices(context, ref),
    );
  }

  Future<void> _showDevices(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final client = ref.read(jellyfinClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    List<Map<String, dynamic>> devices;
    try {
      devices = await client.getControllableSessions(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
      );
    } catch (e) {
      showErrorOn(messenger, e);
      return;
    }
    if (!context.mounted) return;
    if (devices.isEmpty) {
      showSnackOn(messenger, l.detailNoControllableDevices);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          // Cap the sheet and let the device list scroll rather than overflow.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  l.detailPlayOnAnotherDeviceTitle,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in devices)
                      ListTile(
                        leading: const Icon(Icons.cast_rounded),
                        title: Text(
                          '${d['DeviceName'] ?? d['Client'] ?? l.detailDevice}',
                        ),
                        subtitle: Text('${d['Client'] ?? ''}'),
                        onTap: () async {
                          Navigator.pop(ctx);
                          try {
                            await client.playOnSession(
                              baseUrl: session.baseUrl,
                              token: session.accessToken,
                              sessionId: '${d['Id']}',
                              itemId: item.id,
                            );
                            showSnackOn(messenger, l.detailPlayingOn(
                                    '${d['DeviceName'] ?? l.detailDevice}',
                                  ),);
                          } catch (e) {
                            showErrorOn(messenger, e);
                          }
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overflow menu with management actions, shown only for actions the user's
/// policy permits (delete / metadata refresh).
class _ItemMenu extends ConsumerWidget {
  final BaseItemDto item;
  // Download mode: the only action is removing the offline copy.
  final bool downloadScoped;
  const _ItemMenu({required this.item, this.downloadScoped = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (downloadScoped) {
      return PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (_) => _removeDownload(context, ref),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'remove',
            child: ListTile(
              leading: Icon(Icons.download_done_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: Text(l.detailRemoveDownload,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      );
    }
    final session = ref.watch(sessionControllerProvider).asData?.value;
    if (session == null) return const SizedBox.shrink();
    final user = ref.watch(currentUserProvider).asData?.value;
    final canDelete =
        (user?.enableContentDeletion ?? false) ||
        (user?.isAdministrator ?? false) ||
        session.canDelete;
    final canRefresh = (user?.isAdministrator ?? false) || session.isAdmin;
    // "Add to Playlist" is available to everyone; refresh/delete are gated.
    final arrKey = _arrKey(item);
    final match = arrKey == null
        ? null
        : ref.watch(arrMatchProvider(arrKey)).asData?.value;
    final app = match?.kind.appName;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) => _onSelected(context, ref, session, v),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'playlist',
          child: ListTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: Text(l.detailAddToPlaylist),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        // Sonarr and Radarr, when connected: the title's page there, a
        // search for what's missing or a better copy, or adding it.
        if (match != null && match.id != null) ...[
          PopupMenuItem(
            value: 'arr-manage',
            child: ListTile(
              leading: const Icon(Icons.dns_rounded),
              title: Text(l.arrManageIn(app!)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'arr-search',
            child: ListTile(
              leading: const Icon(Icons.search_rounded),
              title: Text(match.kind == ArrKind.radarr
                  ? l.arrSearchMovie
                  : l.arrSearchMonitored),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (match.kind == ArrKind.radarr)
            PopupMenuItem(
              value: 'arr-interactive',
              child: ListTile(
                leading: const Icon(Icons.manage_search_rounded),
                title: Text(l.arrInteractiveSearch),
                contentPadding: EdgeInsets.zero,
              ),
            ),
        ] else if (match != null)
          PopupMenuItem(
            value: 'arr-add',
            child: ListTile(
              leading: const Icon(Icons.add_rounded),
              title: Text(l.arrAddTo(app!)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canRefresh)
          PopupMenuItem(
            value: 'refresh',
            child: ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: Text(l.detailRefreshMetadata),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canDelete)
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l.commonDelete,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  Future<void> _removeDownload(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ctrl = ref.read(downloadsProvider.notifier);
    final confirmed = await confirm(context,
        title: l.detailRemoveDownload,
        message: l.detailRemoveOfflineCopy(item.name),
        confirmLabel: l.commonRemove);
    if (!confirmed) return;
    if (item.isSeries) {
      await ctrl.deleteSeries(item.id);
    } else {
      await ctrl.delete(item.id);
    }
    // Nothing left to show once the download's gone.
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _onSelected(
    BuildContext context,
    WidgetRef ref,
    dynamic session,
    String value,
  ) async {
    final l = AppLocalizations.of(context);
    final client = ref.read(jellyfinClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (value.startsWith('arr-')) {
      await _arrAction(context, ref, value);
      return;
    }
    if (value == 'playlist') {
      await showAddToPlaylistSheet(
        context,
        ref,
        itemIds: [item.id],
        label: item.name,
      );
    } else if (value == 'refresh') {
      try {
        await client.refreshItem(
          baseUrl: session.baseUrl,
          token: session.accessToken,
          itemId: item.id,
        );
        showSnackOn(messenger, l.detailMetadataRefreshStarted,
            kind: SnackKind.success);
      } catch (e) {
        showErrorOn(messenger, e);
      }
    } else if (value == 'delete') {
      final confirmed = await confirm(context,
          title: l.detailDeleteItem,
          message: l.detailDeleteConfirm(item.name),
          confirmLabel: l.commonDelete,
          destructive: true);
      if (!confirmed) return;
      try {
        await client.deleteItem(
          baseUrl: session.baseUrl,
          token: session.accessToken,
          itemId: item.id,
        );
        ref.invalidate(resumeItemsProvider);
        ref.invalidate(latestItemsProvider);
        ref.invalidate(favoriteItemsProvider);
        if (context.mounted) {
          context.pop();
          showSnackOn(messenger, l.detailDeleted(item.name),
              kind: SnackKind.success);
        }
      } catch (e) {
        showErrorOn(messenger, e);
      }
    }
  }
}

/// Which app manages [item] and the id it's known by there: TMDB for a
/// movie (Radarr), TVDB for a show (Sonarr). Null for anything else.
({ArrKind kind, int providerId})? _arrKey(BaseItemDto item) {
  if (item.type == 'Movie') {
    final id = int.tryParse(item.tmdbId ?? '');
    return id == null ? null : (kind: ArrKind.radarr, providerId: id);
  }
  if (item.isSeries) {
    final id = int.tryParse(item.tvdbId ?? '');
    return id == null ? null : (kind: ArrKind.sonarr, providerId: id);
  }
  return null;
}

extension on _ItemMenu {
  Future<void> _arrAction(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    final key = _arrKey(item);
    if (key == null) return;
    final match = ref.read(arrMatchProvider(key)).asData?.value;
    if (match == null) return;
    final l = AppLocalizations.of(context);
    final id = match.id;
    final movie = match.kind == ArrKind.radarr;
    switch (value) {
      case 'arr-manage':
        if (id != null) {
          context.push(movie ? '/arr/movie/$id' : '/arr/series/$id');
        }
      case 'arr-interactive':
        if (id != null) context.push('/arr/releases?movie=$id');
      case 'arr-add':
        final term = movie ? 'tmdb:${key.providerId}' : 'tvdb:${key.providerId}';
        context.push(
          '/arr/add/${movie ? 'movie' : 'series'}?term=${Uri.encodeQueryComponent(term)}',
        );
      case 'arr-search':
        if (id == null) return;
        final messenger = ScaffoldMessenger.of(context);
        try {
          if (movie) {
            await ref.read(radarrClientProvider)?.searchMovie(id);
          } else {
            await ref.read(sonarrClientProvider)?.searchSeries(id);
          }
          showSnackOn(messenger, l.arrSearchStarted(match.kind.appName),
              kind: SnackKind.success);
        } catch (e) {
          showSnackOn(messenger, e.toString(), kind: SnackKind.error);
        }
    }
  }
}

/// An icon that pops (scale-fades) when its selected state flips.
class _PopIcon extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final IconData iconOff;
  final Color? selectedColor;

  const _PopIcon({
    required this.selected,
    required this.icon,
    required this.iconOff,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: Icon(
        selected ? icon : iconOff,
        key: ValueKey(selected),
        color: selected ? selectedColor : null,
      ),
    );
  }
}

class _CastSection extends StatelessWidget {
  final List<Person> people;
  const _CastSection({required this.people});

  @override
  Widget build(BuildContext context) {
    // Billed cast first (Actors), then the rest of the crew.
    final cast = [...people]
      ..sort((a, b) {
        int rank(Person p) => p.type == 'Actor' ? 0 : 1;
        return rank(a).compareTo(rank(b));
      });
    final shown = cast.take(30).toList();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final Widget castRow = SizedBox(
      height: 158,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _PersonCard(person: shown[i]),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              l.detailCastCrew,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // On TV wrap the cast strip as a focus row (like the media rows) so LEFT
        // escapes to the rail and the focused card scrolls into view.
        isTvDevice ? TvFocusRow(child: castRow) : castRow,
      ],
    );
  }
}

class _PersonCard extends StatefulWidget {
  final Person person;
  const _PersonCard({required this.person});

  @override
  State<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<_PersonCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final person = widget.person;
    final role = person.role?.isNotEmpty == true
        ? person.role!
        : (person.type ?? '');
    final onTap = person.id.isEmpty
        ? null
        : () => context.push('/person', extra: person);
    final card = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: person.id.isEmpty ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 100,
          child: Column(
            children: [
              AnimatedScale(
                scale: _hover ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: _PersonAvatar(
                  person: person,
                  size: 84,
                  ring: _hover ? theme.colorScheme.primary : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                person.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (role.isNotEmpty)
                Text(
                  role,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    // On TV the card is one D-pad target (TvFocusable is a no-op off TV).
    // Non-navigable people (no id) stay unfocusable.
    if (onTap == null) return card;
    return TvFocusable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: card,
    );
  }
}

class _PersonAvatar extends ConsumerWidget {
  final Person person;
  final double size;
  final Color? ring;
  const _PersonAvatar({required this.person, this.size = 64, this.ring});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final client = ref.watch(jellyfinClientProvider);
    final headers = ref.watch(imageHeadersProvider);
    final cache = ref.watch(downloadImageCacheProvider);
    final File? local =
        person.id.isEmpty ? null : cache?.file('people/${person.id}.jpg');

    Widget placeholder() => Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.person_rounded,
        color: scheme.onSurfaceVariant,
        size: size * 0.5,
      ),
    );

    Widget fileOrPlaceholder() => local != null
        ? Image.file(local,
            fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder())
        : placeholder();

    Widget inner;
    if (session == null ||
        person.primaryImageTag == null ||
        person.id.isEmpty) {
      // Offline (or no server photo): use the cached cast photo if we have one.
      inner = fileOrPlaceholder();
    } else {
      final url = client.imageUrl(
        baseUrl: session.baseUrl,
        itemId: person.id,
        type: 'Primary',
        tag: person.primaryImageTag,
        maxHeight: 200,
      );
      inner = Image.network(
        url,
        fit: BoxFit.cover,
        headers: headers,
        errorBuilder: (_, _, _) => fileOrPlaceholder(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring != null ? Border.all(color: ring!, width: 2.5) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: SizedBox(width: size, height: size, child: inner),
      ),
    );
  }
}

class _NextUpSection extends ConsumerWidget {
  final String seriesId;
  const _NextUpSection({required this.seriesId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nextUp = ref.watch(nextUpProvider(seriesId));
    return nextUp.when(
      loading: () => const SliverToBoxAdapter(),
      error: (_, _) => const SliverToBoxAdapter(),
      data: (ep) {
        if (ep == null) return const SliverToBoxAdapter();
        final l = AppLocalizations.of(context);
        final theme = Theme.of(context);
        final label = (ep.parentIndexNumber != null && ep.indexNumber != null)
            ? 'S${ep.parentIndexNumber}:E${ep.indexNumber} · ${ep.name}'
            : ep.name;
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.detailNextUp,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TvFocusRing(
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      await context.push('/player', extra: ep);
                      if (!context.mounted) return;
                      ref.invalidate(nextUpProvider(seriesId));
                      ref.invalidate(episodesProvider(seriesId));
                      ref.invalidate(resumeItemsProvider);
                    },
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 150,
                            height: 84,
                            child: MediaImage(item: ep, landscape: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    size: 18,
                                    color: theme.colorScheme.primary,
                                  ),
                                  Text(
                                    ep.canResume
                                        ? l.detailResume
                                        : l.commonPlay,
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Premium metadata row: year, runtime, community rating, and an outlined
/// certification badge, as pills.
/// A soft rounded metadata pill.
/// The primary action row (play/resume + watched/favorite + remote/download),
/// wrapping onto multiple lines when the column is narrow.
class _ActionBar extends ConsumerWidget {
  final BaseItemDto item;
  final bool downloadScoped;
  final String? sourceType;
  final void Function(BaseItemDto playItem, {bool resume}) onPlay;
  const _ActionBar(
      {required this.item,
      required this.onPlay,
      this.downloadScoped = false,
      this.sourceType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // In download mode Cast/Play-on need the server, so they only appear online.
    final online = !downloadScoped ||
        ref.watch(sessionControllerProvider).asData?.value != null;

    // A series (episodes) or, in download mode, a music album (tracks): Play
    // targets the first child.
    final grouped = item.isSeries || (downloadScoped && item.type == 'MusicAlbum');
    if (grouped) {
      if (downloadScoped) {
        // Play the first downloaded child. Cast targets it too, and only when
        // online (it streams from the server); no download button.
        final map = ref.watch(downloadsProvider).asData?.value ??
            const <String, DownloadEntry>{};
        final ctrl = ref.read(downloadsProvider.notifier);
        final eps = map.values
            .where((e) =>
                e.status == DownloadStatus.complete && e.seriesId == item.id)
            .toList()
          ..sort((a, b) {
            final s = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
            return s != 0
                ? s
                : (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
          });
        final first = eps.isEmpty ? null : eps.first;
        final firstItem =
            first == null ? null : _downloadEpisodeItem(first, ctrl.isWatched(first));
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            HoverPillButton(
              primary: true,
              icon: Icons.play_arrow_rounded,
              label: l.commonPlay,
              onTap: firstItem == null ? null : () => onPlay(firstItem),
            ),
            if (online && firstItem != null) _ChromecastButton(target: firstItem),
            if (item.trailerUrl != null) _TrailerButton(item: item),
          ],
        );
      }
      final next = ref.watch(nextUpProvider(item.id)).asData?.value;
      final code =
          (next?.parentIndexNumber != null && next?.indexNumber != null)
          ? 'S${next!.parentIndexNumber}:E${next.indexNumber}'
          : null;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          HoverPillButton(
            primary: true,
            icon: Icons.play_arrow_rounded,
            label: next == null
                ? l.commonPlay
                : (next.canResume
                      ? (code == null
                            ? l.detailResume
                            : l.detailResumeCode(code))
                      : (code == null ? l.commonPlay : l.detailPlayCode(code))),
            onTap: next == null ? null : () => onPlay(next),
          ),
          if (next != null) _ChromecastButton(target: next),
          if (item.trailerUrl != null) _TrailerButton(item: item),
          _DownloadButton(item: item, asType: sourceType),
        ],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        HoverPillButton(
          primary: true,
          icon: Icons.play_arrow_rounded,
          label: item.canResume
              ? l.detailResumeFrom(_fmtTicks(item.resumePositionTicks))
              : l.commonPlay,
          onTap: () => onPlay(item),
        ),
        if (item.canResume)
          HoverPillButton(
            icon: Icons.replay_rounded,
            label: l.detailPlayFromStart,
            onTap: () => onPlay(item, resume: false),
          ),
        if (item.trailerUrl != null) _TrailerButton(item: item),
        if (!item.isAlbum) ...[
          // Cast self-hides without a route; Play-on needs a session. In
          // download mode both are gated on being online. Download button is
          // dropped there (already downloaded; remove via the overflow menu).
          if (online) _ChromecastButton(target: item),
          if (online) _RemoteButton(item: item),
          if (!downloadScoped) _DownloadButton(item: item, asType: sourceType),
        ],
      ],
    );
  }
}

/// A Chromecast button on the detail page: casts [target] to a Cast device and
/// opens the player so its cast remote is shown. Hides itself where Cast isn't
/// available (desktop, or no Google Play Services), so it only appears when
/// there's actually something to cast to.
class _ChromecastButton extends ConsumerWidget {
  final BaseItemDto target;
  const _ChromecastButton({required this.target});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CastButton(
      pill: true,
      title: target.name,
      resolve: () async {
        final session = ref.read(sessionControllerProvider).asData?.value;
        if (session == null) return null;
        try {
          return await ref
              .read(jellyfinClientProvider)
              .castStream(
                baseUrl: session.baseUrl,
                userId: session.userId,
                token: session.accessToken,
                itemId: target.id,
              );
        } catch (_) {
          return null;
        }
      },
      onStarted: () => context.push('/player', extra: target),
    );
  }
}

/// Compact trailer button that sits alongside Play / Cast / Download.
class _TrailerButton extends StatelessWidget {
  final BaseItemDto item;
  final bool header;
  const _TrailerButton({required this.item, this.header = false});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    void open() => context.push(
      '/trailer',
      extra: (url: item.trailerUrl!, title: item.name),
    );
    if (header) {
      return HeaderActionButton(
        icon: Icons.movie_outlined,
        tooltip: l.detailWatchTrailer,
        label: l.detailTrailer,
        onTap: open,
      );
    }
    return HoverPillButton(
      icon: Icons.movie_outlined,
      label: l.detailTrailer,
      onTap: open,
    );
  }
}

/// An outlined content-rating (certification) badge, e.g. "TV-14".
/// Loading placeholder for the detail screen (backdrop band + poster + lines),
/// so it doesn't flash a bare spinner then jump to the full layout.
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        ShimmerBox(
          height: (w / 2.35).clamp(320.0, 680.0),
          borderRadius: BorderRadius.zero,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShimmerBox(width: 150, height: 225),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ShimmerBox(width: 240, height: 34),
                    const SizedBox(height: 14),
                    ShimmerBox(width: w * 0.4, height: 16),
                    const SizedBox(height: 18),
                    const ShimmerBox(width: 150, height: 48),
                    const SizedBox(height: 20),
                    ShimmerBox(width: w * 0.5, height: 14),
                    const SizedBox(height: 8),
                    ShimmerBox(width: w * 0.45, height: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

String _fmtTicks(int ticks) {
  final total = ticks ~/ 10000000; // ticks(100ns) -> seconds
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// The detail title: the show/movie's logo art when the server has one, else a
/// bold text title (matching the Home hero's treatment).
class _DetailTitle extends ConsumerWidget {
  final BaseItemDto item;

  /// Rendered over the backdrop: white text with a shadow, for legibility.
  final bool onDark;
  const _DetailTitle({required this.item, this.onDark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text = Text(
      item.isEpisode ? (item.seriesName ?? item.name) : item.name,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: onDark ? Colors.white : null,
        shadows: onDark
            ? const [Shadow(blurRadius: 8, color: Colors.black)]
            : null,
      ),
    );
    // Episodes render the SERIES name as the title; make it tap through to the
    // series page (requested in #16). Mouse cursor is the desktop affordance.
    if (item.isEpisode) {
      final seriesId = item.seriesId;
      if (seriesId == null) return text;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => context.push('/item',
              extra: BaseItemDto(
                  id: seriesId,
                  name: item.seriesName ?? item.name,
                  type: 'Series')),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: item.seriesName ?? item.name),
              // A small chevron so the title reads as navigable on touch too,
              // not just via the desktop hover cursor.
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 26,
                      color: onDark ? Colors.white : null,
                      shadows: onDark
                          ? const [Shadow(blurRadius: 8, color: Colors.black)]
                          : null),
                ),
              ),
            ]),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: onDark ? Colors.white : null,
              shadows: onDark
                  ? const [Shadow(blurRadius: 8, color: Colors.black)]
                  : null,
            ),
          ),
        ),
      );
    }
    final session = ref.watch(sessionControllerProvider).asData?.value;
    if (!item.hasLogo || session == null) return text;

    final url = ref
        .watch(jellyfinClientProvider)
        .imageUrl(
          baseUrl: session.baseUrl,
          itemId: item.logoItemId!,
          type: 'Logo',
          tag: item.logoTag,
          maxHeight: 150,
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 78, maxWidth: 440),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Image.network(
          url,
          headers: ref.watch(imageHeadersProvider),
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          errorBuilder: (_, _, _) => text,
        ),
      ),
    );
  }
}

/// A row of the title's extras: behind the scenes, deleted scenes, interviews,
/// featurettes, and trailer files held on the server. Hidden when there are
/// none, which is most of the time.
class _Extras extends ConsumerWidget {
  final String itemId;
  const _Extras({required this.itemId});

  /// Jellyfin's ExtraType, in the user's language. Unknown kinds fall back to
  /// no label rather than showing the raw enum name.
  static String? _kind(AppLocalizations l, String? type) => switch (type) {
        'Trailer' => l.extraTypeTrailer,
        'BehindTheScenes' => l.extraTypeBehindTheScenes,
        'DeletedScene' => l.extraTypeDeletedScene,
        'Interview' => l.extraTypeInterview,
        'Scene' => l.extraTypeScene,
        'Featurette' => l.extraTypeFeaturette,
        'Short' => l.extraTypeShort,
        'Clip' => l.extraTypeClip,
        'Sample' => l.extraTypeSample,
        _ => null,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extras = ref.watch(extrasProvider(itemId));
    // No skeleton here: unlike More Like This, most titles have no extras at
    // all, so a placeholder would flash on every page for nothing.
    final items = extras.asData?.value ?? const <BaseItemDto>[];
    if (items.isEmpty) return const SliverToBoxAdapter();
    final l = AppLocalizations.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: MediaSection(
          title: l.detailExtras,
          height: 210,
          children: [
            for (final e in items)
              ExtraCard(
                item: e,
                kind: _kind(l, e.extraType),
                onTap: () => context.push('/player', extra: e),
              ),
          ],
        ),
      ),
    );
  }
}

/// A "More Like This" row of similar titles at the foot of the detail page.
class _MoreLikeThis extends ConsumerWidget {
  final String itemId;
  const _MoreLikeThis({required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final similar = ref.watch(similarItemsProvider(itemId));
    // Show a section skeleton while loading instead of vanishing silently.
    if (similar.isLoading && !similar.hasValue) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(bottom: 24),
          child: SectionSkeleton(height: 324),
        ),
      );
    }
    final items = similar.asData?.value ?? const <BaseItemDto>[];
    if (items.isEmpty) return const SliverToBoxAdapter();
    final l = AppLocalizations.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: MediaSection(
          title: l.detailMoreLikeThis,
          height: 324,
          children: [
            for (final it in items)
              PosterCard(
                item: it,
                onTap: () => context.push('/item', extra: it),
              ),
          ],
        ),
      ),
    );
  }
}
