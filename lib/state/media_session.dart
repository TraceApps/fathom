import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The video player's live state for the OS media session (MPRIS on Linux, SMTC
/// on Windows). While a video is on screen it registers here, and the desktop
/// integrations present it instead of the music player; on exit it clears and
/// they hand back to music. Null means "no video active, use the music player".
///
/// Callbacks route the OS transport buttons (play/pause/stop/next/previous/seek)
/// back into the video player. [onSeek] takes an absolute position.
class VideoMediaSession {
  final String title;
  final String? subtitle; // e.g. "Series · S1:E2" for episodes; null for movies
  final String? artUrl;
  final bool playing;
  final Duration position;
  final Duration duration;
  final bool canNext; // next episode available
  final bool canPrev; // previous episode available
  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function() onStop;
  final Future<void> Function()? onNext;
  final Future<void> Function()? onPrevious;
  final Future<void> Function(Duration) onSeek;

  const VideoMediaSession({
    required this.title,
    this.subtitle,
    this.artUrl,
    required this.playing,
    required this.position,
    required this.duration,
    this.canNext = false,
    this.canPrev = false,
    this.onNext,
    this.onPrevious,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    required this.onSeek,
  });

  VideoMediaSession copyWith({bool? playing, Duration? position}) =>
      VideoMediaSession(
        title: title,
        subtitle: subtitle,
        artUrl: artUrl,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        duration: duration,
        canNext: canNext,
        canPrev: canPrev,
        onNext: onNext,
        onPrevious: onPrevious,
        onPlay: onPlay,
        onPause: onPause,
        onStop: onStop,
        onSeek: onSeek,
      );
}

class VideoMediaSessionController extends Notifier<VideoMediaSession?> {
  // Identifies which player screen owns the session. Episode changes replace the
  // whole screen, so the outgoing screen must not clear the incoming one's
  // session on dispose — [end] only clears when the token still matches.
  Object? _owner;

  @override
  VideoMediaSession? build() => null;

  /// Register (or replace) the active video source, owned by [token].
  void begin(VideoMediaSession session, Object token) {
    _owner = token;
    state = session;
  }

  /// Cheap playing/position updates that don't rebuild the callbacks/metadata.
  /// Token-guarded so a screen being torn down (e.g. the previous episode) can't
  /// stamp its dying player's state onto the incoming screen's session.
  void updatePlayback(
      {bool? playing, Duration? position, required Object token}) {
    if (!identical(_owner, token)) return;
    final s = state;
    if (s == null) return;
    state = s.copyWith(playing: playing, position: position);
  }

  /// Hand control back to the music player, but only if [token] still owns it.
  ///
  /// Players call this as they're disposed, which happens while the tree is
  /// being rebuilt, and a provider can't change then ("Tried to modify a
  /// provider while the widget tree was building"). So the session is let
  /// go of now and cleared a moment later, unless a new player has taken it
  /// in between.
  void end(Object token) {
    if (!identical(_owner, token)) return;
    _owner = null;
    Future.microtask(() {
      if (_owner == null) state = null;
    });
  }
}

final videoMediaSessionProvider =
    NotifierProvider<VideoMediaSessionController, VideoMediaSession?>(
        VideoMediaSessionController.new);
