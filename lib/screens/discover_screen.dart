import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/status_colors.dart';
import '../api/error_text.dart';
import '../api/seerr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';
import '../data/seerr_companies.dart';
import '../models/seerr_custom_slider.dart';
import '../models/seerr_genre.dart';
import '../models/seerr_request.dart';
import '../models/seerr_result.dart';
import '../models/arr.dart';
import '../services/tv_mode.dart';
import '../state/arr_providers.dart';
import '../state/preferences.dart';
import '../state/seerr_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/page_width.dart';
import '../widgets/reorder.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/app_snack.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/cached_image.dart';
import '../widgets/context_menu.dart';
import '../widgets/search_field.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/hover_pill_button.dart';
import '../widgets/media_section.dart';
import '../widgets/tv_focus.dart';
import '../widgets/media_cards.dart';
import '../widgets/motion.dart';
import '../widgets/seerr_add_slider_dialog.dart';
import '../widgets/seerr_avatar.dart';
import '../widgets/seerr_edit_request_dialog.dart';
import '../widgets/seerr_poster_card.dart';
import '../widgets/shimmer.dart';
import '../widgets/app_spinner.dart';
import '../widgets/ui_common.dart';

/// Seerr Discover: browse trending / popular and request titles.
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final configured = ref.watch(seerrConfiguredProvider);
    if (!configured) {
      return Scaffold(
        appBar: AppBar(
            leading: mobileDrawerLeading(context),
            title: Text(l.browseDiscover)),
        body: EmptyState(
          icon: Icons.travel_explore_rounded,
          title: l.browseConnectSeerr,
          message: l.browseConnectSeerrMessage,
          action: FilledButton(
            onPressed: () => context.push('/seerr-settings'),
            child: Text(l.browseSetUp),
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: mobileDrawerLeading(context),
          title: Text(l.browseDiscover),
          actions: [
            // Only meaningful on the Discover tab, so it appears there alone.
            Builder(builder: (context) {
              final controller = DefaultTabController.of(context);
              return AnimatedBuilder(
                animation: controller,
                builder: (context, _) => controller.index == 0
                    ? IconButton(
                        tooltip: l.browseCustomizeDiscover,
                        icon: const Icon(Icons.tune_rounded),
                        onPressed: () => context.push('/seerr-layout'),
                      )
                    : const SizedBox.shrink(),
              );
            }),
            IconButton(
              tooltip: l.browseSettings,
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => context.push('/seerr-settings'),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l.seerrTabBrowse),
              Tab(text: l.commonSearch),
              Tab(text: l.browseRequests),
            ],
          ),
        ),
        body: const TabBarView(
          // Each tab gets its own raster layer, so the switch animation
          // composites cached textures instead of repainting the content.
          children: [
            RepaintBoundary(child: _DiscoverHome()),
            RepaintBoundary(child: _SeerrSearchTab()),
            RepaintBoundary(child: _RequestsTab()),
          ],
        ),
      ),
    );
  }
}

/// The Seerr Discover rows and their titles, in the same set as the Jellyseerr
/// web home. The order shown, and which are hidden, come from preferences and
/// are edited on the Customize Discover screen.
Map<String, String> _seerrRowTitles(AppLocalizations l) => <String, String>{
      'recentlyAdded': l.browseRecentlyAdded,
      'recentRequests': l.browseRecentRequests,
      'trending': l.browseTrending,
      'popularMovies': l.browsePopularMovies,
      'movieGenres': l.browseMovieGenres,
      'upcomingMovies': l.browseUpcomingMovies,
      'studios': l.browseStudios,
      'popularSeries': l.browsePopularSeries,
      'seriesGenres': l.browseSeriesGenres,
      'upcomingSeries': l.browseUpcomingSeries,
      'networks': l.browseNetworks,
    };

/// The built-in Discover rows, in default order.
const kSeerrBuiltinRows = <String>[
  'recentlyAdded',
  'recentRequests',
  'trending',
  'popularMovies',
  'movieGenres',
  'upcomingMovies',
  'studios',
  'popularSeries',
  'seriesGenres',
  'upcomingSeries',
  'networks',
];

List<SeerrCustomSlider> _customSliders(Prefs p) =>
    [for (final m in p.seerrCustomSliders) SeerrCustomSlider.fromMap(m)];

/// Every valid row id for a given prefs: the built-ins plus any custom sliders.
List<String> _knownRows(Prefs p) =>
    [...kSeerrBuiltinRows, for (final c in _customSliders(p)) 'custom:${c.id}'];

/// Resolves the saved order + hidden set into the list of row ids to show.
/// Unknown ids (from an older or newer build) are dropped, and any known row
/// missing from a saved order is appended so new rows still appear.
List<String> orderedSeerrRows(
  List<String> order,
  List<String> hidden, {
  Iterable<String> known = kSeerrBuiltinRows,
}) {
  final knownSet = known.toSet();
  final seen = <String>{};
  final ordered = <String>[
    for (final id in order)
      if (knownSet.contains(id) && seen.add(id)) id,
    for (final id in known)
      if (seen.add(id)) id,
  ];
  final hiddenSet = hidden.toSet();
  return [for (final id in ordered) if (!hiddenSet.contains(id)) id];
}

/// Jellyseerr-style Discover home: the rows in the user's chosen order.
class _DiscoverHome extends ConsumerWidget {
  const _DiscoverHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final customs = {for (final c in _customSliders(p)) 'custom:${c.id}': c};
    final rows = orderedSeerrRows(p.seerrRowOrder, p.seerrHiddenRows,
        known: _knownRows(p));
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        for (final id in rows)
          if (customs[id] != null)
            _CustomRow(slider: customs[id]!)
          else
            _seerrSection(l, id),
      ],
    );
  }
}

/// A row backed by a user-created slider (genre or keyword search).
class _CustomRow extends ConsumerWidget {
  final SeerrCustomSlider slider;
  const _CustomRow({required this.slider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = switch (slider.type) {
      'movieGenre' => ref.watch(seerrGenreResultsProvider(
          (mediaType: 'movie', genreId: slider.genreId, sortBy: null))),
      'tvGenre' => ref.watch(seerrGenreResultsProvider(
          (mediaType: 'tv', genreId: slider.genreId, sortBy: null))),
      _ => ref.watch(seerrKeywordProvider(slider.data)),
    };
    return async.when(
      loading: () =>
          _RowShell(title: slider.title, child: const SectionSkeleton(height: 300)),
      error: (e, _) =>
          _RowShell(title: slider.title, child: const SectionError()),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return _RowShell(
          title: slider.title,
          child: _HList(
            itemCount: list.length,
            itemBuilder: (context, i) =>
                EntranceFade(
                    index: i,
                    onceKey: '${list[i].mediaType}${list[i].tmdbId}',
                    child: SeerrPosterCard(result: list[i])),
          ),
        );
      },
    );
  }
}

/// Builds the row widget for a section id.
Widget _seerrSection(AppLocalizations l, String id) => switch (id) {
      'recentlyAdded' => const _RecentlyAddedRow(),
      'recentRequests' => const _RecentRequestsRow(),
      'trending' => _SeerrRow(title: l.browseTrending, provider: _Row.trending),
      'popularMovies' =>
        _SeerrRow(title: l.browsePopularMovies, provider: _Row.popularMovies),
      'movieGenres' => _GenreRow(title: l.browseMovieGenres, mediaType: 'movie'),
      'upcomingMovies' => _SeerrRow(
          title: l.browseUpcomingMovies, provider: _Row.upcomingMovies),
      'studios' =>
        _CompanyRow(title: l.browseStudios, companies: kSeerrStudios),
      'popularSeries' =>
        _SeerrRow(title: l.browsePopularSeries, provider: _Row.popularSeries),
      'seriesGenres' => _GenreRow(title: l.browseSeriesGenres, mediaType: 'tv'),
      'upcomingSeries' => _SeerrRow(
          title: l.browseUpcomingSeries, provider: _Row.upcomingSeries),
      'networks' =>
        _CompanyRow(title: l.browseNetworks, companies: kSeerrNetworks),
      _ => const SizedBox.shrink(),
    };

