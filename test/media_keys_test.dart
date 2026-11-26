import 'dart:io';

import 'package:fathom/widgets/media_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// A TV remote's Play, Pause, Rewind, Fast Forward, Next and Previous
// buttons. Only Play/Pause was heard; the rest woke the controls and did
// nothing else.

List<String> _press(
  LogicalKeyboardKey key, {
  bool playing = true,
  bool ends = true,
  bool held = false,
  bool canSeek = true,
}) {
  final did = <String>[];
  final known = handleMediaKey(
    key,
    playing: playing,
    held: held,
    canSeek: canSeek,
    toggle: () => did.add('toggle'),
    back: () => did.add('back'),
    forward: () => did.add('forward'),
    next: ends ? () => did.add('next') : null,
    previous: ends ? () => did.add('previous') : null,
  );
  return [...did, if (!known) 'not a media key'];
}

void main() {
  test('each button does its own thing', () {
    expect(_press(LogicalKeyboardKey.mediaPlayPause), ['toggle']);
    expect(_press(LogicalKeyboardKey.mediaRewind), ['back']);
    expect(_press(LogicalKeyboardKey.mediaFastForward), ['forward']);
    expect(_press(LogicalKeyboardKey.mediaTrackNext), ['next']);
    expect(_press(LogicalKeyboardKey.mediaTrackPrevious), ['previous']);
  });

  test('Play only plays and Pause only pauses', () {
    expect(_press(LogicalKeyboardKey.mediaPlay, playing: true), isEmpty);
    expect(_press(LogicalKeyboardKey.mediaPlay, playing: false), ['toggle']);
    expect(_press(LogicalKeyboardKey.mediaPause, playing: true), ['toggle']);
    expect(_press(LogicalKeyboardKey.mediaPause, playing: false), isEmpty);
    expect(_press(LogicalKeyboardKey.mediaStop, playing: true), ['toggle']);
  });

  test('with no next episode, Next is still dealt with, quietly', () {
    expect(_press(LogicalKeyboardKey.mediaTrackNext, ends: false), isEmpty);
  });

  test('a held button steps for Rewind and Fast Forward only', () {
    // A held Next used to skip a video (or open another player) at every
    // repeat of the key.
    expect(_press(LogicalKeyboardKey.mediaFastForward, held: true), ['forward']);
    expect(_press(LogicalKeyboardKey.mediaRewind, held: true), ['back']);
    expect(_press(LogicalKeyboardKey.mediaTrackNext, held: true), isEmpty);
    expect(_press(LogicalKeyboardKey.mediaTrackPrevious, held: true), isEmpty);
    expect(_press(LogicalKeyboardKey.mediaPlayPause, held: true), isEmpty);
  });

  test('something live has nowhere to seek to', () {
    // The on-screen seek buttons are hidden for Live TV; the remote's
    // Rewind and Fast Forward asked the stream to seek past its edge.
    expect(_press(LogicalKeyboardKey.mediaFastForward, canSeek: false), isEmpty);
    expect(_press(LogicalKeyboardKey.mediaRewind, canSeek: false), isEmpty);
    expect(_press(LogicalKeyboardKey.mediaPlayPause, canSeek: false), ['toggle']);
  });

  test('the players say when a key is held and when the stream is live', () {
    final exo = File('lib/screens/exo_player_screen.dart').readAsStringSync();
    final controls = File('lib/widgets/player_controls.dart').readAsStringSync();
    expect(exo, contains('canSeek: !_isLive'));
    expect(controls, contains('canSeek: !widget.isLive'));
    for (final src in [exo, controls]) {
      expect(src, contains('held: event is KeyRepeatEvent'));
    }
  });

  test('any other key is left to the player', () {
    expect(_press(LogicalKeyboardKey.arrowLeft), ['not a media key']);
  });

  test('all three TV players listen', () {
    for (final f in [
      'lib/screens/exo_player_screen.dart',
      'lib/widgets/player_controls.dart',
      'lib/widgets/youtube_exo_player.dart',
    ]) {
      expect(File(f).readAsStringSync(), contains('handleMediaKey('), reason: f);
    }
  });
}
