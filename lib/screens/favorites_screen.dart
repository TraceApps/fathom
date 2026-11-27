import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../routing/app_shell.dart';
import '../state/library_providers.dart';
import '../widgets/item_grid.dart';

/// Everything the user has favorited, from Jellyfin's own Favorites (so it's
/// the same list as in every other Jellyfin app): movies, shows, episodes,
/// collections, videos, music and people. Chips across the top narrow it to
/// one kind; only kinds that have something in them get a chip.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  FavoriteGroup? _group; // null: All

  static String _label(AppLocalizations l, FavoriteGroup g) => switch (g) {
    FavoriteGroup.movies => l.browseMovies,
    FavoriteGroup.shows => l.browseShows,
    FavoriteGroup.episodes => l.browseEpisodes,
    FavoriteGroup.collections => l.browseCollections,
    FavoriteGroup.videos => l.browseVideos,
    FavoriteGroup.music => l.browseMusic,
    FavoriteGroup.playlists => l.browsePlaylists,
    FavoriteGroup.people => l.browsePeople,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = ref.watch(favoriteItemsProvider);
    final all = items.asData?.value ?? const <BaseItemDto>[];
    final present = {for (final i in all) ?FavoriteGroup.of(i)};
    final groups = [
      for (final g in FavoriteGroup.values)
        if (present.contains(g)) g,
    ];
    // A chip whose kind emptied (the last one was unfavorited) falls back to
    // All instead of leaving an empty page behind.
    final group = groups.contains(_group) ? _group : null;
    return Scaffold(
      appBar: AppBar(
        leading: mobileLeading(context),
        title: Text(l.browseFavorites),
        actions: [
          IconButton(
            tooltip: l.commonRefresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(favoriteItemsProvider),
          ),
        ],
        // One kind needs no chips: All already is that kind.
        bottom: groups.length < 2
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    children: [
                      for (final g in <FavoriteGroup?>[null, ...groups])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(g == null ? l.browseAll : _label(l, g)),
                            selected: group == g,
                            onSelected: (_) => setState(() => _group = g),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
      body: ItemGridBody(
        items: group == null
            ? items
            : items.whenData(
                (list) => [
                  for (final i in list)
                    if (group.types.contains(i.type)) i,
                ],
              ),
        emptyIcon: Icons.favorite_border_rounded,
        emptyTitle: l.browseNoFavorites,
        onRefresh: () => ref.invalidate(favoriteItemsProvider),
      ),
    );
  }
}