enum _Row {
  trending('trending'),
  popularMovies('popularMovies'),
  upcomingMovies('upcomingMovies'),
  popularSeries('popularSeries'),
  upcomingSeries('upcomingSeries');

  final String key;
  const _Row(this.key);
}

class _SeerrRow extends ConsumerWidget {
  final String title;
  final _Row provider;
  const _SeerrRow({required this.title, required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = switch (provider) {
      _Row.trending => ref.watch(seerrTrendingProvider),
      _Row.popularMovies => ref.watch(seerrMoviesProvider),
      _Row.upcomingMovies => ref.watch(seerrUpcomingMoviesProvider),
      _Row.popularSeries => ref.watch(seerrTvProvider),
      _Row.upcomingSeries => ref.watch(seerrUpcomingTvProvider),
    };

    return async.when(
      loading: () => _RowShell(
        title: title,
        child: const SectionSkeleton(height: 300),
      ),
      error: (e, _) => _RowShell(title: title, child: const SectionError()),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return _RowShell(
          title: title,
          onSeeAll: () => context.push('/seerr-category',
              extra: (key: provider.key, title: title)),
          child: _HList(
            itemCount: list.length,
            itemBuilder: (context, i) => EntranceFade(
              index: i,
              onceKey: '${list[i].mediaType}${list[i].tmdbId}',
              child: SeerrPosterCard(result: list[i]),
            ),
          ),
        );
      },
    );
  }
}

/// Recently added, available titles. The `/media` endpoint gives only ids and
/// status, so each card resolves its own poster from the detail endpoint.
class _RecentlyAddedRow extends ConsumerWidget {
  const _RecentlyAddedRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(seerrRecentlyAddedProvider);
    return async.when(
      loading: () => _RowShell(
          title: l.browseRecentlyAdded,
          child: const SectionSkeleton(height: 300)),
      error: (e, _) =>
          _RowShell(title: l.browseRecentlyAdded, child: const SectionError()),
      data: (refs) {
        if (refs.isEmpty) return const SizedBox.shrink();
        return _RowShell(
          title: l.browseRecentlyAdded,
          child: _HList(
            itemCount: refs.length,
            itemBuilder: (context, i) => EntranceFade(
              index: i,
              onceKey: 'ra${refs[i].mediaType}${refs[i].tmdbId}',
              child: _EnrichedPosterCard(
                  mediaType: refs[i].mediaType, tmdbId: refs[i].tmdbId),
            ),
          ),
        );
      },
    );
  }
}

/// The most recent requests, as Jellyseerr-style landscape request cards
/// (backdrop, title, requester, status).
class _RecentRequestsRow extends ConsumerWidget {
  const _RecentRequestsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(seerrRecentRequestsProvider);
    return async.when(
      loading: () => _RowShell(
          title: l.browseRecentRequests,
          height: 230,
          child: const SectionSkeleton(height: 230)),
      error: (e, _) => _RowShell(
          title: l.browseRecentRequests,
          height: 230,
          child: const SectionError()),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return _RowShell(
          title: l.browseRecentRequests,
          height: 230,
          child: _HList(
            itemCount: list.length,
            itemBuilder: (context, i) => EntranceFade(
              index: i,
              onceKey: 'rq${list[i].id}',
              child: _RequestCard(request: list[i]),
            ),
          ),
        );
      },
    );
  }
}

/// A Jellyseerr-style request card: backdrop behind, a left column with the
/// year, title, requester and status, and the poster on the right.
class _RequestCard extends ConsumerStatefulWidget {
  final SeerrRequest request;
  const _RequestCard({required this.request});

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _hover = false;

  (String, Color) _status(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = widget.request;
    if (r.isDeclined) {
      return (l.browseDeclined, Theme.of(context).colorScheme.error);
    }
    if (r.isFailed) return (l.browseFailed, const Color(0xFFEF4444));
    return switch (r.mediaStatus) {
      5 => (l.browseAvailable, const Color(0xFF22C55E)),
      4 => (l.browsePartiallyAvailable, const Color(0xFF14B8A6)),
      3 => (l.browseProcessing, const Color(0xFF3B82F6)),
      2 => (l.browsePending, const Color(0xFFF59E0B)),
      _ => (r.isPending ? l.browsePending : l.browseApproved,
          const Color(0xFFF59E0B)),
    };
  }

