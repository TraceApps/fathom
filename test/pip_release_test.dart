import 'package:fathom/state/pip_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Stands in for a libmpv player: the dock only keeps it, stops it and
/// disposes it. A real one hung CI runners (no sound device) in dispose.
class _Player implements Player {
  int stopped = 0, disposed = 0;

  @override
  Future<void> stop() async => stopped++;

  @override
  Future<void> dispose() async => disposed++;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Controller implements VideoController {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// A minimized YouTube video's dropout recovery travels with its player: the
// dock stops it when the player goes away (closed or replaced), and leaves it
// running when the video is reopened full size, where the page takes it over.
void main() {
  void adopt(PipController pip, Player player, void Function() onRelease) =>
      pip.adopt(
        player: player,
        controller: _Controller(),
        title: 't',
        matchId: 'id',
        route: '/youtube/watch',
        routeExtra: 'x',
        handoffData: 'handoff',
        onRelease: onRelease,
      );

  test('not released when the video is reopened full size', () {
    // The reopened page takes the recovery over (handoffData) and keeps it.
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final pip = c.read(pipProvider.notifier);
    final p = _Player();
    var released = 0;
    adopt(pip, p, () => released++);
    expect(pip.handoffData, 'handoff');
    pip.detachForReclaim();
    expect(released, 0);
    expect(pip.handoffData, isNull);
    // The page owns the player now: the dock leaves it playing.
    c.dispose();
    expect(p.disposed, 0);
  });

  test('released when another video takes the dock', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final pip = c.read(pipProvider.notifier);
    final p = _Player(), other = _Player();
    var first = 0, second = 0;
    adopt(pip, p, () => first++);
    adopt(pip, p, () => second++); // same player: nothing disposed
    expect((first, second), (1, 0));
    expect(p.disposed, 0);
    adopt(pip, other, () {}); // a new player: the old one goes
    await pumpEventQueue();
    expect(second, 1);
    expect((p.stopped, p.disposed), (1, 1));
    expect(other.disposed, 0);
  });

  test('released when the dock closes', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final pip = c.read(pipProvider.notifier);
    final p = _Player();
    var released = 0;
    adopt(pip, p, () => released++);
    await pip.close();
    expect(released, 1);
    expect((p.stopped, p.disposed), (1, 1));
    expect(pip.player, isNull);
  });
}
