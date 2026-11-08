import 'dart:convert';
import 'dart:io';

import 'package:fathom/models/arr.dart';
import 'package:fathom/screens/arr_add_screen.dart';
import 'package:fathom/services/settings_backup.dart';
import 'package:fathom/state/preferences.dart';
import 'package:flutter_test/flutter_test.dart';

dynamic _fixture(String name) =>
    jsonDecode(File('test/fixtures/arr/$name.json').readAsStringSync());

ArrRootFolder _root(String path, List<String> unmapped) => ArrRootFolder(
  id: 1,
  path: path,
  unmappedFolders: [
    for (final n in unmapped) ArrFolder(name: n, path: '$path/$n'),
  ],
);

ArrAddedWith _movie(String path, int profile, [String avail = 'released']) => (
  path: path,
  qualityProfileId: profile,
  minimumAvailability: avail,
  seriesType: null,
  seasonFolder: null,
);

void main() {
  test('root folders carry the folders the app does not manage yet', () {
    // Recorded from Radarr 6.4.4 with a movie folder it was never told about.
    final roots = [
      for (final m in _fixture('radarr_rootfolder') as List)
        ArrRootFolder.fromJson(m),
    ];
    expect(roots.single.path, '/movies');
    expect(roots.single.unmappedFolders.single.name, 'The Matrix 1999 [1080p]');
    expect(
      roots.single.unmappedFolders.single.path,
      '/movies/The Matrix 1999 [1080p]',
    );
    // Sonarr's recorded root folder has none.
    final tv = [
      for (final m in _fixture('sonarr_rootfolder') as List)
        ArrRootFolder.fromJson(m),
    ];
    expect(tv.first.unmappedFolders, isEmpty);
  });

  group('existing folder', () {
    final roots = [
      _root('/movies', [
        'The Matrix 1999 [1080p]',
        'The Matrix Reloaded (2003)',
        'Dune Part Two (2024)',
        'Breaking Bad',
        'Kids',
      ]),
    ];

    test('matches the title then its year, whatever the punctuation', () {
      final m = arrExistingFolder(roots, title: 'The Matrix', year: 1999);
      expect(m?.folder.path, '/movies/The Matrix 1999 [1080p]');
      expect(m?.sure, isTrue);
      expect(
        arrExistingFolder(
          roots,
          title: 'The Matrix Reloaded',
          year: 2003,
        )?.folder.name,
        'The Matrix Reloaded (2003)',
      );
    });

    test('never takes a different title that starts the same', () {
      expect(arrExistingFolder(roots, title: 'Dune', year: 2021), isNull);
      expect(arrExistingFolder(roots, title: 'The Matrix', year: 2021), isNull);
    });

    test('the title alone, with a year known, is shown but not assumed', () {
      // "Breaking Bad" for a 2008 show, or a "Dune" folder for the 2021 film
      // that may hold the 1984 one: Add asks rather than adopting it.
      final m = arrExistingFolder(roots, title: 'Breaking Bad', year: 2008);
      expect(m?.folder.name, 'Breaking Bad');
      expect(m?.sure, isFalse);
      final remake = arrExistingFolder(
        [
          _root('/movies', ['Dune']),
        ],
        title: 'Dune',
        year: 2021,
      );
      expect(remake?.sure, isFalse);
      // With no year to check, the title alone is the best there is.
      expect(arrExistingFolder(roots, title: 'Breaking Bad')?.sure, isTrue);
    });

    test("Jellyfin's folder name settles it, but only for this title", () {
      final odd = [
        _root('/movies', ['Dune', 'Dune 2021 2160p']),
      ];
      // Two folders match Dune; Jellyfin says which one plays it.
      final m = arrExistingFolder(
        odd,
        title: 'Dune',
        year: 2021,
        hint: 'DUNE 2021 2160p',
      );
      expect(m?.folder.name, 'Dune 2021 2160p');
      expect(m?.sure, isTrue);
      // A collection folder ("Kids/Frozen.mkv") is never taken for a title
      // that isn't its name.
      expect(
        arrExistingFolder(roots, title: 'Frozen', year: 2013, hint: 'Kids'),
        isNull,
      );
      // A hint for another title (the search changed) doesn't make a match.
      expect(
        arrExistingFolder(
          roots,
          title: 'Alien',
          year: 1979,
          hint: 'The Matrix 1999 [1080p]',
        ),
        isNull,
      );
    });

    test('two candidates means no guess', () {
      final two = [
        _root('/movies', ['Heat (1995)']),
        _root('/movies-4k', ['Heat 1995 2160p']),
      ];
      expect(arrExistingFolder(two, title: 'Heat', year: 1995), isNull);
    });
  });

  test('a Jellyfin path gives the folder name, for movies and shows', () {
    expect(
      arrFolderNameOf(
        '/media/movies/The Matrix 1999 [1080p]/matrix.mkv',
        isFile: true,
      ),
      'The Matrix 1999 [1080p]',
    );
    expect(
      arrFolderNameOf(r'D:\Movies\Heat (1995)\Heat.MP4', isFile: true),
      'Heat (1995)',
    );
    // A disc rip's path is its folder, even one named like a release.
    expect(
      arrFolderNameOf('/media/movies/Inception.2010.720p', isFile: true),
      'Inception.2010.720p',
    );
    expect(
      arrFolderNameOf('/media/tv/Breaking Bad', isFile: false),
      'Breaking Bad',
    );
    expect(
      arrFolderNameOf('/media/tv/Breaking Bad/', isFile: false),
      'Breaking Bad',
    );
    expect(arrFolderNameOf(null, isFile: true), isNull);
    expect(arrFolderNameOf('movie.mkv', isFile: true), isNull);
  });

  test('a path belongs to its longest matching root folder', () {
    const roots = ['/media/movies', '/media/movies-4k'];
    expect(
      arrRootOf('/media/movies-4k/Dune (2021)', roots),
      '/media/movies-4k',
    );
    expect(arrRootOf('/media/movies/Dune (1984)', roots), '/media/movies');
    expect(arrRootOf('/elsewhere/Dune', roots), isNull);
  });

  group('starting choices', () {
    const roots = ['/movies', '/movies-4k'];
    const profiles = [1, 4, 5]; // Any, HD-1080p, Ultra-HD
    final library = [
      _movie('/movies/A (2001)', 4),
      _movie('/movies/B (2002)', 4),
      _movie('/movies-4k/C (2003)', 5, 'inCinemas'),
      _movie('/movies/D (2004)', 1, 'inCinemas'),
      _movie('/movies/E (2005)', 4, 'inCinemas'),
    ];

    test('with nothing saved, what most of the library uses', () {
      final c = arrStartingChoice(
        kind: ArrKind.radarr,
        saved: const ArrAddDefaults(),
        roots: roots,
        profiles: profiles,
        library: library,
      );
      expect(c.qualityProfileId, 4, reason: 'HD-1080p, not the first (Any)');
      expect(c.profileSource, ArrChoiceSource.library);
      expect(c.rootFolder, '/movies');
      expect(c.minimumAvailability, 'inCinemas');
      expect(c.monitor, 'movieOnly');
      expect(c.search, isTrue);
    });

    test('saved defaults win while they still exist on the server', () {
      final c = arrStartingChoice(
        kind: ArrKind.radarr,
        saved: const ArrAddDefaults(
          rootFolder: '/movies-4k',
          qualityProfileId: 5,
          search: false,
        ),
        roots: roots,
        profiles: profiles,
        library: library,
      );
      expect(c.qualityProfileId, 5);
      expect(c.profileSource, ArrChoiceSource.saved);
      expect(c.rootFolder, '/movies-4k');
      expect(c.search, isFalse);
    });

    test('a saved profile or folder that was deleted falls back', () {
      final c = arrStartingChoice(
        kind: ArrKind.radarr,
        saved: const ArrAddDefaults(rootFolder: '/gone', qualityProfileId: 99),
        roots: roots,
        profiles: profiles,
        library: library,
      );
      expect(c.qualityProfileId, 4);
      expect(c.profileSource, ArrChoiceSource.library);
      expect(c.rootFolder, '/movies');
    });

    test('an empty library starts on the first of each', () {
      final c = arrStartingChoice(
        kind: ArrKind.sonarr,
        saved: const ArrAddDefaults(),
        roots: roots,
        profiles: profiles,
        library: const [],
      );
      expect(c.qualityProfileId, 1);
      expect(c.profileSource, ArrChoiceSource.first);
      expect(c.rootFolder, '/movies');
      expect(c.monitor, 'all');
      expect(c.seriesType, 'standard');
      expect(c.seasonFolder, isTrue);
    });

    test('shows take the usual series type and season folders', () {
      final c = arrStartingChoice(
        kind: ArrKind.sonarr,
        saved: const ArrAddDefaults(),
        roots: const ['/anime'],
        profiles: profiles,
        library: [
          for (var i = 0; i < 3; i++)
            (
              path: '/anime/Show $i',
              qualityProfileId: 5,
              minimumAvailability: null,
              seriesType: 'anime',
              seasonFolder: false,
            ),
        ],
      );
      expect(c.seriesType, 'anime');
      expect(c.seasonFolder, isFalse);
      expect(c.qualityProfileId, 5);
    });
  });

  test('a draft saves only what belongs to its app', () {
    final draft = ArrChoiceDraft.from(
      arrStartingChoice(
        kind: ArrKind.radarr,
        saved: const ArrAddDefaults(),
        roots: const ['/movies'],
        profiles: const [4],
        library: const [],
      ),
    );
    final movie = draft.toDefaults(kind: ArrKind.radarr);
    expect(movie.seriesType, isNull);
    expect(movie.minimumAvailability, 'released');
    // Adding into an existing folder leaves the saved root and search as
    // they were, even when nothing was saved: one such add must not turn
    // search off for every add after it.
    final kept = draft.toDefaults(
      kind: ArrKind.radarr,
      keep: const ArrAddDefaults(),
    );
    expect(kept.rootFolder, isNull);
    expect(kept.search, isNull);
    expect(kept.qualityProfileId, 4);
    expect(
      ArrAddDefaults.fromJson(kept.toJson()).qualityProfileId,
      kept.qualityProfileId,
    );
  });

  test('defaults survive a restart and travel in backups', () {
    final p = Prefs(
      radarrAddDefaults: const ArrAddDefaults(
        rootFolder: '/movies',
        qualityProfileId: 4,
      ).toJson(),
    );
    final back = Prefs.fromJson(jsonDecode(jsonEncode(p.toJson())));
    expect(ArrAddDefaults.fromJson(back.radarrAddDefaults).qualityProfileId, 4);
    expect(secretPrefKeys.contains('radarrAddDefaults'), isFalse);
    expect(const Prefs().sonarrAddDefaults, isEmpty);
  });

  test('id searches only go to the app that knows that id', () {
    const both = [ArrKind.radarr, ArrKind.sonarr];
    expect(arrAddKindsFor('tmdb:603', both), [ArrKind.radarr]);
    expect(arrAddKindsFor('TVDB:81189', both), [ArrKind.sonarr]);
    expect(arrAddKindsFor('imdb:tt0133093', both), both);
    expect(arrAddKindsFor('dune', both), both);
    // Sonarr alone reads tmdb: as a TV id, so it still gets the search.
    expect(arrAddKindsFor('tmdb:1396', const [ArrKind.sonarr]), [
      ArrKind.sonarr,
    ]);
  });
}