  Future<void> _act(String action) async {
    final l = AppLocalizations.of(context);
    final client = ref.read(seerrClientProvider);
    if (client == null) return;
    final r = widget.request;
    final title = ref
            .read(seerrDetailProvider(
                (mediaType: r.mediaType, tmdbId: r.tmdbId)))
            .asData
            ?.value
            .title ??
        (r.mediaType == 'tv' ? l.browseThisSeries : l.browseThisMovie);
    try {
      switch (action) {
        case 'approve':
          await client.approveRequest(r.id);
        case 'decline':
          await client.declineRequest(r.id);
        case 'retry':
          await client.retryRequest(r.id);
      }
      ref.invalidate(seerrRecentRequestsProvider);
      ref.invalidate(seerrPendingRequestsProvider);
      ref.invalidate(seerrRequestsProvider);
      final done = switch (action) {
        'approve' => l.browseApprovedTitle(title),
        'decline' => l.browseDeclinedTitle(title),
        'retry' => l.browseRetryingTitle(title),
        _ => l.browseDone,
      };
      if (mounted) showSnack(context, done, kind: SnackKind.success);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Inline Approve/Decline (pending) or Retry (failed) pills, for a manager.
  Widget _actions() {
    final l = AppLocalizations.of(context);
    final r = widget.request;
    final perms = ref.watch(seerrPermissionsProvider).value ?? 0;
    if (!seerrCan(perms, kSeerrManageRequests)) return const SizedBox.shrink();
    final pills = <Widget>[];
    if (r.isPending) {
      pills.add(HoverPillButton(
          icon: Icons.check_rounded,
          label: l.browseApprove,
          color: const Color(0xFF22C55E),
          onTap: () => _act('approve')));
      pills.add(HoverPillButton(
          icon: Icons.close_rounded,
          label: l.browseDecline,
          color: const Color(0xFFEF4444),
          onTap: () => _act('decline')));
    } else if (r.isFailed) {
      pills.add(HoverPillButton(
          icon: Icons.refresh_rounded,
          label: l.commonRetry,
          color: Theme.of(context).colorScheme.primary,
          onTap: () => _act('retry')));
    }
    if (pills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: pills),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = widget.request;
    final key = (mediaType: r.mediaType, tmdbId: r.tmdbId);
    final detail = ref.watch(seerrDetailProvider(key)).asData?.value;
    final title = detail?.title ??
        (r.mediaType == 'tv'
            ? l.browseSeriesNumber(r.tmdbId)
            : l.browseMovieNumber(r.tmdbId));
    final (statusLabel, statusColor) = _status(context);

    final onTap = detail == null
        ? null
        : () => context.push('/seerr-detail',
            extra: SeerrResult(
              tmdbId: r.tmdbId,
              mediaType: r.mediaType,
              title: title,
              posterPath: detail.posterPath,
              backdropPath: detail.backdropPath,
              status: r.mediaStatus,
            ));
    final card = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: _hover ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: 344,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black
                        .withValues(alpha: _hover ? 0.45 : 0.3),
                    blurRadius: _hover ? 18 : 10,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (detail?.backdropUrl != null)
                  CachedImage(
                      url: detail!.backdropUrl!,
                      errorBuilder: (_) => const SizedBox()),
                // Darken, heavier on the left where the text sits.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.88),
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _info(theme, title, statusLabel, statusColor)),
                      const SizedBox(width: 12),
                      if (detail?.posterUrl != null)
                        // Fixed width (not AspectRatio, whose width tracked the
                        // card's height and could squeeze the text column until
                        // the status pill overflowed). Cover-crops to fill height.
                        SizedBox(
                          width: 92,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedImage(
                                url: detail!.posterUrl!,
                                errorBuilder: (_) => const SizedBox()),
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
    );
    if (onTap == null) return card;
    return TvFocusable(
        onTap: onTap, borderRadius: BorderRadius.circular(14), child: card);
  }

  Widget _info(
      ThemeData theme, String title, String statusLabel, Color statusColor) {
    final l = AppLocalizations.of(context);
    final r = widget.request;
    final detail = ref.watch(seerrDetailProvider(
            (mediaType: r.mediaType, tmdbId: r.tmdbId)))
        .asData
        ?.value;
    final year = detail?.year;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (year != null)
          Text(year,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        Text(title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        const Spacer(),
        if (r.requestedBy != null)
          Row(
            children: [
              SeerrAvatar(
                name: r.requestedBy!,
                avatarUrl: seerrAvatarUrl(
                    ref.read(seerrClientProvider)?.baseUrl ?? '',
                    r.requestedByAvatar),
                radius: 11,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(r.requestedBy!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        if (r.mediaType == 'tv' && r.seasons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Text('${l.browseSeasonLabel} ',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                Flexible(
                  child: Text(r.seasons.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Text('${l.browseStatus}  ',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              // Flexible + ellipsis so a long status ("Partially Available")
              // shrinks to fit the narrow info column instead of overflowing.
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: onStatus(statusColor),
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
        _actions(),
      ],
    );
  }
}

/// A poster card whose title and artwork are resolved from the detail endpoint,
/// for rows that start from a bare (mediaType, tmdbId) reference.
class _EnrichedPosterCard extends ConsumerWidget {
  final String mediaType;
  final int tmdbId;
  const _EnrichedPosterCard({required this.mediaType, required this.tmdbId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async =
        ref.watch(seerrDetailProvider((mediaType: mediaType, tmdbId: tmdbId)));
    final d = async.asData?.value;
    if (d == null) {
      // Loading or failed: hold the slot with a poster-shaped shimmer that fills
      // the row, matching the card layout so nothing reflows as cards resolve.
      return const SizedBox(
        width: 176,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: ShimmerBox()),
            SizedBox(height: 6),
            ShimmerBox(
                height: 12,
                width: 120,
                borderRadius: BorderRadius.all(Radius.circular(6))),
          ],
        ),
      );
    }
    return SeerrPosterCard(
      result: SeerrResult(
        tmdbId: d.tmdbId,
        mediaType: d.mediaType,
        title: d.title,
        overview: d.overview,
        posterPath: d.posterPath,
        backdropPath: d.backdropPath,
        status: d.status,
        voteAverage: d.voteAverage,
      ),
    );
  }
}

/// A row of genre tiles (artwork with the genre name), from the genre slider.
class _GenreRow extends ConsumerWidget {
  final String title;
  final String mediaType; // 'movie' | 'tv'
  const _GenreRow({required this.title, required this.mediaType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = mediaType == 'tv'
        ? ref.watch(seerrTvGenresProvider)
        : ref.watch(seerrMovieGenresProvider);
    return async.when(
      loading: () => _RowShell(
          title: title,
          height: 130,
          child: const SectionSkeleton(height: 130)),
      error: (e, _) =>
          _RowShell(title: title, height: 130, child: const SectionError()),
      data: (genres) {
        if (genres.isEmpty) return const SizedBox.shrink();
        return _RowShell(
          title: title,
          height: 130,
          child: _HList(
            itemCount: genres.length,
            itemBuilder: (context, i) =>
                EntranceFade(
                    index: i,
                    onceKey: 'g${genres[i].mediaType}${genres[i].id}',
                    child: _GenreCard(genre: genres[i])),
          ),
        );
      },
    );
  }
}

class _GenreCard extends StatelessWidget {
  final SeerrGenre genre;
  const _GenreCard({required this.genre});

  @override
  Widget build(BuildContext context) {
    // A colour derived from the genre name, not a movie's artwork: a genre
    // isn't one film, so a plain varying-colour tile reads more honestly.
    final hue = (genre.name.hashCode.abs() % 360).toDouble();
    final top = HSLColor.fromAHSL(1, hue, 0.52, 0.42).toColor();
    final bottom = HSLColor.fromAHSL(1, (hue + 24) % 360, 0.55, 0.28).toColor();
    return SizedBox(
      width: 220,
      child: HoverPosterArt(
        borderRadius: 14,
        onTap: () => context.push('/seerr-genre',
            extra: (
              mediaType: genre.mediaType,
              genreId: genre.id,
              title: genre.name,
            )),
        art: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [top, bottom],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                genre.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of studio or network logo cards, from the curated list. Static data,
/// so there's no loading state.
class _CompanyRow extends StatelessWidget {
  final String title;
  final List<SeerrCompany> companies;
  const _CompanyRow({required this.title, required this.companies});

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      title: title,
      height: 130,
      child: _HList(
        itemCount: companies.length,
        itemBuilder: (context, i) =>
            EntranceFade(
                index: i,
                onceKey: 'co${companies[i].kind}${companies[i].id}',
                child: _CompanyCard(company: companies[i])),
      ),
    );
  }
}

/// A studio/network tile: the duotone logo centered on a surface card, matching
/// Jellyseerr's CompanyCard. Tapping opens that company's titles.
class _CompanyCard extends StatelessWidget {
  final SeerrCompany company;
  const _CompanyCard({required this.company});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 220,
      child: HoverPosterArt(
        borderRadius: 14,
        onTap: () => context.push('/seerr-company',
            extra: (kind: company.kind, id: company.id, title: company.name)),
        art: Container(
          color: scheme.surfaceContainerHigh,
          padding: const EdgeInsets.all(28),
          alignment: Alignment.center,
          child: CachedImage(
            url: company.imageUrl,
            fit: BoxFit.contain,
            // If the logo can't load, the name keeps the tile meaningful.
            errorBuilder: (_) => Center(
              child: Text(
                company.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontal row that scrolls with the mouse wheel, not only by dragging.
/// On desktop a vertical wheel over the row moves it sideways; once it reaches
/// an end the event falls through so the page keeps scrolling. Without this,
/// most of a long row (all the studios, all the networks) stays unreachable.
class _HList extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  const _HList({required this.itemCount, required this.itemBuilder});

  @override
  State<_HList> createState() => _HListState();
}

class _HListState extends State<_HList> {
  final _controller = ScrollController();
  bool _hover = false;
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // An arrow only means something if there's room to move that way, so each is
  // shown only when the row can actually scroll in that direction.
  void _updateArrows() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final left = pos.pixels > pos.minScrollExtent + 1;
    final right = pos.pixels < pos.maxScrollExtent - 1;
    if (left != _canLeft || right != _canRight) {
      setState(() {
        _canLeft = left;
        _canRight = right;
      });
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !_controller.hasClients) return;
    final primary = e.scrollDelta.dy;
    if (primary == 0) return; // a horizontal wheel: let the list handle it
    final pos = _controller.position;
    final atStart = _controller.offset <= pos.minScrollExtent;
    final atEnd = _controller.offset >= pos.maxScrollExtent;
    // At an end in the wheel's direction, let the page scroll instead.
    if ((primary < 0 && atStart) || (primary > 0 && atEnd)) return;
    _controller.jumpTo((_controller.offset + primary)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent));
  }

  void _scrollBy(int sign) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final target = (_controller.offset + sign * pos.viewportDimension * 0.85)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _controller.animateTo(target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerSignal: _onSignal,
        child: NotificationListener<ScrollMetricsNotification>(
          // Fires when the content size changes (async rows filling in), so the
          // arrows appear/disappear without needing a scroll first.
          onNotification: (_) {
            _updateArrows();
            return false;
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ListView.separated(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.itemCount,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: widget.itemBuilder,
              ),
              ScrollAffordance(
                  visible: _hover && _canLeft,
                  left: true,
                  onTap: () => _scrollBy(-1)),
              ScrollAffordance(
                  visible: _hover && _canRight,
                  left: false,
                  onTap: () => _scrollBy(1)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowShell extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onSeeAll;
  final double height;
  const _RowShell(
      {required this.title,
      required this.child,
      this.onSeeAll,
      this.height = 300});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          trailing: onSeeAll == null
              ? null
              : TextButton(
                  onPressed: onSeeAll,
                  child: Text(AppLocalizations.of(context).browseSeeAll),
                ),
        ),
        SizedBox(height: height, child: child),
      ],
    );
  }
}

/// Full grid for one Discover category (opened from a row's "See all").
class SeerrCategoryScreen extends ConsumerWidget {
  final String categoryKey;
  final String title;
  const SeerrCategoryScreen(
      {super.key, required this.categoryKey, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = switch (categoryKey) {
      'popularMovies' => seerrMoviesProvider,
      'popularSeries' => seerrTvProvider,
      'upcomingMovies' => seerrUpcomingMoviesProvider,
      'upcomingSeries' => seerrUpcomingTvProvider,
      _ => seerrTrendingProvider,
    };
    final async = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: async.when(
        loading: () => const PosterGridSkeleton(),
        error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(provider),
        ),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.movie_filter_rounded,
                title: AppLocalizations.of(context).browseNothingToShow)
            : _SeerrResultGrid(list: list),
      ),
    );
  }
}

/// Full grid for one genre, opened from a genre-slider tile.
/// The TMDB sort options offered on a filterable grid, per media type.
/// A function taking [AppLocalizations] so the labels can be localized.
List<(String, String)> _sortOptions(AppLocalizations l, String mediaType) => [
      ('popularity.desc', l.browseSortPopularity),
      (
        mediaType == 'tv' ? 'first_air_date.desc' : 'primary_release_date.desc',
        l.browseSortNewest
      ),
      ('vote_average.desc', l.browseSortTopRated),
    ];

/// A sort menu for the filterable grids.
class _SortAction extends StatelessWidget {
  final String mediaType;
  final String value;
  final ValueChanged<String> onChanged;
  const _SortAction(
      {required this.mediaType, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final options = _sortOptions(l, mediaType);
    final label = options.firstWhere((o) => o.$1 == value,
        orElse: () => options.first);
    return PopupMenuButton<String>(
      tooltip: l.browseSort,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final o in options)
          PopupMenuItem(
            value: o.$1,
            child: Row(
              children: [
                Icon(o.$1 == value
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded),
                const SizedBox(width: 10),
                Text(o.$2),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          const Icon(Icons.sort_rounded, size: 20),
          const SizedBox(width: 6),
          Text(label.$2),
        ]),
      ),
    );
  }
}

class SeerrGenreScreen extends ConsumerStatefulWidget {
  final String mediaType;
  final int genreId;
  final String title;
  const SeerrGenreScreen({
    super.key,
    required this.mediaType,
    required this.genreId,
    required this.title,
  });

  @override
  ConsumerState<SeerrGenreScreen> createState() => _SeerrGenreScreenState();
}

class _SeerrGenreScreenState extends ConsumerState<SeerrGenreScreen> {
  String _sortBy = 'popularity.desc';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(seerrGenreResultsProvider((
      mediaType: widget.mediaType,
      genreId: widget.genreId,
      sortBy: _sortBy,
    )));
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        _SortAction(
            mediaType: widget.mediaType,
            value: _sortBy,
            onChanged: (v) => setState(() => _sortBy = v)),
      ]),
      body: async.when(
        loading: () => const PosterGridSkeleton(),
        error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(seerrGenreResultsProvider(( mediaType: widget.mediaType, genreId: widget.genreId, sortBy: _sortBy, ))),
        ),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.movie_filter_rounded,
                title: l.browseNothingToShow)
            : _SeerrResultGrid(list: list),
      ),
    );
  }
}

/// Full grid for one studio or network, opened from a company card.
class SeerrCompanyScreen extends ConsumerStatefulWidget {
  final String kind; // 'studio' | 'network'
  final int id;
  final String title;
  const SeerrCompanyScreen({
    super.key,
    required this.kind,
    required this.id,
    required this.title,
  });

  @override
  ConsumerState<SeerrCompanyScreen> createState() => _SeerrCompanyScreenState();
}

class _SeerrCompanyScreenState extends ConsumerState<SeerrCompanyScreen> {
  String _sortBy = 'popularity.desc';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mediaType = widget.kind == 'network' ? 'tv' : 'movie';
    final async = ref.watch(
        seerrCompanyResultsProvider((kind: widget.kind, id: widget.id, sortBy: _sortBy)));
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        _SortAction(
            mediaType: mediaType,
            value: _sortBy,
            onChanged: (v) => setState(() => _sortBy = v)),
      ]),
      body: async.when(
        loading: () => const PosterGridSkeleton(),
        error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(seerrCompanyResultsProvider((kind: widget.kind, id: widget.id, sortBy: _sortBy))),
        ),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.movie_filter_rounded,
                title: l.browseNothingToShow)
            : _SeerrResultGrid(list: list),
      ),
    );
  }
}

