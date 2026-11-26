import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/arr.dart';
import 'preferences.dart';

// More than one server of an app (a 4K Radarr beside the usual one). One of
// each app is in use at a time, in the usual fields (sonarrUrl and the
// rest), so every page simply follows it. The others wait in
// Prefs.arrServers, each with its own Defaults for New Titles: a quality
// profile's number means something else on another server. Switching swaps
// the two.

/// One saved server of an app.
class ArrServer {
  final String id;
  final ArrKind kind;

  /// What the user calls it ("4K"); empty for the one there always was.
  final String name;
  final String url;

  /// Its API key, from this device only: never in a backup.
  final String apiKey;

  /// Its Defaults for New Titles (ArrAddDefaults as JSON).
  final Map<String, dynamic> addDefaults;

  /// The one in use.
  final bool active;

  const ArrServer({
    required this.id,
    required this.kind,
    required this.name,
    required this.url,
    required this.apiKey,
    this.addDefaults = const {},
    this.active = false,
  });

  /// Has what it needs to connect. A server brought back by a backup has
  /// no key yet.
  bool get ready => url.isNotEmpty && apiKey.isNotEmpty;

  Map<String, dynamic> toStored() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'url': url,
    'addDefaults': addDefaults,
  };
}

/// A new server id.
String newArrServerId() {
  final r = Random.secure();
  return List.generate(
    12,
    (_) => r.nextInt(36).toRadixString(36),
  ).join();
}

(String, String, Map<String, dynamic>) _activeFields(Prefs p, ArrKind k) =>
    switch (k) {
      ArrKind.sonarr => (p.sonarrUrl, p.sonarrApiKey, p.sonarrAddDefaults),
      ArrKind.radarr => (p.radarrUrl, p.radarrApiKey, p.radarrAddDefaults),
      ArrKind.lidarr => (p.lidarrUrl, p.lidarrApiKey, p.lidarrAddDefaults),
    };

Prefs _withActive(
  Prefs p,
  ArrKind k,
  String url,
  String key,
  Map<String, dynamic> defaults,
) => switch (k) {
  ArrKind.sonarr => p.copyWith(
    sonarrUrl: url,
    sonarrApiKey: key,
    sonarrAddDefaults: defaults,
  ),
  ArrKind.radarr => p.copyWith(
    radarrUrl: url,
    radarrApiKey: key,
    radarrAddDefaults: defaults,
  ),
  ArrKind.lidarr => p.copyWith(
    lidarrUrl: url,
    lidarrApiKey: key,
    lidarrAddDefaults: defaults,
  ),
};

/// The id and name of the server of [k] in use; an id is made up for the
/// one there always was, the first time it's needed.
(String?, String) _activeIdName(Prefs p, ArrKind k) {
  final a = p.arrActiveServers[k.name];
  if (a is! Map) return (null, '');
  return (a['id'] as String?, (a['name'] as String?) ?? '');
}

/// Every server of [k]: the one in use first, then the others as saved.
List<ArrServer> arrServersOf(Prefs p, ArrKind k) {
  final (url, key, defaults) = _activeFields(p, k);
  final (id, name) = _activeIdName(p, k);
  return [
    if (url.isNotEmpty)
      ArrServer(
        // The one there always was has no id saved: a fixed one, so it can
        // be opened by it (Settings) and stays the same once it's saved.
        id: id == null || id.isEmpty ? 'main-${k.name}' : id,
        kind: k,
        name: name,
        url: url,
        apiKey: key,
        addDefaults: defaults,
        active: true,
      ),
    for (final s in p.arrServers)
      if (s['kind'] == k.name)
        ArrServer(
          id: '${s['id'] ?? ''}',
          kind: k,
          name: '${s['name'] ?? ''}',
          url: '${s['url'] ?? ''}',
          apiKey: p.arrServerKeys['${s['id']}'] ?? '',
          addDefaults: s['addDefaults'] is Map
              ? Map<String, dynamic>.from(s['addDefaults'] as Map)
              : const {},
        ),
  ];
}

