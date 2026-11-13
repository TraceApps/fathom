import 'package:fathom/services/system_pip_controls.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Android's PiP window showed the music player's media session controls, so
// play/pause there never reached the video. The video screen now gives the
// window its own buttons; these check they drive the right video.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.fathom.player/pip_controls');
  final sent = <Object?>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    sent.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setButtons') sent.add(call.arguments);
      return null;
    });
  });

  final calls = <String>[];
  void bind(Object owner, {bool playing = true}) => SystemPipControls.bind(
        owner: owner,
        playing: playing,
        onPlay: () async => calls.add('play'),
        onPause: () async => calls.add('pause'),
        onSeekBy: (s) => calls.add('seek $s'),
        backSeconds: 10,
        forwardSeconds: 30,
        playPauseLabel: 'Play / Pause',
        backLabel: 'Back 10s',
        forwardLabel: 'Forward 30s',
      );

  test('the window buttons drive the video', () async {
    calls.clear();
    final screen = Object();
    bind(screen);
    await Future<void>.delayed(Duration.zero);
    expect(sent.single, {
      'playPauseLabel': 'Play / Pause',
      'backLabel': 'Back 10s',
      'forwardLabel': 'Forward 30s',
      'playing': true,
    });
    for (final a in ['pause', 'play', 'back', 'forward']) {
      await SystemPipControls.handle(a);
    }
    expect(calls, ['pause', 'play', 'seek -10', 'seek 30']);
    SystemPipControls.unbind(screen);
  });

  test('play/pause follows the video, sent only on a change', () async {
    final screen = Object();
    bind(screen);
    SystemPipControls.update(owner: screen, playing: true);
    SystemPipControls.update(owner: screen, playing: false);
    SystemPipControls.update(owner: screen, playing: false);
    await Future<void>.delayed(Duration.zero);
    expect(sent.map((a) => (a as Map)['playing']), [true, false]);
    SystemPipControls.unbind(screen);
  });

  test('a screen leaving after the next one opened keeps its hands off',
      () async {
    calls.clear();
    final old = Object(), next = Object();
    bind(old);
    bind(next, playing: false);
    SystemPipControls.update(owner: old, playing: true); // ignored
    SystemPipControls.unbind(old); // ignored
    await SystemPipControls.handle('play');
    expect(calls, ['play']);
    await Future<void>.delayed(Duration.zero);
    expect(sent.last, isNotNull);
    expect((sent.last as Map)['playing'], false);
    SystemPipControls.unbind(next);
    await Future<void>.delayed(Duration.zero);
    expect(sent.last, isNull, reason: 'buttons cleared when the video closes');
    await SystemPipControls.handle('play');
    expect(calls, ['play'], reason: 'no video, nothing to drive');
  });

  test('the outgoing episode leaves PiP on for the next one', () {
    // Next episode: the new screen switches PiP on before the old one is torn
    // down. Only the screen that switched it on may switch it off.
    final ep1 = Object(), ep2 = Object();
    SystemPipControls.claimPip(ep1);
    SystemPipControls.claimPip(ep2);
    expect(SystemPipControls.releasePip(ep1), isFalse);
    expect(SystemPipControls.releasePip(ep2), isTrue);
    expect(SystemPipControls.releasePip(ep2), isFalse);
  });
}
