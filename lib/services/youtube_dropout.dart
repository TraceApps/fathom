/// Spots a YouTube stream dropping mid-play, so the player can reload it from
/// the same spot instead of treating the drop as the end of the video.
///
/// googlevideo links are tied to the address that resolved them. When a
/// connection drops (Wi-Fi roaming, a mobile handover, a new IPv6 address),
/// mpv reconnects, the server refuses it with 403, and that track just ends:
/// the audio first, then the picture once its buffer runs dry. mpv then reports
/// the video as finished, which used to autoplay the next one.
class YtDropoutWatch {
  YtDropoutWatch({this.maxTries = 3});

  /// Reloads allowed for dropouts close together before giving up.
  final int maxTries;

  static final _refused = RegExp(r'HTTP error 4\d\d');

  DateTime? _reconnectingAt;
  int _tries = 0;
  Duration? _lastAt;

  /// Feed every mpv log line. True when a reconnect was just refused: ffmpeg
  /// logs `http: Will reconnect at <byte>`, then "http: HTTP error 403
  /// Forbidden". A 4xx with no reconnect before it (a caption fetch, say) is
  /// not a dropout.
  bool refusedAfterReconnect(String prefix, String text, {DateTime? now}) {
    if (prefix != 'ffmpeg') return false;
    final at = now ?? DateTime.now();
    if (text.contains('Will reconnect at')) {
      _reconnectingAt = at;
      return false;
    }
    final since = _reconnectingAt;
    if (since == null ||
        at.difference(since) > const Duration(seconds: 30) ||
        !_refused.hasMatch(text)) {
      return false;
    }
    _reconnectingAt = null;
    return true;
  }

  /// Whether mpv's "completed" at [position] stopped short of the real end
  /// [duration], so it was a dropout rather than the video finishing.
  static bool endedEarly(Duration position, Duration duration) =>
      duration > Duration.zero &&
      position < duration - const Duration(seconds: 5);

  /// Takes one reload attempt for a dropout at [position]. False once
  /// [maxTries] dropouts came without the video getting more than 30 seconds
  /// past the last one (or going back before it): a video that keeps dropping on the spot moves on, and
  /// one on a flaky network that plays on between drops recovers every time.
  bool takeTry(Duration position) {
    final last = _lastAt;
    // Well past the last drop (it played on), or well before it (the
    // viewer went back, or the track started over): a new run of tries.
    if (last != null &&
        (position - last > const Duration(seconds: 30) ||
            last - position > const Duration(seconds: 10))) {
      _tries = 0;
    }
    if (_tries >= maxTries) return false;
    _tries++;
    _lastAt = position;
    return true;
  }

  /// Starts a new run of tries (a fresh chance, like reopening the video).
  void reset() {
    _tries = 0;
    _lastAt = null;
  }

  /// The attempt number [takeTry] last handed out, for the log.
  int get tries => _tries;
}

/// What [YtStallWatch] found wrong with a video that says it's playing.
enum YtStall {
  /// The audio stopped while the picture plays on: its connection dropped
  /// and the reconnect failed without a refusal (reset, server error), so mpv
  /// ended the audio track and keeps showing the video in silence.
  silent,

  /// Nothing moves although the video is playing and not buffering: a
  /// connection that hangs instead of failing.
  frozen,
}

/// Spots the stream failures that never end the video, so [YtDropoutWatch]
/// and mpv's own end never see them. Fed a sample every few seconds; reports
/// on every sample for as long as the failure lasts, so the caller can try a
/// light fix first and a heavier one if it persists.
class YtStallWatch {
  /// How long the picture may play on without audio.
  static const silentAfter = Duration(seconds: 6);

  /// How long a playing video may stand still while mpv isn't seeking or
  /// waiting for its cache. mpv can't tell a hung audio connection from one
  /// too slow to play (neither shows in its cache state), and a picture stuck
  /// this long is broken for the viewer either way: fresh links are the fix.
  static const frozenAfter = Duration(seconds: 20);

  /// The tail ignored for silence: some uploads' audio ends before the
  /// picture does.
  static const endTail = Duration(seconds: 15);

  /// A jump bigger than playback could cover between samples (2x speed for
  /// a few seconds) is a seek, not playback.
  static const seekJump = Duration(seconds: 8);

  bool _hadAudio = false;
  Duration? _lastPos;
  double? _lastAudio;
  DateTime? _silentSince;
  DateTime? _stillSince;

  /// [position] and [duration] are the video's, [audioPts] mpv's audio clock
  /// (null while no audio plays). [loading] is true while mpv seeks or waits
  /// for its cache.
  YtStall? sample({
    required Duration position,
    required Duration duration,
    required double? audioPts,
    required bool playing,
    required bool loading,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final lastPos = _lastPos;
    final lastAudio = _lastAudio;
    _lastPos = position;
    _lastAudio = audioPts;
    if (audioPts != null) _hadAudio = true;
    final delta = lastPos == null ? null : position - lastPos;
    if (!playing ||
        loading ||
        delta == null ||
        delta.isNegative ||
        delta > seekJump) {
      _silentSince = null;
      _stillSince = null;
      return null;
    }
    final moved = delta > const Duration(milliseconds: 500);
    final nearEnd =
        duration > Duration.zero && position > duration - endTail;
    final audioStuck = audioPts == null ||
        (lastAudio != null && (audioPts - lastAudio).abs() <= 0.5);
    // Audio back after a gap (a seek re-syncs it): not silent.
    final audioBack = audioPts != null && lastAudio == null;
    if (moved && _hadAudio && !nearEnd && audioStuck && !audioBack) {
      _silentSince ??= at;
    } else {
      _silentSince = null;
    }
    if (!moved) {
      _stillSince ??= at;
    } else {
      _stillSince = null;
    }
    final silent = _silentSince;
    if (silent != null && at.difference(silent) >= silentAfter) {
      return YtStall.silent;
    }
    final still = _stillSince;
    if (still != null && at.difference(still) >= frozenAfter) {
      return YtStall.frozen;
    }
    return null;
  }

  /// A new stream was opened: forget the old one.
  void reset() {
    _hadAudio = false;
    _lastPos = null;
    _lastAudio = null;
    _silentSince = null;
    _stillSince = null;
  }
}
