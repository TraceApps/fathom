import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/api/jellyfin_client.dart';
import 'package:fathom/models/base_item.dart';
import 'package:fathom/routing/app_shell.dart';
import 'package:fathom/routing/item_page.dart';
import 'package:fathom/screens/detail_screen.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/widgets/player_controls.dart';
import 'package:fathom/widgets/ui_common.dart';
import 'package:fathom/widgets/video_system_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:media_kit/media_kit.dart' show PlayerState;

import 'support/fake_player.dart';

// What using the app end to end on an emulator, against a real server,
// turned up before 1.0 (2026-11-27). One test per defect.

/// A page that shows [mobileLeading], and can be told to redraw.
class _Page extends StatefulWidget {
  const _Page({super.key});
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: mobileLeading(context), title: const Text('Watchlist')),
        body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('a title')))),
          child: const Text('open'),
        ),
      );
}

class _Recorder implements HttpClientAdapter {
  final List<Object?> bodies = [];
  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    bodies.add(o.data);
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets(
      "a section's own page keeps its menu button when it redraws under a "
      'title', (tester) async {
    // Phone size: that's where the menu button and Back share the corner.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final page = GlobalKey<_PageState>();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: _Page(key: page)),
    ));
    expect(find.byType(DrawerMenuButton), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // The page redraws while the title is open over it (a list refreshed
    // after playing or favoriting). It used to take a Back arrow here, and
    // keep it once the title closed, with nothing behind it to go back to.
    // ignore: invalid_use_of_protected_member
    page.currentState!.setState(() {});
    await tester.pump();
    Navigator.of(tester.element(find.text('a title'))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(DrawerMenuButton), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('a page opened over another gets Back', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const _Page())),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byType(DrawerMenuButton), findsNothing);
  });

  group('tapping the picture', () {
    Future<FakePlayer> playing(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 450);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final player = FakePlayer(const PlayerState(playing: true));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FathomPlayerControls(
            player: player,
            title: 'A video',
            isLive: false,
            loading: false,
            onBack: () {},
            onSeekBy: (_) {},
            onToggleMute: () {},
          ),
        ),
      ));
      // Long enough for the controls to take themselves away.
      await tester.pump(const Duration(seconds: 7));
      await tester.pump(const Duration(seconds: 1));
      return player;
    }

    testWidgets('a finger brings hidden controls up without pausing',
        (tester) async {
      final player = await playing(tester);
      await tester.tapAt(const Offset(400, 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(player.asked, isNot(contains('playOrPause')));
      // With the controls up, the next tap pauses, as a click does.
      await tester.tapAt(const Offset(400, 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(player.asked.where((a) => a == 'playOrPause'), hasLength(1));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a mouse click plays or pauses, as before', (tester) async {
      final player = await playing(tester);
      await tester.tapAt(const Offset(400, 200),
          kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(player.asked.where((a) => a == 'playOrPause'), hasLength(1));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  testWidgets("a dialog's fields outlive its way out", (tester) async {
    // Server Addresses and Change Password disposed their text controllers
    // the moment the dialog began to close; a redraw while it was still
    // fading out (the keyboard coming back for a field behind it) then
    // broke the screen.
    final ctrl = TextEditingController(text: 'http://server');
    late StateSetter redraw;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            await showDialog<void>(
              context: context,
              builder: (_) => StatefulBuilder(builder: (_, setState) {
                redraw = setState;
                return AlertDialog(content: TextField(controller: ctrl));
              }),
            );
            disposeAfterDialog([ctrl]);
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Back: the dialog starts to leave, and redraws on its way out.
    await tester.binding.handlePopRoute();
    await tester.pump();
    redraw(() {});
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    // And it is disposed in the end, not leaked.
    await tester.pump(const Duration(seconds: 1));
    expect(() => ctrl.addListener(() {}), throwsFlutterError);
  });

  test('a player leaving after Next leaves the screen to the new one', () {
    // Next replaces one player with another: the new one takes video mode
    // (landscape, bars hidden) as it opens, and the old one, on its way out
    // a moment later, used to undo it.
    final oldPlayer = Object(), newPlayer = Object();
    VideoSystemUi.take(oldPlayer);
    VideoSystemUi.take(newPlayer);
    expect(VideoSystemUi.giveBack(oldPlayer), isFalse);
    // The one still playing does give it back when it closes, once.
    expect(VideoSystemUi.giveBack(newPlayer), isTrue);
    expect(VideoSystemUi.giveBack(newPlayer), isFalse);
  });

  test('a song opens its album, not a movie page of itself', () {
    final song = BaseItemDto(
        id: 'a1', name: 'Song', type: 'Audio', album: 'Album', albumId: 'al1');
    final page = itemPage(song) as DetailScreen;
    expect(page.item.id, 'al1');
    expect(page.item.type, 'MusicAlbum');
  });

  test('Playlists and Live TV are not listed again among the libraries', () {
    BaseItemDto view(String? type) =>
        BaseItemDto(id: '$type', name: '$type', collectionType: type);
    expect(isLibraryView(view('movies')), isTrue);
    expect(isLibraryView(view('music')), isTrue);
    expect(isLibraryView(view(null)), isTrue); // a mixed library
    expect(isLibraryView(view('playlists')), isFalse);
    expect(isLibraryView(view('livetv')), isFalse);
  });

  test('a pause is told to the server', () async {
    final server = _Recorder();
    final client = JellyfinClient(
        deviceId: 'd', httpClient: Dio()..httpClientAdapter = server);
    await client.reportPlaybackProgress(
        baseUrl: 'http://jf', token: 't', itemId: 'i', positionTicks: 5, isPaused: true);
    await client.reportPlaybackProgress(
        baseUrl: 'http://jf', token: 't', itemId: 'i', positionTicks: 6);
    Map<String, dynamic> body(int i) => server.bodies[i] is String
        ? jsonDecode(server.bodies[i] as String) as Map<String, dynamic>
        : Map<String, dynamic>.from(server.bodies[i] as Map);
    expect(body(0)['IsPaused'], isTrue);
    expect(body(1)['IsPaused'], isFalse);
  });
}
