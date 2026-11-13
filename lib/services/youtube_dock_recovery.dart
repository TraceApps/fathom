import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../models/youtube_caption.dart';
import 'youtube_dropout.dart';
import 'youtube_streams.dart';

/// Dropout recovery for a YouTube video playing in the mini player. The watch
/// screen that recovered it is gone once the video is minimized, so this takes
/// over with the same rules: on a refused reconnect, or an end well short of
/// the real end, resolve fresh links and reopen at the same spot, rendition and
/// caption. Cancelled when the video is reopened full size or the dock closes.
class YtDockRecovery {
  YtDockRecovery({
    required this.player,
    required this.url,
    required this.watch,
    this.adaptiveLabel,
    this.muxedLabel = 'Auto',
    this.muxedOnly = false,
    this.caption,
    Future<YtStreams> Function(String url)? resolve,
  }) : _resolve = resolve ?? ((u) => resolveYoutubeStreams(u, live: false)) {
    _subs = [
      player.stream.log.listen((e) {
        if (watch.refusedAfterReconnect(e.prefix, e.text)) {
          debugPrint('[yt] mini player stream refused: ${e.text.trim()}');
          unawaited(recover());
        }
      }),
      player.stream.completed.listen((done) {
        if (done &&
            YtDropoutWatch.endedEarly(
                player.state.position, player.state.duration)) {
          unawaited(recover());
        }
      }),
    ];
  }

  final Player player;
  final String url;

  /// Carried over from the watch screen, so drops just before minimizing
  /// still count toward the tries.
  final YtDropoutWatch watch;

  /// The adaptive rendition that was playing (its label, e.g. 1080p).
  final String? adaptiveLabel;

  /// The muxed rendition the viewer picked ('Auto' for the default).
  final String muxedLabel;

  /// The screen had fallen back to the muxed stream.
  final bool muxedOnly;
  final YoutubeCaption? caption;
  final Future<YtStreams> Function(String url) _resolve;

  late final List<StreamSubscription<Object>> _subs;
  Future<bool>? _recovery;
  Timer? _watchdog;
  bool _cancelled = false;

  /// Reloads the stream; callers during a reload share its result.
  Future<bool> recover() =>
      _recovery ??= _reload().whenComplete(() => _recovery = null);

  Future<bool> _reload() async {
    _watchdog?.cancel();
    if (_cancelled) return false;
    final pos = player.state.position;
    final play = player.state.playing || player.state.completed;
    if (!watch.takeTry(pos)) {
      debugPrint('[yt] mini player stream keeps dropping; '
          'giving up at ${pos.inSeconds}s');
      return false;
    }
    debugPrint('[yt] mini player stream dropped at ${pos.inSeconds}s; '
        'reloading (try ${watch.tries})');
    try {
      final s = await _resolve(url);
      if (_cancelled) return true;
      final start = pos > Duration.zero ? pos : null;
      if (s.isAdaptive && !muxedOnly) {
        final q = s.qualities.where((x) => x.label == adaptiveLabel).firstOrNull ??
            defaultQualityFor(s.qualities, 'auto');
        if (q == null) return false;
        await player.open(Media(q.url, start: start), play: play);
        if (_cancelled) return true;
        await player.setAudioTrack(AudioTrack.uri(s.audioUrl!));
      } else {
        final u = s.muxedQualities
                .where((x) => x.label == muxedLabel)
                .firstOrNull
                ?.url ??
            s.muxedUrl;
        if (u == null) return false;
        await player.open(Media(u, start: start), play: play);
      }
      if (_cancelled) return true;
      final c = caption;
      if (c != null) {
        try {
          await player.setSubtitleTrack(
              SubtitleTrack.uri(c.vttUrl, title: c.label, language: c.code));
        } catch (_) {}
      }
      debugPrint('[yt] mini player stream reloaded at ${pos.inSeconds}s');
      if (play) _watchReload(pos);
      return true;
    } catch (e) {
      debugPrint('[yt] mini player stream reload failed: $e');
      return false;
    }
  }

  /// Same check as the watch screen: the reload must get going within 15 s
  /// (a minute while buffering), else try again until the tries run out.
  void _watchReload(Duration pos, [int checks = 1]) {
    _watchdog = Timer(const Duration(seconds: 15), () {
      if (_cancelled || _recovery != null) return;
      if (player.state.position > pos + const Duration(seconds: 1)) return;
      if (!player.state.playing && !player.state.completed) return;
      if (player.state.buffering && checks < 4) {
        _watchReload(pos, checks + 1);
        return;
      }
      debugPrint('[yt] mini player reload never started playing');
      unawaited(recover());
    });
  }

  /// Stop watching: the video was reopened full size or the dock closed.
  void cancel() {
    _cancelled = true;
    _watchdog?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
  }
}
