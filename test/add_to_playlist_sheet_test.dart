import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/youtube_local_playlist.dart';
import 'package:fathom/models/youtube_video.dart';
import 'package:fathom/state/youtube_providers.dart';
import 'package:fathom/widgets/add_to_youtube_playlist.dart';

class _FakePlaylists extends YoutubeLocalPlaylists {
  _FakePlaylists(this._initial);
  final List<YoutubeLocalPlaylist> _initial;

  @override
  Future<List<YoutubeLocalPlaylist>> build() async => _initial;
}

final _video = YoutubeVideo(
  id: 'vid1',
  title: 'The Secret to Grilled Scallops That Never Stick | Full Episode | '
      "America's Test Kitchen (S21 E23)",
  author: 'ATK',
  url: 'https://www.youtube.com/watch?v=vid1',
  thumbnailUrl: 'https://example.invalid/t.jpg',
);

Future<void> openSheet(
    WidgetTester tester, List<YoutubeLocalPlaylist> lists) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      youtubeLocalPlaylistsProvider.overrideWith(() => _FakePlaylists(lists)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddToYoutubePlaylist(context, _video),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('removal is spelled out in its own right, not inside the title',
      (tester) async {
    await openSheet(tester, [
      YoutubeLocalPlaylist(id: 'p1', name: 'TEST', videos: [_video]),
    ]);

    // The instruction must be its own widget. Concatenated onto the video
    // title it renders as one grey blob and gets missed.
    expect(find.text('Tick a playlist to add this video. Untick to remove it.'),
        findsOneWidget);
    // And the saved row says so itself, so the tick isn't the only signal.
    expect(find.textContaining('Saved. Untick to remove.'), findsOneWidget);
    expect(find.text('Save to Playlist'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
  });

  testWidgets('an unsaved playlist row does not claim to be saved',
      (tester) async {
    await openSheet(tester, [
      const YoutubeLocalPlaylist(id: 'p1', name: 'TEST'),
    ]);
    expect(find.textContaining('Saved'), findsNothing);
    expect(find.text('0 videos'), findsOneWidget);
  });

  testWidgets('with no playlists there is nothing to untick, so no hint',
      (tester) async {
    await openSheet(tester, []);
    expect(find.textContaining('Untick to remove'), findsNothing);
    expect(find.text('New Playlist'), findsOneWidget);
  });
}
