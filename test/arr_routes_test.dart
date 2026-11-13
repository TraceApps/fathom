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

    // _get/_post/_put/_delete('path'), _send('METHOD', 'path') for calls
    // that need a body or query the short forms don't take, plus
    // _api('path') for a GET made directly (the slow release search).
    final call = RegExp(
      r"_(get|post|put|delete|api)\(\s*'([^']*)'"
      r"|_send\(\s*'(GET|POST|PUT|DELETE)',\s*'([^']*)'",
    );
    final checked = <String>[];
    final sent = <String>[];
    String route0(String method, String path) => '$method $path';
    final unknown = <String>[];
    for (final m in call.allMatches(src)) {
      // '$id' and '${x.y}' segments are the spec's {id}.
      final raw = m.group(2) ?? m.group(4)!;
      final path = '/api/v3/${raw.replaceAll(RegExp(r'\$\{[^}]*\}|\$\w+'), '{}')}';
      final method = m.group(3) ??
          (m.group(1) == 'api' ? 'GET' : m.group(1)!.toUpperCase());
      if (m.group(3) != null) sent.add(route0(method, path));
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
    // The _send calls are seen too (they once slipped past this scan).
    expect(sent, containsAll([
      'PUT /api/v3/series/{}',
      'PUT /api/v3/movie/{}',
      'DELETE /api/v3/episodefile/bulk',
    ]));
    expect(unknown, isEmpty, reason: 'Not in the app\'s API:\n${unknown.join('\n')}');
  });
}
