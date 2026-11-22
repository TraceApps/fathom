import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/arr_widgets.dart';
import 'package:fathom/widgets/cached_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// How Activity's lists look: a download's card with its poster and its
// title's wide picture, the smaller rows of the lists that are logs, and the
// top of the section on the narrowest phones.

const _wide = Size(1360, 850);
const _phone = Size(412, 892);

/// A Radarr that answers each list from what the test gave it.
class _Radarr implements HttpClientAdapter {
  final List<Map<String, dynamic>> queue;
  final List<Map<String, dynamic>> history;
  final List<Map<String, dynamic>> wanted;
  _Radarr({
    this.queue = const [],
    this.history = const [],
    this.wanted = const [],
  });

  Map<String, dynamic> _page(List<Map<String, dynamic>> records) => {
    'page': 1,
    'pageSize': 50,
    'totalRecords': records.length,
    'records': records,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final path = o.uri.path.replaceFirst(RegExp(r'^.*/api/v3/'), '');
    final Object reply = switch (path) {
      'queue' => _page(queue),
      'queue/status' => {
        'totalCount': queue.length,
        'warnings': false,
        'errors': false,
      },
      'history' => _page(history),
      'wanted/missing' => _page(wanted),
      'wanted/cutoff' || 'blocklist' => _page(const []),
      'system/status' => {'version': '1.0.0'},
      _ => const [],
    };
    return ResponseBody.fromString(
      jsonEncode(reply),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _poster = {
  'coverType': 'poster',
  'remoteUrl': 'https://image.tmdb.org/t/p/original/poster.jpg',
};
const _fanart = {
  'coverType': 'fanart',
  'remoteUrl': 'https://image.tmdb.org/t/p/original/fanart.jpg',
};

Map<String, dynamic> _movie({bool fanart = true}) => {
  'id': 5,
  'title': 'Dune',
  'year': 2021,
  'monitored': true,
  'hasFile': false,
  'isAvailable': true,
  'status': 'released',
  'images': [_poster, if (fanart) _fanart],
};

const _gb = 1024 * 1024 * 1024;

/// A movie on its way, done in [left] when that's given.
Map<String, dynamic> _download({
  bool fanart = true,
  Duration? left,
  String status = 'downloading',
}) => {
  'id': 1,
  'title': 'Dune.2021.1080p.BluRay.x264-GROUP',
  'status': status,
  'movieId': 5,
  'movie': _movie(fanart: fanart),
  'size': 4 * _gb,
  'sizeleft': 1 * _gb,
  'quality': {
    'quality': {'name': 'Bluray-1080p'},
  },
  'downloadClient': 'qBittorrent',
  if (left != null)
    'estimatedCompletionTime': DateTime.now()
        .toUtc()
        .add(left)
        .toIso8601String(),
};

const _grabbed = {
  'id': 3,
  'date': '2026-11-20T10:00:00Z',
  'eventType': 'grabbed',
  'sourceTitle': 'Dune.2021.1080p.BluRay.x264-GROUP',
  'movieId': 5,
  'quality': {
    'quality': {'name': 'Bluray-1080p'},
  },
  'data': {'indexer': 'Indexer'},
};

Future<void> _open(WidgetTester t, _Radarr radarr, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final router = GoRouter(
    initialLocation: '/arr',
    routes: [
      GoRoute(path: '/arr', builder: (_, _) => const ArrScreen()),
      GoRoute(
        path: '/arr/add/:kind',
        builder: (_, s) =>
            Scaffold(body: Text('add: ${s.pathParameters['kind']}')),
      ),
    ],
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        sonarrClientProvider.overrideWithValue(null),
        radarrClientProvider.overrideWithValue(
          RadarrClient('http://r', 'k', dio: Dio()..httpClientAdapter = radarr),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(const Color(0xFF8AB4F8)),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await _settle(t);
}

/// Lets the answers arrive and the page draw them. Never pumpAndSettle: the
/// spinners and the queue's reload never go quiet.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tab(WidgetTester t, String name) async {
  await t.tap(find.widgetWithText(Tab, name));
  await _settle(t);
  // The swipe between tabs runs for 300 ms.
  await t.pump(const Duration(milliseconds: 400));
  await _settle(t);
}

/// The small poster of the list's one row or card.
Size _thumb(WidgetTester t) => t.getSize(
  find.byWidgetPredicate((w) => w is ArrArt && w.type == 'poster'),
);

ArrCardWash _wash(WidgetTester t) =>
    t.widget<ArrCardWash>(find.byType(ArrCardWash));

/// The wide picture behind the list's one card, where it has one.
Finder _washArt() => find.descendant(
  of: find.byType(ArrCardWash),
  matching: find.byWidgetPredicate((w) => w is ArrArt && w.type == 'fanart'),
);

/// The card's own color laid over that picture: plain at the near end,
/// thinner toward the far one.
Finder _washTint() => find.descendant(
  of: find.byType(ArrCardWash),
  matching: find.byWidgetPredicate((w) {
    if (w is! DecoratedBox || w.decoration is! BoxDecoration) return false;
    final g = (w.decoration as BoxDecoration).gradient;
    return g is LinearGradient &&
        g.colors.length == 4 &&
        g.colors.first.a == 1 &&
        g.colors.last.a < 1;
  }),
);

/// That the picture is kept in memory at about the size it's drawn: never
/// smaller, and less than a step more.
void _decodedForItsPlace(Size drawn, double? decoded) {
  final needs = math.max(drawn.width, drawn.height * 16 / 9);
  expect(decoded, isNotNull);
  expect(decoded!, greaterThanOrEqualTo(needs));
  expect(decoded, lessThan(needs + 160));
}

/// The line beside a download's state: what's left of it, then what it is.
Finder _meta() => find.textContaining('Bluray-1080p', findRichText: true);

/// True when the text drew whole: not cut short and not wrapped.
bool _whole(WidgetTester t, Finder text) {
  final p = t.renderObject<RenderParagraph>(text);
  return p.getMaxIntrinsicWidth(double.infinity) <= p.size.width + 0.5;
}

Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(
      Future.value(
        ByteData.sublistView(
          File('assets/fonts/Inter-$w.ttf').readAsBytesSync(),
        ),
      ),
    );
  }
  await loader.load();
}

void main() {
  group('how a download is doing', () {
    ArrQueueItem item(
      String? status,
      String? tracked,
      String? state, {
      int id = 1,
      double left = 0,
      String? error,
    }) => ArrQueueItem(
      kind: ArrKind.radarr,
      id: id,
      title: 'Dune',
      status: status,
      trackedDownloadStatus: tracked,
      trackedDownloadState: state,
      size: 100,
      sizeleft: left,
      errorMessage: error,
    );
    ArrQueueState of(String? status, String? tracked, String? state) =>
        item(status, tracked, state).state;

    test('is read from what the app says of it', () {
      const s = ArrQueueState.values;
      // Lidarr's Import Failed is the tenth.
      expect(s, hasLength(10));
      for (final (status, tracked, state, is_) in [
        ('downloading', 'ok', 'downloading', ArrQueueState.downloading),
        (null, null, null, ArrQueueState.downloading),
        ('paused', 'ok', 'downloading', ArrQueueState.paused),
        ('queued', 'ok', 'downloading', ArrQueueState.queued),
        ('delay', 'ok', null, ArrQueueState.delayed),
        ('completed', 'ok', 'downloading', ArrQueueState.waitingToImport),
        ('completed', 'ok', 'importPending', ArrQueueState.waitingToImport),
        ('completed', 'ok', 'importing', ArrQueueState.importing),
        // Failed, however it's said: an error is one too, as in the apps.
        ('failed', 'ok', 'downloading', ArrQueueState.failed),
        ('downloading', 'ok', 'failed', ArrQueueState.failed),
        ('downloading', 'warning', 'failed', ArrQueueState.failed),
        ('completed', 'warning', 'failedPending', ArrQueueState.failed),
        ('completed', 'ok', 'failedPending', ArrQueueState.failed),
        ('downloading', 'error', 'downloading', ArrQueueState.failed),
        ('completed', 'error', 'importPending', ArrQueueState.failed),
        ('completed', 'error', 'importBlocked', ArrQueueState.failed),
        // A warning with nothing more exact to say.
        ('downloading', 'warning', 'downloading', ArrQueueState.needsAttention),
        ('warning', 'ok', 'downloading', ArrQueueState.needsAttention),
        ('paused', 'warning', 'downloading', ArrQueueState.needsAttention),
        ('downloadClientUnavailable', 'ok', null, ArrQueueState.needsAttention),
        // Blocked is the more exact word than its warning.
        ('completed', 'warning', 'importBlocked', ArrQueueState.importBlocked),
        ('completed', 'ok', 'importBlocked', ArrQueueState.importBlocked),
        // A warning outranks how far it got: it waits on a person now (and
        // Manual Import is offered on exactly these).
        ('completed', 'warning', 'importPending', ArrQueueState.needsAttention),
        ('completed', 'warning', 'importing', ArrQueueState.needsAttention),
        ('completed', 'warning', 'downloading', ArrQueueState.needsAttention),
      ]) {
        expect(
          of(status, tracked, state),
          is_,
          reason: '$status, $tracked, $state',
        );
      }
    });

    // Two alike (both stuck, as far along): the same order every time the
    // queue is asked for, whichever app answers first, so a row doesn't
    // swap places under the remote or the pointer.
    test('keeps one order between downloads alike', () {
      ArrQueueItem alike(ArrKind kind, int id) => ArrQueueItem(
        kind: kind,
        id: id,
        title: 'Dune',
        status: 'completed',
        trackedDownloadState: 'importBlocked',
        size: 100,
        sizeleft: 0,
      );
      final a = alike(ArrKind.sonarr, 9);
      final b = alike(ArrKind.radarr, 2);
      final c = alike(ArrKind.radarr, 7);
      for (final start in [
        [a, b, c],
        [c, b, a],
        [b, c, a],
      ]) {
        final sorted = [...start]..sort(arrQueueOrder);
        expect(sorted, [a, b, c], reason: '$start');
      }
    });

    test('comes first in the queue exactly when its card says it\'s stuck', () {
      // One of every reading above, the stuck ones nearly done and the rest
      // barely started, so only the state can put them where they belong.
      final all = [
        item('downloading', 'ok', 'downloading', id: 1, left: 10),
        item('completed', 'ok', 'importPending', id: 2),
        item('paused', 'ok', 'downloading', id: 3, left: 20),
        // Only a message about it, with nothing wrong said of it.
        item('downloading', 'ok', 'downloading', id: 4, left: 30, error: 'x'),
        item('downloading', 'ok', 'failed', id: 5, left: 90),
        item('completed', 'ok', 'failedPending', id: 6, left: 91),
        item('downloading', 'error', 'downloading', id: 7, left: 92),
        item('completed', 'warning', 'importPending', id: 8, left: 93),
        item('completed', 'ok', 'importBlocked', id: 9, left: 94),
        item('downloadClientUnavailable', 'ok', null, id: 10, left: 95),
        item('warning', 'ok', 'downloading', id: 11, left: 96),
        item('failed', 'ok', 'downloading', id: 12, left: 97),
      ]..sort(arrQueueOrder);
      expect([for (final i in all) i.id], [5, 6, 7, 8, 9, 10, 11, 12, 2, 1, 3, 4]);
      // The two never part: what sorts first is what's said in its color.
      final stuck = [for (final i in all) i.state.needsHelp];
      expect(stuck.indexOf(false), 8);
      expect(stuck.lastIndexOf(true), 7);
      // And Manual Import is only ever offered on one that says so.
      for (final state in ['importPending', 'importBlocked', 'importing']) {
        final i = ArrQueueItem(
          kind: ArrKind.radarr,
          id: 1,
          title: 'Dune',
          downloadId: 'abc',
          status: 'completed',
          trackedDownloadStatus: 'warning',
          trackedDownloadState: state,
        );
        expect(i.canManualImport, isTrue, reason: state);
        expect(i.state.needsHelp, isTrue, reason: state);
      }
    });

    test('needs help only when it\'s stuck', () {
      expect(
        [
          for (final s in ArrQueueState.values)
            if (s.needsHelp) s,
        ],
        [
          ArrQueueState.failed,
          ArrQueueState.importBlocked,
          ArrQueueState.importFailed,
          ArrQueueState.needsAttention,
        ],
      );
    });

    test('has a word and a color of its own', () {
      final l = lookupAppLocalizations(const Locale('en'));
      const scheme = ColorScheme.dark();
      (String, Color) standing(String? status, String? tracked, String? state) =>
          arrQueueStanding(
            l,
            scheme,
            ArrQueueItem(
              kind: ArrKind.radarr,
              id: 1,
              title: 'Dune',
              status: status,
              trackedDownloadStatus: tracked,
              trackedDownloadState: state,
            ),
          );
      expect(standing('failed', null, null), ('Failed', arrMissingColor));
      expect(
        standing('completed', 'warning', 'importBlocked'),
        ('Import Blocked', arrWarningColor),
      );
      expect(
        standing('downloading', 'warning', null),
        ('Needs Attention', arrWarningColor),
      );
      expect(
        standing('completed', 'ok', 'importPending'),
        ('Waiting to Import', arrDownloadedColor),
      );
      expect(
        standing('completed', 'ok', 'importing'),
        ('Importing', arrDownloadedColor),
      );
      expect(standing('paused', null, null), ('Paused', scheme.outline));
      expect(standing('queued', null, null), ('Queued', arrQueuedColor));
      expect(standing('delay', null, null), ('Delayed', scheme.outline));
      expect(
        standing('downloading', 'ok', 'downloading'),
        ('Downloading', arrUnreleasedColor),
      );
    });
  });

  group('a download\'s card', () {
    testWidgets('with room has a bigger poster, over the title\'s picture', (
      t,
    ) async {
      await _open(t, _Radarr(queue: [_download()]), _wide);
      await _tab(t, 'Activity');
      expect(_thumb(t), const Size(64, 96));
      expect(_wash(t).quiet, isFalse);
      final picture = t.widget<ArrArt>(_washArt());
      // Nothing where the picture isn't there yet: no gray box in the card.
      expect(picture.bare, isTrue);
      expect(_washTint(), findsOneWidget);
      // Kept at the size it's drawn, not the 1280 or 1920 it comes in at.
      _decodedForItsPlace(t.getSize(_washArt()), picture.decodeWidth);
      expect(picture.decodeWidth, lessThan(1000));
      expect(
        t
            .widget<CachedImage>(
              find.descendant(
                of: _washArt(),
                matching: find.byType(CachedImage),
              ),
            )
            .cacheWidth,
        picture.decodeWidth,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('on a phone has the smaller one, the picture kept quiet', (
      t,
    ) async {
      await _open(t, _Radarr(queue: [_download()]), _phone);
      await _tab(t, 'Activity');
      expect(_thumb(t), const Size(52, 78));
      expect(_wash(t).quiet, isTrue);
      final picture = t.widget<ArrArt>(_washArt());
      _decodedForItsPlace(t.getSize(_washArt()), picture.decodeWidth);
      // A phone's card is a fraction of a window's, and so is its picture.
      expect(picture.decodeWidth, lessThanOrEqualTo(480));
      expect(t.takeException(), isNull);
    });

    test('keeps its picture as wide as it\'s drawn, a step at a time', () {
      const w = ArrCardWash.decodeWidth;
      // Wider than 16:9: the picture is as wide as its place.
      expect(w(const Size(300, 90)), 320);
      expect(w(const Size(320, 90)), 320);
      expect(w(const Size(321, 90)), 480);
      // Taller: it fills the height, and is wider than its place for it.
      expect(w(const Size(100, 180)), 320);
      expect(w(const Size(100, 200)), 480);
      // Never nothing, before there's a size to go by.
      expect(w(Size.zero), 160);
    });

    testWidgets('of a title with no wide picture is the card alone', (t) async {
      await _open(t, _Radarr(queue: [_download(fanart: false)]), _wide);
      await _tab(t, 'Activity');
      expect(_wash(t).picture, isNull);
      // Neither the picture nor the color that goes over one.
      expect(_washArt(), findsNothing);
      expect(_washTint(), findsNothing);
      expect(_thumb(t), const Size(64, 96));
    });

    testWidgets('says how long is left first, then what it is', (t) async {
      await _open(
        t,
        _Radarr(
          queue: [
            // Half a minute to spare: the clock moves on while this runs.
            _download(left: const Duration(minutes: 90, seconds: 30)),
          ],
        ),
        _wide,
      );
      await _tab(t, 'Activity');
      expect(
        t.widget<RichText>(_meta()).text.toPlainText(),
        '1h 30m left · Bluray-1080p · 4.0 GB · qBittorrent',
      );
    });

    testWidgets('only says how long while it downloads', (t) async {
      await _open(
        t,
        _Radarr(
          queue: [
            _download(left: const Duration(minutes: 90), status: 'paused'),
          ],
        ),
        _wide,
      );
      await _tab(t, 'Activity');
      expect(
        t.widget<RichText>(_meta()).text.toPlainText(),
        'Bluray-1080p · 4.0 GB · qBittorrent',
      );
    });

    testWidgets('keeps that to one line on the narrowest phone', (t) async {
      await _loadInter();
      await _open(
        t,
        _Radarr(
          queue: [_download(left: const Duration(minutes: 90, seconds: 30))],
        ),
        const Size(320, 640),
      );
      await _tab(t, 'Activity');
      final line = t.renderObject<RenderParagraph>(_meta());
      expect(line.maxLines, 1);
      expect(line.overflow, TextOverflow.ellipsis);
      // What gives way is the end of it: the time left is still read.
      expect(line.text.toPlainText(), startsWith('1h 30m left'));
      final chip = t.getRect(find.byType(ArrChip));
      final meta = t.getRect(_meta());
      expect(meta.left, greaterThan(chip.right));
      expect(meta.center.dy, closeTo(chip.center.dy, 2));
      expect(meta.right, lessThanOrEqualTo(320 - 16));
      expect(t.takeException(), isNull);
    });
  });

  group('a row of a list that\'s a log', () {
    testWidgets('with more to say has a bigger picture where there\'s room', (
      t,
    ) async {
      final history = [
        {..._grabbed, 'movie': _movie()},
      ];
      await _open(t, _Radarr(history: history), _wide);
      await _tab(t, 'Activity');
      await t.tap(find.text('History'));
      await _settle(t);
      expect(find.text('Dune'), findsOneWidget);
      expect(_thumb(t), const Size(56, 84));
    });

    testWidgets('keeps the small one on a phone', (t) async {
      final history = [
        {..._grabbed, 'movie': _movie()},
      ];
      await _open(t, _Radarr(history: history), _phone);
      await _tab(t, 'Activity');
      await t.tap(find.text('History'));
      await _settle(t);
      expect(find.text('Dune'), findsOneWidget);
      expect(_thumb(t), const Size(46, 69));
    });

    testWidgets('of two lines keeps the small one however wide', (t) async {
      await _open(t, _Radarr(wanted: [_movie()]), _wide);
      await _tab(t, 'Wanted');
      expect(find.text('Dune'), findsOneWidget);
      expect(_thumb(t), const Size(46, 69));
    });

    testWidgets('has no picture behind it', (t) async {
      final history = [
        {..._grabbed, 'movie': _movie()},
      ];
      await _open(t, _Radarr(history: history), _wide);
      await _tab(t, 'Activity');
      await t.tap(find.text('History'));
      await _settle(t);
      expect(find.byType(ArrCardWash), findsNothing);
    });
  });

  group('on the narrowest phones', () {
    testWidgets('Add is the button alone below 400, and still adds', (t) async {
      await _open(t, _Radarr(), const Size(399, 780));
      expect(find.text('Add'), findsNothing);
      await t.tap(find.byTooltip('Add'));
      await _settle(t);
      expect(find.text('add: movie'), findsOneWidget);
    });

    testWidgets('Add is named from 400', (t) async {
      await _open(t, _Radarr(), const Size(400, 780));
      expect(find.text('Add'), findsOneWidget);
      expect(find.byTooltip('Add'), findsNothing);
      await t.tap(find.text('Add'));
      await _settle(t);
      expect(find.text('add: movie'), findsOneWidget);
    });

    for (final width in [320.0, 360.0]) {
      testWidgets('the section\'s name is whole at ${width.round()}', (
        t,
      ) async {
        await _loadInter();
        await _open(t, _Radarr(), Size(width, 780));
        final name = find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Manage'),
        );
        expect(_whole(t, name), isTrue);
        // Set a little smaller on the narrowest, and at its own size from
        // 360.
        final scale = t.getRect(name).width / t.getSize(name).width;
        if (width < 360) {
          expect(scale, inInclusiveRange(0.85, 1));
        } else {
          expect(scale, closeTo(1, 0.001));
        }
        expect(
          t.getRect(name).right,
          lessThanOrEqualTo(t.getRect(find.byTooltip('Add')).left),
        );
        expect(t.takeException(), isNull);
      });

      testWidgets('Wanted\'s switch and buttons share a line at '
          '${width.round()}', (t) async {
        await _loadInter();
        await _open(t, _Radarr(wanted: [_movie()]), Size(width, 780));
        await _tab(t, 'Wanted');
        final bar = find.byType(ArrToolbar);
        final lead = t.getRect(
          find.descendant(
            of: bar,
            matching: find.byType(ArrSwitch<ArrWantedList>),
          ),
        );
        final showing = t.getRect(
          find.descendant(of: bar, matching: find.byTooltip('Showing')),
        );
        final more = t.getRect(
          find.descendant(of: bar, matching: find.byTooltip('More')),
        );
        expect(showing.left, greaterThanOrEqualTo(lead.right));
        expect(more.left, greaterThanOrEqualTo(showing.right - 0.5));
        expect(showing.center.dy, closeTo(lead.center.dy, 1));
        expect(more.right, lessThanOrEqualTo(width));
        for (final label in ['Missing', 'Cutoff Unmet']) {
          final text = t.renderObject<RenderParagraph>(
            find.descendant(of: bar, matching: find.text(label)),
          );
          expect(text.size.height, lessThan(24), reason: '$label on one line');
        }
        expect(t.takeException(), isNull);
      });
    }
  });
}
