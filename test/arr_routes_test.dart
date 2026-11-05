import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every Sonarr and Radarr call Fathom makes must be a route the app serves,
/// checked against the route lists taken from their published API specs
/// (test/fixtures/sonarr_routes.txt, radarr_routes.txt). Calls in
/// SonarrClient go to Sonarr, in RadarrClient to Radarr, and the shared ones
/// in ArrClient to both.
void main() {
  Set<String> routes(String app) => {
        for (final line in File('test/fixtures/${app}_routes.txt').readAsLinesSync())
          if (line.isNotEmpty && !line.startsWith('#')) line,
      };

  test('every Arr call uses a route the app serves', () {
    final sonarr = routes('sonarr');
    final radarr = routes('radarr');
    final src = File('lib/api/arr_client.dart').readAsStringSync();
    final sonarrAt = src.indexOf('class SonarrClient');
    final radarrAt = src.indexOf('class RadarrClient');
    expect(sonarrAt, greaterThan(0));
    expect(radarrAt, greaterThan(sonarrAt));

    // _get/_post/_put/_delete('path'), plus _api('path') for a GET made
    // directly (the slow release search).
    final call = RegExp(r"_(get|post|put|delete|api)\(\s*'([^']*)'");
    final checked = <String>[];
    final unknown = <String>[];
    for (final m in call.allMatches(src)) {
      // '$id' and '${x.y}' segments are the spec's {id}.
      final path = '/api/v3/${m.group(2)!.replaceAll(RegExp(r'\$\{[^}]*\}|\$\w+'), '{}')}';
      final method = m.group(1) == 'api' ? 'GET' : m.group(1)!.toUpperCase();
      final route = '$method $path';
      final apps = m.start > radarrAt
          ? {'radarr': radarr}
          : m.start > sonarrAt
              ? {'sonarr': sonarr}
              : {'sonarr': sonarr, 'radarr': radarr};
      for (final a in apps.entries) {
        checked.add('${a.key} $route');
        if (!a.value.contains(route)) unknown.add('${a.key}: $route');
      }
    }
    expect(checked.length, greaterThan(40), reason: 'the scan found too few calls');
    expect(unknown, isEmpty, reason: 'Not in the app\'s API:\n${unknown.join('\n')}');
  });
}
