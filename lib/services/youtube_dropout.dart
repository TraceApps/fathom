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
  /// past the last one: a video that keeps dropping on the spot moves on, and
  /// one on a flaky network that plays on between drops recovers every time.
  bool takeTry(Duration position) {
    final last = _lastAt;
    if (last != null && position - last > const Duration(seconds: 30)) {
      _tries = 0;
    }
    if (_tries >= maxTries) return false;
    _tries++;
    _lastAt = position;
    return true;
  }

  /// The attempt number [takeTry] last handed out, for the log.
  int get tries => _tries;
}
