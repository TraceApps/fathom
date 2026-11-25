import 'package:fathom/routing/nav_destinations.dart';
import 'package:fathom/state/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The side menu's list: Browse and Downloads have places of their own, so
// hiding Libraries hides only Libraries.

NavDest _d(String route, {bool fixed = false}) =>
    (route: route, icon: Icons.circle, label: route, fixed: fixed);

final _all = [
  _d('/home', fixed: true),
  _d('/search'),
  _d('/libraries'),
  _d(navBrowseGroup),
  _d('/favorites'),
  _d('/watchlist'),
  _d('/downloads'),
  _d('/arr'),
];

List<String> _routes(Prefs p) => [
  for (final d in orderNavDestinations(_all, p)) d.route,
];

void main() {
  test('hiding Libraries leaves Browse and Downloads', () {
    final routes = _routes(const Prefs(navHidden: ['/libraries']));
    expect(routes.contains('/libraries'), isFalse);
    expect(routes, containsAll([navBrowseGroup, '/downloads']));
  });

  test('Browse and Downloads can be hidden on their own; Home never', () {
    final routes = _routes(
      const Prefs(navHidden: [navBrowseGroup, '/downloads', '/home']),
    );
    expect(routes, ['/home', '/search', '/libraries', '/favorites', '/watchlist', '/arr']);
  });

  test('an order saved before Browse had a place keeps it under Libraries', () {
    // Saved by a version that knew neither Browse nor Downloads.
    final routes = _routes(
      const Prefs(
        navOrder: ['/home', '/arr', '/libraries', '/search', '/favorites', '/watchlist'],
      ),
    );
    expect(routes, [
      '/home',
      '/arr',
      '/libraries',
      navBrowseGroup,
      '/search',
      '/favorites',
      '/watchlist',
      // New to the list: after what was ordered.
      '/downloads',
    ]);
  });

  test('a saved place for Browse is kept', () {
    final routes = _routes(
      const Prefs(navOrder: ['/home', navBrowseGroup, '/libraries']),
    );
    expect(routes.take(3), ['/home', navBrowseGroup, '/libraries']);
  });

  test('with Libraries not in the saved order, Browse keeps its default place', () {
    final sorted = sortNavDestinations(_all, ['/home', '/search']);
    expect([for (final d in sorted) d.route], [for (final d in _all) d.route]);
  });
}
