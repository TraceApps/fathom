import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/app_shown.dart';
import '../theme/status_colors.dart';
import '../api/error_text.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../models/base_item.dart';
import '../models/seerr_detail.dart';
import '../models/seerr_result.dart';
import '../state/arr_providers.dart';
import '../state/library_providers.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../state/seerr_providers.dart';
import '../state/session_controller.dart';
import '../services/tv_mode.dart';
import '../widgets/over_art_bar.dart';
import '../widgets/app_snack.dart';
import '../widgets/error_view.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/hover_pill_button.dart';
import '../widgets/tv_focus.dart';
import '../widgets/media_section.dart';
import '../widgets/cached_image.dart';
import '../widgets/detail_header.dart';
import '../widgets/meta_pill.dart';
import '../widgets/score_pills.dart';
import '../widgets/seerr_manage_dialog.dart';
import '../widgets/seerr_poster_card.dart';
import '../widgets/seerr_request_dialog.dart';
import '../widgets/app_spinner.dart';
import '../api/jellyfin_client.dart';

/// Rich Seerr detail page: backdrop, overview, cast, and requesting
/// (movie whole, or per-season for TV).
/// Wraps a horizontal content strip as a TV focus row (LEFT escapes to the rail,
/// the focused card scrolls into view), matching the media rows. Pass-through
/// off TV.
Widget _tvRow(Widget child) => isTvDevice ? TvFocusRow(child: child) : child;

class SeerrDetailScreen extends ConsumerWidget {
  final SeerrResult result;
  const SeerrDetailScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (mediaType: result.mediaType, tmdbId: result.tmdbId);
    final async = ref.watch(seerrDetailProvider(key));

    return Scaffold(
      body: async.when(
        loading: () => _loadingHeader(context),
        error: (e, _) => _ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(seerrDetailProvider(key)),
        ),
        data: (d) => _DetailBody(detail: d),
      ),
    );
  }

  Widget _loadingHeader(BuildContext context) => Stack(
    children: [
      if (result.posterUrl != null)
        Positioned.fill(
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Colors.black54,
              BlendMode.darken,
            ),
            child: CachedImage(
              url: result.posterUrl!,
              errorBuilder: (_) => const SizedBox(),
            ),
          ),
        ),
      const Center(child: AppSpinner()),
      SafeArea(
        child: BackButton(color: Theme.of(context).colorScheme.onSurface),
      ),
    ],
  );
}

