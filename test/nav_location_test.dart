import 'dart:io';

import 'package:fathom/routing/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// The side menu lights the tile of the page you're on. A page opened over
// another keeps the router's matched location underneath it, so Settings
// opened from Home lit Home, and Home Layout ("/home-layout") did too.

const _tiles = ['/home', '/favorites', '/libraries'];

Future<String> _after(WidgetTester t, String pushed) async {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) => Column(
          children: [
            Text(
              'lit:${navLocation(GoRouterState.of(context), _tiles)}',
              textDirection: TextDirection.ltr,
            ),
            Expanded(child: child),
          ],
        ),
        routes: [
          GoRoute(
            path: '/home',
            builder: (c, _) => TextButton(
              onPressed: () => c.push(pushed),
              child: const Text('open'),
            ),
          ),
          for (final p in [
            '/settings',
            '/preferences',
            '/home-layout',
            '/connections/mdblist',
            '/favorites',
            '/notifications',
            '/item',
            '/playlists',
            '/genres',
            '/library',
          ])
            GoRoute(path: p, builder: (_, _) => const SizedBox()),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(MaterialApp.router(routerConfig: router));
  await t.pumpAndSettle();
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  final text = t.widget<Text>(find.textContaining('lit:')).data!;
  return text.substring(4);
}

void main() {
  for (final page in [
    '/settings',
    '/preferences',
    '/home-layout',
    '/connections/mdblist',
  ]) {
    testWidgets('$page opened from Home lights Settings', (t) async {
      expect(await _after(t, page), '/settings');
    });
  }

  testWidgets('a page with a tile of its own lights that tile', (t) async {
    expect(await _after(t, '/favorites'), '/favorites');
    expect(await _after(t, '/notifications'), '/notifications');
  });

  testWidgets('a Browse page or a library opened over Home lights its own row',
      (t) async {
    // A phone opens these over the page it was on. The menu lit Home.
    expect(await _after(t, '/playlists'), '/playlists');
    expect(await _after(t, '/genres'), '/genres');
    expect(await _after(t, '/library'), '/library');
  });

  testWidgets("a title's page leaves the section it came from lit", (t) async {
    expect(await _after(t, '/item'), '/home');
  });

  group('where a TV remote lands in the side menu', () {
    const routes = ['/home', '/search', '/libraries', '/browse', '/favorites'];

    test('inside a library: on Libraries, not Home', () {
      expect(navAnchor('/library', routes), '/libraries');
      expect(navAnchor('/libraries', routes), '/libraries');
    });

    test('on a Browse page: on Browse', () {
      expect(navAnchor('/genres', routes), '/browse');
    });

    test('on a page with a tile: that tile', () {
      expect(navAnchor('/favorites', routes), '/favorites');
    });

    test('on a page with none: the first tile, so there is somewhere', () {
      expect(navAnchor('/item', routes), '/home');
      expect(navAnchor('/library', ['/home', '/favorites']), '/home');
    });
  });

  test('the Settings tile opens Settings once, not again on top of itself', () {
    final src = File('lib/routing/app_shell.dart').readAsStringSync();
    expect(
      src,
      contains("if (!location.startsWith('/settings')) context.push('/settings');"),
    );
  });
}