/// Reorder and toggle the Seerr Discover rows, matching the Jellyseerr web
/// customization. Saved to preferences.
class SeerrDiscoverLayoutScreen extends ConsumerWidget {
  const SeerrDiscoverLayoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final rowTitles = _seerrRowTitles(l);
    final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final c = ref.read(preferencesProvider.notifier);
    final customs = {for (final s in _customSliders(p)) 'custom:${s.id}': s};
    // Every known row, in saved order, so hidden ones still show here to toggle.
    final rows = orderedSeerrRows(p.seerrRowOrder, const [],
        known: _knownRows(p));
    final hidden = p.seerrHiddenRows.toSet();

    void deleteCustom(String id) {
      final sid = id.substring('custom:'.length);
      c.edit((x) => x.copyWith(
            seerrCustomSliders: [
              for (final m in x.seerrCustomSliders)
                if ('${m['id']}' != sid) m,
            ],
            seerrRowOrder:
                x.seerrRowOrder.where((r) => r != id).toList(),
            seerrHiddenRows:
                x.seerrHiddenRows.where((r) => r != id).toList(),
          ));
    }

    final scheme = Theme.of(context).colorScheme;

    void move(int from, int to) {
      if (to < 0 || to >= rows.length) return;
      final list = [...rows];
      list.insert(to, list.removeAt(from));
      c.edit((x) => x.copyWith(seerrRowOrder: list));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.browseCustomizeDiscover),
        actions: [
          TextButton(
            onPressed: () => c.edit((x) => x.copyWith(
                seerrRowOrder: kDefaultSeerrRows, seerrHiddenRows: const [])),
            child: Text(l.commonReset),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSlider(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.browseAddSlider),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Text(
                  l.browseReorderHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: PageWidth(builder: (_, inset) => ReorderableListView(
                  buildDefaultDragHandles: false,
                  padding: pageInsets(inset, const EdgeInsets.only(top: 4, bottom: 96)),
                  // ignore: deprecated_member_use
                  onReorder: (oldIndex, newIndex) {
                    final list = [...rows];
                    if (newIndex > oldIndex) newIndex -= 1;
                    list.insert(newIndex, list.removeAt(oldIndex));
                    c.edit((x) => x.copyWith(seerrRowOrder: list));
                  },
                  children: [
                    for (final (i, id) in rows.indexed)
                      Container(
                        key: ValueKey(id),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 5),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color:
                                  scheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 16, 6, 16),
                                child: Icon(Icons.drag_indicator,
                                    color: dragGripColor(context)),
                              ),
                            ),
                            Expanded(
                              child: Opacity(
                                opacity: hidden.contains(id) ? 0.45 : 1,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      customs[id]?.title ??
                                          rowTitles[id] ??
                                          id,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15),
                                    ),
                                    if (customs[id] != null)
                                      Text(l.browseCustomSlider,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.keyboard_arrow_up_rounded),
                              tooltip: l.browseMoveUp,
                              onPressed: i == 0 ? null : () => move(i, i - 1),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon:
                                  const Icon(Icons.keyboard_arrow_down_rounded),
                              tooltip: l.browseMoveDown,
                              onPressed: i == rows.length - 1
                                  ? null
                                  : () => move(i, i + 1),
                            ),
                            if (customs[id] != null)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline_rounded),
                                tooltip: l.browseDeleteSlider,
                                color: scheme.error,
                                onPressed: () => deleteCustom(id),
                              ),
                            const SizedBox(width: 4),
                            Switch(
                              value: !hidden.contains(id),
                              onChanged: (visible) {
                                final next = {...hidden};
                                if (visible) {
                                  next.remove(id);
                                } else {
                                  next.add(id);
                                }
                                c.edit((x) => x.copyWith(
                                    seerrHiddenRows: next.toList()));
                              },
                            ),
                            const SizedBox(width: 10),
                          ],
                        ),
                      ),
                  ],
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addSlider(BuildContext context, WidgetRef ref) async {
    final slider = await showSeerrAddSliderDialog(context, ref);
    if (slider == null) return;
    final c = ref.read(preferencesProvider.notifier);
    c.edit((x) => x.copyWith(
          seerrCustomSliders: [...x.seerrCustomSliders, slider.toMap()],
          // Place new sliders at the end of the visible order.
          seerrRowOrder: [
            ...orderedSeerrRows(x.seerrRowOrder, const [],
                known: _knownRows(x)),
            'custom:${slider.id}',
          ],
        ));
  }
}