/// Puts the server [id] of [k] in use, and the one in use with the others.
Prefs arrSwitchServer(Prefs p, ArrKind k, String id) {
  final all = arrServersOf(p, k);
  final target = all.where((s) => !s.active && s.id == id).firstOrNull;
  if (target == null) return p;
  final current = all.where((s) => s.active).firstOrNull;
  final keys = {...p.arrServerKeys}..remove(target.id);
  final others = [
    for (final s in p.arrServers)
      if (s['id'] != target.id) s,
  ];
  if (current != null) {
    final currentId = current.id.isEmpty ? newArrServerId() : current.id;
    others.add(
      ArrServer(
        id: currentId,
        kind: k,
        name: current.name,
        url: current.url,
        apiKey: current.apiKey,
        addDefaults: current.addDefaults,
      ).toStored(),
    );
    keys[currentId] = current.apiKey;
  }
  return _withActive(
    p,
    k,
    target.url,
    target.apiKey,
    target.addDefaults,
  ).copyWith(
    arrServers: others,
    arrServerKeys: keys,
    arrActiveServers: {
      ...p.arrActiveServers,
      k.name: {'id': target.id, 'name': target.name},
    },
  );
}

/// Saves another server of [k], not in use yet. With none in use, it's put
/// in use.
Prefs arrAddServer(
  Prefs p,
  ArrKind k, {
  required String name,
  required String url,
  required String apiKey,
}) {
  final id = newArrServerId();
  final (activeUrl, _, defaults) = _activeFields(p, k);
  if (activeUrl.isEmpty) {
    return _withActive(p, k, url, apiKey, defaults).copyWith(
      arrActiveServers: {
        ...p.arrActiveServers,
        k.name: {'id': id, 'name': name},
      },
    );
  }
  return p.copyWith(
    arrServers: [
      ...p.arrServers,
      ArrServer(
        id: id,
        kind: k,
        name: name,
        url: url,
        apiKey: apiKey,
      ).toStored(),
    ],
    arrServerKeys: {...p.arrServerKeys, id: apiKey},
  );
}

/// Forgets a server that isn't in use.
Prefs arrRemoveServer(Prefs p, String id) => p.copyWith(
  arrServers: [
    for (final s in p.arrServers)
      if (s['id'] != id) s,
  ],
  arrServerKeys: {...p.arrServerKeys}..remove(id),
);

/// Names a server (the one in use, or another), or changes its address or
/// key: a server brought back by a backup needs its key again.
Prefs arrEditServer(
  Prefs p,
  ArrKind k,
  String id, {
  String? name,
  String? url,
  String? apiKey,
}) {
  final all = arrServersOf(p, k);
  final s = all.where((s) => s.id == id).firstOrNull;
  if (s == null) return p;
  if (s.active) {
    final (oldUrl, key, defaults) = _activeFields(p, k);
    return _withActive(p, k, url ?? oldUrl, apiKey ?? key, defaults).copyWith(
      arrActiveServers: {
        ...p.arrActiveServers,
        k.name: {
          'id': s.id.isEmpty ? newArrServerId() : s.id,
          'name': name ?? s.name,
        },
      },
    );
  }
  return p.copyWith(
    arrServers: [
      for (final x in p.arrServers)
        if (x['id'] == id)
          {...x, 'name': name ?? x['name'], 'url': url ?? x['url']}
        else
          x,
    ],
    arrServerKeys: apiKey == null
        ? p.arrServerKeys
        : {...p.arrServerKeys, id: apiKey},
  );
}

/// Every server of [k], following the settings.
final arrServersProvider = Provider.family<List<ArrServer>, ArrKind>((ref, k) {
  final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
  return arrServersOf(p, k);
});

/// The apps with more than one server: where a switch is worth showing.
final arrMultiServerKindsProvider = Provider<List<ArrKind>>(
  (ref) => [
    for (final k in ArrKind.values)
      if (ref.watch(arrServersProvider(k)).length > 1) k,
  ],
);

/// Disconnects the server of [k] in use. Another saved server of [k] takes
/// its place; with none, the app is simply disconnected (its Defaults for
/// New Titles kept, as they always were).
Prefs arrDisconnectActive(Prefs p, ArrKind k) {
  // One that can connect: a server brought back by a backup has no key.
  final others = [
    for (final s in arrServersOf(p, k))
      if (!s.active && s.ready) s,
  ];
  if (others.isEmpty) {
    final (_, _, defaults) = _activeFields(p, k);
    return _withActive(p, k, '', '', defaults).copyWith(
      arrActiveServers: {...p.arrActiveServers}..remove(k.name),
    );
  }
  final switched = arrSwitchServer(p, k, others.first.id);
  // The one disconnected went to the end of the saved list.
  return arrRemoveServer(switched, '${switched.arrServers.last['id']}');
}

