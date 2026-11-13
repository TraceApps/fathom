import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show WidgetsBinding, Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/diagnostics.dart';
import 'sleep_timer.dart';
import '../services/secure_http.dart';
import 'radio.dart';

import 'audio_handler.dart';
import 'cast.dart';
import 'downloads.dart';
import '../api/jellyfin_client.dart';
import '../models/base_item.dart';
import '../models/radio_station.dart';
import '../models/session.dart';
import '../models/youtube_audio_item.dart';
import '../models/youtube_video.dart';
import '../services/live_players.dart';
import '../services/youtube_innertube.dart' show YtChannelTabKind;
import '../services/youtube_dropout.dart';
import '../services/youtube_streams.dart';
import 'providers.dart';
import 'youtube_providers.dart';
import 'session_controller.dart';
import 'volume_sync.dart';
import 'preferences.dart';

/// A single, app-wide audio player (separate from the video player).
final audioPlayerProvider = Provider<Player>((ref) {
  final player = Player();
  // Music shares the app's volume with video. One app, one pair of speakers:
  // a level set for a late-night episode should mean the same for an album.
  final volume = VolumeSync(
    player: player,
    read: () => ref.read(preferencesProvider).asData?.value.volume ?? 100,
    write: (v) =>
        ref.read(preferencesProvider.notifier).edit((x) => x.copyWith(volume: v)),
  )..attach();
  // This player is created early (mini player / radio), often before the async
  // preferences have loaded — so attach() above read the default (100, full)
  // while the slider shows the remembered level. Re-apply the stored volume the
  // moment preferences arrive so audio actually plays at that level.
  if (ref.read(preferencesProvider).asData == null) {
    late final ProviderSubscription<AsyncValue<Prefs>> sub;
    sub = ref.listen(preferencesProvider, (_, next) {
      if (next.asData != null) {
        volume.reapply();
        sub.close();
      }
    });
  }
  // Registered so quitting with music playing tears mpv down before the engine
  // goes: this provider's onDispose never runs, because nothing disposes the
  // root container at process exit.
  LivePlayers.add(player);
  ref.onDispose(() {
    volume.dispose();
    LivePlayers.remove(player);
    player.dispose();
  });
  return player;
});

class AudioState {
  final List<BaseItemDto> queue;
  final BaseItemDto? current;
  final bool shuffle;
  final PlaylistMode repeat;
  // Internet radio: when [radioStation] is set, the player is on a live radio
  // stream (not the music queue), and the UI shows a radio presentation (no
  // seek/skip). [radioTitle] is the live ICY "now playing" line, if any.
  // [radioArtwork] is a per-song album-art URL when the stream sends one
  // (iHeart-style `amgArtworkURL`); otherwise null and the UI shows the logo.
  final RadioStation? radioStation;
  final String? radioTitle;
  final String? radioArtwork;
  // Live time-shift: [radioSeekable] is true when the stream supports scrubbing
  // (rewind/skip). [radioBehindLive] is how far behind the live edge playback is
  // (Duration.zero = live). [radioWindow] is how far back you can currently go
  // (the buffered window), for drawing the scrub bar.
  final bool radioSeekable;
  final Duration radioBehindLive;
  final Duration radioWindow;

  // Background YouTube audio: when [ytCurrent] is set the player is on an
  // audio-only YouTube track (not the music queue or radio). There's no separate
  // audio queue — the up-next comes from the ONE shared youtubeQueueProvider,
  // same as the video player; audio is just a playback mode over that queue.
  final YoutubeAudioItem? ytCurrent;

  const AudioState({
    this.queue = const [],
    this.current,
    this.shuffle = false,
    this.repeat = PlaylistMode.none,
    this.radioStation,
    this.radioTitle,
    this.radioArtwork,
    this.radioSeekable = false,
    this.radioBehindLive = Duration.zero,
    this.radioWindow = Duration.zero,
    this.ytCurrent,
  });

  bool get hasTrack => current != null || ytCurrent != null;
  bool get isRadio => radioStation != null;
  bool get isYoutubeAudio => ytCurrent != null;
  // "At live" once we're within a couple of seconds of the edge.
  bool get radioAtLive => radioBehindLive.inMilliseconds < 2500;

  AudioState copyWith({
    List<BaseItemDto>? queue,
    BaseItemDto? current,
    bool? shuffle,
    PlaylistMode? repeat,
    Object? radioStation = _unset,
    Object? radioTitle = _unset,
    Object? radioArtwork = _unset,
    bool? radioSeekable,
    Duration? radioBehindLive,
    Duration? radioWindow,
    Object? ytCurrent = _unset,
  }) =>
      AudioState(
        queue: queue ?? this.queue,
        current: current ?? this.current,
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
        radioStation: radioStation == _unset
            ? this.radioStation
            : radioStation as RadioStation?,
        radioTitle:
            radioTitle == _unset ? this.radioTitle : radioTitle as String?,
        radioArtwork: radioArtwork == _unset
            ? this.radioArtwork
            : radioArtwork as String?,
        radioSeekable: radioSeekable ?? this.radioSeekable,
        radioBehindLive: radioBehindLive ?? this.radioBehindLive,
        radioWindow: radioWindow ?? this.radioWindow,
        ytCurrent: ytCurrent == _unset
            ? this.ytCurrent
            : ytCurrent as YoutubeAudioItem?,
      );
}

const _unset = Object();

/// Owns the queue, mirrors the player's track index for the UI, and reports
/// playback to the server (now-playing + play counts, i.e. scrobbling).
class AudioController extends Notifier<AudioState> {
  Player get _player => ref.read(audioPlayerProvider);
  Timer? _progressTimer;
  Timer? _radioIcyTimer; // polls the live ICY "now playing" while on radio
  Timer? _radioTick; // 1s ticker for live time-shift (behind-live / seekable)
  StreamSubscription<void>? _noisySub; // pause on BT/headphone disconnect (mobile)
  StreamSubscription<AudioInterruptionEvent>? _interruptSub; // pause on focus loss / AA disconnect
  StreamSubscription<String>? _radioErrorSub; // auto-reconnect on a dropped stream
  DateTime? _radioLastReconnectAttempt;
  // Set on a stream error, cleared once playback is actually flowing again.
  // Tells togglePlay() that resuming needs a real reconnect, not a bare
  // unpause (which can leave mpv trying to resume a dead connection and
  // replaying stale buffered data instead of continuing live).
  bool _radioNeedsReconnect = false;
  // A stream that failed to come back gets retried on a growing delay. mpv
  // stops reporting errors once it gives up, so "the next error will retry"
  // (which this used to rely on) means nothing happens at all: the station
  // sits paused until the user notices.
  Timer? _radioRetry;
  int _radioRetryAttempt = 0;
  // A reconnect's open() is running. Error events that arrive meanwhile belong
  // to that attempt and must not count as attempts of their own.
  bool _radioReconnectInFlight = false;
  // Bumped when the user pauses or stops mid-reconnect, so an attempt already
  // in flight knows to stand down instead of starting the station again.
  int _radioReconnectGen = 0;
  // Set when that stand-down was a pause (not a new station or a stop), so
  // the attempt pauses the station it just reopened. Cleared by any new
  // attempt, which means the user asked to play again.
  bool _radioPausedMidReconnect = false;

  /// Radio is between a dropped connection and audio flowing again: an
  /// attempt in flight or the next one queued. The OS media session is told
  /// playback is still on (buffering) throughout; see [_pushPlaybackState].
  bool get _radioReconnecting =>
      state.isRadio &&
      !_pausedByInterruption && // a call's pause is a real pause
      (_radioReconnectInFlight || (_radioRetry?.isActive ?? false));
  // True while playback is paused by something transient (a recording app, a
  // call, a notification). Radio reconnects rather than unpauses when the
  // interruption ends, since a live stream can't resume where it stopped.
  bool _pausedByInterruption = false;
  // Live edge in playback time: advances by wall-clock every tick, so pausing or
  // rewinding leaves playback behind it. Reset on tune / go-live.
  Duration _radioEdge = Duration.zero;
  DateTime? _radioTickWall;
  static const _radioMaxWindow = Duration(minutes: 30);
  String? _artLookupKey; // the song title whose artwork we're currently resolving
  int _emptyIcyCount = 0; // consecutive empty ICY reads (debounces ad/gap clears)
  String? _reportedId;
  int _lastPositionTicks = 0;
  // Background YouTube audio: whether to auto-append a related track at the end,
  // and a guard so overlapping completion/next events don't double-advance while
  // the next track's stream URL is still resolving.
  bool _ytAutoplay = true;
  bool _ytAdvancing = false;
  // Consecutive resolve failures (YouTube bot wall / rate limit). A failed track
  // auto-advances rather than dead-ending, but a fully blocked playlist must not
  // blast through every track in a couple seconds — stop after this many in a
  // row. Reset on any successful open or user-initiated skip.
  int _ytResolveFailStreak = 0;
  // Dropouts on the current YouTube track (see YtDropoutWatch), fresh for
  // every play of a track, so a dropped connection reloads the track instead
  // of skipping it.
  YtDropoutWatch _ytDropout = YtDropoutWatch();
  // A dropped track whose reload couldn't get through (still offline): Play
  // tries it again from this spot rather than resuming a dead link.
  ({YoutubeAudioItem item, Duration at})? _ytStalled;
  static const _ytMaxResolveFailStreak = 4;
  // Bumped on every YouTube-audio open, so a load-watchdog from a track we've
  // already moved past can't skip the current one.
  int _ytLoadToken = 0;
  // Resolved audio-URL cache (YouTube URLs last ~6h; cache under that) so a
  // pre-resolved next track opens instantly instead of gapping while it fetches.
  final Map<String, ({String url, DateTime at})> _ytUrlCache = {};
  static const _ytUrlTtl = Duration(hours: 5);
  // Videos played this background session, so continuation never loops back onto
  // one you just heard.
  final Set<String> _ytPlayed = {};
  // Ordered history of YouTube-audio items played, so Previous can step back a
  // song (the shared queue is forward-only and discards played tracks).
  final List<YoutubeAudioItem> _ytHistory = [];
  final Map<String, BaseItemDto> _byId = {};
  final _random = Random();
  // The OS media session (mobile only); null on desktop or if init failed.
  FathomAudioHandler? _handler;

  // The platform audio session. We hold media audio focus while playing so the
  // system — and Android Auto / a projected head unit — routes our output;
  // without focus the car stays silent even though playback is running.
  AudioSession? _audioSession;

  // A bundled radio glyph, copied to a cache file so the media notification has
  // artwork to show for stations that carry no favicon (audio_service loads art
  // from a file/content URI, not a Flutter asset). Null until first prepared.
  Uri? _radioArtUri;