class _SeerrSearchTab extends ConsumerStatefulWidget {
  const _SeerrSearchTab();
  @override
  ConsumerState<_SeerrSearchTab> createState() => _SeerrSearchTabState();
}

class _SeerrSearchTabState extends ConsumerState<_SeerrSearchTab> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(seerrQueryProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(seerrSearchProvider);
    final query = ref.watch(seerrQueryProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SearchField(
            controller: _controller,
            hint: l.browseSeerrSearchHint,
            onChanged: (v) => ref.read(seerrQueryProvider.notifier).set(v),
            onClear: () => ref.read(seerrQueryProvider.notifier).set(''),
          ),
        ),
        Expanded(
          child: query.trim().isEmpty
              ? EmptyState(
                  icon: Icons.search_rounded,
                  title: l.browseSearchSeerrTitle,
                  message: l.browseSearchSeerrMessage,
                )
              : async.when(
                  loading: () => const PosterGridSkeleton(),
                  error: (e, _) => ErrorView(
                    message: errorText(e),
                    onRetry: () => ref.invalidate(seerrSearchProvider),
                  ),
                  data: (list) => list.isEmpty
                      ? EmptyState(
                          icon: Icons.search_off_rounded,
                          title: l.browseNoResults)
                      : _SeerrResultGrid(list: list),
                ),
        ),
      ],
    );
  }
}

class _SeerrResultGrid extends StatelessWidget {
  final List<SeerrResult> list;
  const _SeerrResultGrid({required this.list});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 184,
        mainAxisSpacing: 18,
        crossAxisSpacing: 14,
        childAspectRatio: 0.54,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) => EntranceFade(
        index: i,
        onceKey: 'gr${list[i].mediaType}${list[i].tmdbId}',
        child: list[i].mediaType == 'person'
            ? SeerrPersonSearchCard(person: list[i])
            : SeerrGridCard(result: list[i]),
      ),
    );
  }
}

// Jellyseerr's Requests-page options, matched exactly. Functions (not const
// lists) so the labels can be localized; the ids stay stable for the API.
List<(String, String)> _requestStatusFilters(AppLocalizations l) =>
    <(String, String)>[
      ('all', l.browseAll),
      ('pending', l.browsePending),
      ('approved', l.browseApproved),
      ('completed', l.browseCompleted),
      ('processing', l.browseProcessing),
      ('failed', l.browseFailed),
      ('available', l.browseAvailable),
      ('unavailable', l.browseUnavailable),
      ('deleted', l.browseDeleted),
    ];
List<(String, String)> _requestMediaTypes(AppLocalizations l) =>
    <(String, String)>[
      ('all', l.browseAll),
      ('movie', l.browseMovies),
      ('tv', l.browseTvShows),
    ];
List<(String, String)> _requestSorts(AppLocalizations l) => <(String, String)>[
      ('added', l.browseSortMostRecent),
      ('modified', l.browseSortLastModified),
    ];

