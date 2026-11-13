import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../models/youtube_caption.dart';
import 'youtube_dropout.dart';
import 'youtube_streams.dart';

/// Keeps a YouTube video going through dropped connections, for the whole life
/// of its player: on the watch page, in the mini player, and back.
///
/// googlevideo links are tied to the address that resolved them, so after a
/// network change the reconnect is refused and the stream ends early. This
/// spots that (the refused reconnect in mpv's log, or an end well short of the
/// real end), resolves fresh links and reopens at the same spot, rendition and
/// caption. One object per player, handed along with it, so the tries, the
/// viewer's choices and a reload under way all survive minimizing and
/// reopening.
class YtStreamRecovery {
  YtStreamRecovery({
    required this.player,
    required this.url,
    Future<YtStreams> Function(String url)? resolve,
    Future<YtQuality?> Function(List<YtQuality> qualities, String probeUrl)?
        autoPick,
  })  : _resolve = resolve ?? ((u) => resolveYoutubeStreams(u, live: false)),
        _autoPick = autoPick ?? autoQualityByBandwidth {
    _subs = [
      player.stream.log.listen((e) {
        if (watch.refusedAfterReconnect(e.prefix, e.text)) {
          debugPrint('[yt] stream refused: ${e.text.trim()}');
          unawaited(recover());
        }
      }),
      player.stream.completed.listen((done) async {
        if (!done) return;
        // mpv reports a dropped stream as the end of the video. Well short of
        // the real end, reload instead (a reload already under way is waited
        // for); otherwise, or if that fails, the video has ended.
        if (_endedEarly() && await recover()) return;
        _end();
      }),
      // Played on past the last reload's spot: that reload worked.
      player.stream.position.listen((p) {
        final at = _reloadAt;
        if (at != null && p > at + const Duration(seconds: 1)) _reloadAt = null;
      }),
    ];
  }

  final Player player;
  final String url;
  final Future<YtStreams> Function(String url) _resolve;
  final Future<YtQuality?> Function(List<YtQuality>, String) _autoPick;
  final YtDropoutWatch watch = YtDropoutWatch();

  // What a reload reopens, kept up to date by the screen showing the video.
  /// Playback has started at least once (a failed first load is not a drop).
  bool ready = false;
  bool live = false;

  /// The adaptive stream never started, so the muxed one is in use.
  bool fellBack = false;

  /// The adaptive rendition last opened.
  YtQuality? openQuality;

  /// The quality menu's pick ('Auto' for the default).
  String qualityLabel = 'Auto';

  /// The viewer's quality preference: 'auto' or a height like '720'.
  String qualityPref = 'auto';
  YoutubeCaption? caption;

  /// Set by the screen showing the video, cleared when it lets go (the mini
  /// player then just keeps playing): fresh streams to refill the menus, and
  /// the video ending (for autoplay).
  void Function(YtStreams streams)? onReloaded;
  void Function()? onEnded;

  late final List<StreamSubscription<Object>> _subs;
  Future<bool>? _recovery;
  Timer? _watchdog;
  // Where the last reload reopened, until playback gets past it. A reload
  // whose new links fail too leaves the player at 0:00, and the next try
  // must still go back to this spot.
  Duration? _reloadAt;
  // Ran out of tries; the player sits stopped on a dead link.
  bool _gaveUp = false;
  bool _disposed = false;

  bool _endedEarly() =>
      !live &&
      ready &&
      isYoutubeUrl(url) &&
      YtDropoutWatch.endedEarly(player.state.position, player.state.duration);

  void _end() {
    _watchdog?.cancel();
    if (!_disposed) onEnded?.call();
  }

  /// Resolves fresh links and reopens at the current spot. True when it
  /// reloaded, false when it gave up. Callers during a reload share it.
  Future<bool> recover() =>
      _recovery ??= _reload().whenComplete(() => _recovery = null);

