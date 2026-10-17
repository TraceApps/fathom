import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/radio_station.dart';
import '../services/secure_http.dart';
import 'preferences.dart';
import 'providers.dart';

/// The user's saved radio stations (grouped, with favorites), persisted locally.
/// Fathom has no backend, so this lives on the device; import/export can move it
/// between installs.
class RadioController extends AsyncNotifier<List<RadioStation>> {
  static const _key = 'fathom_radio_stations';

  @override
  Future<List<RadioStation>> build() async {
    final raw = await ref.read(secureStorageProvider).read(key: _key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => RadioStation.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<RadioStation> get _list => List.of(state.asData?.value ?? const []);

  Future<void> _persist(List<RadioStation> list) async {
    state = AsyncData(list);
    await ref.read(secureStorageProvider).write(
        key: _key, value: jsonEncode(list.map((s) => s.toJson()).toList()));
  }

  /// Replace the entire saved library (used by settings import).
  Future<void> importAll(List<RadioStation> stations) => _persist(stations);

  /// The order the next/previous-station media controls step through: the
  /// exact order the Radio screen displays stations in (Favorites, then each
  /// group alphabetically, then Ungrouped), but with a station that's both
  /// favorited and grouped counted once, at its Favorites position, so a
  /// hands-off skip button never lands on the same station twice per lap.
  List<RadioStation> get skipOrder {
    final list = _list;
    final seen = <String>{};
    final out = <RadioStation>[];
    void addAll(Iterable<RadioStation> src) {
      for (final s in src) {
        if (seen.add(s.id)) out.add(s);
      }
    }

    addAll(list.where((s) => s.favorite));
    final byGroup = <String, List<RadioStation>>{};
    final ungrouped = <RadioStation>[];
    for (final s in list) {
      if (s.group != null && s.group!.isNotEmpty) {
        byGroup.putIfAbsent(s.group!, () => []).add(s);
      } else {
        ungrouped.add(s);
      }
    }
    for (final g in byGroup.keys.toList()..sort()) {
      addAll(byGroup[g]!);
    }
    addAll(ungrouped);
    return out;
  }

  /// Group names in use, sorted; ungrouped stations live under a null group.
  List<String> get groups {
    final set = <String>{};
    for (final s in _list) {
      if (s.group != null && s.group!.isNotEmpty) set.add(s.group!);
    }
    final g = set.toList()..sort();
    return g;
  }

  Future<void> add(RadioStation station) async {
    final list = _list;
    // De-dupe by URL so re-adding a directory station just updates it.
    final i = list.indexWhere((s) => s.url == station.url);
    if (i >= 0) {
      list[i] = station.copyWith(favorite: list[i].favorite);
    } else {
      list.add(station);
    }
    await _persist(list);
  }

  Future<void> remove(String id) async {
    final list = _list..removeWhere((s) => s.id == id);
    await _persist(list);
  }

  Future<void> updateStation(RadioStation station) async {
    final list = _list;
    final i = list.indexWhere((s) => s.id == station.id);
    if (i < 0) return;
    list[i] = station;
    await _persist(list);
  }

  /// Reorders a section (a bucket of stations shown together, e.g. Favorites or
  /// one group) to match [idsInNewOrder]. Only the positions those stations
  /// occupy in the saved list are rearranged; every other station stays put.
  Future<void> reorderBucket(List<String> idsInNewOrder) async {
    final list = _list;
    final inBucket = idsInNewOrder.toSet();
    final byId = {for (final s in list) s.id: s};
    // The slots (indexes in the flat list) currently held by this bucket.
    final slots = <int>[];
    for (var i = 0; i < list.length; i++) {
      if (inBucket.contains(list[i].id)) slots.add(i);
    }
    // Drop the bucket's stations back into those same slots, new order.
    for (var k = 0; k < slots.length && k < idsInNewOrder.length; k++) {
      final s = byId[idsInNewOrder[k]];
      if (s != null) list[slots[k]] = s;
    }
    await _persist(list);
  }

  /// Renames a group, moving every station in [from] to [to].
  Future<void> renameGroup(String from, String to) async {
    final t = to.trim();
    if (t.isEmpty || t == from) return;
    final list = _list;
    for (var i = 0; i < list.length; i++) {
      if (list[i].group == from) list[i] = list[i].copyWith(group: t);
    }
    await _persist(list);
  }

  /// Deletes a group by moving its stations to Other (ungrouped). The stations
  /// themselves are kept — only the grouping is removed.
  Future<void> deleteGroup(String name) async {
    final list = _list;
    for (var i = 0; i < list.length; i++) {
      if (list[i].group == name) list[i] = list[i].copyWith(group: null);
    }
    await _persist(list);
  }

  Future<void> toggleFavorite(String id) async {
    final list = _list;
    final i = list.indexWhere((s) => s.id == id);
    if (i < 0) return;
    list[i] = list[i].copyWith(favorite: !list[i].favorite);
    await _persist(list);
  }

  /// Searches the radio-browser.info directory. Transient results (not saved
  /// until the user adds one). Returns [] on failure so the UI degrades quietly.
  // radio-browser is a pool of community mirrors and any single one can be down
  // or unreachable from a given network (this is why search worked on desktop
  // but not mobile). `all.api` is the DNS round-robin the project recommends;
  // the named hosts are fallbacks if that entry is having a bad day.
  static const _mirrors = [
    'https://all.api.radio-browser.info',
    'https://de1.api.radio-browser.info',
    'https://nl1.api.radio-browser.info',
    'https://at1.api.radio-browser.info',
  ];

  Future<List<RadioStation>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final dio = await secureDio(
        options: BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ));
    // radio-browser asks clients to send a descriptive User-Agent (app + version);
    // some mirrors reject bare/blank agents.
    final opts = Options(headers: {
      'User-Agent': 'Fathom/0.9.0 (+https://github.com/TraceApps/fathom)',
    });
    for (final host in _mirrors) {
      try {
        final res = await dio.get(
          '$host/json/stations/search',
          queryParameters: {
            'name': query.trim(),
            'limit': 60,
            'hidebroken': true,
            'order': 'votes',
            'reverse': true,
          },
          options: opts,
        );
        final data = res.data;
        // Only a JSON array is a real answer. Anything else (an HTML error page,
        // a redirect body, a rate-limit notice) means this mirror is misbehaving
        // — fall through to the next rather than crashing on a bad cast, which is
        // what silently emptied search on some networks.
        if (data is! List) {
          debugPrint('[radio] $host: non-list response'
              ' (${res.statusCode}, ${data.runtimeType}); trying next');
          continue;
        }
        debugPrint('[radio] $host: ${data.length} results');
        return data
            .whereType<Map>()
            .map((e) =>
                RadioStation.fromRadioBrowser(Map<String, dynamic>.from(e)))
            .where((s) => s.url.isNotEmpty && s.name.isNotEmpty)
            .toList();
      } on DioException catch (e) {
        debugPrint('[radio] $host: ${e.type} ${e.message ?? ''}; trying next');
        continue; // this mirror failed — try the next
      }
    }
    debugPrint('[radio] all mirrors failed or returned no usable data');
    return [];
  }
}

final radioControllerProvider =
    AsyncNotifierProvider<RadioController, List<RadioStation>>(
        RadioController.new);

/// True when the user has switched the internet-radio integration on. Off by
/// default: Fathom is primarily a Jellyfin client, so radio is opt-in.
final radioEnabledProvider = Provider<bool>((ref) =>
    ref.watch(preferencesProvider).asData?.value.radioEnabled ?? false);