/// One of the Requests-page control dropdowns: a leading icon + a compact
/// dropdown in a rounded field, matching Jellyseerr's header controls.
class _RequestFilterDropdown extends StatelessWidget {
  final IconData icon;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  const _RequestFilterDropdown({
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppDropdown<String>(
      leading: icon,
      value: value,
      options: {for (final o in options) o.$1: o.$2},
      onChanged: onChanged,
    );
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final filter = ref.watch(seerrRequestFilterProvider);
    final mediaType = ref.watch(seerrRequestMediaTypeProvider);
    final sort = ref.watch(seerrRequestSortProvider);
    final dir = ref.watch(seerrRequestSortDirProvider);
    final async = ref.watch(seerrRequestsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        PageHeader(maxWidth: cardListMaxWidth, child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _RequestFilterDropdown(
                icon: Icons.layers_rounded,
                value: mediaType,
                options: _requestMediaTypes(l),
                onChanged: (v) =>
                    ref.read(seerrRequestMediaTypeProvider.notifier).set(v),
              ),
              _RequestFilterDropdown(
                icon: Icons.filter_alt_rounded,
                value: filter,
                options: _requestStatusFilters(l),
                onChanged: (v) =>
                    ref.read(seerrRequestFilterProvider.notifier).set(v),
              ),
              _RequestFilterDropdown(
                icon: Icons.sort_rounded,
                value: sort,
                options: _requestSorts(l),
                onChanged: (v) =>
                    ref.read(seerrRequestSortProvider.notifier).set(v),
              ),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () =>
                        ref.read(seerrRequestSortDirProvider.notifier).toggle(),
                    child: Tooltip(
                      message: l.browseToggleSortDirection,
                      child: SizedBox(
                        height: 42,
                        width: 44,
                        child: Center(
                          child: AnimatedRotation(
                            turns: dir == 'asc' ? 0.5 : 0,
                            duration: const Duration(milliseconds: 220),
                            child: Icon(Icons.arrow_downward_rounded,
                                size: 20, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        )),
        Expanded(
          child: async.when(
            loading: () => const Center(child: AppSpinner()),
            error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(seerrRequestsProvider),
        ),
            data: (list) => list.isEmpty
                ? EmptyState(
                    icon: Icons.inbox_rounded,
                    title: l.browseNoRequests,
                    message: l.browseNoRequestsMessage)
                : RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(seerrRequestsProvider),
                    child: PageWidth(maxWidth: cardListMaxWidth, builder: (_, inset) => ListView.builder(
                      padding: pageInsets(inset, const EdgeInsets.symmetric(vertical: 6)),
                      itemCount: list.length,
                      itemBuilder: (context, i) =>
                          SeerrRequestTile(request: list[i]),
                    )),
                  ),
          ),
        ),
      ],
    );
  }
}

String _seerrAgo(AppLocalizations l, String? iso) {
  if (iso == null) return '';
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inDays >= 1) return l.browseDaysAgo(d.inDays);
  if (d.inHours >= 1) return l.browseHoursAgo(d.inHours);
  if (d.inMinutes >= 1) return l.browseMinutesAgo(d.inMinutes);
  return l.browseJustNow;
}

/// A Jellyseerr-style request row: backdrop, poster, title, the request fields
/// (status, requested/modified by, profile), and permission-gated actions.
/// Discover's Requests tab lists them all; the Manage section's Activity tab
/// lists the ones waiting for an answer.
class SeerrRequestTile extends ConsumerWidget {
  final SeerrRequest request;
  const SeerrRequestTile({super.key, required this.request});

  (String, Color) _status(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = request;
    if (r.isDeclined) return (l.browseDeclined, Theme.of(context).colorScheme.error);
    return switch (r.mediaStatus) {
      5 => (l.browseAvailable, const Color(0xFF22C55E)),
      4 => (l.browsePartiallyAvailable, const Color(0xFF14B8A6)),
      3 => (l.browseProcessing, const Color(0xFF3B82F6)),
      2 => (l.browsePending, const Color(0xFFF59E0B)),
      _ => (r.isPending ? l.browsePending : l.browseApproved,
          const Color(0xFFF59E0B)),
    };
  }

  Future<bool> _confirm(
      BuildContext context, String title, String action) async {
    final l = AppLocalizations.of(context);
    final ok = await confirm(context,
        title: title,
        message: l.browseConfirmUndone(action),
        confirmLabel: action,
        destructive: true);
    return ok;
  }

  Future<void> _act(BuildContext context, WidgetRef ref, String action) async {
    final l = AppLocalizations.of(context);
    // The lists are told through the app's own scope, not the row's: an
    // answer takes the row off its list, and it may be gone (scrolled away,
    // or answered from a sheet) before Seerr has replied.
    final scope = ProviderScope.containerOf(context, listen: false);
    void changed() {
      scope.invalidate(seerrRequestsProvider);
      scope.invalidate(seerrRecentRequestsProvider);
      scope.invalidate(seerrPendingRequestsProvider);
    }

    if (action == 'edit') {
      final ok = await showSeerrEditRequestDialog(context, request);
      if (ok) {
        changed();
        if (context.mounted) {
          showSnack(context, l.browseRequestUpdated, kind: SnackKind.success);
        }
      }
      return;
    }
    final client = scope.read(seerrClientProvider);
    if (client == null) return;
    if (action == 'delete' &&
        !await _confirm(context, l.browseDeleteRequest, l.browseDeleteRequest)) {
      return;
    }
    if (action == 'remove') {
      final svc = request.mediaType == 'tv' ? 'Sonarr' : 'Radarr';
      if (!context.mounted ||
          !await _confirm(context, l.browseRemoveFromService(svc),
              l.browseRemoveFromService(svc))) {
        return;
      }
    }
    if (!context.mounted) return;
    final title = scope
            .read(seerrDetailProvider(
                (mediaType: request.mediaType, tmdbId: request.tmdbId)))
            .value
            ?.title ??
        (request.mediaType == 'tv' ? l.browseThisSeries : l.browseThisMovie);
    final arr = request.mediaType == 'tv' ? 'Sonarr' : 'Radarr';
    try {
      switch (action) {
        case 'approve':
          await client.approveRequest(request.id);
        case 'decline':
          await client.declineRequest(request.id);
        case 'retry':
          await client.retryRequest(request.id);
        case 'delete':
          await client.deleteRequest(request.id);
        case 'remove':
          if (request.mediaId != null) {
            await client.deleteMediaFile(request.mediaId!, is4k: request.is4k);
          }
      }
      changed();
      final done = switch (action) {
        'approve' => l.browseApprovedTitle(title),
        'decline' => l.browseDeclinedTitle(title),
        'retry' => l.browseRetryingTitle(title),
        'delete' => l.browseDeletedRequestFor(title),
        'remove' => l.browseRemovedFromService(title, arr),
        _ => l.browseDone,
      };
      if (context.mounted) showSnack(context, done, kind: SnackKind.success);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = request;
    // `value` throughout: what was last known stands while it's read again
    // (any saved setting does that), so the row and its buttons don't blink.
    final detail =
        ref.watch(seerrDetailProvider((mediaType: r.mediaType, tmdbId: r.tmdbId)))
            .value;
    final perms = ref.watch(seerrPermissionsProvider).value ?? 0;
    final canManage = seerrCan(perms, kSeerrManageRequests);
    final isAdmin = perms & kSeerrAdmin != 0;
    final profileNames =
        ref.watch(seerrProfileNamesProvider(r.mediaType)).value ?? const {};

    final title = detail?.title ??
        (r.mediaType == 'tv'
            ? l.browseSeriesNumber(r.tmdbId)
            : l.browseMovieNumber(r.tmdbId));
    final (statusLabel, statusColor) = _status(context);
    final profileName =
        r.profileId != null ? profileNames[r.profileId] : null;
    // Fathom's own Radarr or Sonarr, when it has the title: its page there,
    // where the download is followed and fixed.
    final arrKey = arrKeyOfSeerr(
        mediaType: r.mediaType,
        tmdbId: r.tmdbId,
        tvdbId: detail?.tvdbId ?? r.tvdbId);
    final arr =
        arrKey == null ? null : ref.watch(arrMatchProvider(arrKey)).value;
    final arrId = arr?.id;
    final manageIn = arr == null ? '' : l.arrManageIn(arr.kind.appName);
    void openArr() => arrOpenTitlePage(context, arr!.kind, arrId!);

    void openDetail() {
      if (detail == null) return;
      context.push('/seerr-detail',
          extra: SeerrResult(
            tmdbId: r.tmdbId,
            mediaType: r.mediaType,
            title: title,
            posterPath: detail.posterPath,
            backdropPath: detail.backdropPath,
            status: r.mediaStatus,
          ));
    }

    Widget fields() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _fieldRow(theme, l, l.browseStatus,
                pill: _pill(statusLabel, statusColor)),
            if (r.requestedBy != null)
              _fieldRow(theme, l, l.browseRequested,
                  ago: _seerrAgo(l, r.createdAt),
                  name: r.requestedBy!,
                  avatar: _avatarUrl(ref, r.requestedByAvatar)),
            if (r.modifiedBy != null)
              _fieldRow(theme, l, l.browseModified,
                  ago: _seerrAgo(l, r.updatedAt),
                  name: r.modifiedBy!,
                  avatar: _avatarUrl(ref, r.modifiedByAvatar)),
            if (profileName != null)
              _fieldRow(theme, l, l.browseProfile, value: profileName),
            if (r.mediaType == 'tv' && r.seasons.isNotEmpty)
              _fieldRow(theme, l, l.browseSeasons, value: r.seasons.join(', ')),
          ],
        );