  Future<bool> _reload() async {
    _watchdog?.cancel();
    if (_disposed || live || !ready || !isYoutubeUrl(url)) return false;
    // A reopen that failed leaves the player at 0:00: go back to the reload's
    // spot. Anywhere else is where the viewer really is (they may have
    // sought back since).
    final now = player.state.position;
    final at = _reloadAt;
    final pos = at != null && now < const Duration(seconds: 1) ? at : now;
    // Keep a paused video paused. completed clears playing, so a video that
    // ran out was playing.
    final play = player.state.playing || player.state.completed;
    if (!watch.takeTry(pos)) {
      _gaveUp = true;
      debugPrint('[yt] stream keeps dropping; giving up at ${pos.inSeconds}s');
      return false;
    }
    debugPrint('[yt] stream dropped at ${pos.inSeconds}s; '
        'reloading (try ${watch.tries})');
    try {
      final s = await _resolve(url);
      if (_disposed) return true;
      // Open at the spot rather than at 0:00 and seek: no flash of the start,
      // and no SponsorBlock skip firing on the way.
      final start = pos > Duration.zero ? pos : null;
      _reloadAt = pos;
      if (s.isAdaptive && !fellBack) {
        final label = openQuality?.label;
        final q = s.qualities.where((x) => x.label == label).firstOrNull ??
            (qualityPref == 'auto'
                ? await _autoPick(s.qualities, s.audioUrl!)
                : defaultQualityFor(s.qualities, qualityPref));
        if (q == null || _disposed) return false;
        openQuality = q;
        await player.open(Media(q.url, start: start), play: play);
        await player.setAudioTrack(AudioTrack.uri(s.audioUrl!));
      } else {
        // Muxed: keep the viewer's pick if the fresh list still has it.
        final u = s.muxedQualities
                .where((x) => x.label == qualityLabel)
                .firstOrNull
                ?.url ??
            s.muxedUrl;
        if (u == null) return false;
        await player.open(Media(u, start: start), play: play);
      }
      final c = caption;
      if (c != null) {
        try {
          await player.setSubtitleTrack(
              SubtitleTrack.uri(c.vttUrl, title: c.label, language: c.code));
        } catch (_) {}
      }
      debugPrint('[yt] stream reloaded at ${pos.inSeconds}s');
      onReloaded?.call(s);
      // open() can succeed and the new link still never play (offline,
      // refused again); that raises no end, so check it got going.
      if (play) _watchReload(pos);
      return true;
    } catch (e) {
      debugPrint('[yt] stream reload failed: $e');
      return false;
    }
  }

  /// Checks a reload got going: every 15 s, up to a minute while mpv is still
  /// buffering (a weak connection right after a network change can be slow),
  /// then tries again, or ends the video once the tries are used up.
  void _watchReload(Duration pos, [int checks = 1]) {
    _watchdog = Timer(const Duration(seconds: 15), () async {
      if (_disposed || _recovery != null) return;
      if (player.state.position > pos + const Duration(seconds: 1)) return;
      // Paused by the viewer since: not stuck.
      if (!player.state.playing && !player.state.completed) return;
      if (player.state.buffering && checks < 4) {
        _watchReload(pos, checks + 1);
        return;
      }
      debugPrint('[yt] reload never started playing');
      if (!await recover()) _end();
    });
  }

  /// For a page reopening this player: if it stopped on a dropped stream the
  /// mini player gave up on, try again with fresh tries, and end the video
  /// if that fails too.
  Future<void> resumeIfDropped() async {
    if (_disposed || _recovery != null) return;
    if (!_gaveUp && (!player.state.completed || !_endedEarly())) return;
    _gaveUp = false;
    watch.reset();
    if (!await recover()) _end();
  }

  /// The player is being torn down: stop watching it.
  void dispose() {
    _disposed = true;
    _watchdog?.cancel();
    onReloaded = null;
    onEnded = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
  }
}
