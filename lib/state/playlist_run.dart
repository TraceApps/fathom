import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/base_item.dart';
import '../models/play_queue.dart';
import '../routing/app_shell.dart' show rootNavigatorKey;
import 'audio_player.dart';

/// Carries a playlist that mixes songs with movies and episodes from one
/// player to the other, so it plays through in its own order.
///
/// Songs play as a music queue, as far as the next video; when that queue
/// finishes, the video player opens on the video after it. The video player
/// hands back here when what comes next (or before) is a song.
class PlaylistRun {
  PlaylistRun(this._ref) {
    _ref.read(audioControllerProvider.notifier).onMusicQueueFinished =
        _musicFinished;
  }

  final Ref _ref;

  // Where the playlist goes on once the songs playing now have finished,
  // and the songs themselves, to know they're still the ones playing.
  PlayQueue? _after;
  List<String> _songIds = const [];

  /// The songs from [queue]'s current item up to the next video, and where
  /// the playlist goes on after them (null when the songs end it).
  static (List<BaseItemDto>, PlayQueue?) songsFrom(PlayQueue queue) {
    final items = queue.items;
    var end = queue.index;
    while (end < items.length && items[end].isAudio) {
      end++;
    }
    return (
      items.sublist(queue.index, end),
      end < items.length ? queue.at(end) : null,
    );
  }

  /// Plays [queue] from its current item, a song.
  Future<void> playSongs(PlayQueue queue) async {
    final (songs, after) = songsFrom(queue);
    if (songs.isEmpty) return;
    _after = after;
    _songIds = [for (final s in songs) s.id];
    await _ref.read(audioControllerProvider.notifier).playQueue(songs, 0);
  }

  void _musicFinished() {
    final after = _after;
    _after = null;
    if (after == null) return;
    // Only if what finished is what this started: other music played since
    // (an album opened meanwhile) isn't the playlist's.
    final playing = [
      for (final t in _ref.read(audioControllerProvider).queue) t.id,
    ];
    if (playing.isEmpty || !playing.every(_songIds.contains)) return;
    // And only with the app on screen: a video doesn't start by itself
    // behind a locked screen or another app.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    // The music's own bar goes away with it: the video takes over.
    _ref.read(audioControllerProvider.notifier).stopMusic();
    GoRouter.of(context).push('/player', extra: after);
  }
}

final playlistRunProvider = Provider<PlaylistRun>(PlaylistRun.new);