    final decide = r.isPending && canManage;
    final retry = r.isFailed && canManage;
    final canDelete = canManage || r.isPending;
    final canRemove = isAdmin && r.mediaId != null && (r.mediaStatus ?? 0) >= 3;
    final removeFrom =
        l.browseRemoveFromService(r.mediaType == 'tv' ? 'Sonarr' : 'Radarr');

    // A TV keeps the row it had, every action a button to move to.
    if (!isTvDevice) {
      // Everything the row does, by name: under its menu button, and on a
      // right-click or a long press.
      final menu = <ContextMenuAction>[
        if (decide) ...[
          ContextMenuAction(
              icon: Icons.check_circle_outline_rounded,
              label: l.browseApprove,
              onTap: () => _act(context, ref, 'approve')),
          ContextMenuAction(
              icon: Icons.cancel_outlined,
              label: l.browseDecline,
              onTap: () => _act(context, ref, 'decline')),
          ContextMenuAction(
              icon: Icons.tune_rounded,
              label: l.browseEditRequest,
              onTap: () => _act(context, ref, 'edit')),
        ],
        if (retry)
          ContextMenuAction(
              icon: Icons.refresh_rounded,
              label: l.commonRetry,
              onTap: () => _act(context, ref, 'retry')),
        if (arrId != null)
          ContextMenuAction(icon: kManageIcon, label: manageIn, onTap: openArr),
        if (canDelete)
          ContextMenuAction(
              icon: Icons.delete_outline_rounded,
              label: l.browseDeleteRequest,
              color: scheme.error,
              onTap: () => _act(context, ref, 'delete')),
        if (canRemove)
          ContextMenuAction(
              icon: Icons.delete_sweep_outlined,
              label: removeFrom,
              color: scheme.error,
              onTap: () => _act(context, ref, 'remove')),
      ];
      // In the open, only what the row is waiting for: its answer. Without
      // one to give, the way to the download in Sonarr or Radarr.
      final answers = <Widget>[
        if (decide) ...[
          _AnswerButton(
              icon: Icons.check_rounded,
              label: l.browseApprove,
              background: _approveColor,
              foreground: _onApproveColor,
              onTap: () => _act(context, ref, 'approve')),
          _AnswerButton(
              icon: Icons.close_rounded,
              label: l.browseDecline,
              background: scheme.errorContainer,
              foreground: scheme.onErrorContainer,
              onTap: () => _act(context, ref, 'decline')),
        ] else if (retry)
          _AnswerButton(
              icon: Icons.refresh_rounded,
              label: l.commonRetry,
              background: scheme.primary,
              foreground: scheme.onPrimary,
              onTap: () => _act(context, ref, 'retry')),
      ];
      final manage = answers.isEmpty && arrId != null
          ? _AnswerButton(
              icon: kManageIcon,
              label: manageIn,
              background: scheme.secondaryContainer,
              foreground: scheme.onSecondaryContainer,
              onTap: openArr)
          : null;
      return _RequestTileCard(
        title: title,
        year: detail?.year,
        posterUrl: detail?.posterUrl,
        backdropUrl: detail?.backdropUrl,
        onOpen: detail == null ? null : openDetail,
        menu: menu,
        answers: answers,
        manage: manage,
        fields: fields,
      );
    }

