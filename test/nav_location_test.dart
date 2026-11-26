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

  testWidgets("a title's page leaves the section it came from lit", (t) async {
    expect(await _after(t, '/item'), '/home');
  });
}