  /// Ensures the radio fallback artwork exists on disk and caches its file URI.
  /// Best-effort: on any failure the notification simply falls back to no art.
  Future<void> _ensureRadioArt() async {
    if (_radioArtUri != null) return;
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/fathom_radio_art.png');
      if (!await f.exists()) {
        final data = await rootBundle.load('assets/radio_art.png');
        await f.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      }
      _radioArtUri = Uri.file(f.path);
    } catch (_) {
      // Leave null — _pushRadioNowPlaying just omits art.
    }
  }

  // The stream URL always contains /Audio/{itemId}/stream — resolve the current
  // track by URL so it stays correct even after shuffling reorders the queue.
  static final _idPattern = RegExp(r'/Audio/([^/]+)/stream');
  String? _itemIdFromUri(String uri) => _idPattern.firstMatch(uri)?.group(1);

  @override
  AudioState build() {
    // Hand off to / back from a Chromecast. On connect, pause local so audio
    // isn't playing in two places. On disconnect, resume local from the track
    // and position the receiver reached (like Spotify/YT Music), so stopping
    // the cast continues seamlessly on the phone.
    ref.listen(castControllerProvider.select((s) => s.casting), (prev, next) {
      if (next == true) {
        _player.pause();
      } else if (prev == true) {
        final c = ref.read(castControllerProvider);
        _resumeLocalFromCast(c.currentUrl, c.positionMs, c.playing);
      }
    });
    // Follow the receiver's current queue item (it auto-advances / Skip on the
    // device), so the app's now-playing display tracks what's actually playing.
    ref.listen(castControllerProvider.select((s) => s.currentUrl), (_, url) {
      if (url == null) return;
      final id = RegExp(r'/Audio/([0-9a-fA-F]+)/').firstMatch(url)?.group(1);
      if (id == null || id == state.current?.id) return;
      final matches = state.queue.where((t) => t.id == id);
      if (matches.isNotEmpty) state = state.copyWith(current: matches.first);
    });
    // Wire the OS media session (mobile). The handler owns no player, so route
    // its transport buttons back into ours; state is pushed the other way below.
    _handler = ref.read(audioHandlerProvider);
    final h = _handler;
    if (h != null) {
      // Radio after a dropped connection needs a real reconnect, not a bare
      // unpause of the dead one; and a pause mid-reconnect must stop the
      // retries, or the next one starts the station again.
      h.onPlay = () => state.isRadio && _radioNeedsReconnect
          ? _reconnectRadio(force: true)
          : (_retryStalledYt() ?? _player.play());
      h.onPause = () async {
        if (state.isRadio) _cancelRadioReconnect('paused');
        await _player.pause();
      };
      // Skip routes by mode: radio has no track queue, so skip means switch
      // station; the YouTube queue advances itself (one track at a time); the
      // music queue uses the player's own playlist.
      h.onNext = () => state.isRadio
          ? _radioSkip(1)
          : state.isYoutubeAudio
              ? _ytNext(user: true)
              : _player.next();
      h.onPrevious = () => state.isRadio
          ? _radioSkip(-1)
          : state.isYoutubeAudio
              ? _ytPrevious()
              : _player.previous();
      h.onSeek = _player.seek;
      // Stop from the notification: leave radio / YouTube-audio mode entirely,
      // else just stop the music queue.
      h.onStop = () async => state.isRadio
          ? await stopRadio()
          : state.isYoutubeAudio
              ? await stopYoutubeAudio()
              : _player.stop();
      // Android Auto (and any MediaBrowser client): serve the browse tree and
      // route tapped items / voice search into the same playback methods the
      // in-app UI uses, so behaviour is identical in the car.
      h.onGetChildren = _autoGetChildren;
      h.onPlayFromMediaId = _autoPlayFromMediaId;
      h.onSearch = _autoSearch;
      h.onPlayFromSearch = _autoPlayFromSearch;
      // Now-playing controls from the car / notification.
      h.onSetShuffle = (enabled) async {
        if (state.shuffle != enabled) await toggleShuffle();
      };
      h.onSetRepeat = (mode) async {
        await _setRepeat(switch (mode) {
          AudioServiceRepeatMode.one => PlaylistMode.single,
          AudioServiceRepeatMode.all ||
          AudioServiceRepeatMode.group =>
            PlaylistMode.loop,
          AudioServiceRepeatMode.none => PlaylistMode.none,
        });
      };
      h.onSkipToQueueItem = (index) async {
        if (state.isYoutubeAudio) {
          await _ytJumpTo(index);
        } else {
          await jumpTo(index);
        }
      };
      h.onToggleFavorite = _toggleCurrentFavorite;
      h.onToggleShuffle = toggleShuffle;
      h.onCycleRepeat = cycleRepeat;
      // Keep the car's up-next in sync as the shared YouTube queue changes.
      ref.listen(youtubeQueueProvider, (_, _) {
        if (state.isYoutubeAudio) _pushQueue();
      });
      // Pause on Bluetooth/headphone disconnect (audio "becoming noisy"), like
      // every media app: blasting out of the phone speaker after you unplug is
      // jarring. Mobile-only (h != null). No-op while casting (local is paused).
      AudioSession.instance.then((session) async {
        _audioSession = session;
        // Configure the session FIRST: without this the platform never registers
        // the audio-becoming-noisy receiver, so a Bluetooth/headset disconnect
        // wouldn't pause and radio would blast out of the phone speaker. Video
        // playback configures its own session, but radio/audio needs this here
        // (there's no video screen to do it).
        await session.configure(const AudioSessionConfiguration.music());
        _noisySub = session.becomingNoisyEventStream.listen((_) {
          Diagnostics.instance.add(
              'media', 'audio became noisy, playing=${_player.state.playing}');
          if (_player.state.playing) _player.pause();
        });
        // Pause when we lose audio focus — this is what fires when Android Auto
        // (or a Bluetooth car) disconnects and audio would otherwise fall back to
        // the phone speaker. We don't auto-resume on the tail: a disconnect is
        // deliberate, so playback stays paused until the user restarts it.
        _interruptSub = session.interruptionEventStream.listen((event) {
          Diagnostics.instance.add('media',
              'audio focus ${event.begin ? 'lost' : 'back'} (${event.type.name})');
          // Losing focus for good drops it on the platform side; ask again on
          // the next play (see _activateAudioSession).
          if (event.begin && event.type == AudioInterruptionType.unknown) {
            _focusGranted = null;
          }
          if (event.begin) {
            if (!_player.state.playing) return;
            // A transient interruption (a recording app taking the mic, a call,
            // a notification) says to come back afterwards; an unknown one is a
            // deliberate handover like a Bluetooth or Android Auto disconnect,
            // where resuming would blast out of the phone speaker.
            _pausedByInterruption = event.type != AudioInterruptionType.unknown;
            Diagnostics.instance.add('radio',
                'interrupted (${event.type.name}), resume=$_pausedByInterruption');
            _player.pause();
            return;
          }
          if (!_pausedByInterruption) return;
          _pausedByInterruption = false;
          Diagnostics.instance.add('radio', 'interruption over, resuming');
          if (state.isRadio) {
            // The connection is long dead by now (the log shows the server
            // dropping it about ten seconds in), so take it from the top.
            unawaited(_reconnectRadio(force: true));
          } else if (state.hasTrack) {
            unawaited(_player.play());
          }
        });
      }).catchError((_) {});
    }

    // Prefetch the next playlist entry so music transitions are near-gapless
    // (mpv doesn't do this by default). YouTube audio is single Medias, so it
    // pre-resolves the next URL separately. An mpv option; harmless elsewhere.
    try {
      final p = _player.platform as dynamic;
      unawaited(p.setProperty('prefetch-playlist', 'yes'));
      // On Android, output via AudioTrack (not OpenSL ES): AudioTrack carries the
      // media audio attributes + focus that Android — and Android Auto — route
      // by, so a projected head unit actually gets our sound.
      if (Platform.isAndroid) unawaited(p.setProperty('ao', 'audiotrack'));
    } catch (_) {}
    _applyReplayGain();
    // Follow the setting live, so changing it doesn't need a restart or a
    // track change to take effect.
    ref.listen(preferencesProvider, (prev, next) {
      final a = prev?.asData?.value;
      final b = next.asData?.value;
      if (b == null) return;
      if (a?.replayGain != b.replayGain ||
          a?.replayGainFallback != b.replayGainFallback) {
        _applyReplayGain();
      }
    });

    final subPlaylist = _player.stream.playlist.listen((pl) {
      // Keep the visible queue in the player's real order (matters once shuffle
      // or a reorder has rearranged things), and follow the current track.
      final ordered = pl.medias
          .map((m) => _byId[_itemIdFromUri(m.uri)])
          .whereType<BaseItemDto>()
          .toList();
      final id = (pl.index >= 0 && pl.index < pl.medias.length)
          ? _itemIdFromUri(pl.medias[pl.index].uri)
          : null;
      final track = id != null ? _byId[id] : null;
      if (track != null && track.id != state.current?.id) {
        _reportStopped();
        _lastPositionTicks = 0;
        _reportStart(track.id);
        state = state.copyWith(
            queue: ordered.isNotEmpty ? ordered : state.queue, current: track);
        _pushNowPlaying();
        _pushPlaybackState(); // refresh the Favorite heart for the new track
        _pushQueue();
      } else if (ordered.isNotEmpty) {
        state = state.copyWith(queue: ordered);
        _pushQueue();
      }
    });
    final subPosition = _player.stream.position.listen((p) {
      _lastPositionTicks = p.inMicroseconds * 10;
    });
    // The music queue auto-advances via the player's playlist; a YouTube-audio
    // track is a single Media, so advance the YouTube queue ourselves when it
    // finishes.
    final subCompleted = _player.stream.completed.listen((done) {
      if (!done || !state.isYoutubeAudio) return;
      // media_kit also fires `completed` when a media fails to open (its
      // duration stays zero). Only a real end-of-track — a non-zero duration
      // that actually played out — should advance, otherwise a bad/expired URL
      // cascades "completed -> next -> completed" through the whole queue.
      if (_player.state.duration <= Duration.zero) return;
      // A dropped connection ends the track early (the link is tied to the
      // old address and the reconnect is refused): reload it from the same
      // spot with a fresh link instead of moving on.
      final cur = state.ytCurrent;
      final pos = _player.state.position;
      if (cur != null &&
          YtDropoutWatch.endedEarly(pos, _player.state.duration)) {
        if (_ytDropout.takeTry(pos)) {
          Diagnostics.instance.add('yt', 'track dropped at ${pos.inSeconds}s; '
              'reloading (try ${_ytDropout.tries})');
          _ytUrlCache.remove(cur.videoId); // the old link is the dead one
          unawaited(_playYtItem(cur, startAt: pos, reload: true));
          return;
        }
        Diagnostics.instance.add(
            'yt', 'track keeps dropping; moving on at ${pos.inSeconds}s');
      }
      // The sleep timer is set to stop at the end of this track.
      if (ref.read(sleepTimerProvider.notifier).consumeEndOfItem()) return;
      // Repeat-one: replay the current track instead of advancing. The Next
      // button still skips, because it calls _ytNext directly.
      if (state.repeat == PlaylistMode.single) {
        _ytDropout = YtDropoutWatch(); // a new play of the track
        unawaited(_player.seek(Duration.zero));
        unawaited(_player.play());
        return;
      }
      _ytNext();
    });
    // Mirror transport state to the media session. Position is extrapolated by
    // the OS between updates, so pushing on play/pause/buffer/duration changes
    // (plus the 10s progress tick) keeps the notification honest.
    StreamSubscription<bool>? subPlaying, subBuffering;
    StreamSubscription<Duration>? subDuration;
    if (h != null) {
      subPlaying = _player.stream.playing.listen((playing) {
        _pushPlaybackState();
        // Claim audio focus whenever playback starts, not only when a source
        // is opened. Another app taking focus for good makes audio_session
        // drop both the focus and its headphone-disconnect listener, and
        // resuming with Play never asked for them back: no pause when the
        // earbuds disconnect, and two apps playing over each other.
        // setActive is a no-op while focus is already held.
        if (playing) unawaited(_activateAudioSession());
      });
      subBuffering = _player.stream.buffering.listen((_) => _pushPlaybackState());
      // Re-publish now-playing once the real duration is known.
      subDuration = _player.stream.duration.listen((_) => _pushNowPlaying());
    }
    // A dropped connection (network loss, a dead cell zone) surfaces here as a
    // stream error, not a user pause. Auto-reconnect at the live edge instead
    // of leaving the station stalled on a connection that's never coming back
    // on its own; also flags togglePlay() in case the user hits Play first.
    _radioErrorSub = _player.stream.error.listen((e) {
      if (!state.isRadio) return;
      Diagnostics.instance.add('radio', 'stream error: $e, reconnecting');
      _radioNeedsReconnect = true;
      unawaited(_reconnectRadio());
    });
    final subRadioPlaying = _player.stream.playing.listen((playing) {
      if (!state.isRadio) return;
      Diagnostics.instance.add('radio', 'playing=$playing');
    });
    final subRadioBuffering = _player.stream.buffering.listen((buffering) {
      if (state.isRadio) {
        Diagnostics.instance.add('radio', 'buffering=$buffering');
        // Buffering ending with the player playing is the first moment audio
        // is really flowing; `playing` alone goes true while mpv is still
        // trying a dead connection.
        if (!buffering && _player.state.playing) {
          _radioNeedsReconnect = false;
          _radioRecovered();
        }
      }
    });
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _reportProgress();
      _pushPlaybackState();
    });
    // Sleep timer: a timed stop fades out whatever is playing (or pauses the
    // cast device); "end of track" pauses just before the track ends instead
    // of letting the queue move on. Checked against the position rather than
    // waiting for a track change, because the queue advances inside the
    // player itself and the next song would already be playing.
    final sleep = ref.read(sleepTimerProvider.notifier);
    final unregisterSleep = sleep.register((fade) async {
      final cast = ref.read(castControllerProvider);
      if (cast.casting) {
        if (cast.playing) await ref.read(castControllerProvider.notifier).pause();
        return;
      }
      await fadeOutAndPause(_player, fade);
    });
    final subSleepEnd = _player.stream.position.listen((pos) {
      if (!sleep.stopsAtEndOfItem || state.isRadio || !_player.state.playing) {
        return;
      }
      final dur = _player.state.duration;
      if (dur > Duration.zero &&
          dur - pos <= const Duration(milliseconds: 400) &&
          sleep.consumeEndOfItem()) {
        unawaited(_player.pause());
      }
    });
    ref.onDispose(() {
      unregisterSleep();
      subSleepEnd.cancel();
      subPlaylist.cancel();
      subPosition.cancel();
      subCompleted.cancel();
      subPlaying?.cancel();
      subBuffering?.cancel();
      subDuration?.cancel();
      subRadioPlaying.cancel();
      subRadioBuffering.cancel();
      _progressTimer?.cancel();
      _radioIcyTimer?.cancel();
      _radioTick?.cancel();
      _radioRetry?.cancel();
      _noisySub?.cancel();
      _interruptSub?.cancel();
      _radioErrorSub?.cancel();
      _reportStopped();
    });
    return const AudioState();
  }

  /// Publish the current track's metadata to the OS media session.
  void _pushNowPlaying() {
    // YouTube audio publishes its own MediaItem (title/channel/thumbnail); a
    // duration event should refresh THAT, not push a stale music track over it.
    if (state.isYoutubeAudio) {
      _pushYtNowPlaying(state.ytCurrent);
      return;
    }
    // Radio publishes its own MediaItem via _pushRadioNowPlaying; don't let a
    // stream duration/playlist event push a stale music track over it.
    if (state.isRadio) return;
    final h = _handler;
    final t = state.current;
    if (h == null || t == null) return;
    final c = _ctx();
    Uri? art;
    if (c != null) {
      // A song usually has no image of its own; the album carries the art. Fall
      // back to it, matching MediaImage's resolution.
      String? imgItemId, imgTag;
      if (t.primaryImageTag != null) {
        imgItemId = t.id;
        imgTag = t.primaryImageTag;
      } else if (t.albumPrimaryImageTag != null && t.albumId != null) {
        imgItemId = t.albumId;
        imgTag = t.albumPrimaryImageTag;
      }
      if (imgItemId != null) {
        art = Uri.tryParse(c.client.imageUrl(
          baseUrl: c.session.baseUrl,
          itemId: imgItemId,
          tag: imgTag,
          maxHeight: 512,
        ));
      }
    }
    final dur = _player.state.duration;
    h.setNowPlaying(MediaItem(
      id: t.id,
      title: t.name,
      artist: t.albumArtist ??
          (t.artists.isNotEmpty ? t.artists.join(', ') : null),
      album: t.album,
      duration: dur > Duration.zero ? dur : null,
      artUri: art,
    ));
  }

  /// Publish current transport state (playing/paused, position, buffered).
  void _pushPlaybackState() {
    final h = _handler;
    if (h == null) return;
    final s = _player.state;
    final t = state.current;
    // Favorite heart + shuffle/repeat: only for a Jellyfin library track.
    final musicQueue = !state.isRadio && !state.isYoutubeAudio && t != null;
    bool? favorite;
    if (musicQueue) {
      favorite = _favOverride[t.id] ?? t.userData.isFavorite;
    }
    // Which queue row the car highlights: the current track's index for music,
    // always the head (0) for YouTube (current + up-next), nothing for radio.
    int? queueIndex;
    if (state.isYoutubeAudio) {
      queueIndex = 0;
    } else if (!state.isRadio) {
      final i = currentIndex;
      if (i >= 0) queueIndex = i;
    }
    // Mid-reconnect the player itself reads stopped, but to the listener the
    // station is still on, just reconnecting. Saying so keeps the media
    // notification honest (a pause button, not play) and, on Android, keeps
    // Fathom a foreground media app: reported as paused, the system freezes
    // it in the background and the queued retry never fires.
    final reconnecting = _radioReconnecting;
    h.setPlayback(
      playing: s.playing || reconnecting,
      buffering: s.buffering || reconnecting,
      position: s.position,
      buffered: s.buffer,
      speed: s.rate,
      radio: state.isRadio,
      shuffle: state.shuffle,
      repeat: switch (state.repeat) {
        PlaylistMode.single => AudioServiceRepeatMode.one,
        PlaylistMode.loop => AudioServiceRepeatMode.all,
        PlaylistMode.none => AudioServiceRepeatMode.none,
      },
      favorite: favorite,
      queueIndex: queueIndex,
      musicQueue: musicQueue,
    );
  }

  /// Jump to a row in the YouTube queue. Row 0 is the current track; the rest
  /// index into the shared up-next, which we advance to that point.
  Future<void> _ytJumpTo(int index) async {
    if (!state.isYoutubeAudio) return;
    if (index <= 0) {
      await _player.seek(Duration.zero);
      return;
    }
    final q = ref.read(youtubeQueueProvider);
    final target = index - 1; // row 0 is the current track
    if (target < 0 || target >= q.length) return;
    ref.read(youtubeQueueProvider.notifier).playAll(q.sublist(target + 1));
    await _playYtItem(_toAudioItem(q[target]));
  }

  // Local favorite overrides for the current session, so the heart flips
  // instantly on toggle without re-fetching the item from the server.
  final Map<String, bool> _favOverride = {};

  Future<void> _setRepeat(PlaylistMode mode) async {
    await _player.setPlaylistMode(mode);
    state = state.copyWith(repeat: mode);
    _pushPlaybackState();
  }

  /// Toggle the current track's Jellyfin favorite (the car's heart button).
  Future<void> _toggleCurrentFavorite() async {
    final t = state.current;
    final c = _ctx();
    if (t == null || c == null) return;
    final current = _favOverride[t.id] ?? t.userData.isFavorite;
    final next = !current;
    _favOverride[t.id] = next;
    _pushPlaybackState(); // reflect immediately
    try {
      await c.client.setFavorite(
        baseUrl: c.session.baseUrl,
        userId: c.session.userId,
        token: c.session.accessToken,
        itemId: t.id,
        favorite: next,
      );
    } catch (_) {
      _favOverride[t.id] = current; // revert on failure
      _pushPlaybackState();
    }
  }

  /// Publish the music queue as the media session's up-next list, so the car
  /// shows the queue and can jump within it. Radio/YouTube carry no such queue.
  void _pushQueue() {
    final h = _handler;
    if (h == null) return;
    // Radio is a single live stream — no queue.
    if (state.isRadio) {
      if (h.queue.valueOrNull?.isNotEmpty ?? false) h.queue.add(const []);
      return;
    }
    // YouTube audio: the current track followed by the shared up-next queue, so
    // playing off a playlist shows the rest and you can jump within it.
    if (state.isYoutubeAudio) {
      final cur = state.ytCurrent;
      final up = ref.read(youtubeQueueProvider);
      h.queue.add([
        if (cur != null)
          MediaItem(
            id: cur.videoId,
            title: cur.title,
            artist: cur.author,
            artUri: Uri.tryParse(cur.thumbnailUrl),
          ),
        for (final v in up)
          MediaItem(
            id: v.id,
            title: v.title,
            artist: v.author,
            artUri: Uri.tryParse(v.thumbnailUrl),
          ),
      ]);
      return;
    }
    final c = _ctx();
    h.queue.add([
      for (final t in state.queue)
        MediaItem(
          id: t.id,
          title: t.name,
          artist: t.albumArtist ??
              (t.artists.isNotEmpty ? t.artists.join(', ') : null),
          album: t.album,
          artUri: c == null ? null : _autoArt(t, c),
        ),
    ]);
  }

  ({Session session, JellyfinClient client})? _ctx() {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return null;
    return (session: session, client: ref.read(jellyfinClientProvider));
  }

  /// A media source for a track: its downloaded local file if present (so it
  /// plays offline, in the music player), otherwise the server audio stream.
  /// Null when neither is available (offline and not downloaded).
  Media? _mediaFor(BaseItemDto track) {
    final local = ref.read(downloadsProvider.notifier).localPathFor(track.id);
    if (local != null) return Media(local);
    final c = _ctx();
    if (c == null) return null;
    return Media(c.client.audioStreamUrl(
      baseUrl: c.session.baseUrl,
      itemId: track.id,
      token: c.session.accessToken,
    ));
  }

  Future<void> playQueue(List<BaseItemDto> tracks, int startIndex,
      {bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    _radioIcyTimer?.cancel(); // leaving radio for the music queue
    _radioTick?.cancel();
    // Prefer a downloaded track's local file (works offline); otherwise stream
    // from the server. A track that's neither is dropped so the index stays valid.
    final wantId = tracks[startIndex].id;
    final playable = <BaseItemDto>[];
    final medias = <Media>[];
    for (final t in tracks) {
      final m = _mediaFor(t);
      if (m != null) {
        playable.add(t);
        medias.add(m);
      }
    }
    if (medias.isEmpty) return;
    tracks = playable;
    _reportStopped();
    _byId
      ..clear()
      ..addEntries(tracks.map((t) => MapEntry(t.id, t)));
    // Shuffle: start on a RANDOM track (not always the first) and turn the
    // player's shuffle mode on. A normal play starts at [startIndex] in order,
    // and explicitly turns shuffle off so the two buttons are true opposites.
    var startAt = tracks.indexWhere((t) => t.id == wantId);
    if (startAt < 0) startAt = 0;
    final index =
        (shuffle && tracks.length > 1) ? _random.nextInt(tracks.length) : startAt;
    state = state.copyWith(
        queue: tracks,
        current: tracks[index],
        shuffle: shuffle,
        // Leaving a YouTube item set keeps isYoutubeAudio true, so the OS media
        // session would keep showing the YouTube title/art over this track.
        ytCurrent: null,
        radioStation: null,
        radioTitle: null,
        radioSeekable: false,
        radioBehindLive: Duration.zero,
        radioWindow: Duration.zero);
    await _activateAudioSession();
    await _player.open(Playlist(medias, index: index));
    _applyVolume();
    await _player.setShuffle(shuffle);
    _lastPositionTicks = 0;
    _reportStart(tracks[index].id);
    // Publish to the media session right away so its foreground notification
    // appears promptly (and Android sees startForeground before its deadline).
    _pushNowPlaying();
    _pushPlaybackState();
    _pushQueue();
  }

  /// Play an internet-radio station: opens its live stream (replacing the music
  /// queue), switches the UI to the radio presentation, and polls ICY metadata.
  Future<void> playStation(RadioStation s) async {
    Diagnostics.instance.add('radio', 'tuning in: ${s.name}');
    _radioIcyTimer?.cancel();
    _radioTick?.cancel();
    _radioRetry?.cancel();
    _radioRetryAttempt = 0;
    _radioReconnectGen++; // an old station's attempt in flight stands down
    _radioPausedMidReconnect = false;
    _reportStopped(); // no Jellyfin scrobble for radio
    _reportedId = null;
    _radioNeedsReconnect = false;
    state = state.copyWith(
      radioStation: s,
      // Clear any YouTube item — otherwise isYoutubeAudio stays true and the
      // media session keeps showing the YouTube title/art/time over the radio.
      ytCurrent: null,
      radioTitle: null,
      radioArtwork: null,
      radioSeekable: false,
      radioBehindLive: Duration.zero,
      radioWindow: Duration.zero,
    );
    _radioEdge = Duration.zero;
    _emptyIcyCount = 0;
    _radioTickWall = null;
    await _ensureRadioArt(); // ready before the first now-playing push
    await _configureRadioBuffer();
    await _activateAudioSession();
    await _player.open(Media(s.url));
    _applyVolume();
    _pushRadioNowPlaying(s, null);
    _pushPlaybackState();
    _pushQueue(); // radio has no queue — clears any leftover music queue
    _startIcyPolling();
    _startRadioTick();
  }

  /// Switches to the next ([step] 1) or previous ([step] -1) station, for the
  /// media notification / Android Auto / car skip buttons. Walks
  /// [RadioController.skipOrder] (Favorites, then each group, then
  /// Ungrouped, the same order the Radio screen shows), wrapping at either
  /// end. If the current station isn't in that list at all (a Browse/search
  /// preview that was never saved), next lands on the first saved station and
  /// previous on the last, rather than doing nothing.
  Future<void> _radioSkip(int step) async {
    final order = ref.read(radioControllerProvider.notifier).skipOrder;
    if (order.isEmpty) return;
    final current = state.radioStation;
    final i = current == null
        ? -1
        : order.indexWhere((s) => s.id == current.id);
    if (i < 0) {
      await playStation(step > 0 ? order.first : order.last);
      return;
    }
    final wrapped = (i + step) % order.length;
    await playStation(order[wrapped < 0 ? wrapped + order.length : wrapped]);
  }

  /// Enable a back-buffer + forced seeking so we can pause (and keep buffering)
  /// and, where the stream allows, rewind/skip within the buffered window.
  Future<void> _configureRadioBuffer() async {
    try {
      final p = _player.platform as dynamic;
      const bytes = 96 * 1024 * 1024; // ~96 MiB each way (several minutes of audio)
      await p.setProperty('force-seekable', 'yes');
      await p.setProperty('demuxer-max-bytes', '$bytes');
      await p.setProperty('demuxer-max-back-bytes', '$bytes');
    } catch (_) {}
  }

  /// Stop radio and leave radio mode (back to whatever music context existed).
  Future<void> stopRadio() async {
    _radioIcyTimer?.cancel();
    _radioTick?.cancel();
    _radioRetry?.cancel();
    _radioRetryAttempt = 0;
    _radioReconnectGen++;
    _radioPausedMidReconnect = false;
    _radioNeedsReconnect = false;
    await _player.stop();
    state = state.copyWith(
      radioStation: null,
      radioTitle: null,
      radioArtwork: null,
      radioSeekable: false,
      radioBehindLive: Duration.zero,
      radioWindow: Duration.zero,
    );
  }

  // ---- Background YouTube audio (a mode over the shared YouTube queue) -----

  YoutubeAudioItem _toAudioItem(YoutubeVideo v) => YoutubeAudioItem(
        videoId: v.id,
        title: v.title,
        author: v.author,
        thumbnailUrl: v.thumbnailUrl,
        duration: v.duration,
      );

  /// Play a YouTube video's audio in the background. Reuses the whole audio stack
  /// (foreground service, OS media controls, mini-player) and — crucially — the
  /// ONE shared `youtubeQueueProvider` for up-next, so enqueuing behaves the same
  /// in audio and video mode. [startAt] resumes at the position handed off from
  /// the video player; [autoplay] plays a related track when the queue runs dry.
  Future<void> playYoutubeAudio(
    YoutubeAudioItem item, {
    Duration startAt = Duration.zero,
    bool autoplay = true,
  }) async {
    _radioIcyTimer?.cancel();
    _radioTick?.cancel();
    _reportStopped(); // no Jellyfin scrobble for YouTube
    _reportedId = null;
    _ytAutoplay = autoplay;
    _ytPlayed.clear(); // a fresh Listen session may revisit videos
    state = state.copyWith(
      ytCurrent: item,
      radioStation: null,
      radioTitle: null,
      radioArtwork: null,
      radioSeekable: false,
      radioBehindLive: Duration.zero,
      radioWindow: Duration.zero,
    );
    await _playYtItem(item, startAt: startAt);
  }

  /// Resolve an item's audio stream (cached / fresh, so an expired URL is never
  /// reused) and open it. Pushes now-playing and pre-resolves the next queued
  /// item so the hand-over when this one ends is near-seamless.
  Future<void> _playYtItem(YoutubeAudioItem item,
      {Duration startAt = Duration.zero,
      bool retried = false,
      bool reload = false}) async {
    // Claim this load up front so a newer skip (Next/Previous pressed while this
    // slow resolve is still running) supersedes it — otherwise the stale resolve
    // opens over the track the user actually skipped to.
    final token = ++_ytLoadToken;
    _ytStalled = null;
    // A new play of a track starts its dropout tries over; a reload keeps
    // counting.
    if (!reload) _ytDropout = YtDropoutWatch();
    final url = await _resolveYtUrl(item.videoId);
    if (token != _ytLoadToken) return; // superseded by a newer skip
    if (url == null) {
      // Couldn't resolve (YouTube bot wall / rate limit). Advance to the next
      // track rather than dead-ending on this one — but bypass the advance guard
      // (we're likely inside an in-flight _ytNext, whose _ytAdvancing=true would
      // otherwise swallow this) and cap consecutive failures so a fully blocked
      // playlist doesn't race through every track in seconds. Don't retry: it
      // only adds requests and deepens any rate-limit throttle.
      if (token != _ytLoadToken) return; // superseded by a newer skip
      // Reloading a dropped track: the network is likely still down, and
      // moving on would ignore repeat-one and the sleep timer. Stop here,
      // and let Play try again from the same spot.
      if (reload) {
        _ytStalled = (item: item, at: startAt);
        Diagnostics.instance.add('yt',
            'track reload failed (offline?); Play retries at ${startAt.inSeconds}s');
        return;
      }
      if (++_ytResolveFailStreak >= _ytMaxResolveFailStreak) {
        _ytResolveFailStreak = 0;
        _ytAdvancing = false; // release so the user can start playback again
        return; // give up quietly instead of blasting through the whole queue
      }
      await _ytNext(onFailure: true);
      return;
    }
    if (!state.isYoutubeAudio) return; // left YouTube mode while resolving
    _ytResolveFailStreak = 0; // resolved OK — clear the failure guard
    if (!reload) _ytPlayed.add(item.videoId);
    state = state.copyWith(ytCurrent: item);
    await _activateAudioSession();
    if (token != _ytLoadToken) return; // superseded during session activation
    // Open at the spot rather than at 0:00 and seek: no blip of the start.
    await _player.open(
        Media(url, start: startAt > Duration.zero ? startAt : null));
    _applyVolume();
    // A reload is the same track: the now-playing card, the queue and the
    // next track's link are already in place.
    if (!reload) {
      _pushYtNowPlaying(item);
      _pushPlaybackState();
      _pushQueue(); // current track advanced: refresh the car's up-next
      final up = ref.read(youtubeQueueProvider);
      if (up.isNotEmpty) unawaited(_resolveYtUrl(up.first.id));
    } else {
      _pushPlaybackState();
    }
    unawaited(_watchLoad(item, token, retried, startAt, reload));
  }

  /// Guard against a track that never actually loads — an expired or blocked URL
  /// that media_kit neither plays nor reports a duration for. If no real
  /// duration arrives, re-resolve a fresh URL once (a stale cached URL is the
  /// usual culprit), then skip forward — rather than hang on "loading" forever.
  Future<void> _watchLoad(YoutubeAudioItem item, int token, bool retried,
      Duration startAt, bool reload) async {
    if (_player.state.duration > Duration.zero) return;
    try {
      await _player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 12));
      return; // loaded fine
    } catch (_) {
      // Timed out with no duration. Ignore if we've since moved to another track.
      if (token != _ytLoadToken ||
          !state.isYoutubeAudio ||
          state.ytCurrent?.videoId != item.videoId) {
        return;
      }
      if (!retried) {
        _ytUrlCache.remove(item.videoId); // drop the (likely stale) URL
        await _playYtItem(item,
            startAt: startAt, retried: true, reload: reload);
      } else if (!reload) {
        await _ytNext();
      } else {
        _ytStalled = (item: item, at: startAt);
        Diagnostics.instance.add('yt',
            'track reload never loaded (offline?); Play retries at ${startAt.inSeconds}s');
      }
    }
  }

  /// Re-apply the remembered volume to the audio player. media_kit keeps this
  /// player's last volume across `open()`, so a fresh source (e.g. handing off
  /// from a video playing at 50%) would otherwise start at this player's stale
  /// level until the slider is nudged. Called after every open.
  void _applyVolume() {
    final v = (ref.read(preferencesProvider).asData?.value.volume ?? 100)
        .toDouble()
        .clamp(0.0, 100.0);
    unawaited(_player.setVolume(v));
  }

  /// Take media audio focus. Called at each playback start so the system — and
  /// Android Auto — routes our audio; without it a projected head unit is silent.
  Future<void> _activateAudioSession() async {
    try {
      final s = _audioSession ??= await AudioSession.instance;
      final granted = await s.setActive(true);
      // Logged only when it changes: this runs on every play.
      if (granted != _focusGranted) {
        _focusGranted = granted;
        Diagnostics.instance.add('media', 'audio focus requested: granted=$granted');
      }
    } catch (e) {
      Diagnostics.instance.add('media', 'audio focus request failed: $e');
    }
  }

  bool? _focusGranted;

  /// Resolve an item's audio URL, reusing a recently-resolved one from the cache
  /// so a pre-resolved next track opens instantly.
  Future<String?> _resolveYtUrl(String videoId) async {
    final cached = _ytUrlCache[videoId];
    if (cached != null && DateTime.now().difference(cached.at) < _ytUrlTtl) {
      return cached.url;
    }
    final url = await resolveYoutubeAudioUrl(videoId);
    if (url != null) _ytUrlCache[videoId] = (url: url, at: DateTime.now());
    return url;
  }

  /// Advance: the shared queue wins (an explicit instruction), then autoplay a
  /// related track once the queue is empty. Same precedence as the video player.
  Future<void> _ytNext({bool user = false, bool onFailure = false}) async {
    if (!state.isYoutubeAudio) return;
    // A user skip resets the failure guard — they're actively navigating, so
    // don't let an earlier auto-fail streak cut them off.
    if (user) _ytResolveFailStreak = 0;
    // Auto-advance (completion) is guarded so it can't double-fire. A user skip
    // interrupts an in-flight resolve instead — the load token in _playYtItem
    // supersedes the stale one — so Next stays responsive during a slow resolve.
    // onFailure advances past an unresolvable track and must bypass the guard
    // (it's called from inside an in-flight _ytNext).
    if (!user && !onFailure && _ytAdvancing) return;
    _ytAdvancing = true;
    try {
      // Remember the outgoing track so Previous can step back to it.
      final cur = state.ytCurrent;
      if (cur != null) {
        _ytHistory.add(cur);
        if (_ytHistory.length > 100) _ytHistory.removeAt(0);
      }
      var next = ref.read(youtubeQueueProvider.notifier).takeNext();
      // Repeat-all: when the queue runs out, reload the playlist and continue.
      if (next == null && state.repeat == PlaylistMode.loop) {
        ref.read(youtubeQueueProvider.notifier).reloadSource();
        next = ref.read(youtubeQueueProvider.notifier).takeNext();
      }
      if (next != null) {
        await _playYtItem(_toAudioItem(next));
      } else if (_ytAutoplay) {
        final rel = await _resolveRelated(state.ytCurrent?.videoId);
        if (rel != null) await _playYtItem(rel);
      }
    } finally {
      _ytAdvancing = false;
    }
  }

  /// Step back a song using [_ytHistory]. More than a few seconds into the
  /// current track (or with no history), restart it instead, like every music
  /// player.
  Future<void> _ytPrevious() async {
    if (!state.isYoutubeAudio) return;
    if (_player.state.position > const Duration(seconds: 3) ||
        _ytHistory.isEmpty) {
      await _player.seek(Duration.zero);
      return;
    }
    final prev = _ytHistory.removeLast();
    await _playYtItem(prev);
  }

  /// One related track to continue with, deduped against what's queued, played
  /// this session, or already watched to the end — so it moves you forward.
  Future<YoutubeAudioItem?> _resolveRelated(String? videoId) async {
    if (videoId == null) return null;
    try {
      final details = await ref.read(youtubeWatchProvider(videoId).future);
      final queued = ref.read(youtubeQueueProvider).map((v) => v.id).toSet();
      final history = ref.read(youtubeHistoryProvider.notifier);
      for (final r in details.related) {
        if (r.isShort ||
            r.id == videoId ||
            _ytPlayed.contains(r.id) ||
            queued.contains(r.id) ||
            (history.entryFor(r.id)?.finished ?? false)) {
          continue;
        }
        return _toAudioItem(r);
      }
    } catch (_) {}
    return null;
  }

  void _pushYtNowPlaying(YoutubeAudioItem? item) {
    final h = _handler;
    if (h == null || item == null) return;
    final dur = item.duration ??
        (_player.state.duration > Duration.zero ? _player.state.duration : null);
    h.setNowPlaying(MediaItem(
      id: item.videoId,
      title: item.title,
      artist: item.author,
      duration: dur,
      artUri: Uri.tryParse(item.thumbnailUrl),
    ));
  }

  /// Stop background YouTube audio and leave the mode. Leaves the shared queue
  /// intact (you might switch back to watching it).
  Future<void> stopYoutubeAudio() async {
    await _player.stop();
    state = state.copyWith(ytCurrent: null);
  }

  /// Jump back to the live edge. When the stream is seekable (the bar is showing)
  /// we seek to the buffered edge — instant, keeps the rewind buffer, and avoids
  /// the reconnect flicker that briefly drops `seekable` and hides the bar. Only
  /// a non-seekable stream needs a reconnect to get back to live.
  Future<void> radioGoLive() async {
    final s = state.radioStation;
    if (s == null) return;
    if (state.radioSeekable) {
      state = state.copyWith(radioBehindLive: Duration.zero);
      await _player.seek(_radioEdge);
      return;
    }
    _radioEdge = Duration.zero;
    _emptyIcyCount = 0;
    _radioTickWall = null;
    state = state.copyWith(radioBehindLive: Duration.zero);
    await _player.open(Media(s.url));
    _applyVolume();
  }

  /// Recovers from a dropped stream (a connectivity loss mid-broadcast):
  /// reopens the station fresh at the live edge, instead of resuming a
  /// connection mpv may have already given up on, which can otherwise replay
  /// stale buffered audio from earlier in the session rather than continuing
  /// live. Debounced, since a flaky connection can fire several error events
  /// in a row.
  Future<void> _reconnectRadio({bool force = false}) async {
    final s = state.radioStation;
    if (s == null) return;
    // Not while something else holds the audio: reconnecting mid-recording
    // would take the focus back and play over whatever interrupted us. The
    // interruption's own tail resumes instead.
    if (_pausedByInterruption) {
      Diagnostics.instance.add('radio', 'reconnect deferred: interrupted');
      _radioNeedsReconnect = true;
      return;
    }
    final now = DateTime.now();
    final last = _radioLastReconnectAttempt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(seconds: 3)) {
      // A flaky stream fires a burst of errors; only the first should act. The
      // rest used to be dropped entirely, which is how a failed attempt became
      // the last one ever.
      Diagnostics.instance.add('radio', 'reconnect skipped: debounced');
      // One failed attempt fires several errors (the lookup, then the open).
      // They belong to the attempt already running or queued, so only line up
      // a retry when there's neither; counting each one pushed the next try
      // from 3 seconds out to 30 after a single failure.
      if (!_radioReconnectInFlight && !(_radioRetry?.isActive ?? false)) {
        _scheduleRadioRetry();
      }
      return;
    }
    _radioLastReconnectAttempt = now;
    _radioEdge = Duration.zero;
    _emptyIcyCount = 0;
    _radioTickWall = null;
    state = state.copyWith(radioBehindLive: Duration.zero, radioSeekable: false);
    Diagnostics.instance.add('radio', 'reconnect attempt: ${s.name}');
    final gen = _radioReconnectGen;
    _radioPausedMidReconnect = false;
    _radioRetry?.cancel();
    _radioReconnectInFlight = true;
    _pushPlaybackState();
    try {
      await _player.open(Media(s.url));
      _applyVolume();
      Diagnostics.instance.add('radio', 'reconnect: open() returned');
    } catch (e) {
      Diagnostics.instance.add('radio', 'reconnect failed: $e');
    } finally {
      _radioReconnectInFlight = false;
    }
    if (gen != _radioReconnectGen || !state.isRadio) {
      // Paused, stopped or switched station while this attempt was opening.
      // open() starts playback, so a pause has to be applied again; a stop or
      // a new station has already taken over the player.
      if (_radioPausedMidReconnect && state.isRadio) await _player.pause();
      _pushPlaybackState();
      return;
    }
    // open() returning proves nothing: a DNS failure surfaces as an error event
    // afterwards, not an exception. Line up the next attempt (one per real
    // attempt), and cancel it once audio is actually flowing (see the
    // buffering listener).
    _scheduleRadioRetry();
  }

  /// Stops reconnecting because the user paused or stopped mid-reconnect. The
  /// station still needs a real reconnect, so Play reconnects rather than
  /// unpausing a dead stream.
  void _cancelRadioReconnect(String why) {
    if (!_radioReconnecting) return;
    _radioReconnectGen++;
    _radioPausedMidReconnect = true;
    _radioRetry?.cancel();
    _radioRetry = null;
    _radioRetryAttempt = 0;
    Diagnostics.instance.add('radio', 'reconnect cancelled: $why');
    _pushPlaybackState();
  }

  /// Queues another reconnect on a growing delay, until playback is confirmed
  /// flowing again. Without this a station that failed to come back stayed
  /// silently paused, because mpv stops reporting errors once it gives up.
  void _scheduleRadioRetry() {
    if (!state.isRadio || state.radioStation == null) return;
    _radioRetry?.cancel();
    // 20 tries over about twenty minutes: long enough to ride out a tunnel or
    // a router reboot, short of retrying forever on a station that's gone.
    if (_radioRetryAttempt >= 20) {
      Diagnostics.instance.add('radio', 'reconnect: giving up for now');
      _radioRetry = null;
      _pushPlaybackState(); // now genuinely stopped
      return;
    }
    const steps = [3, 5, 10, 20, 30, 60];
    final delay = Duration(
        seconds: steps[_radioRetryAttempt.clamp(0, steps.length - 1)]);
    _radioRetryAttempt++;
    Diagnostics.instance.add(
        'radio', 'reconnect retry #$_radioRetryAttempt in ${delay.inSeconds}s');
    _radioRetry = Timer(delay, () {
      if (!state.isRadio || _pausedByInterruption) return;
      if (_player.state.playing && !_player.state.buffering) {
        _radioRetryAttempt = 0;
        _pushPlaybackState();
        return;
      }
      unawaited(_reconnectRadio(force: true));
    });
    _pushPlaybackState();
  }

  /// Playback is flowing again: stop retrying and reset the backoff.
  void _radioRecovered() {
    if (_radioRetry == null && _radioRetryAttempt == 0) return;
    Diagnostics.instance.add('radio', 'reconnected, back to live');
    _radioRetry?.cancel();
    _radioRetry = null;
    _radioRetryAttempt = 0;
    _pushPlaybackState();
  }

  /// Rewind/skip within the buffered window (seekable streams only). Negative to
  /// rewind. Clamped to the window and the live edge.
  Future<void> radioSeekBy(Duration delta) async {
    if (!state.isRadio || !state.radioSeekable) return;
    final pos = _player.state.position;
    final lowest = _radioEdge - state.radioWindow;
    var target = pos + delta;
    if (target < lowest) target = lowest;
    if (target > _radioEdge) target = _radioEdge;
    if (target < Duration.zero) target = Duration.zero;
    await _player.seek(target);
  }

  /// Seek to a point [behind] the live edge (0 = live), for the scrub bar.
  Future<void> radioSeekBehind(Duration behind) async {
    if (!state.isRadio || !state.radioSeekable) return;
    var target = _radioEdge - behind;
    if (target < Duration.zero) target = Duration.zero;
    await _player.seek(target);
  }

  void _startRadioTick() {
    _radioTick?.cancel();
    Future<void> tick() async {
      if (!state.isRadio) return;
      final now = DateTime.now();
      final last = _radioTickWall ?? now;
      _radioTickWall = now;
      // The live edge advances in real time regardless of what we're doing.
      _radioEdge += now.difference(last);
      final pos = _player.state.position;
      // Snap the edge to playback while we're at (or ahead of) it, so normal
      // live playback stays at 0 behind and small clock drift can't accumulate.
      if (_player.state.playing && pos >= _radioEdge - const Duration(seconds: 1)) {
        _radioEdge = pos > _radioEdge ? pos : _radioEdge;
        if ((_radioEdge - pos) < const Duration(seconds: 1)) _radioEdge = pos;
      }
      var behind = _radioEdge - pos;
      if (behind < Duration.zero) behind = Duration.zero;
      final window = _radioEdge < _radioMaxWindow ? _radioEdge : _radioMaxWindow;
      bool seekable = state.radioSeekable;
      try {
        final sk = await (_player.platform as dynamic).getProperty('seekable');
        seekable = sk == 'yes' || sk == '1' || sk == true;
      } catch (_) {}
      // Only push when something the UI shows actually changed (avoid rebuild
      // spam): behind to the second, seekable, or window to the second.
      final changed = seekable != state.radioSeekable ||
          behind.inSeconds != state.radioBehindLive.inSeconds ||
          window.inSeconds != state.radioWindow.inSeconds;
      if (changed) {
        state = state.copyWith(
          radioSeekable: seekable,
          radioBehindLive: behind,
          radioWindow: window,
        );
      }
    }

    // Run once now so seekable/window begin updating immediately instead of
    // after the first one-second delay, then keep ticking every second.
    unawaited(tick());
    _radioTick =
        Timer.periodic(const Duration(seconds: 1), (_) => unawaited(tick()));
  }

  void _startIcyPolling() {
    _radioIcyTimer?.cancel();
    Future<void> poll() async {
      if (!state.isRadio) return;
      try {
        final t = await (_player.platform as dynamic)
            .getProperty('metadata/by-key/icy-title');
        final raw = (t is String) ? t : '';
        final title = _sanitizeIcy(raw);
        // Per-song album art if the station embeds it (iHeart amgArtworkURL).
        final embedded = _extractArtwork(raw);
        if (title.isEmpty) {
          // A single empty read is usually a transient blip (seeking / a short
          // re-buffer) — clearing then would flash the logo and force an art
          // re-download when the same title returns a beat later. Only treat it
          // as a real gap/ad after a couple in a row.
          _emptyIcyCount++;
          if (_emptyIcyCount >= 2) {
            _artLookupKey = null;
            if (state.radioTitle != null || state.radioArtwork != null) {
              state = state.copyWith(radioTitle: null, radioArtwork: null);
              final s = state.radioStation;
              if (s != null) _pushRadioNowPlaying(s, null);
            }
          }
          return;
        }
        _emptyIcyCount = 0;
        final titleChanged = title != state.radioTitle;
        if (titleChanged) {
          // New song: adopt embedded art if present, else clear the old art and
          // look it up generically (iTunes) — but only for something that looks
          // like a real "Artist - Title", so ad text doesn't pull a random cover.
          state = state.copyWith(
            radioTitle: title,
            radioArtwork: embedded.isNotEmpty ? embedded : null,
          );
          final s = state.radioStation;
          if (s != null) _pushRadioNowPlaying(s, title);
          if (embedded.isNotEmpty) {
            _artLookupKey = title.toLowerCase();
          } else if (_looksLikeSong(title)) {
            _artLookupKey = null;
            unawaited(_resolveArtwork(title));
          } else {
            // Not a song (ad text / station tagline): keep the station logo,
            // don't guess a cover. Logged so mystery art is traceable.
            debugPrint('[radio-art] "$title" is not a song — keeping logo');
            _artLookupKey = null;
          }
        } else if (embedded.isNotEmpty && embedded != state.radioArtwork) {
          state = state.copyWith(radioArtwork: embedded);
          final s = state.radioStation;
          if (s != null) _pushRadioNowPlaying(s, state.radioTitle);
        }
      } catch (_) {}
    }

    poll();
    _radioIcyTimer =
        Timer.periodic(const Duration(seconds: 6), (_) => poll());
  }

  /// Clean up an ICY "now playing" line. Many stations (iHeart, etc.) send a
  /// structured StreamTitle with embedded key="value" fields plus a lot of junk
  /// (`title="X",artist="Y",url="song_spot=...MediaBaseId=..."`); pull the real
  /// title/artist out and format "Artist - Title". Plain "Artist - Title"
  /// strings pass through untouched.
  static String _sanitizeIcy(String raw) {
    final t = raw.replaceAll('\u0000', '').trim();
    if (t.isEmpty) return '';
    var s = _icyDecodeEntities(t);

    // Unwrap a `StreamTitle='...'` / `StreamTitle="..."` wrapper if a feed sends
    // the whole assignment rather than just the value.
    final wrap = RegExp(r'''^StreamTitle\s*=\s*['"](.*)['"];?\s*$''',
            caseSensitive: false, dotAll: true)
        .firstMatch(s);
    if (wrap != null) s = wrap.group(1)!.trim();

    // Strip a leading "Now Playing:" / "Now playing -" label.
    s = s.replaceFirst(
        RegExp(r'^\s*now\s*playing\s*[:\-–—]\s*', caseSensitive: false), '');
    if (s.isEmpty) return '';

    // 1) RDS asterisk: `Song*<title>*<artist>*…` (Spot/Ad/Promo = ad → drop).
    final star = RegExp(
            r'^(Song|Spot|Track|Music|News|Promo|Ad|Advert)\s*\*\s*([^*]*?)\s*\*\s*([^*]*?)\s*(?:\*|$)',
            caseSensitive: false)
        .firstMatch(s);
    if (star != null) {
      final type = star.group(1)!.toLowerCase();
      if (const {'spot', 'ad', 'promo', 'advert'}.contains(type)) return '';
      return _icyFinish(_icyJoin(star.group(3), star.group(2)));
    }

    // 2) JSON now-playing blob: {"artist":"X","title":"Y"} / {"song":…}.
    if (s.contains('{') && s.contains('"')) {
      final r = _icyJoin(
        _icyJson(s, const ['artist', 'performer', 'author', 'albumartist']),
        _icyJson(s, const ['title', 'song', 'track', 'songtitle', 'name']),
      );
      if (r.isNotEmpty) return _icyFinish(r);
    }
    // 3) iHeart `text="Song"` with the artist before it, e.g.
    //    `Doja Cat - text="Paint The Town Red" song_spot="M" MediaBaseId=…`.
    final iheart =
        RegExp(r'^(.*?)\s*\btext\s*=\s*"([^"]+)"', caseSensitive: false)
            .firstMatch(s);
    if (iheart != null) {
      final prefix =
          iheart.group(1)!.replaceAll(RegExp(r'[\s\-–—]+$'), '').trim();
      return _icyFinish(_icyJoin(prefix, iheart.group(2)));
    }

    // 4) Explicit key=value fields (quoted or unquoted; , ; & | newline
    //    separated): `title="X",artist="Y"`, `artist=X; song=Y`, …
    final kt = _icyKv(s, const ['title', 'song', 'track', 'songtitle']);
    final ka = _icyKv(s, const ['artist', 'performer', 'author', 'albumartist']);
    if ((kt != null && kt.isNotEmpty) || (ka != null && ka.isNotEmpty)) {
      return _icyFinish(_icyJoin(ka, kt));
    }

    // 5) A bare `key="..."` blob with no readable prefix — metadata with no song
    //    (iHeart ad break `adContext="<base64 VAST url>"`) → show nothing.
    if (RegExp(r'^\w+\s*=\s*"').hasMatch(s)) return '';

    // 6) Drop a trailing "key=…" junk tail, keeping the clean "Artist - Title"
    //    prefix (`Artist - Title song_spot="F" MediaBaseId=1234` → `Artist - Title`).
    final cut = s.indexOf(RegExp(r'\s+\w+\s*=\s*["\d]'));
    if (cut > 0) s = s.substring(0, cut).trim();

    // 7) Plain string (Artist - Title, or a single field).
    return _icyFinish(s);
  }

  /// Join an (artist, title) pair as "Artist - Title", dropping either side when
  /// it's blank so there's never a dangling separator.
  static String _icyJoin(String? artist, String? title) =>
      [artist?.trim() ?? '', title?.trim() ?? '']
          .where((x) => x.isNotEmpty)
          .join(' - ');

  /// Decode the handful of HTML entities feeds commonly emit.
  static String _icyDecodeEntities(String s) => s
      .replaceAll(RegExp(r'&amp;', caseSensitive: false), '&')
      .replaceAll(RegExp(r'&lt;', caseSensitive: false), '<')
      .replaceAll(RegExp(r'&gt;', caseSensitive: false), '>')
      .replaceAll(RegExp(r'&quot;', caseSensitive: false), '"')
      .replaceAll(RegExp(r'&apos;', caseSensitive: false), "'")
      .replaceAll('&#39;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));

  /// First non-empty JSON string field among [keys], e.g. `"title":"X"`.
  static String? _icyJson(String s, List<String> keys) {
    for (final k in keys) {
      final m = RegExp('"$k"' r'\s*:\s*"([^"]*)"', caseSensitive: false)
          .firstMatch(s);
      final v = m?.group(1)?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// First non-empty `key=value` among [keys], quoted or unquoted.
  static String? _icyKv(String s, List<String> keys) {
    for (final k in keys) {
      final q = RegExp('\\b$k' r'''\s*=\s*(?:"([^"]*)"|'([^']*)')''',
              caseSensitive: false)
          .firstMatch(s);
      if (q != null) {
        final v = (q.group(1) ?? q.group(2) ?? '').trim();
        if (v.isNotEmpty) return v;
      }
      final u = RegExp('\\b$k' r'\s*=\s*(.+?)(?=\s+\w+\s*=|[,;&|]|$)',
              caseSensitive: false)
          .firstMatch(s);
      final uv = u?.group(1)?.trim();
      if (uv != null && uv.isNotEmpty && !RegExp(r'^\w+\s*=').hasMatch(uv)) {
        return uv;
      }
    }
    return null;
  }

  /// Normalize dashes/whitespace, strip a dangling separator, drop ad markers,
  /// and cap the length.
  static String _icyFinish(String input) {
    final s = input
        .replaceAll(RegExp(r'[‐‑‒–—―−]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s*-\s*$'), '')
        .replaceAll(RegExp(r'^\s*-\s*'), '')
        .trim();
    if (s.isEmpty || _icyAdMarkers.contains(s.toLowerCase())) return '';
    return s.length > 200 ? s.substring(0, 200).trim() : s;
  }

  /// Ad/placeholder StreamTitles meaning "no song is playing".
  static const _icyAdMarkers = {
    'advertisement', 'commercial break', 'commercial', 'ad break', 'ads',
    'advert', 'intermission', 'station id', 'unknown', 'no program',
    'offline', 'no title', 'n/a', 'na', 'loading', 'buffering',
    'live stream', 'live', 'radio', 'music', 'default'
  };

  /// Pull a per-song artwork URL out of the raw StreamTitle when the station
  /// embeds one. iHeart streams carry `amgArtworkURL="..."`; most don't, in
  /// which case we fall back to a generic lookup ([_resolveArtwork]).
  static String _extractArtwork(String raw) {
    final m = RegExp(r'amgArtworkURL\s*=\s*"([^"]+)"', caseSensitive: false)
        .firstMatch(raw);
    return m?.group(1)?.trim() ?? '';
  }

  /// Generic album-art lookup for any station that reports a clean
  /// "Artist - Title": queries the free iTunes Search API and, if the song is
  /// still current, sets it as the radio artwork. Best-effort; silent on miss.
  Future<void> _resolveArtwork(String title) async {
    final key = title.toLowerCase();
    _artLookupKey = key;
    try {
      final dio = await secureDio(
          options: BaseOptions(connectTimeout: const Duration(seconds: 6)));
      // Normalize the term: collabs come through as "A / B - Title" or
      // "A & B - Title", which iTunes matches poorly with the separators intact.
      final term = title
          .replaceAll(RegExp(r'\s*[/,&]\s*'), ' ')
          .replaceAll(RegExp(r'\s+[-–—]\s+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final res = await dio.get(
        'https://itunes.apple.com/search',
        queryParameters: {
          'term': term.isEmpty ? title : term,
          'media': 'music',
          'entity': 'song',
          'limit': 1,
        },
        options: Options(
            headers: {'User-Agent': 'Fathom'}, responseType: ResponseType.plain),
      );
      // The song may have changed (or radio stopped) while we were fetching.
      if (_artLookupKey != key || !state.isRadio) return;
      final body = res.data;
      final decoded = body is String ? jsonDecode(body) : body;
      final results = (decoded is Map) ? decoded['results'] as List? : null;
      if (results == null || results.isEmpty) return;
      final match = results.first as Map;
      // Guard against iTunes returning an unrelated "best guess" (its default
      // for junk queries, e.g. a random greatest-hits): require the result to
      // share a real word with what we searched for.
      final resultWords = ('${match['trackName'] ?? ''} '
                  '${match['artistName'] ?? ''} '
                  '${match['collectionName'] ?? ''}')
              .toLowerCase()
              .split(RegExp(r'[^a-z0-9]+'))
              .where((w) => w.length >= 3)
              .toSet();
      final queryWords = (term.isEmpty ? title : term)
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9]+'))
          .where((w) => w.length >= 3)
          .toSet();
      // Whole-word overlap, NOT substring: a tagline like "...Hit Music..."
      // must not match a "Greatest Hits" album (which is how a Z100 branding
      // line pulled Hank Williams art). A junk query that shares no whole word
      // with iTunes' best guess -> skip the art entirely.
      final overlap = queryWords.intersection(resultWords).length;
      if (queryWords.isNotEmpty && overlap == 0) {
        debugPrint('[radio-art] no match for "$title" — itunes returned '
            '"${match['artistName']} - ${match['trackName']}", dropped');
        return;
      }
      final art100 = match['artworkUrl100'] as String?;
      if (art100 == null || art100.isEmpty) return;
      // iTunes serves 100px; bump the size token for a crisp cover.
      final big = art100.replaceAll('100x100bb', '600x600bb');
      if (_artLookupKey == key && state.isRadio && state.radioTitle == title) {
        debugPrint('[radio-art] set art for "$title" -> '
            '${match['artistName']} - ${match['trackName']}');
        state = state.copyWith(radioArtwork: big);
        final s = state.radioStation;
        if (s != null) _pushRadioNowPlaying(s, title);
      }
    } catch (_) {}
  }

  /// Station-branding / promo text that has a "-" but is NOT a song, so it
  /// shouldn't drive an art lookup: a broadcast frequency (100.3), a callsign
  /// ("WHTZ FM"), "hit music", a "#1"/"your #1" boast, or a URL. Kept narrow so
  /// real titles ("I Am the Walrus", "Radio Ga Ga") aren't caught — no bare
  /// "am"/"fm"/"radio" words.
  static final RegExp _brandingRe = RegExp(
      r'\b\d{2,3}[.,]\d\b'
      r'|\b[kw][a-z]{2,3}[\s\-]?fm\b'
      r'|hit\s*music'
      r'|\byour\s+#?\s*1\b'
      r'|#\s*1\b'
      r'|https?://|\bwww\.|\.com\b',
      caseSensitive: false);

  /// True when an ICY line looks like a real song we can search art for: an
  /// "Artist - Title" with both sides non-trivial, and not station branding.
  /// Ad taglines / bare station text fail this, so we don't pull a random cover
  /// (e.g. a "greatest hits").
  static bool _looksLikeSong(String s) {
    final t = s.trim();
    if (_brandingRe.hasMatch(t)) return false;
    final m = RegExp(r'^(.{2,}?)\s+-\s+(.{2,})$').firstMatch(t);
    if (m == null) return false;
    final a = m.group(1)!.trim();
    final b = m.group(2)!.trim();
    return a.length >= 2 && b.length >= 2 && t.length <= 120;
  }

  /// Called when a resolved artwork URL fails to load, so the UI falls back to
  /// the station logo cleanly (and the redundant logo chip disappears).
  void clearRadioArtwork(String url) {
    if (state.isRadio && state.radioArtwork == url) {
      _artLookupKey = null;
      state = state.copyWith(radioArtwork: null);
    }
  }

  void _pushRadioNowPlaying(RadioStation s, String? icy) {
    final h = _handler;
    if (h == null) return;
    final hasIcy = icy != null && icy.isNotEmpty;
    final art = (state.radioArtwork != null && state.radioArtwork!.isNotEmpty)
        ? state.radioArtwork!
        : (s.favicon ?? '');
    // Fall back to the bundled radio glyph so the notification never shows an
    // empty art placeholder for stations without a logo.
    final artUri = art.isNotEmpty ? Uri.tryParse(art) : _radioArtUri;
    h.setNowPlaying(MediaItem(
      id: s.id,
      title: hasIcy ? icy : s.name,
      artist: hasIcy ? s.name : (s.tags ?? 'Radio'),
      artUri: artUri,
    ));
  }

  void _reportStart(String itemId) {
    final c = _ctx();
    if (c == null) return;
    _reportedId = itemId;
    unawaited(c.client.reportPlaybackStart(
      baseUrl: c.session.baseUrl,
      token: c.session.accessToken,
      itemId: itemId,
      positionTicks: 0,
    ));
  }

  void _reportProgress() {
    final c = _ctx();
    final id = _reportedId;
    if (c == null || id == null) return;
    unawaited(c.client.reportPlaybackProgress(
      baseUrl: c.session.baseUrl,
      token: c.session.accessToken,
      itemId: id,
      positionTicks: _lastPositionTicks,
    ));
  }

  void _reportStopped() {
    final c = _ctx();
    final id = _reportedId;
    if (c == null || id == null) return;
    unawaited(c.client.reportPlaybackStopped(
      baseUrl: c.session.baseUrl,
      token: c.session.accessToken,
      itemId: id,
      positionTicks: _lastPositionTicks,
    ));
    _reportedId = null;
  }

  /// Play on a YouTube track whose dropout reload couldn't get through:
  /// reload it from where it stopped. Null when there's nothing to retry.
  Future<void>? _retryStalledYt() {
    final st = _ytStalled;
    if (st == null ||
        !state.isYoutubeAudio ||
        state.ytCurrent?.videoId != st.item.videoId ||
        // Really playing (it loaded after all). A link that never loaded can
        // still read as playing, and that tap must retry, not pause.
        (_player.state.playing && _player.state.duration > Duration.zero)) {
      return null;
    }
    Diagnostics.instance.add('yt', 'Play: retrying the dropped track');
    return _playYtItem(st.item, startAt: st.at, reload: true);
  }

  Future<void> togglePlay() {
    // While casting, drive the cast device, not local playback (otherwise
    // hitting play resumes audio on the phone alongside the cast).
    final cast = ref.read(castControllerProvider);
    if (cast.casting) {
      final c = ref.read(castControllerProvider.notifier);
      return cast.playing ? c.pause() : c.play();
    }
    // Resuming radio after a dropped connection needs a real reconnect, not a
    // bare unpause: see _reconnectRadio.
    if (state.isRadio && !_player.state.playing && _radioNeedsReconnect) {
      Diagnostics.instance
          .add('radio', 'togglePlay: resuming via reconnect (needsReconnect)');
      return _reconnectRadio();
    }
    final stalled = _retryStalledYt();
    if (stalled != null) return stalled;
    if (state.isRadio) {
      Diagnostics.instance.add('radio',
          'togglePlay: playing=${_player.state.playing}, needsReconnect=$_radioNeedsReconnect');
      // Pausing mid-reconnect: stop the retries too, or the next one starts
      // the station again.
      if (_player.state.playing && _radioReconnecting) {
        _cancelRadioReconnect('paused');
        return _player.pause();
      }
    }
    return _player.playOrPause();
  }

  /// Hand playback back to the local player when a cast session ends: jump to
  /// the track the receiver was on, seek to its position, and resume if it was
  /// playing. The local playlist mirrors the cast queue, so indices line up.
  Future<void> _resumeLocalFromCast(
      String? url, int positionMs, bool wasPlaying) async {
    if (url != null) {
      final id = RegExp(r'/Audio/([0-9a-fA-F]+)/').firstMatch(url)?.group(1);
      if (id != null) {
        final idx = state.queue.indexWhere((t) => t.id == id);
        if (idx >= 0) await _player.jump(idx);
      }
    }
    if (positionMs > 0) {
      await _player.seek(Duration(milliseconds: positionMs));
    }
    if (wasPlaying) {
      await _player.play();
    } else {
      await _player.pause();
    }
  }

  Future<void> next() {
    final cast = ref.read(castControllerProvider);
    if (cast.casting) {
      return ref.read(castControllerProvider.notifier).queueNext();
    }
    if (state.isRadio) return _radioSkip(1);
    if (state.isYoutubeAudio) return _ytNext(user: true);
    return _player.next();
  }

  Future<void> previous() {
    final cast = ref.read(castControllerProvider);
    if (cast.casting) {
      return ref.read(castControllerProvider.notifier).queuePrev();
    }
    if (state.isRadio) return _radioSkip(-1);
    if (state.isYoutubeAudio) return _ytPrevious();
    return _player.previous();
  }

  Future<void> seek(Duration position) {
    final cast = ref.read(castControllerProvider);
    if (cast.casting) {
      return ref
          .read(castControllerProvider.notifier)
          .seek(position.inMilliseconds);
    }
    return _player.seek(position);
  }

  /// Index of the now-playing track within the visible queue.
  int get currentIndex {
    final id = state.current?.id;
    if (id == null) return -1;
    return state.queue.indexWhere((t) => t.id == id);
  }

  /// Jump straight to a queue entry (indexes match the player's order).
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    await _player.jump(index);
  }

  /// Drop a track from the queue.
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    await _player.remove(index);
  }

  /// Reorder the queue. media_kit's move(from, to) makes [from] take the place
  /// of the entry at [to] (mpv semantics), which matches ReorderableListView's
  /// raw newIndex without the usual decrement. The playlist stream then
  /// re-syncs the visible order.
  Future<void> moveQueue(int oldIndex, int newIndex) async {
    final len = state.queue.length;
    if (oldIndex < 0 || oldIndex >= len) return;
    // Allow to == len so a track can be dropped in the last slot (media_kit
    // treats that as insert-at-end); only clamp genuinely out-of-range values.
    final to = newIndex < 0 ? 0 : (newIndex > len ? len : newIndex);
    if (to == oldIndex) return;
    await _player.move(oldIndex, to);
  }

  /// Volume-levels music from its ReplayGain tags. mpv does the work: it reads
  /// REPLAYGAIN_TRACK_GAIN / REPLAYGAIN_ALBUM_GAIN and applies the gain, so
  /// this is a property, not a filter chain. Files without the tags get
  /// [Prefs.replayGainFallback] instead (0 dB, i.e. nothing, by default), which
  /// is what keeps an untagged album from jumping out against a tagged one.
  void _applyReplayGain() {
    final prefs = ref.read(preferencesProvider).asData?.value;
    if (prefs == null) return;
    try {
      final p = _player.platform as dynamic;
      final on = prefs.replayGain != 'off';
      unawaited(p.setProperty('replaygain', on ? prefs.replayGain : 'no'));
      // Measured: mpv applies the fallback whenever its ReplayGain logic isn't
      // active, so leaving a non-zero one set while levelling is off quietly
      // attenuates everything, with the slider hidden and no way back.
      unawaited(p.setProperty(
          'replaygain-fallback', on ? '${prefs.replayGainFallback}' : '0'));
      // Never let a positive gain clip: mpv lowers it instead.
      unawaited(p.setProperty('replaygain-clip', 'no'));
    } catch (_) {}
  }

  /// Append a track to the end of the queue, or start fresh if nothing plays.
  Future<void> addToQueue(BaseItemDto track) async {
    if (!state.hasTrack) {
      await playQueue([track], 0);
      return;
    }
    final media = _mediaFor(track);
    if (media == null) return;
    _byId[track.id] = track;
    await _player.add(media);
  }

  /// Queue a track to play right after the current one.
  Future<void> playNext(BaseItemDto track) async {
    if (!state.hasTrack) {
      await playQueue([track], 0);
      return;
    }
    final media = _mediaFor(track);
    if (media == null) return;
    _byId[track.id] = track;
    // Capture positions before the add so a concurrent playlist event can't
    // shift them: the appended track lands at the old length.
    final insertIndex = state.queue.length;
    final target = currentIndex + 1;
    await _player.add(media);
    if (target < insertIndex) await _player.move(insertIndex, target);
  }

  Future<void> toggleShuffle() async {
    final value = !state.shuffle;
    if (state.isYoutubeAudio) {
      // YouTube audio has no player playlist; shuffle the shared up-next.
      final qn = ref.read(youtubeQueueProvider.notifier);
      value ? qn.shuffleRemaining() : qn.restoreOrder();
    } else {
      await _player.setShuffle(value);
    }
    state = state.copyWith(shuffle: value);
    _pushPlaybackState(); // refresh the car's Shuffle button state
  }

  Future<void> cycleRepeat() async {
    final next = switch (state.repeat) {
      PlaylistMode.none => PlaylistMode.loop,
      PlaylistMode.loop => PlaylistMode.single,
      PlaylistMode.single => PlaylistMode.none,
    };
    // YouTube audio is a single Media, so its repeat is handled manually (the
    // completion handler + _ytNext). Driving the player's playlist mode would
    // loop the one track and suppress the `completed` event we advance on.
    if (!state.isYoutubeAudio) {
      await _player.setPlaylistMode(next);
    }
    state = state.copyWith(repeat: next);
    _pushPlaybackState(); // refresh the car's Repeat button state
  }

  // ---- Android Auto browse tree --------------------------------------------
  //
  // The car renders its own driver-safe UI over the MediaBrowserService that
  // audio_service exposes; we only supply the content tree and route taps back
  // into the ordinary playback methods above, so playing from the car behaves
  // exactly like playing in the app. Media IDs encode enough context to rebuild
  // the queue on tap:
  //   cat:<name>                      a top-level folder
  //   playlist:<id> / album:<id>      a browsable Jellyfin container
  //   station:<id>                    a playable radio favorite
  //   song|<parent>|<parentId>|<id>   a playable track, played in its list's
  //                                   order starting at itself
  //                                   (<parent> = playlist | album | favorites)
  //   single|<id>                     a lone playable track (search results)

  AppLocalizations? _l10nCache;

  /// Content-style hints for a browsable folder whose children are a list.
  static const _listExtras = {
    AndroidContentStyle.browsableHintKey:
        AndroidContentStyle.listItemHintValue,
    AndroidContentStyle.playableHintKey: AndroidContentStyle.listItemHintValue,
  };

  /// Videos surfaced in the car's YouTube browse/search, keyed by id, so a
  /// tapped result can be played without re-fetching its metadata.
  final Map<String, YoutubeVideo> _autoYtCache = {};

  /// Load the app's strings for the device locale (falling back to English),
  /// without a BuildContext — the browse tree can be built while the car has
  /// started us headless, before any screen exists.
  Future<AppLocalizations> _l10n() async {
    final cached = _l10nCache;
    if (cached != null) return cached;
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    final locale = AppLocalizations.supportedLocales.firstWhere(
      (l) => l.languageCode == device.languageCode,
      orElse: () => const Locale('en'),
    );
    final l = await AppLocalizations.delegate.load(locale);
    _l10nCache = l;
    return l;
  }

  bool _isAudio(BaseItemDto t) => t.mediaType == 'Audio' || t.type == 'Audio';

  Uri? _autoArt(BaseItemDto t, ({Session session, JellyfinClient client}) c) {
    String? id, tag;
    if (t.primaryImageTag != null) {
      id = t.id;
      tag = t.primaryImageTag;
    } else if (t.albumPrimaryImageTag != null && t.albumId != null) {
      id = t.albumId;
      tag = t.albumPrimaryImageTag;
    }
    if (id == null) return null;
    return Uri.tryParse(c.client.imageUrl(
      baseUrl: c.session.baseUrl,
      itemId: id,
      tag: tag,
      maxHeight: 512,
    ));
  }

  static const _pkg = 'app.fathom.player';

  /// A browsable folder. [childStyle] is how its children render (list / grid /
  /// category-with-icons); [icon] is a res/drawable name shown as the folder's
  /// own icon (loaded by the car via an android.resource URI).
  MediaItem _autoFolder(String id, String title,
          {int childStyle = AndroidContentStyle.listItemHintValue,
          String? icon}) =>
      MediaItem(
        id: id,
        title: title,
        playable: false,
        artUri: icon == null
            ? null
            : Uri.parse('android.resource://$_pkg/drawable/$icon'),
        extras: {
          AndroidContentStyle.browsableHintKey: childStyle,
          AndroidContentStyle.playableHintKey:
              AndroidContentStyle.listItemHintValue,
        },
      );

  /// A playable "action" row (e.g. Shuffle All) with an icon.
  MediaItem _autoAction(String id, String title, String icon) => MediaItem(
        id: id,
        title: title,
        playable: true,
        artUri: Uri.parse('android.resource://$_pkg/drawable/$icon'),
      );

  MediaItem _autoSong(String id, BaseItemDto t,
          ({Session session, JellyfinClient client}) c) =>
      MediaItem(
        id: id,
        title: t.name,
        artist: t.albumArtist ??
            (t.artists.isNotEmpty ? t.artists.join(', ') : null),
        album: t.album,
        playable: true,
        artUri: _autoArt(t, c),
      );

  /// Children of a browse node. Root lists the categories that actually have
  /// content; everything below pulls from the same Jellyfin/radio sources the
  /// app uses.
  Future<List<MediaItem>> _autoGetChildren(String parentMediaId) async {
    try {
      if (parentMediaId == AudioService.browsableRootId ||
          parentMediaId == 'root') {
        return await _autoRoot();
      }
      // Top-level tabs.
      if (parentMediaId == 'tab:home') return await _autoHome();
      if (parentMediaId == 'tab:library') return await _autoLibrary();
      if (parentMediaId == 'tab:radio') return await _autoRadioStations();
      if (parentMediaId == 'tab:youtube') return await _autoYoutubeRoot();
      // Home shortcuts + Library extras.
      if (parentMediaId == 'home:recent') return await _autoRecentlyPlayed();
      if (parentMediaId == 'home:recentalbums') return await _autoRecentAlbums();
      if (parentMediaId == 'cat:genres') return await _autoGenres();
      if (parentMediaId.startsWith('genre:')) {
        return await _autoGenreAlbums(parentMediaId.substring('genre:'.length));
      }
      if (parentMediaId == 'cat:radio') return await _autoRadioStations();
      if (parentMediaId == 'radio:favorites') {
        return await _radioStationsWhere((s) => s.favorite);
      }
      if (parentMediaId == 'radio:ungrouped') {
        return await _radioStationsWhere((s) => s.group == null || s.group!.isEmpty);
      }
      if (parentMediaId.startsWith('radiogroup:')) {
        final g = parentMediaId.substring('radiogroup:'.length);
        return await _radioStationsWhere((s) => s.group == g);
      }
      if (parentMediaId == 'cat:playlists') return await _autoPlaylists();
      if (parentMediaId == 'cat:albums') return await _autoAlbums();
      if (parentMediaId == 'cat:artists') return await _autoArtists();
      if (parentMediaId.startsWith('artist:')) {
        return await _autoArtistAlbums(parentMediaId.substring('artist:'.length));
      }
      if (parentMediaId == 'cat:youtube') return await _autoYoutubeRoot();
      if (parentMediaId == 'ytcat:whatsnew') return await _autoYtWhatsNew();
      if (parentMediaId == 'ytcat:playlists') return await _autoYtPlaylists();
      if (parentMediaId == 'ytcat:subs') return await _autoYtSubs();
      if (parentMediaId.startsWith('ytpl:')) {
        return await _autoYtPlaylistVideos(parentMediaId.substring('ytpl:'.length));
      }
      if (parentMediaId.startsWith('ytch:')) {
        return await _autoYtChannelVideos(parentMediaId.substring('ytch:'.length));
      }
      if (parentMediaId == 'cat:favorites') {
        final tracks = await _songsForParent('favorites', '');
        final c = _ctx();
        if (c == null) return const [];
        return tracks
            .map((t) => _autoSong('song|favorites||${t.id}', t, c))
            .toList();
      }
      if (parentMediaId.startsWith('playlist:')) {
        final id = parentMediaId.substring('playlist:'.length);
        final tracks = await _songsForParent('playlist', id);
        final c = _ctx();
        if (c == null) return const [];
        return tracks
            .map((t) => _autoSong('song|playlist|$id|${t.id}', t, c))
            .toList();
      }
      if (parentMediaId.startsWith('album:')) {
        final id = parentMediaId.substring('album:'.length);
        final tracks = await _songsForParent('album', id);
        final c = _ctx();
        if (c == null) return const [];
        return tracks
            .map((t) => _autoSong('song|album|$id|${t.id}', t, c))
            .toList();
      }
    } catch (_) {
      // A failed fetch (network, expired token) yields an empty folder rather
      // than a broken car UI.
    }
    return const [];
  }

  /// The root: the top-level tabs (Home / Library / Radio / YouTube). Android
  /// Auto renders these browsable root nodes as the tab bar. Each is included
  /// only when it has something to show.
  Future<List<MediaItem>> _autoRoot() async {
    final l = await _l10n();
    final prefs = ref.read(preferencesProvider).asData?.value;
    final items = <MediaItem>[];
    const cat = AndroidContentStyle.categoryListItemHintValue;
    if (_ctx() != null) {
      items
        ..add(_autoFolder('tab:home', l.autoHome,
            childStyle: cat, icon: 'ic_auto_home'))
        ..add(_autoFolder('tab:library', l.autoLibrary,
            childStyle: cat, icon: 'ic_auto_library'));
    }
    if (prefs?.radioEnabled ?? false) {
      // Show the Radio tab whenever there's at least one saved station (not only
      // favorites) — otherwise it silently vanishes for people who never starred
      // one.
      final stations = await ref.read(radioControllerProvider.future);
      if (stations.isNotEmpty) {
        items.add(_autoFolder('tab:radio', l.autoRadio, icon: 'ic_auto_radio'));
      }
    }
    if (prefs?.youtubeEnabled ?? false) {
      items.add(_autoFolder('tab:youtube', l.autoYoutube,
          childStyle: cat, icon: 'ic_auto_youtube'));
    }
    return items;
  }

  /// Home: a quick-start mix of the most-reached-for shortcuts.
  Future<List<MediaItem>> _autoHome() async {
    final l = await _l10n();
    const grid = AndroidContentStyle.gridItemHintValue;
    return [
      // One-tap "just play something" — ideal in the car.
      _autoAction('mix:all', l.autoShuffleAll, 'ic_auto_shuffle'),
      _autoAction('mix:favorites', l.autoFavoritesMix, 'ic_auto_favorite'),
      _autoFolder('home:recent', l.autoRecentlyPlayed, icon: 'ic_auto_history'),
      _autoFolder('home:recentalbums', l.autoRecentlyAdded,
          childStyle: grid, icon: 'ic_auto_new'),
      _autoFolder('cat:playlists', l.autoPlaylists, icon: 'ic_auto_playlists'),
      _autoFolder('cat:favorites', l.autoFavoriteSongs,
          icon: 'ic_auto_favorite'),
    ];
  }

  /// Library: the full Jellyfin music browse.
  Future<List<MediaItem>> _autoLibrary() async {
    final l = await _l10n();
    const grid = AndroidContentStyle.gridItemHintValue;
    const cat = AndroidContentStyle.categoryListItemHintValue;
    return [
      _autoFolder('cat:playlists', l.autoPlaylists, icon: 'ic_auto_playlists'),
      _autoFolder('cat:albums', l.autoAlbums,
          childStyle: grid, icon: 'ic_auto_album'),
      _autoFolder('cat:artists', l.autoArtists, icon: 'ic_auto_artist'),
      _autoFolder('cat:genres', l.autoGenres,
          childStyle: cat, icon: 'ic_auto_genre'),
      _autoFolder('cat:favorites', l.autoFavoriteSongs,
          icon: 'ic_auto_favorite'),
    ];
  }

  MediaItem _radioItem(RadioStation s) {
    final art = (s.favicon != null && s.favicon!.isNotEmpty)
        ? Uri.tryParse(s.favicon!)
        : _radioArtUri;
    return MediaItem(
      id: 'station:${s.id}',
      title: s.name,
      artist: s.tags,
      playable: true,
      artUri: art,
    );
  }

  Future<List<MediaItem>> _radioStationsWhere(
      bool Function(RadioStation) test) async {
    final stations = await ref.read(radioControllerProvider.future);
    await _ensureRadioArt();
    return stations.where(test).map(_radioItem).toList();
  }

  /// The Radio tab. When the user has organised stations into groups, show the
  /// groups (plus Favorites and any ungrouped) as folders; otherwise a flat
  /// list, favorites first.
  Future<List<MediaItem>> _autoRadioStations() async {
    final stations = await ref.read(radioControllerProvider.future);
    await _ensureRadioArt();
    final groups = ref.read(radioControllerProvider.notifier).groups;
    if (groups.isEmpty) {
      final ordered = [
        ...stations.where((s) => s.favorite),
        ...stations.where((s) => !s.favorite),
      ];
      return ordered.map(_radioItem).toList();
    }
    final l = await _l10n();
    final items = <MediaItem>[];
    if (stations.any((s) => s.favorite)) {
      items.add(_autoFolder('radio:favorites', l.autoRadioFavorites,
          icon: 'ic_auto_favorite'));
    }
    for (final g in groups) {
      items.add(_autoFolder('radiogroup:$g', g, icon: 'ic_auto_radio'));
    }
    if (stations.any((s) => s.group == null || s.group!.isEmpty)) {
      items.add(_autoFolder('radio:ungrouped', l.autoRadioOther,
          icon: 'ic_auto_radio'));
    }
    return items;
  }

  Future<List<MediaItem>> _autoPlaylists() async {
    final c = _ctx();
    if (c == null) return const [];
    final pls = await c.client.getPlaylists(
      baseUrl: c.session.baseUrl,
      userId: c.session.userId,
      token: c.session.accessToken,
    );
    return pls
        .map((p) => MediaItem(
              id: 'playlist:${p.id}',
              title: p.name,
              playable: false,
              artUri: _autoArt(p, c),
              extras: const {
                AndroidContentStyle.browsableHintKey:
                    AndroidContentStyle.listItemHintValue,
                AndroidContentStyle.playableHintKey:
                    AndroidContentStyle.listItemHintValue,
              },
            ))
        .toList();
  }

  /// Library → Albums: the whole album collection, A–Z.
  Future<List<MediaItem>> _autoAlbums() async {
    final c = _ctx();
    if (c == null) return const [];
    final res = await c.client.getItems(
      baseUrl: c.session.baseUrl,
      userId: c.session.userId,
      token: c.session.accessToken,
      includeItemTypes: 'MusicAlbum',
      recursive: true,
      sortBy: 'SortName',
      limit: 500,
    );
    return res.items.map((a) => _albumNode(a, c)).toList();
  }

  /// Home → Recently Added: newest albums first (kept short for the car).
  Future<List<MediaItem>> _autoRecentAlbums() async {
    final c = _ctx();
    if (c == null) return const [];
    final res = await c.client.getItems(
      baseUrl: c.session.baseUrl,
      userId: c.session.userId,
      token: c.session.accessToken,
      includeItemTypes: 'MusicAlbum',
      recursive: true,
      sortBy: 'DateCreated',
      sortOrder: 'Descending',
      limit: 100,
    );
    return res.items.map((a) => _albumNode(a, c)).toList();
  }

  /// Library → Genres.
  Future<List<MediaItem>> _autoGenres() async {
    final c = _ctx();
    if (c == null) return const [];
    final genres = await c.client.getGenres(
      baseUrl: c.session.baseUrl,
      userId: c.session.userId,
      token: c.session.accessToken,
    );
    return genres
        .map((g) => _autoFolder('genre:${g.name}', g.name,
            childStyle: AndroidContentStyle.gridItemHintValue,
            icon: 'ic_auto_genre'))
        .toList();
  }

  Future<List<MediaItem>> _autoGenreAlbums(String genre) async {
    final c = _ctx();
    if (c == null) return const [];
    final res = await c.client.getItems(
      baseUrl: c.session.baseUrl,
      userId: c.session.userId,
      token: c.session.accessToken,
      genres: genre,
      includeItemTypes: 'MusicAlbum',
      recursive: true,
      sortBy: 'SortName',
      limit: 300,
    );
    return res.items.map((a) => _albumNode(a, c)).toList();
  }

  /// Home → Recently Played songs (plays the list from the tapped track).
  Future<List<MediaItem>> _autoRecentlyPlayed() async {
    final c = _ctx();
    if (c == null) return const [];
    final tracks = await _songsForParent('recent', '');
    return tracks
        .map((t) => _autoSong('song|recent||${t.id}', t, c))
        .toList();
  }

  MediaItem _albumNode(
          BaseItemDto a, ({Session session, JellyfinClient client}) c) =>
      MediaItem(
        id: 'album:${a.id}',
        title: a.name,
        artist: a.albumArtist,
        playable: false,
        artUri: _autoArt(a, c),
        extras: _listExtras,
      );

  Future<List<MediaItem>> _autoArtists() async {
    final c = _ctx();
    if (c == null) return const [];
    final artists = await c.client.getArtists(
      baseUrl: c.session.baseUrl,
      userId: c.session.userId,
      token: c.session.accessToken,
    );
    return artists
        .map((a) => MediaItem(
              id: 'artist:${a.id}',
              title: a.name,
              playable: false,
              artUri: _autoArt(a, c),
              extras: _listExtras,
            ))
        .toList();
  }

  Future<List<MediaItem>> _autoArtistAlbums(String artistId) async {
    final c = _ctx();
    if (c == null) return const [];
    final res = await c.client.getItems(
      baseUrl: c.session.baseUrl,
      userId: c.session.userId,
      token: c.session.accessToken,
      albumArtistIds: artistId,
      includeItemTypes: 'MusicAlbum',
      recursive: true,
      sortBy: 'ProductionYear,SortName',
      sortOrder: 'Descending',
      limit: 200,
    );
    return res.items.map((a) => _albumNode(a, c)).toList();
  }

  /// The audio tracks that make up a browse container, in play order.
  Future<List<BaseItemDto>> _songsForParent(String type, String id) async {
    final c = _ctx();
    if (c == null) return const [];
    switch (type) {
      case 'playlist':
        final items = await c.client.getPlaylistItems(
          baseUrl: c.session.baseUrl,
          userId: c.session.userId,
          token: c.session.accessToken,
          playlistId: id,
        );
        return items.where(_isAudio).toList();
      case 'album':
        final res = await c.client.getItems(
          baseUrl: c.session.baseUrl,
          userId: c.session.userId,
          token: c.session.accessToken,
          parentId: id,
          includeItemTypes: 'Audio',
          sortBy: 'ParentIndexNumber,IndexNumber,SortName',
          limit: 500,
        );
        return res.items;
      case 'favorites':
        final res = await c.client.getItems(
          baseUrl: c.session.baseUrl,
          userId: c.session.userId,
          token: c.session.accessToken,
          includeItemTypes: 'Audio',
          isFavorite: true,
          recursive: true,
          sortBy: 'SortName',
          limit: 500,
        );
        return res.items;
      case 'recent':
        final res = await c.client.getItems(
          baseUrl: c.session.baseUrl,
          userId: c.session.userId,
          token: c.session.accessToken,
          includeItemTypes: 'Audio',
          filters: 'IsPlayed',
          recursive: true,
          sortBy: 'DatePlayed',
          sortOrder: 'Descending',
          limit: 100,
        );
        return res.items;
    }
    return const [];
  }

  // ---- YouTube (audio-only), shown only when YouTube is enabled ------------

  MediaItem _ytSong(String id, YoutubeVideo v) => MediaItem(
        id: id,
        title: v.title,
        artist: v.author,
        duration: v.duration,
        playable: true,
        artUri: Uri.tryParse(v.thumbnailUrl),
      );

  Future<List<MediaItem>> _autoYoutubeRoot() async {
    final l = await _l10n();
    return [
      _autoFolder('ytcat:whatsnew', l.autoYoutubeWhatsNew, icon: 'ic_auto_new'),
      _autoFolder('ytcat:playlists', l.autoYoutubePlaylists,
          icon: 'ic_auto_playlists'),
      _autoFolder('ytcat:subs', l.autoYoutubeSubscriptions,
          icon: 'ic_auto_subscriptions'),
    ];
  }

  /// YouTube → What's New: newest uploads from the channels you follow.
  Future<List<MediaItem>> _autoYtWhatsNew() async {
    final feed = await ref.read(youtubeFeedProvider.future);
    for (final v in feed.videos) {
      _autoYtCache[v.id] = v;
    }
    return feed.videos
        .map((v) => _ytSong('ytsong|feed||${v.id}', v))
        .toList();
  }

  Future<List<MediaItem>> _autoYtPlaylists() async {
    final pls = await ref.read(youtubeLocalPlaylistsProvider.future);
    return pls
        .map((p) => MediaItem(
              id: 'ytpl:${p.id}',
              title: p.name,
              playable: false,
              artUri: p.thumbnailUrl.isNotEmpty
                  ? Uri.tryParse(p.thumbnailUrl)
                  : null,
              extras: _listExtras,
            ))
        .toList();
  }

  Future<List<MediaItem>> _autoYtPlaylistVideos(String playlistId) async {
    final pls = await ref.read(youtubeLocalPlaylistsProvider.future);
    final match = pls.where((p) => p.id == playlistId);
    if (match.isEmpty) return const [];
    final vids = match.first.videos;
    for (final v in vids) {
      _autoYtCache[v.id] = v;
    }
    return vids
        .map((v) => _ytSong('ytsong|pl|$playlistId|${v.id}', v))
        .toList();
  }

  Future<List<MediaItem>> _autoYtSubs() async {
    final chans = await ref.read(youtubeSubscriptionsProvider.future);
    return chans
        .map((ch) => MediaItem(
              id: 'ytch:${ch.id}',
              title: ch.title,
              playable: false,
              artUri:
                  ch.logoUrl.isNotEmpty ? Uri.tryParse(ch.logoUrl) : null,
              extras: _listExtras,
            ))
        .toList();
  }

  Future<List<MediaItem>> _autoYtChannelVideos(String channelId) async {
    final tab = await ref
        .read(youtubeInnerTubeProvider)
        .channelTab(channelId, YtChannelTabKind.videos);
    for (final v in tab.videos) {
      _autoYtCache[v.id] = v;
    }
    return tab.videos
        .map((v) => _ytSong('ytsong|ch|$channelId|${v.id}', v))
        .toList();
  }

  /// The video list backing a YouTube "song" media id, for building the queue.
  Future<List<YoutubeVideo>> _ytListFor(String kind, String ownerId) async {
    if (kind == 'pl') {
      final pls = await ref.read(youtubeLocalPlaylistsProvider.future);
      final match = pls.where((p) => p.id == ownerId);
      return match.isEmpty ? const [] : match.first.videos;
    }
    if (kind == 'ch') {
      final tab = await ref
          .read(youtubeInnerTubeProvider)
          .channelTab(ownerId, YtChannelTabKind.videos);
      return tab.videos;
    }
    if (kind == 'feed') {
      final feed = await ref.read(youtubeFeedProvider.future);
      return feed.videos;
    }
    return const [];
  }

  /// Play a YouTube video's audio, walking the rest of [list] afterwards via the
  /// shared YouTube queue — the same handoff the in-app "Listen to all" uses.
  Future<void> _playYtList(List<YoutubeVideo> list, int startIndex) async {
    if (list.isEmpty) return;
    final i = startIndex < 0 ? 0 : startIndex;
    ref.read(youtubeQueueProvider.notifier).playAll(list.sublist(
          i + 1 > list.length ? list.length : i + 1,
        ));
    await playYoutubeAudio(_toAudioItem(list[i]));
  }

  /// Play a tapped browse item. Songs play their whole list starting at the tap;
  /// a container plays from its first track; a station tunes the radio.
  Future<void> _autoPlayFromMediaId(String mediaId) async {
    try {
      if (mediaId == 'mix:all') {
        // Shuffle All: a random batch of library songs, played shuffled.
        final c = _ctx();
        if (c == null) return;
        final res = await c.client.getItems(
          baseUrl: c.session.baseUrl,
          userId: c.session.userId,
          token: c.session.accessToken,
          includeItemTypes: 'Audio',
          recursive: true,
          sortBy: 'Random',
          limit: 200,
        );
        if (res.items.isNotEmpty) await playQueue(res.items, 0, shuffle: true);
        return;
      }
      if (mediaId == 'mix:favorites') {
        final tracks = await _songsForParent('favorites', '');
        if (tracks.isNotEmpty) await playQueue(tracks, 0, shuffle: true);
        return;
      }
      if (mediaId.startsWith('station:')) {
        final id = mediaId.substring('station:'.length);
        final stations = await ref.read(radioControllerProvider.future);
        final match = stations.where((s) => s.id == id);
        if (match.isNotEmpty) await playStation(match.first);
        return;
      }
      if (mediaId.startsWith('ytsong|')) {
        final parts = mediaId.split('|'); // ytsong | pl|ch | ownerId | videoId
        if (parts.length != 4) return;
        final list = await _ytListFor(parts[1], parts[2]);
        await _playYtList(list, list.indexWhere((v) => v.id == parts[3]));
        return;
      }
      if (mediaId.startsWith('ytsingle|')) {
        final v = _autoYtCache[mediaId.substring('ytsingle|'.length)];
        if (v == null) return; // metadata gone (process restart); ignore the tap
        ref.read(youtubeQueueProvider.notifier).clear();
        await playYoutubeAudio(_toAudioItem(v));
        return;
      }
      if (mediaId.startsWith('ytsearchpl:')) {
        // A YouTube playlist from search: fetch its videos and play the lot.
        final vids = await ref
            .read(youtubeInnerTubeProvider)
            .playlist(mediaId.substring('ytsearchpl:'.length));
        await _playYtList(vids, 0);
        return;
      }
      if (mediaId.startsWith('single|')) {
        final c = _ctx();
        if (c == null) return;
        final item = await c.client.getItem(
          baseUrl: c.session.baseUrl,
          userId: c.session.userId,
          token: c.session.accessToken,
          itemId: mediaId.substring('single|'.length),
        );
        await playQueue([item], 0);
        return;
      }
      if (mediaId.startsWith('song|')) {
        final parts = mediaId.split('|'); // song | parent | parentId | songId
        if (parts.length != 4) return;
        final tracks = await _songsForParent(parts[1], parts[2]);
        if (tracks.isEmpty) return;
        final idx = tracks.indexWhere((t) => t.id == parts[3]);
        await playQueue(tracks, idx < 0 ? 0 : idx);
        return;
      }
      if (mediaId.startsWith('album:')) {
        final tracks = await _songsForParent('album', mediaId.substring(6));
        if (tracks.isNotEmpty) await playQueue(tracks, 0);
      } else if (mediaId.startsWith('playlist:')) {
        final tracks = await _songsForParent('playlist', mediaId.substring(9));
        if (tracks.isNotEmpty) await playQueue(tracks, 0);
      }
    } catch (_) {
      // Swallow: a failed tap should never crash the car's media session.
    }
  }

  /// Search results for the car's search UI: songs from the Jellyfin library
  /// first, then YouTube videos (audio) when YouTube is enabled.
  Future<List<MediaItem>> _autoSearch(String query) async {
    if (query.trim().isEmpty) return const [];
    final out = <MediaItem>[];
    final c = _ctx();
    if (c != null) {
      try {
        final res = await c.client.getItems(
          baseUrl: c.session.baseUrl,
          userId: c.session.userId,
          token: c.session.accessToken,
          searchTerm: query,
          includeItemTypes: 'Audio',
          recursive: true,
          limit: 50,
        );
        out.addAll(res.items.map((t) => _autoSong('single|${t.id}', t, c)));
      } catch (_) {}
    }
    if (ref.read(preferencesProvider).asData?.value.youtubeEnabled ?? false) {
      try {
        final page = await ref.read(youtubeInnerTubeProvider).search(query);
        for (final v in page.videos.take(25)) {
          _autoYtCache[v.id] = v;
          out.add(_ytSong('ytsingle|${v.id}', v));
        }
        for (final pl in page.playlists.take(10)) {
          out.add(MediaItem(
            id: 'ytsearchpl:${pl.id}',
            title: pl.title,
            artist: pl.author,
            playable: true,
            artUri: pl.thumbnailUrl.isNotEmpty
                ? Uri.tryParse(pl.thumbnailUrl)
                : null,
          ));
        }
      } catch (_) {}
    }
    return out;
  }

  /// A "Play ..." voice command from the car / Assistant: library first, then
  /// YouTube (audio) if enabled, then a radio favorite whose name matches.
  Future<void> _autoPlayFromSearch(String query) async {
    if (query.trim().isEmpty) return;
    try {
      final c = _ctx();
      if (c != null) {
        final res = await c.client.getItems(
          baseUrl: c.session.baseUrl,
          userId: c.session.userId,
          token: c.session.accessToken,
          searchTerm: query,
          includeItemTypes: 'Audio',
          recursive: true,
          limit: 50,
        );
        if (res.items.isNotEmpty) {
          await playQueue(res.items, 0);
          return;
        }
      }
      final prefs = ref.read(preferencesProvider).asData?.value;
      if (prefs?.youtubeEnabled ?? false) {
        final page = await ref.read(youtubeInnerTubeProvider).search(query);
        if (page.videos.isNotEmpty) {
          await _playYtList(page.videos.take(25).toList(), 0);
          return;
        }
      }
      if (prefs?.radioEnabled ?? false) {
        final q = query.toLowerCase();
        final stations = await ref.read(radioControllerProvider.future);
        final match = stations.where((s) => s.name.toLowerCase().contains(q));
        if (match.isNotEmpty) await playStation(match.first);
      }
    } catch (_) {
      // Best-effort: a failed voice search just does nothing.
    }
  }
}

final audioControllerProvider =
    NotifierProvider<AudioController, AudioState>(AudioController.new);