    final actions = <Widget>[
      if (r.isPending && canManage) ...[
        _RequestButton(
            icon: Icons.tune_rounded,
            label: l.commonEdit,
            onTap: () => _act(context, ref, 'edit')),
        _RequestButton(
            icon: Icons.check_circle_outline_rounded,
            label: l.browseApprove,
            color: const Color(0xFF22C55E),
            onTap: () => _act(context, ref, 'approve')),
        _RequestButton(
            icon: Icons.cancel_outlined,
            label: l.browseDecline,
            color: scheme.error,
            onTap: () => _act(context, ref, 'decline')),
      ],
      if (r.isFailed && canManage)
        _RequestButton(
            icon: Icons.refresh_rounded,
            label: l.commonRetry,
            color: scheme.primary,
            onTap: () => _act(context, ref, 'retry')),
      if (arrId != null)
        _RequestButton(icon: kManageIcon, label: manageIn, onTap: openArr),
      if (canManage || r.isPending)
        _RequestButton(
            icon: Icons.delete_outline_rounded,
            label: l.browseDeleteRequest,
            color: scheme.error,
            onTap: () => _act(context, ref, 'delete')),
      if (isAdmin &&
          r.mediaId != null &&
          (r.mediaStatus ?? 0) >= 3)
        _RequestButton(
            icon: Icons.delete_sweep_outlined,
            label: l.browseRemoveFromService(
                r.mediaType == 'tv' ? 'Sonarr' : 'Radarr'),
            color: scheme.error,
            onTap: () => _act(context, ref, 'remove')),
    ];

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 860;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14)),
        child: Stack(
          children: [
            if (detail?.backdropUrl != null)
              Positioned.fill(
                child: Image.network(detail!.backdropUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox()),
              ),
            // A scrim in the surface colour so the normal theme text is legible
            // over any backdrop, in light or dark.
            Positioned.fill(
              child: ColoredBox(
                  color: scheme.surface.withValues(alpha: 0.86)),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _PosterThumb(url: detail?.posterUrl, onTap: openDetail),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (detail?.year != null)
                          Text(detail!.year!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant)),
                        InkWell(
                          onTap: openDetail,
                          child: Text(title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        if (!wide) ...[
                          const SizedBox(height: 8),
                          fields(),
                        ],
                      ],
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(width: 12),
                    SizedBox(width: 250, child: fields()),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 232,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final a in actions)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: a,
                            ),
                        ],
                      ),
                    ),
                  ] else
                    Builder(builder: (btnContext) {
                      return IconButton(
                        tooltip: AppLocalizations.of(context).commonMore,
                        icon: const Icon(Icons.more_vert_rounded),
                        onPressed: () {
                          final box =
                              btnContext.findRenderObject() as RenderBox?;
                          final at = box == null
                              ? Offset.zero
                              : box.localToGlobal(
                                  box.size.center(Offset.zero));
                          showContextMenu(context, at: at, title: title, actions: [
                            if (r.isPending && canManage) ...[
                              ContextMenuAction(
                                  icon: Icons.tune_rounded,
                                  label: l.browseEditRequest,
                                  onTap: () => _act(context, ref, 'edit')),
                              ContextMenuAction(
                                  icon: Icons.check_circle_outline_rounded,
                                  label: l.browseApprove,
                                  onTap: () => _act(context, ref, 'approve')),
                              ContextMenuAction(
                                  icon: Icons.cancel_outlined,
                                  label: l.browseDecline,
                                  onTap: () => _act(context, ref, 'decline')),
                            ],
                            if (r.isFailed && canManage)
                              ContextMenuAction(
                                  icon: Icons.refresh_rounded,
                                  label: l.commonRetry,
                                  onTap: () => _act(context, ref, 'retry')),
                            if (arrId != null)
                              ContextMenuAction(
                                  icon: kManageIcon,
                                  label: manageIn,
                                  onTap: openArr),
                            if (canManage || r.isPending)
                              ContextMenuAction(
                                  icon: Icons.delete_outline_rounded,
                                  label: l.browseDeleteRequest,
                                  color: scheme.error,
                                  onTap: () => _act(context, ref, 'delete')),
                            if (isAdmin &&
                                r.mediaId != null &&
                                (r.mediaStatus ?? 0) >= 3)
                              ContextMenuAction(
                                  icon: Icons.delete_sweep_outlined,
                                  label: l.browseRemoveFromService(
                                      r.mediaType == 'tv' ? 'Sonarr' : 'Radarr'),
                                  color: scheme.error,
                                  onTap: () => _act(context, ref, 'remove')),
                          ]);
                        },
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  String? _avatarUrl(WidgetRef ref, String? raw) =>
      seerrAvatarUrl(ref.read(seerrClientProvider)?.baseUrl ?? '', raw);

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                color: onStatus(color),
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      );

  Widget _fieldRow(ThemeData theme, AppLocalizations l, String label,
      {Widget? pill,
      String? value,
      String? ago,
      String? name,
      String? avatar}) {
    final labelStyle = theme.textTheme.bodySmall
        ?.copyWith(fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The names line up whatever they hold, and one too long for
          // its place (larger text, a longer language) is drawn smaller
          // before it's broken in two.
          SizedBox(
            width: 78,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(label, maxLines: 1, style: labelStyle),
            ),
          ),
          // The status is read whole: on the narrowest phone it's drawn
          // smaller before it's cut short or runs off the card.
          if (pill != null)
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: pill,
              ),
            ),
          if (value != null)
            Flexible(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall)),
          // One line, so it gives way at its end however narrow the row
          // or long the words: when, the face, then the name.
          if (name != null)
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  if (ago != null && ago.isNotEmpty)
                    TextSpan(
                        text: '${l.browseAgoBy(ago)} ',
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant)),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 5),
                      child:
                          SeerrAvatar(name: name, avatarUrl: avatar, radius: 8),
                    ),
                  ),
                  TextSpan(
                      text: name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Approve's green, and what's written on it.
const _approveColor = Color(0xFF22C55E);
const _onApproveColor = Color(0xFF052E16);

/// A request as a card, away from a TV: the poster, what was asked and by
/// whom, and the answer it waits for in the open. Everything else it does
/// is under its menu. Pressing it opens the title.
class _RequestTileCard extends StatelessWidget {
  final String title;
  final String? year;
  final String? posterUrl;
  final String? backdropUrl;
  final VoidCallback? onOpen;
  final List<ContextMenuAction> menu;

  /// Approve and Decline, or Retry. Empty with no answer to give.
  final List<Widget> answers;

  /// Shown in their place where there's room, with no answer to give.
  final Widget? manage;
  final Widget Function() fields;

  const _RequestTileCard({
    required this.title,
    required this.year,
    required this.posterUrl,
    required this.backdropUrl,
    required this.onOpen,
    required this.menu,
    required this.answers,
    required this.manage,
    required this.fields,
  });

  /// Narrower than this (a phone), the answers go under the row.
  static const compactBelow = 560.0;

  /// From this width the fields have a column of their own.
  static const wideFrom = 860.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = theme.cardTheme.color ?? scheme.surfaceContainer;
    void openMenu(Offset at) =>
        showContextMenu(context, at: at, title: title, actions: menu);
    return LayoutBuilder(builder: (context, c) {
      final compact = c.maxWidth < compactBelow;
      final wide = c.maxWidth >= wideFrom;
      final beside = [...answers, if (!compact) ?manage];
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (year != null)
            Text(year!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (!wide) ...[
            const SizedBox(height: 8),
            fields(),
          ],
        ],
      );
      final body = Padding(
        // The menu button brings its own space at the far end.
        padding: EdgeInsetsDirectional.fromSTEB(
            14, 14, menu.isEmpty ? 14 : 4, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                _RequestPoster(
                    url: posterUrl, width: wide ? 72 : (compact ? 56 : 64)),
                const SizedBox(width: 14),
                Expanded(child: heading),
                if (wide) ...[
                  const SizedBox(width: 12),
                  SizedBox(width: 250, child: fields()),
                ],
                if (!compact && beside.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  // As wide as the widest of them, one under the other.
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 132),
                    child: IntrinsicWidth(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, b) in beside.indexed) ...[
                            if (i > 0) const SizedBox(height: 8),
                            b,
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                if (menu.isNotEmpty)
                  Builder(builder: (button) {
                    return IconButton(
                      tooltip: AppLocalizations.of(context).commonMore,
                      icon: const Icon(Icons.more_vert_rounded),
                      onPressed: () {
                        final box = button.findRenderObject() as RenderBox?;
                        openMenu(box == null
                            ? Offset.zero
                            : box.localToGlobal(box.size.center(Offset.zero)));
                      },
                    );
                  }),
              ],
            ),
            // On a phone the answers are a row of their own, each as wide
            // as the other and easy to hit.
            if (compact && answers.isNotEmpty)
              Padding(
                padding: EdgeInsetsDirectional.only(
                    top: 12, end: menu.isEmpty ? 0 : 10),
                child: Row(
                  children: [
                    for (final (i, b) in answers.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: b),
                    ],
                  ],
                ),
              ),
          ],
        ),
      );
      final card = Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: color,
        child: ArrCardWash(
          color: color,
          picture: backdropUrl == null
              ? null
              : (width) => CachedImage(
                  url: backdropUrl!,
                  cacheWidth: width,
                  alignment: const Alignment(0, -0.4),
                  placeholder: const SizedBox.shrink(),
                  errorBuilder: (_) => const SizedBox.shrink(),
                ),
          // Its own ink, over the picture.
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: onOpen, child: body),
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: menu.isEmpty
            ? card
            : GestureDetector(
                onSecondaryTapUp: (d) => openMenu(d.globalPosition),
                onLongPressStart: (d) => openMenu(d.globalPosition),
                child: card,
              ),
      );
    });
  }
}

/// The poster in a request's card.
class _RequestPoster extends StatelessWidget {
  final String? url;
  final double width;
  const _RequestPoster({required this.url, required this.width});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final none = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.movie_rounded, color: scheme.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: width * 1.5,
        child: url == null
            ? none
            : CachedImage(
                url: url!, cacheWidth: width, errorBuilder: (_) => none),
      ),
    );
  }
}

/// An answer to a request, in the open on its card.
class _AnswerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  const _AnswerButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: const TextStyle(
            fontFamily: kAppFontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label,
          maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
    );
  }
}

/// A poster thumbnail in a request row.
class _PosterThumb extends StatelessWidget {
  final String? url;
  final VoidCallback onTap;
  const _PosterThumb({required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TvFocusable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 84,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: url != null
                ? CachedImage(url: url!, errorBuilder: (_) => _ph(theme))
                : _ph(theme),
          ),
        ),
      ),
    );
  }

  Widget _ph(ThemeData theme) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.movie_rounded,
            size: 18, color: theme.colorScheme.onSurfaceVariant),
      );
}

/// A compact filled action button for request rows.
class _RequestButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _RequestButton(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          minimumSize: const Size.fromHeight(38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          textStyle: const TextStyle(
              fontFamily: kAppFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
        icon: Icon(icon, size: 17),
        label: Text(label, maxLines: 1, softWrap: false),
      ),
    );
  }
}