/// After a backup is restored over [local]: the backup brings addresses,
/// names and defaults, but keys never leave a device, so a backup made
/// while another server was in use would pair this device's key with the
/// wrong address. Keys are paired again by address (a key belongs to the
/// server there), a server listed twice is listed once, and this device's
/// servers the backup didn't know of are kept.
Prefs arrReconcileRestore(Prefs local, Prefs restored) {
  var p = restored;
  for (final k in ArrKind.values) {
    final mine = arrServersOf(local, k);
    // The same address written another way (a trailing slash, the host in
    // capitals) is the same server: its key stays, as the other
    // connections' do.
    String at(String u) =>
        u.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();
    String? keyAt(String url) => mine
        .where((s) => at(s.url) == at(url) && s.apiKey.isNotEmpty)
        .firstOrNull
        ?.apiKey;
    final (url, _, defaults) = _activeFields(p, k);
    var (activeId, activeName) = _activeIdName(p, k);
    final others = <Map<String, dynamic>>[];
    final keys = <String, String>{};
    final seen = <String>{if (url.isNotEmpty) url};
    // A saved server's key is kept under its id, so an id names one server
    // and one only. The ids in a backup are whatever its maker wrote: two
    // servers under one id (one at an address of theirs, one at yours), or
    // one under the id of a server of yours, would have shared your key, and
    // the app would have sent it to their address at its next check. Every
    // server here gets an id of its own; one that's taken, or missing, is
    // given a new one.
    final taken = <String>{};
    // The server in use has an id too, a fixed one when none was ever saved.
    final startId = activeId == null || activeId.isEmpty
        ? 'main-${k.name}'
        : activeId;
    if (url.isNotEmpty) taken.add(startId);
    String own(String id) {
      var mine_ = id;
      while (mine_.isEmpty || !taken.add(mine_)) {
        mine_ = newArrServerId();
      }
      return mine_;
    }

    for (final s in p.arrServers) {
      if (s['kind'] != k.name) continue;
      final sUrl = '${s['url'] ?? ''}';
      if (sUrl == url && url.isNotEmpty) {
        // The one in use, listed again: it's that one.
        activeId = '${s['id'] ?? ''}';
        activeName = '${s['name'] ?? ''}';
        continue;
      }
      if (!seen.add(sUrl)) continue;
      final id = own('${s['id'] ?? ''}');
      others.add({...s, 'id': id});
      final key = keyAt(sUrl);
      if (key != null) keys[id] = key;
    }
    // This device's servers the backup didn't have.
    for (final s in mine) {
      if (s.url.isEmpty || !seen.add(s.url)) continue;
      final id = own(s.id);
      others.add(
        ArrServer(
          id: id,
          kind: k,
          name: s.name,
          url: s.url,
          apiKey: s.apiKey,
          addDefaults: s.addDefaults,
        ).toStored(),
      );
      if (s.apiKey.isNotEmpty) keys[id] = s.apiKey;
    }
    if (url.isEmpty && others.isEmpty) continue;
    p = _withActive(p, k, url, url.isEmpty ? '' : keyAt(url) ?? '', defaults)
        .copyWith(
          arrServers: [
            for (final s in p.arrServers)
              if (s['kind'] != k.name) s,
            ...others,
          ],
          arrServerKeys: {
            // Keys kept from before stay only where no server of this kind
            // (in the backup or after it) goes by that id: the ones for
            // this kind are exactly [keys], each found by address.
            for (final e in p.arrServerKeys.entries)
              if (!taken.contains(e.key) &&
                  !p.arrServers.any(
                    (s) => s['kind'] == k.name && '${s['id']}' == e.key,
                  ))
                e.key: e.value,
            ...keys,
          },
          arrActiveServers: {
            ...p.arrActiveServers,
            if (url.isNotEmpty && activeId != null)
              k.name: {
                // Not an id a saved server holds: switching away saves the
                // one in use under its id, key and all.
                'id': activeId == startId
                    ? activeId
                    : activeId.isEmpty || taken.contains(activeId)
                    ? newArrServerId()
                    : activeId,
                'name': activeName,
              },
          },
        );
  }
  return p;
}
