import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import 'providers.dart';
import 'session_controller.dart';
import 'watchlist.dart';
import '../api/jellyfin_client.dart';

/// The signed-in user's playlists — excluding the hidden Watchlist playlist
/// ([WatchlistController.kWatchlistName]), which has its own dedicated screen
/// and shouldn't appear twice or invite manual mismanagement here.
final playlistsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final playlists = await client.getPlaylists(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
  return playlists
      .where((p) => p.name != WatchlistController.kWatchlistName)
      .toList();
});

/// The items inside a playlist, in order.
final playlistItemsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, playlistId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getPlaylistItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    playlistId: playlistId,
  );
});

/// Names given to playlists in this run of the app, by id: a page opened on
/// a playlist holds the name it was opened with, so a rename shows through
/// here until the list is read again.
class PlaylistNames extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};
  void set(String id, String name) => state = {...state, id: name};
}

final playlistNamesProvider =
    NotifierProvider<PlaylistNames, Map<String, String>>(PlaylistNames.new);

/// Whether [name] can be a playlist's name: not empty, and not the one the
/// Watchlist is kept under (a playlist by that name would become it).
bool isPlaylistNameFree(String name) =>
    name.trim().isNotEmpty &&
    name.trim().toLowerCase() !=
        WatchlistController.kWatchlistName.toLowerCase();
