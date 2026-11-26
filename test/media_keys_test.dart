import 'dart:io';

import 'package:fathom/widgets/media_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// A TV remote's Play, Pause, Rewind, Fast Forward, Next and Previous
// buttons. Only Play/Pause was heard; the rest woke the controls and did
// nothing else.

List<String> _press(LogicalKeyboardKey key, {bool playing = true, bool ends = true}) {
  final did = <String>[];
  final known = handleMediaKey(
    key,
    playing: playing,
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
