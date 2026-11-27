import 'package:flutter/material.dart';
import '../routing/item_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';
import '../models/base_item.dart';
import '../services/tv_mode.dart';
import '../state/arr_providers.dart';
import '../state/library_providers.dart';
import '../state/palette.dart';
import '../state/preferences.dart';
import '../widgets/arr_home_rows.dart';
import '../widgets/featured_hero.dart';
import '../widgets/tv_focus.dart';
import '../widgets/media_cards.dart';
import '../widgets/media_section.dart';
import '../widgets/window_frame.dart';
import '../widgets/motion.dart';
import '../widgets/error_view.dart';
import '../widgets/shimmer.dart';

/// The library home: Continue Watching, Recently Added, and the user's
/// libraries. Tapping an item is a stub until detail + playback land next.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const double _posterRowHeight = 324;
  static const double _landscapeRowHeight = 210;
  static const double _resumeRowHeight = 238; // larger Continue Watching / Next Up

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // One row per show, resume and Next Up merged and ordered by what you
    // actually last watched (see continueWatchingProvider).
    final resume = ref.watch(continueWatchingProvider);
    final latest = ref.watch(latestItemsProvider);
    final hero = ref.watch(heroItemsProvider);
    final views = ref.watch(userViewsProvider);
    final prefs = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    // Sonarr's and Radarr's rows, where one of the apps is connected.
    final arrRows = ref.watch(arrConfiguredProvider);

    Future<void> refresh() async {
      ref.invalidate(resumeItemsProvider);
      ref.invalidate(nextUpItemsProvider);
      ref.invalidate(latestItemsProvider);
      ref.invalidate(heroItemsProvider);
      ref.invalidate(userViewsProvider);
      // Not waited for: Sonarr or Radarr out of reach would hold the
      // refresh until they gave up.
      ref.invalidate(arrQueueProvider);
      ref.invalidate(arrHomeComingUpProvider);
      await Future.wait([
        ref.read(continueWatchingProvider.future),
        ref.read(latestItemsProvider.future),
        ref.read(userViewsProvider.future),
      ]);
    }

    final featured = hero.asData?.value;
    final heroItem = (featured != null && featured.isNotEmpty)
        ? featured.first
        : null;
    final accent = heroItem == null
        ? null
        : ref.watch(itemAccentProvider(heroItem)).asData?.value;
    final scheme = Theme.of(context).colorScheme;

    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Ambient, art-driven wash behind the whole page.
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                        (accent ?? scheme.primary).withValues(alpha: 0.28),
                        scheme.surface),
                    scheme.surface,
                  ],
                  stops: const [0.0, 0.6],
                ),
              ),
            ),
          ),
          RefreshIndicator(
            onRefresh: refresh,
            child: CustomScrollView(
              // Always scrollable so pull-to-refresh fires even when Home fits
              // on screen without needing to scroll.
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
            // With no banner up top (turned off, nothing to feature, or the
            // server out of reach), the first row would sit under the
            // floating menu button on a phone: leave it room.
            if (_floatingMenu(context) &&
                !(prefs.homeBanner != 'hide' &&
                    hero.isLoading &&
                    !hero.hasValue) &&
                !(prefs.homeBanner == 'carousel' &&
                    (hero.value ?? const []).isNotEmpty) &&
                !(prefs.homeBanner == 'detailed' && heroItem != null))
              const SliverToBoxAdapter(child: SizedBox(height: 56)),
            if (prefs.homeBanner != 'hide' &&
                hero.isLoading &&
                !hero.hasValue)
              const SliverToBoxAdapter(child: HomeHeroSkeleton())
            else if (prefs.homeBanner == 'carousel')
              SliverToBoxAdapter(
                child: TvScrollToTopOnFocus(
                  // `value`, not `asData?.value`: asData is null while
                  // reloading even when there's a previous list, so every
                  // refresh handed the carousel an empty list for a moment.
                  // It tore its pages down and rebuilt them at page 0 while
                  // still showing the old page's title and logo, so a
                  // Raymond backdrop sat under The Legend of Tarzan's details.
                  child: FeaturedHero(items: hero.value ?? const []),
                ),
              )
            else if (prefs.homeBanner == 'detailed' && heroItem != null)
              SliverToBoxAdapter(
                child: TvScrollToTopOnFocus(
                  child: DetailedHeroBanner(item: heroItem),
                ),
              ),

            // Rows in the user's chosen order (each gated by its toggle),
            // with any an older saved order doesn't name put in.
            for (final rowId in homeRowsInOrder(prefs.homeRowOrder))
              ?switch (rowId) {
                'continueWatching' => prefs.showContinueWatching
                    ? _sectionSliver(
                        context,
                        title: l.browseContinueWatching,
                        height: _resumeRowHeight,
                        async: resume,
                        onRetry: () {
                          ref.invalidate(resumeItemsProvider);
                          ref.invalidate(nextUpItemsProvider);
                        },
                        cardBuilder: (item) => ContinueCard(
                          item: item,
                          onTap: () => context.push('/item', extra: item),
                          inContinueWatching: true,
                        ),
                      )
                    : null,
                'nextUp' => prefs.showNextUp
                    ? _sectionSliver(
                        context,
                        title: l.browseNextUp,
                        height: _resumeRowHeight,
                        async: ref.watch(nextUpItemsProvider),
                        onRetry: () => ref.invalidate(nextUpItemsProvider),
                        cardBuilder: (item) => ContinueCard(
                          item: item,
                          onTap: () => context.push('/item', extra: item),
                        ),
                      )
                    : null,
                'arrDownloading' => arrRows && prefs.showArrDownloading
                    ? const SliverToBoxAdapter(
                        child: ArrDownloadingRow(height: _resumeRowHeight),
                      )
                    : null,
                'arrComingUp' => arrRows && prefs.showArrComingUp
                    ? const SliverToBoxAdapter(
                        child: ArrComingUpRow(height: _posterRowHeight),
                      )
                    : null,
                'recentlyAdded' => prefs.showRecentlyAdded
                    ? _sectionSliver(
                        context,
                        title: l.browseRecentlyAdded,
                        height: _posterRowHeight,
                        async: latest,
                        onRetry: () => ref.invalidate(latestItemsProvider),
                        cardBuilder: (item) => PosterCard(
                          item: item,
                          heroTag: 'home-recent-${item.id}',
                          onTap: () => context.push('/item', extra: item),
                        ),
                      )
                    : null,
                'myMedia' => prefs.showMyMedia
                    ? _sectionSliver(
                        context,
                        title: l.browseMyMedia,
                        height: _landscapeRowHeight,
                        // Live TV has its own nav destination and opens nothing
                        // as a /library tile, so exclude it here like the
                        // Libraries hub and the sidebar do.
                        async: views.whenData((list) => list
                            .where((v) => v.collectionType != 'livetv')
                            .toList()),
                        hideWhenEmpty: false,
                        cardBuilder: (item) => LibraryCard(
                          item: item,
                          onTap: () => openLibraryView(context, item),
                        ),
                      )
                    : null,
                _ => null,
              },

            // Per-library "Latest in X" rows, mirroring Jellyfin's home.
            if (prefs.showLibraryLatest)
              for (final view in (views.asData?.value ?? const <BaseItemDto>[])
                  .where((v) =>
                      v.collectionType == 'movies' ||
                      v.collectionType == 'tvshows'))
                _sectionSliver(
                  context,
                  title: l.browseLatestIn(view.name),
                  height: _posterRowHeight,
                  async: ref.watch(latestInLibraryProvider(view.id)),
                  onRetry: () =>
                      ref.invalidate(latestInLibraryProvider(view.id)),
                  onSeeAll: () => context.push('/library', extra: view),
                  cardBuilder: (item) => PosterCard(
                    item: item,
                    heroTag: 'home-latest-${view.id}-${item.id}',
                    onTap: () => context.push('/item', extra: item),
                  ),
                ),

            // Editorial genre rows for browsing variety.
            if (prefs.showGenreRows)
              for (final genre
                  in (ref.watch(genresProvider).asData?.value ??
                          const <BaseItemDto>[])
                      .take(6))
                _sectionSliver(
                  context,
                  title: genre.name,
                  height: _posterRowHeight,
                  async: ref.watch(genreItemsProvider(
                      (genre: genre.name, sortBy: 'Random', sortOrder: 'Ascending'))),
                  onSeeAll: () => context.push('/genre', extra: genre.name),
                  cardBuilder: (item) => PosterCard(
                    item: item,
                    heroTag: 'home-genre-${genre.name}-${item.id}',
                    onTap: () => context.push('/item', extra: item),
                  ),
                ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
          // Home has no app bar (the hero fills the top), so on a phone a small
          // floating button opens the navigation drawer, with a scrim behind it
          // for legibility over bright hero art.
          if (_floatingMenu(context))
            Positioned(
              top: MediaQuery.of(context).padding.top + 4,
              left: 8,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                    color: Colors.black26, shape: BoxShape.circle),
                child: DrawerMenuButton(),
              ),
            ),
          // Desktop has no pull-to-refresh gesture, so give it a visible refresh
          // control in the top-right, clear of the window buttons (requested in
          // #16). Touch keeps the pull gesture.
          if (isDesktopWindowFrame)
            Positioned(
              top: MediaQuery.of(context).padding.top + 4,
              right: 8,
              child: _HomeRefreshButton(onRefresh: refresh),
            ),
        ],
      ),
    );
    // Desktop refresh shortcuts (F5 / Ctrl+R / Cmd+R). Autofocus so they fire
    // without a click first; touch uses pull-to-refresh, TV uses the D-pad.
    if (!isDesktopWindowFrame) return scaffold;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f5): () => refresh(),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            refresh(),
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () =>
            refresh(),
      },
      child: Focus(autofocus: true, child: scaffold),
    );
  }

  Widget _sectionSliver(
    BuildContext context, {
    required String title,
    required double height,
    required AsyncValue<List<BaseItemDto>> async,
    required Widget Function(BaseItemDto) cardBuilder,
    bool hideWhenEmpty = true,
    VoidCallback? onSeeAll,
    VoidCallback? onRetry,
  }) {
    final l = AppLocalizations.of(context);
    return SliverToBoxAdapter(
      child: async.when(
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(context, title),
            SectionSkeleton(height: height),
          ],
        ),
        error: (e, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(context, title),
            SectionError(
                message: l.browseCouldNotLoad(title), onRetry: onRetry),
          ],
        ),
        data: (items) {
          if (items.isEmpty && hideWhenEmpty) return const SizedBox.shrink();
          if (items.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title(context, title),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(l.browseNothingHereYet,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ],
            );
          }
          return MediaSection(
            title: title,
            height: height,
            onSeeAll: onSeeAll,
            children: [
              for (var i = 0; i < items.length; i++)
                EntranceFade(
                    index: i,
                    onceKey: items[i].id,
                    child: cardBuilder(items[i])),
            ],
          );
        },
      ),
    );
  }

  Widget _title(BuildContext context, String title) =>
      SectionHeader(title: title);
}

/// Desktop refresh control for Home (top-right). Spins while the providers
/// refetch. Touch uses pull-to-refresh instead, so this is desktop-only.
class _HomeRefreshButton extends StatefulWidget {
  final Future<void> Function() onRefresh;
  const _HomeRefreshButton({required this.onRefresh});

  @override
  State<_HomeRefreshButton> createState() => _HomeRefreshButtonState();
}

class _HomeRefreshButtonState extends State<_HomeRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800));
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    _spin.repeat();
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        _spin.stop();
        _spin.reset();
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: AppLocalizations.of(context).commonRefresh,
        onPressed: _run,
        icon: RotationTransition(
          turns: _spin,
          child: const Icon(Icons.refresh_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

/// Whether Home floats a menu button over its top-left corner: on a phone,
/// which has no rail and Home no app bar.
bool _floatingMenu(BuildContext context) =>
    MediaQuery.of(context).size.shortestSide < 600 && !isTvDevice;
