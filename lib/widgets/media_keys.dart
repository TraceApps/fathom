import 'package:flutter/services.dart';

/// What a remote's or a keyboard's media key asks for.
enum MediaKey { play, pause, toggle, stop, rewind, forward, next, previous }

/// The media key [key] is, or null for any other key. A TV remote's Play,
/// Pause, Rewind, Fast Forward, Next and Previous buttons arrive as these;
/// only Play/Pause used to be heard.
MediaKey? mediaKeyOf(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.mediaPlayPause) return MediaKey.toggle;
  if (key == LogicalKeyboardKey.mediaPlay) return MediaKey.play;
  if (key == LogicalKeyboardKey.mediaPause) return MediaKey.pause;
  if (key == LogicalKeyboardKey.mediaStop) return MediaKey.stop;
  if (key == LogicalKeyboardKey.mediaRewind) return MediaKey.rewind;
  if (key == LogicalKeyboardKey.mediaFastForward) return MediaKey.forward;
  if (key == LogicalKeyboardKey.mediaTrackNext) return MediaKey.next;
  if (key == LogicalKeyboardKey.mediaTrackPrevious) return MediaKey.previous;
  return null;
}

/// Runs what [key] asks for with what a player can do. Returns whether the
/// key was one of these (and so is dealt with, even when this player has no
/// next or previous to go to).
///
/// [held] is a key still down and repeating: Rewind and Fast Forward go on
/// stepping while held, the others act once per press (a held Next would
/// skip a whole queue). [canSeek] is false for something live, which has
/// nowhere to seek to.
bool handleMediaKey(
  LogicalKeyboardKey key, {
  required bool playing,
  bool held = false,
  bool canSeek = true,
  required void Function() toggle,
  required void Function() back,
  required void Function() forward,
  void Function()? next,
  void Function()? previous,
  void Function()? stop,
}) {
  final asked = mediaKeyOf(key);
  if (asked == null) return false;
  final steps = asked == MediaKey.rewind || asked == MediaKey.forward;
  if (held && !steps) return true;
  if (steps && !canSeek) return true;
  switch (asked) {
    case MediaKey.toggle:
      toggle();
    case MediaKey.play:
      if (!playing) toggle();
    case MediaKey.pause:
      if (playing) toggle();
    case MediaKey.stop:
      if (stop != null) {
        stop();
      } else if (playing) {
        toggle();
      }
    case MediaKey.rewind:
      back();
    case MediaKey.forward:
      forward();
    case MediaKey.next:
      next?.call();
    case MediaKey.previous:
      previous?.call();
  }
  return true;
}
