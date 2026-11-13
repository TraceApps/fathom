import 'package:fathom/state/pip_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// A minimized YouTube video's dropout recovery travels with its player: the
// dock stops it when the player goes away (closed or replaced), and leaves it
// running when the video is reopened full size, where the page takes it over.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Player player;
  late VideoController controller;
  setUpAll(() {
    MediaKit.ensureInitialized();
    player = Player();
    controller = VideoController(player);
  });

  void adopt(PipController pip, void Function() onRelease, [Player? p]) =>
      pip.adopt(
        player: p ?? player,
        controller: controller,
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
    var released = 0;
    adopt(pip, () => released++);
    expect(pip.handoffData, 'handoff');
    pip.detachForReclaim();
    expect(released, 0);
    expect(pip.handoffData, isNull);
  });

  test('released when another video takes the dock', () {
    final c = ProviderContainer();
    addTearDown(() {
      c.read(pipProvider.notifier).detachForReclaim();
      c.dispose();
    });
    final pip = c.read(pipProvider.notifier);
    var first = 0, second = 0;
    adopt(pip, () => first++);
    adopt(pip, () => second++); // same player: nothing disposed
    expect((first, second), (1, 0));
  });

  test('released when the dock closes', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final pip = c.read(pipProvider.notifier);
    var released = 0;
    final own = Player();
    adopt(pip, () => released++, own);
    await pip.close();
    expect(released, 1);
  });
}
