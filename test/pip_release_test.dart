import 'package:fathom/state/pip_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// The dock tells a minimized YouTube video's dropout recovery to stop whenever
// it lets go of the player; left running, it would reload a stream the
// reopened watch screen (with its own recovery) or nobody owns any more.
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
        onRelease: onRelease,
      );

  test('released once when the video is reopened full size', () {
    final c = ProviderContainer();
    addTearDown(() {
      c.read(pipProvider.notifier).detachForReclaim();
      c.dispose();
    });
    final pip = c.read(pipProvider.notifier);
    var released = 0;
    adopt(pip, () => released++);
    expect(released, 0);
    pip.detachForReclaim();
    pip.detachForReclaim();
    expect(released, 1);
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
    pip.detachForReclaim();
    expect((first, second), (1, 1));
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
