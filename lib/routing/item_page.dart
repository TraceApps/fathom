import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../models/base_item.dart';
import '../screens/artists_screen.dart';
import '../screens/detail_screen.dart';
import '../screens/person_screen.dart';
import '../screens/playlist_detail_screen.dart';
import '../screens/watchlist_screen.dart';
import '../state/watchlist.dart';

/// Whether [item] is the playlist the Watchlist is kept in.
bool isWatchlistPlaylist(BaseItemDto item) =>
    item.type == 'Playlist' && item.name == WatchlistController.kWatchlistName;

/// The page an item opens on, whatever list it was tapped in (search, a
/// library, Favorites, a Home row). A playlist opens as its list of items,
/// the Watchlist's playlist as the Watchlist, an artist as their albums and
/// a person as their filmography, never as a single title's page.
Widget itemPage(BaseItemDto item) {
  if (isWatchlistPlaylist(item)) return const WatchlistScreen();
  return switch (item.type) {
    'Playlist' => PlaylistDetailScreen(playlist: item),
    'MusicArtist' => ArtistAlbumsScreen(
      artistId: item.id,
      artistName: item.name,
    ),
    'Person' => PersonScreen(
      person: Person(
        id: item.id,
        name: item.name,
        primaryImageTag: item.primaryImageTag,
      ),
    ),
    _ => DetailScreen(item: item),
  };
}

/// Where a library from the server's list of views opens. Jellyfin lists
/// Live TV and Playlists there as if they were libraries; both have pages of
/// their own.
String libraryViewRoute(BaseItemDto view) => switch (view.collectionType) {
  'livetv' => '/livetv',
  'playlists' => '/playlists',
  _ => '/library',
};

/// Opens a library from the server's list of views on its own page.
void openLibraryView(BuildContext context, BaseItemDto view) {
  final route = libraryViewRoute(view);
  context.push(route, extra: route == '/library' ? view : null);
}