class _DetailBody extends ConsumerWidget {
  final SeerrDetail detail;
  const _DetailBody({required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final prefs = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final d = detail;
    // Scale the backdrop band with width (taller = closer to the art's 16:9
    // shape) so it isn't cropped into a thin sliver on wide windows.
    final headerHeight = (MediaQuery.sizeOf(context).width / 2.35).clamp(
      320.0,
      680.0,
    );

    final metaLine = [
      d.mediaType == 'tv' ? l.detailSeries : l.detailMovie,
      if (d.year != null) d.year!,
      if (d.runtime != null && d.runtime! > 0) fmtRuntime(d.runtime!),
      // For a show, whether it's still going is the one fact worth surfacing.
      if (d.mediaType == 'tv' &&
          d.statusText != null &&
          d.statusText!.isNotEmpty)
        d.statusLabel(l)!,
    ].join('  ·  ');
    final mdb = ref
        .watch(
          mdbListRatingsProvider((mediaType: d.mediaType, tmdbId: d.tmdbId)),
        )
        .asData
        ?.value;
    final ratingPills = scorePills(
      // Native first, MDBList as gap-fill (never overwrites a real value).
      rtCritic: d.rtCriticScore ?? mdb?.rtCritic,
      rtAudience: d.rtAudienceScore ?? mdb?.rtAudience,
      imdb: d.imdbScore ?? (mdb?.imdb != null ? mdb!.imdb! / 10 : null),
      community: d.voteAverage ?? (mdb?.tmdb != null ? mdb!.tmdb! / 10 : null),
      letterboxd: mdb?.letterboxd,
      metacritic: mdb?.metacritic,
      metacriticUser: mdb?.metacriticUser,
      trakt: mdb?.trakt,
      rogerEbert: mdb?.rogerEbert,
      myAnimeList: mdb?.myAnimeList,
      prefs: prefs,
    );

    // Actions as circular icons in the header on wide windows; as labelled
    // buttons in the body on narrow ones, so nothing crowds the header.
    final wideHeader = MediaQuery.sizeOf(context).width >= 620;
    final canWatch = d.jellyfinMediaId != null;
    // The Manage panel (approve/decline/edit requests + advanced actions) is
    // offered to anyone who can manage requests, for any title Jellyseerr has a
    // media record for. A pending movie also gets the quick View Request pill.
    final perms = ref.watch(seerrPermissionsProvider).value ?? 0;
    final canManage = seerrCan(perms, kSeerrManageRequests);
    final showManage = canManage && d.mediaId != null;
    // Any title with a pending request (movie or TV) gets the View Request pill.
    final showViewRequest = canManage && d.pendingRequest != null;
    // Fathom's own Radarr or Sonarr, when it has the title: its page there,
    // where the download is followed and fixed.
    final arrKey = arrKeyOfSeerr(
      mediaType: d.mediaType,
      tmdbId: d.tmdbId,
      tvdbId: d.tvdbId,
    );
    final arr = arrKey == null
        ? null
        : ref.watch(arrMatchProvider(arrKey)).value;
    final arrId = arr?.id;
    final manageIn = arr == null ? '' : l.arrManageIn(arr.kind.appName);
    void openArr() => arrOpenTitlePage(context, arr!.kind, arrId!);
    // An approved request is what puts a title into the app, so the app is
    // asked again when Seerr's word on the title changes.
    ref.listen(
      seerrDetailProvider((mediaType: d.mediaType, tmdbId: d.tmdbId)),
      (prev, next) {
        final was = prev?.value;
        final now = next.value;
        if (arrKey == null || was == null || now == null) return;
        if (was.status != now.status ||
            was.downloadStatus.isEmpty != now.downloadStatus.isEmpty) {
          ref.invalidate(arrMatchProvider(arrKey));
        }
      },
    );
    final actionIcons = <Widget>[
      if (canWatch)
        HeaderActionButton(
          icon: Icons.play_arrow_rounded,
          tooltip: l.detailWatch,
          primary: true,
          onTap: () => context.push(
            '/item',
            extra: BaseItemDto(id: d.jellyfinMediaId!, name: d.title),
          ),
        ),
      if (!d.isAvailable)
        if (showViewRequest)
          _ViewRequestButton(detail: d, primary: !canWatch)
        else
          _RequestButton(detail: d, iconOnly: true, primary: !canWatch),
      if (d.trailerUrl != null)
        HeaderActionButton(
          icon: Icons.movie_outlined,
          tooltip: l.detailTrailer,
          onTap: () => context.push(
            '/trailer',
            extra: (url: d.trailerUrl!, title: d.title),
          ),
        ),
      if (arrId != null)
        HeaderActionButton(
          icon: kManageIcon,
          tooltip: manageIn,
          onTap: openArr,
        ),
      if (showManage)
        HeaderActionButton(
          icon: Icons.settings_rounded,
          tooltip: l.detailManage,
          onTap: () => showSeerrManageDialog(context, d),
        ),
    ];
    final actionsRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actionIcons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          actionIcons[i],
        ],
      ],
    );

    return CustomScrollView(
      slivers: [
        OverArtBar(child: SliverAppBar(
          expandedHeight: headerHeight,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (d.backdropUrl != null)
                  CachedImage(
                    url: d.backdropUrl!,
                    alignment: const Alignment(0, -0.35),
                    errorBuilder: (_) => Container(
                      color: theme.colorScheme.surfaceContainerHigh,
                    ),
                  )
                else
                  Container(color: theme.colorScheme.surfaceContainerHigh),
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
                  poster: d.posterUrl != null
                      ? CachedImage(
                          url: d.posterUrl!,
                          errorBuilder: (_) => const SizedBox(),
                        )
                      : null,
                  status: (d.status != null && d.status! >= 2)
                      ? _StatusChip(status: d.status)
                      : null,
                  title: _SeerrTitle(detail: d),
                  cert: d.certification != null
                      ? CertBadge(text: d.certification!)
                      : null,
                  metaLine: metaLine,
                  ratings: ratingPills,
                  actions: wideHeader && actionIcons.isNotEmpty
                      ? actionsRow
                      : null,
                ),
              ],
            ),
          ),
        )),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (d.downloadStatus.isNotEmpty)
                  _DownloadProgress(
                    mediaType: d.mediaType,
                    tmdbId: d.tmdbId,
                    downloads: d.downloadStatus,
                    onOpen: arrId == null ? null : openArr,
                    openLabel: manageIn,
                  ),
                // On narrow windows the actions live here as labelled buttons;
                // on wide ones they're the icon cluster in the header instead.
                if (!wideHeader) ...[
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (d.jellyfinMediaId != null)
                        HoverPillButton(
                          primary: true,
                          icon: Icons.play_arrow_rounded,
                          label: l.detailWatch,
                          onTap: () => context.push(
                            '/item',
                            extra: BaseItemDto(
                              id: d.jellyfinMediaId!,
                              name: d.title,
                            ),
                          ),
                        ),
                      if (showViewRequest)
                        _ViewRequestButton(detail: d)
                      else
                        _RequestButton(detail: d),
                      if (d.trailerUrl != null)
                        HoverPillButton(
                          icon: Icons.movie_outlined,
                          label: l.detailTrailer,
                          onTap: () => context.push(
                            '/trailer',
                            extra: (url: d.trailerUrl!, title: d.title),
                          ),
                        ),
                      if (arrId != null)
                        HoverPillButton(
                          icon: kManageIcon,
                          label: manageIn,
                          onTap: openArr,
                        ),
                      if (showManage)
                        HoverPillButton(
                          icon: Icons.settings_rounded,
                          label: l.detailManage,
                          onTap: () => showSeerrManageDialog(context, d),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                if (d.overview != null && d.overview!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    d.overview!,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ],
                if (d.genres.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final g in d.genres)
                        Chip(
                          label: Text(g),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ],
                if (d.cast.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text(l.detailCastCrew, style: _sectionStyle(theme)),
                      const Spacer(),
                      if (d.cast.length > 8 || d.crew.isNotEmpty)
                        TvFocusRing(
                          borderRadius: BorderRadius.circular(8),
                          child: TextButton(
                            onPressed: () => context.push(
                              '/seerr-credits',
                              extra: (
                                title: d.title,
                                cast: d.cast,
                                crew: d.crew,
                              ),
                            ),
                            child: Text(l.detailViewAll),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _tvRow(
                    SizedBox(
                      height: 168,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        itemCount: d.cast.length.clamp(0, 20),
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, i) => _CastCard(cast: d.cast[i]),
                      ),
                    ),
                  ),
                ],
                if (d.mediaType == 'tv' && d.seasons.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(l.detailSeasons, style: _sectionStyle(theme)),
                  const SizedBox(height: 8),
                  _SeasonList(detail: d),
                ],
                if (d.collectionId != null) ...[
                  const SizedBox(height: 16),
                  _CollectionCard(
                    id: d.collectionId!,
                    name: d.collectionName ?? l.detailCollection,
                  ),
                ],
                _TitlesRow(
                  title: l.detailRecommendations,
                  mediaType: d.mediaType,
                  tmdbId: d.tmdbId,
                  similar: false,
                ),
                _TitlesRow(
                  title: l.detailSimilar,
                  mediaType: d.mediaType,
                  tmdbId: d.tmdbId,
                  similar: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  TextStyle? _sectionStyle(ThemeData theme) =>
      theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
}

/// The title over the backdrop: the Jellyfin logo art when the title is already
/// on the server (Seerr/TMDB doesn't provide title logos), otherwise white text.
class _SeerrTitle extends ConsumerWidget {
  final SeerrDetail detail;
  const _SeerrTitle({required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text = Text(
      detail.title,
      style: theme.textTheme.headlineSmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
      ),
    );
    final jfId = detail.jellyfinMediaId;
    final session = ref.watch(sessionControllerProvider).asData?.value;
    if (jfId == null || session == null) return text;
    final url = ref
        .watch(jellyfinClientProvider)
        .imageUrl(
          baseUrl: session.baseUrl,
          itemId: jfId,
          type: 'Logo',
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

class _StatusChip extends StatelessWidget {
  final int? status;
  const _StatusChip({this.status});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (label, color) = switch (status) {
      5 => (l.detailStatusAvailable, const Color(0xFF22C55E)),
      4 => (l.detailStatusPartiallyAvailable, const Color(0xFF14B8A6)),
      3 => (l.detailStatusProcessing, const Color(0xFF3B82F6)),
      2 => (l.detailStatusPending, const Color(0xFFF59E0B)),
      _ => (l.detailStatusNotRequested, Theme.of(context).colorScheme.outline),
    };
    // Solid pill so it reads over the backdrop, like Jellyseerr's status badge.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: onStatus(color),
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RequestButton extends ConsumerStatefulWidget {
  final SeerrDetail detail;

  /// Renders as a circular header action instead of a labelled button.
  final bool iconOnly;
  final bool primary;
  const _RequestButton({
    required this.detail,
    this.iconOnly = false,
    this.primary = false,
  });
  @override
  ConsumerState<_RequestButton> createState() => _RequestButtonState();
}

class _RequestButtonState extends ConsumerState<_RequestButton> {
  void _invalidateLists() {
    ref.invalidate(seerrTrendingProvider);
    ref.invalidate(seerrMoviesProvider);
    ref.invalidate(seerrTvProvider);
    ref.invalidate(seerrSearchProvider);
  }

  Future<void> _openRequest() async {
    final d = widget.detail;
    // The dialog carries the season table (for a series), quality profile and
    // Request As, so the detail page opens it rather than duplicating the flow.
    final ok = await showSeerrRequestDialog(
      context,
      SeerrResult(
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
    if (ok) {
      ref.invalidate(
        seerrDetailProvider((mediaType: d.mediaType, tmdbId: d.tmdbId)),
      );
      _invalidateLists();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = widget.detail;
    if (d.isAvailable) return const SizedBox.shrink();
    // A movie already requested is pending, nothing more to do here (a manager
    // gets the separate View Request control instead). A series can always open
    // the dialog to request further seasons.
    final movieRequested = d.mediaType == 'movie' && d.isRequested;
    if (widget.iconOnly) {
      return HeaderActionButton(
        icon: movieRequested ? Icons.hourglass_top_rounded : Icons.add_rounded,
        tooltip: movieRequested ? l.detailRequested : l.detailRequest,
        primary: widget.primary,
        onTap: movieRequested ? null : _openRequest,
      );
    }
    return HoverPillButton(
      primary: true,
      icon: movieRequested ? Icons.hourglass_top_rounded : Icons.add_rounded,
      label: movieRequested ? l.detailRequested : l.detailRequest,
      onTap: movieRequested ? null : _openRequest,
    );
  }
}

/// The manager's request control on the detail header: a hover-expand pill
/// (matching [HeaderActionButton]) that, on click, drops down an animated
/// Approve / Decline menu the width of the expanded pill. Acts on
/// [SeerrDetail.pendingRequest].
class _ViewRequestButton extends ConsumerStatefulWidget {
  final SeerrDetail detail;
  final bool primary;
  const _ViewRequestButton({required this.detail, this.primary = false});

  @override
  ConsumerState<_ViewRequestButton> createState() => _ViewRequestButtonState();
}

class _ViewRequestButtonState extends ConsumerState<_ViewRequestButton>
    with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  final _pillKey = GlobalKey();
  final _portal = OverlayPortalController();
  bool _hover = false;
  bool _open = false;
  bool _busy = false;
  double _pillWidth = 178;

  late final AnimationController _menu = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
  );

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_busy) return;
    // On TV the hover/overlay menu rows aren't D-pad reachable, so open a
    // focusable sheet with the same actions instead.
    if (isTvDevice) {
      _showTvActions();
      return;
    }
    if (_open) {
      _close();
      return;
    }
    // The pill is already expanded from hover on desktop, so its live width is
    // the expanded width the dropdown should match.
    final w = _pillKey.currentContext?.size?.width;
    if (w != null && w > 60) _pillWidth = w;
    _portal.show();
    setState(() => _open = true);
    _menu.forward(from: 0);
  }

  Future<void> _showTvActions() async {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isTv = widget.detail.mediaType == 'tv';
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              autofocus: true,
              leading: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF22C55E),
              ),
              title: Text(l.detailApprove),
              onTap: () => Navigator.of(ctx).pop('approve'),
            ),
            ListTile(
              leading: Icon(Icons.cancel_rounded, color: scheme.error),
              title: Text(l.detailDecline),
              onTap: () => Navigator.of(ctx).pop('decline'),
            ),
            if (isTv)
              ListTile(
                leading: Icon(Icons.add_rounded, color: scheme.primary),
                title: Text(l.detailRequestMore),
                onTap: () => Navigator.of(ctx).pop('more'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'approve':
        await _act(true);
      case 'decline':
        await _act(false);
      case 'more':
        await _requestMore();
    }
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _menu.reverse().then((_) {
      if (mounted && !_open) _portal.hide();
    });
  }

  Future<void> _requestMore() async {
    _close();
    final d = widget.detail;
    final ok = await showSeerrRequestDialog(
      context,
      SeerrResult(
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
    if (ok && mounted) {
      ref.invalidate(
        seerrDetailProvider((mediaType: d.mediaType, tmdbId: d.tmdbId)),
      );
      ref.invalidate(seerrRequestsProvider);
      ref.invalidate(seerrRecentRequestsProvider);
      ref.invalidate(seerrPendingRequestsProvider);
    }
  }

  Future<void> _act(bool approve) async {
    _close();
    final d = widget.detail;
    final req = d.pendingRequest;
    final client = ref.read(seerrClientProvider);
    if (client == null || req == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (approve) {
        await client.approveRequest(req.id);
      } else {
        await client.declineRequest(req.id);
      }
      ref.invalidate(
        seerrDetailProvider((mediaType: d.mediaType, tmdbId: d.tmdbId)),
      );
      ref.invalidate(seerrRequestsProvider);
      ref.invalidate(seerrRecentRequestsProvider);
      ref.invalidate(seerrPendingRequestsProvider);
      if (mounted) {
        final l = AppLocalizations.of(context);
        showSnack(
          context,
          approve
              ? l.detailApprovedTitle(d.title)
              : l.detailDeclinedTitle(d.title),
          kind: SnackKind.success,
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = _hover || _open;
    final h = widget.primary ? 54.0 : 46.0;
    final fg = widget.primary ? scheme.onPrimary : Colors.white;
    final bg = widget.primary
        ? scheme.primary
        : Colors.black.withValues(alpha: 0.5);
    final iconSize = widget.primary ? 26.0 : 22.0;

    Widget restIcon() => _busy
        ? AppSpinner.inline(color: fg)
        : Icon(Icons.info_outline_rounded, size: iconSize, color: fg);

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => _overlay(scheme),
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Material(
            key: _pillKey,
            color: bg,
            shape: StadiumBorder(
              side: widget.primary
                  ? BorderSide.none
                  : BorderSide(color: Colors.white.withValues(alpha: 0.25)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _toggle,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: h,
                  child: expanded
                      ? Padding(
                          padding: EdgeInsets.only(
                            left: widget.primary ? 20 : 18,
                            right: widget.primary ? 14 : 12,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              restIcon(),
                              const SizedBox(width: 9),
                              Text(
                                AppLocalizations.of(context).detailViewRequest,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: widget.primary ? 15 : 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 3),
                              AnimatedRotation(
                                turns: _open ? 0.5 : 0,
                                duration: const Duration(milliseconds: 190),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                  color: fg,
                                ),
                              ),
                            ],
                          ),
                        )
                      : SizedBox(
                          width: h,
                          child: Center(child: restIcon()),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay(ColorScheme scheme) {
    final l = AppLocalizations.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: Align(
            alignment: Alignment.topLeft,
            child: AnimatedBuilder(
              animation: _menu,
              builder: (context, child) {
                final t = Curves.easeOutCubic.transform(_menu.value);
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, -8 * (1 - t)),
                    child: Transform.scale(
                      scale: 0.94 + 0.06 * t,
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  ),
                );
              },
              child: Material(
                elevation: 10,
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: _pillWidth < 60 ? 178 : _pillWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MenuRow(
                        icon: Icons.check_circle_rounded,
                        label: l.detailApprove,
                        color: const Color(0xFF22C55E),
                        onTap: () => _act(true),
                      ),
                      Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                      _MenuRow(
                        icon: Icons.cancel_rounded,
                        label: l.detailDecline,
                        color: scheme.error,
                        onTap: () => _act(false),
                      ),
                      // A series can still request further seasons, matching
                      // Jellyseerr's "Request More".
                      if (widget.detail.mediaType == 'tv') ...[
                        Divider(
                          height: 1,
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                        _MenuRow(
                          icon: Icons.add_rounded,
                          label: l.detailRequestMore,
                          color: scheme.primary,
                          onTap: _requestMore,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A hover-highlighting row inside the View Request dropdown.
class _MenuRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: _hover
              ? widget.color.withValues(alpha: 0.16)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(widget.icon, size: 19, color: widget.color),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _hover ? widget.color : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonList extends StatelessWidget {
  final SeerrDetail detail;
  const _SeasonList({required this.detail});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        for (final s in detail.seasons)
          TvFocusRing(
            borderRadius: BorderRadius.circular(8),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('${s.seasonNumber}')),
              title: Text(s.name),
              subtitle: Text(l.detailEpisodeCount(s.episodeCount)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SeasonStatus(status: s.status),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              // Open the episode list for the season.
              onTap: () => context.push(
                '/seerr-season',
                extra: (
                  tvId: detail.tmdbId,
                  seasonNumber: s.seasonNumber,
                  seasonName: s.name,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SeasonStatus extends StatelessWidget {
  final int? status;
  const _SeasonStatus({this.status});
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      5 => (Icons.check_circle_rounded, Colors.green),
      4 => (Icons.incomplete_circle_rounded, Colors.teal),
      3 => (Icons.sync_rounded, Colors.blue),
      2 => (Icons.hourglass_top_rounded, Colors.orange),
      _ => (
        Icons.remove_circle_outline_rounded,
        Theme.of(context).colorScheme.outline,
      ),
    };
    return Icon(icon, color: color, size: 20);
  }
}

class _CastCard extends StatefulWidget {
  final SeerrCast cast;
  const _CastCard({required this.cast});
  @override
  State<_CastCard> createState() => _CastCardState();
}

class _CastCardState extends State<_CastCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cast = widget.cast;
    // Same lift-and-ring on hover as the Jellyfin cast cards, so people feel
    // interactive everywhere in the app.
    final card = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.push('/seerr-person', extra: cast.id),
        child: SizedBox(
          width: 92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: _hover ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _hover
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 42,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    foregroundImage: cast.profileUrl != null
                        ? NetworkImage(cast.profileUrl!)
                        : null,
                    child: cast.profileUrl == null
                        ? const Icon(Icons.person_rounded, size: 32)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                cast.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (cast.character != null)
                Text(
                  cast.character!,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    // TV: make the whole card a D-pad target (no-op off TV).
    return TvFocusable(
      onTap: () => context.push('/seerr-person', extra: cast.id),
      borderRadius: BorderRadius.circular(10),
      child: card,
    );
  }
}

/// The page couldn't be read: the shared error view, under a Back button
/// (this page has no app bar of its own).
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const Align(alignment: Alignment.centerLeft, child: BackButton()),
          Expanded(child: ErrorView(message: message, onRetry: onRetry)),
        ],
      ),
    );
  }
}

/// A horizontal row of related titles (Recommendations / Similar). Renders
/// nothing until it has results, so an empty section never leaves a bare header.
class _TitlesRow extends ConsumerWidget {
  final String title;
  final String mediaType;
  final int tmdbId;
  final bool similar;
  const _TitlesRow({
    required this.title,
    required this.mediaType,
    required this.tmdbId,
    required this.similar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (mediaType: mediaType, tmdbId: tmdbId);
    final list =
        (similar
                ? ref.watch(seerrSimilarProvider(key))
                : ref.watch(seerrRecommendationsProvider(key)))
            .asData
            ?.value ??
        const [];
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: MediaSection(
        title: title,
        height: 300,
        children: [for (final r in list) SeerrPosterCard(result: r)],
      ),
    );
  }
}

/// The "Processing" download progress card, matching Jellyseerr: a bar per
/// active download with its percentage, status and estimated finish. Polls the
/// detail on a timer so the bar advances while the download runs.
class _DownloadProgress extends ConsumerStatefulWidget {
  final String mediaType;
  final int tmdbId;
  final List<SeerrDownload> downloads;

  /// Opens the title in Fathom's own Sonarr or Radarr pages, where the
  /// download can be followed and fixed. Null when the app doesn't have it.
  final VoidCallback? onOpen;
  final String openLabel;
  const _DownloadProgress({
    required this.mediaType,
    required this.tmdbId,
    required this.downloads,
    this.onOpen,
    this.openLabel = '',
  });

  @override
  ConsumerState<_DownloadProgress> createState() => _DownloadProgressState();
}

class _DownloadProgressState extends ConsumerState<_DownloadProgress> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      // Not while the app is minimized or in the background: nobody is
      // watching the progress it would fetch.
      if (mounted && appShown) {
        ref.invalidate(
          seerrDetailProvider((
            mediaType: widget.mediaType,
            tmdbId: widget.tmdbId,
          )),
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          for (final d in widget.downloads)
            _card(
              scheme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          d.title.isEmpty ? l.detailDownloading : d.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (widget.onOpen != null)
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: d.progress,
                            minHeight: 8,
                            backgroundColor: scheme.surfaceContainerHighest,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${(d.progress * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _pill(scheme, d.status),
                      const Spacer(),
                      if (_estimated(d.estimatedCompletionTime) case final est?)
                        Text(
                          est,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// A download's card. With somewhere to open, the whole card is the
  /// button for it.
  Widget _card(ColorScheme scheme, {required Widget child}) {
    final inner = Padding(padding: const EdgeInsets.all(14), child: child);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: widget.onOpen == null
          ? inner
          : Tooltip(
              message: widget.openLabel,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: widget.onOpen, child: inner),
              ),
            ),
    );
  }

  Widget _pill(ColorScheme scheme, String status) {
    final label = status.isEmpty
        ? AppLocalizations.of(context).detailDownloading
        : '${status[0].toUpperCase()}${status.substring(1)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.primary,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String? _estimated(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final t = DateTime.tryParse(iso);
    if (t == null) return null;
    final l = AppLocalizations.of(context);
    final diff = t.difference(DateTime.now());
    final secs = diff.inSeconds.abs();
    final label = secs < 60
        ? '${secs}s'
        : diff.inMinutes.abs() < 60
        ? '${diff.inMinutes.abs()} min'
        : '${diff.inHours.abs()}h';
    return diff.isNegative
        ? l.detailEstimatedAgo(label)
        : l.detailEstimatedIn(label);
  }
}

/// A tappable banner linking to the movie's collection (franchise).
class _CollectionCard extends StatelessWidget {
  final int id;
  final String name;
  const _CollectionCard({required this.id, required this.name});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return TvFocusRing(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/seerr-collection', extra: id),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.collections_bookmark_rounded, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.detailPartOfCollection(name),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
