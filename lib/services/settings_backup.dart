import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/accounts_store.dart';
import '../models/radio_station.dart';
import '../models/session.dart';
import '../state/arr_servers.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../state/radio.dart';
import '../state/session_controller.dart';
import '../state/ui_providers.dart';
import 'tv_mode.dart';
import '../state/youtube_providers.dart';

/// Cross-platform export/import of Fathom's own settings, selectable by group.
/// Secrets are NEVER exported: Jellyfin tokens and Seerr passwords live only in
/// the OS secret store, and the few credential-ish preference keys below are
/// stripped explicitly. Server addresses and the username ARE included (not
/// secrets) so a restore reconnects with just a re-entered password/API key.
///
/// Schema 2 (2026-07-30) adds a `groups` manifest and filters preferences by
/// group. Schema 1 files (whole-prefs, no groups) still import: they're treated
/// as containing every group.
const int settingsBackupSchema = 2;

/// Backup groups. [general] is the catch-all: any preference not claimed by a
/// named group lands here, so a newly added setting can never silently drop out.
const backupGroups = <String>[
  'general',
  'appearance',
  'player',
  'youtube',
  'radio',
  'servers',
];

/// Preference keys that are secret-adjacent and must never leave the device.
const secretPrefKeys = <String>{
  'mdbListApiKey',
  'seerrApiKey',
  'seerrCookie',
  'sonarrApiKey',
  'radarrApiKey',
  'lidarrApiKey',
  'prowlarrApiKey',
  'bazarrApiKey',
  'qbitPassword',
  'arrServerKeys',
  'sabApiKey',
};

/// Settings that describe this device, not the person: they stay here, and
/// one found in a backup is ignored. Force TV Mode restored on a phone would
/// turn it into a TV at the next start; a download folder from Linux means
/// nothing on Android; where the mini player sat and when updates were last
/// checked are this install's own business.
const deviceOnlyPrefKeys = <String>{
  'forceTvMode',
  'diagnosticLogging',
  'miniPlayerX',
  'miniPlayerY',
  'youtubeVideoDownloadPath',
  'youtubeAudioDownloadPath',
  'jellyfinDownloadPath',
  'updateLastCheck',
  'updateNotifiedVersion',
  'updateBannerDismissedVersion',
};

bool _travels(String key) =>
    !secretPrefKeys.contains(key) && !deviceOnlyPrefKeys.contains(key);

/// YouTube's own library on this device, kept beside the settings: the
/// channels subscribed to, their feed groups, the playlists made here and
/// the ones saved from YouTube. Each is a list of entries with an `id`.
/// Watch and search history stay on the device.
const youtubeLibraryStores = <String, String>{
  'subscriptions': 'fathom_youtube_subs',
  'feedGroups': 'fathom_youtube_feed_groups',
  'playlists': 'fathom_youtube_playlists',
  'savedPlaylists': 'fathom_youtube_saved_playlists',
};

const _appearanceKeys = <String>{
  'themeMode', 'accentColor', 'amoled', 'showGreeting',
  'homeBanner', 'showContinueWatching', 'showNextUp', 'showRecentlyAdded',
  'showMyMedia', 'showArrDownloading', 'showArrComingUp', 'showLibraryLatest',
  'showGenreRows', 'homeRowOrder',
  'navOrder', 'navHidden', 'cardRating', 'libraryViewMode', 'interfaceScale',
  'showRtCritics', 'showRtAudience', 'showImdbRating', 'showCommunityRating',
  'showLetterboxd', 'showMetacritic', 'showMetacriticUser', 'showTrakt',
  'showRogerEbert', 'showMyAnimeList',
  // How Discover is laid out, beside how Home is.
  'seerrRowOrder', 'seerrHiddenRows', 'seerrCustomSliders',
};

const _playerKeys = <String>{
  'audioLanguage', 'subtitleLanguage', 'subtitleScale', 'subtitleTextColor',
  'subtitleBackgroundOpacity', 'subtitlePosition', 'autoplayNext',
  'maxBitrateMbps', 'playbackSpeed', 'volume', 'showLyricsAutomatically',
  'lookUpMissingLyrics', 'hardwareDecoding', 'displaySync',
  'previewThumbnailsWhileSeeking', 'autoSkipIntro', 'autoSkipCredits',
  'keyBindings', 'playerFit', 'playerBarStyle', 'miniPlayerX', 'miniPlayerY',
  'miniPlayerSize', 'rememberTracks', 'trailerQuality', 'syncPlayEnabled',
  'replayGain', 'replayGainFallback', 'playerBackend', 'audioPassthrough',
  'upNextLeadSeconds', 'upNextStyle',
};

/// Which group a preference key belongs to. YouTube is prefix-matched so new
/// `youtube*` settings are grouped automatically; anything unclaimed is general.
String _prefGroup(String key) {
  if (key.startsWith('youtube')) return 'youtube';
  // The switch that shows Radio goes with the stations: restoring them alone
  // used to leave Radio hidden.
  if (key == 'radioEnabled') return 'radio';
  if (_appearanceKeys.contains(key)) return 'appearance';
  if (_playerKeys.contains(key)) return 'player';
  return 'general';
}

/// The groups that actually have data to export right now (preference groups
/// always do; radio/servers only when there's something saved).
Set<String> availableExportGroups(WidgetRef ref) {
  final groups = <String>{'appearance', 'player', 'youtube', 'general'};
  final radio = ref.read(radioControllerProvider).asData?.value ?? const [];
  if (radio.isNotEmpty) groups.add('radio');
  final accounts = ref.read(sessionControllerProvider.notifier).accounts;
  if (accounts.isNotEmpty) groups.add('servers');
  return groups;
}

/// Builds the export payload containing only the selected [groups].
Future<Map<String, dynamic>> buildSettingsExport(
    WidgetRef ref, String appVersion, Set<String> groups) async {
  // The saved settings themselves, never a blank set because they hadn't
  // been read yet.
  final prefs = await ref.read(preferencesProvider.future);
  final exportedPrefs = <String, dynamic>{};
  for (final entry in prefs.toJson().entries) {
    if (!_travels(entry.key)) continue;
    if (groups.contains(_prefGroup(entry.key))) {
      exportedPrefs[entry.key] = entry.value;
    }
  }

  final result = <String, dynamic>{
    'app': 'fathom',
    'schemaVersion': settingsBackupSchema,
    'appVersion': appVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'groups': groups.where(backupGroups.contains).toList(),
    'preferences': exportedPrefs,
  };

  if (groups.contains('appearance')) {
    // Whether the side menu is open or folded: a look of the app like any
    // other, kept outside the settings themselves.
    final rail = await ref
        .read(secureStorageProvider)
        .read(key: RailExtended.storageKey);
    if (rail != null) result['sideMenuOpen'] = rail == '1';
  }
  if (groups.contains('youtube')) {
    final storage = ref.read(secureStorageProvider);
    final library = <String, dynamic>{};
    for (final store in youtubeLibraryStores.entries) {
      final list = _entries(await storage.read(key: store.value));
      if (list.isNotEmpty) library[store.key] = list;
    }
    if (library.isNotEmpty) result['youtubeLibrary'] = library;
  }
  if (groups.contains('radio')) {
    final radio = await ref.read(radioControllerProvider.future);
    result['radio'] = radio.map((s) => s.toJson()).toList();
  }
  if (groups.contains('servers')) {
    final accounts = ref.read(sessionControllerProvider.notifier).accounts;
    result['servers'] = [
      for (final s in accounts)
        {
          'serverId': s.serverId,
          'serverName': s.serverName,
          'baseUrl': s.baseUrl,
          'internalUrl': s.internalUrl,
          'externalUrl': s.externalUrl,
          'userName': s.userName,
        },
    ];
  }
  return result;
}

/// The entries of a saved list (or of a backup's), each one a map with an
/// id; anything else in it is left out.
List<Map<String, dynamic>> _entries(Object? saved) {
  Object? list = saved;
  if (saved is String) {
    try {
      list = jsonDecode(saved);
    } catch (_) {
      return const [];
    }
  }
  if (list is! List) return const [];
  return [
    for (final e in list)
      if (e is Map && e['id'] is String && (e['id'] as String).isNotEmpty)
        Map<String, dynamic>.from(e),
  ];
}

/// [backup]'s entries added to [local]'s: one already here (by id) is kept
/// as it is, so a restore never loses or overwrites what's on the device.
@visibleForTesting
List<Map<String, dynamic>> mergedById(
  List<Map<String, dynamic>> local,
  List<Map<String, dynamic>> backup,
) {
  final have = {for (final e in local) e['id']};
  return [
    ...local,
    for (final e in backup)
      if (have.add(e['id'])) e,
  ];
}

/// The groups a backup file actually contains, for the import checklist.
Set<String> groupsInBackup(Map<String, dynamic> data) {
  final found = <String>{};
  final prefs = data['preferences'];
  if (prefs is Map) {
    for (final key in prefs.keys) {
      if (key is String && _travels(key)) found.add(_prefGroup(key));
    }
  }
  final radio = data['radio'];
  if (radio is List && radio.isNotEmpty) found.add('radio');
  final library = data['youtubeLibrary'];
  if (library is Map && library.isNotEmpty) found.add('youtube');
  if (data['sideMenuOpen'] is bool) found.add('appearance');
  final servers = data['servers'];
  if (servers is List && servers.isNotEmpty) found.add('servers');
  return found;
}

/// Validates that [data] is a Fathom backup this build can read.
bool isValidBackup(Object? data) =>
    data is Map &&
    data['app'] == 'fathom' &&
    data['schemaVersion'] is int &&
    (data['schemaVersion'] as int) <= settingsBackupSchema;

/// What an import restored, for a user-facing summary.
class ImportSummary {
  final bool preferences;
  final int radioStations;
  final List<String> servers; // "name (user)" per server
  const ImportSummary({
    required this.preferences,
    required this.radioStations,
    required this.servers,
  });
}

/// The settings after the [selectedGroups] of a backup's [backup] settings
/// are laid over [local]; null when the backup changes nothing.
///
/// Secrets never come from a backup, and the ones on this device stay only
/// with the server they were given for: a key or password kept beside an
/// address the backup changed would be sent to that address, which may be
/// another server of the user's, or someone else's (a backup passed along).
/// Those are dropped, and the connection asks for its key again.
Prefs? restoredPrefs(
  Prefs local,
  Map<String, dynamic> backup,
  Set<String> selectedGroups,
) {
  var changed = false;
  final current = local.toJson();
  for (final entry in backup.entries) {
    if (!_travels(entry.key)) continue;
    if (selectedGroups.contains(_prefGroup(entry.key))) {
      current[entry.key] = entry.value;
      changed = true;
    }
  }
  if (!changed) return null;
  // A value the backup has in a form this build can't read costs that
  // setting, not the restore.
  final (restored, _) = prefsFromSaved(current);
  // Sonarr, Radarr and Lidarr (more than one server each): keys are paired
  // with the restored servers by address.
  return _keysFollowAddresses(local, arrReconcileRestore(local, restored));
}

/// [restored] without the secrets of any connection whose address (or, for
/// qBittorrent, user) is no longer the one on this device.
Prefs _keysFollowAddresses(Prefs local, Prefs restored) {
  String at(String url) =>
      url.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();
  bool moved(String was, String now) => at(was) != at(now);
  var p = restored;
  if (moved(local.prowlarrUrl, p.prowlarrUrl)) {
    p = p.copyWith(prowlarrApiKey: '');
  }
  if (moved(local.bazarrUrl, p.bazarrUrl)) p = p.copyWith(bazarrApiKey: '');
  if (moved(local.sabUrl, p.sabUrl)) p = p.copyWith(sabApiKey: '');
  if (moved(local.qbitUrl, p.qbitUrl) ||
      local.qbitUsername.trim() != p.qbitUsername.trim()) {
    p = p.copyWith(qbitPassword: '');
  }
  if (moved(local.seerrUrl, p.seerrUrl)) {
    p = p.copyWith(seerrApiKey: '', seerrCookie: '');
  }
  return p;
}

/// One signed-in account whose home and remote addresses a backup would
/// set, for showing before anything is applied.
class ServerAddressChange {
  final String accountKey;
  final String label; // "name (user)"
  final String? internal;
  final String? external;
  const ServerAddressChange({
    required this.accountKey,
    required this.label,
    required this.internal,
    required this.external,
  });
}

String? _address(Object? v) {
  if (v is! String) return null;
  final t = v.trim().replaceAll(RegExp(r'/+$'), '');
  return t.isEmpty ? null : t;
}

/// The address changes [data] holds for [accounts].
///
/// A backup's addresses go only to the server they were saved for, known by
/// the id the server itself reports, never by its name or by an address in
/// the file: the app moves a signed-in session to whichever of these
/// addresses answers, so one taken from a file that only *names* your server
/// would hand your sign-in to wherever it points. A file from before the id
/// was saved changes no address.
List<ServerAddressChange> serverAddressChanges(
  Map<String, dynamic> data,
  List<Session> accounts,
) {
  final servers = data['servers'];
  if (servers is! List) return const [];
  final changes = <ServerAddressChange>[];
  for (final account in accounts) {
    final id = account.serverId;
    if (id == null || id.isEmpty) continue;
    for (final e in servers.whereType<Map>()) {
      if (e['serverId'] != id) continue;
      final internal = _address(e['internalUrl']);
      final external = _address(e['externalUrl']);
      if (internal == null && external == null) continue;
      if (internal == account.internalUrl && external == account.externalUrl) {
        continue;
      }
      final name = account.serverName ?? account.baseUrl;
      changes.add(
        ServerAddressChange(
          accountKey: accountKey(account),
          label: '$name (${account.userName})',
          internal: internal,
          external: external,
        ),
      );
      break;
    }
  }
  return changes;
}

/// Applies only the [selectedGroups] from [data]. Preferences MERGE over the
/// current ones (so importing just one group leaves the others untouched);
/// radio replaces the library; YouTube's library is added to; servers
/// re-apply home/remote addresses to the signed-in account they were saved
/// for. Secrets are ignored even if present.
///
/// Everything is read and checked first and written after: a bad entry is
/// left out, and never leaves a restore half done.
Future<ImportSummary> applySettingsImport(
    WidgetRef ref, Map<String, dynamic> data, Set<String> selectedGroups) async {
  // Read and check.
  Prefs? merged;
  final prefsJson = data['preferences'];
  if (prefsJson is Map) {
    final local = await ref.read(preferencesProvider.future);
    merged = restoredPrefs(
      local,
      Map<String, dynamic>.from(prefsJson),
      selectedGroups,
    );
  }

  List<RadioStation>? stations;
  if (selectedGroups.contains('radio') && data['radio'] is List) {
    stations = [];
    for (final e in (data['radio'] as List).whereType<Map>()) {
      try {
        stations.add(RadioStation.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {
        // Not a station this build can read: the rest still come back.
      }
    }
  }

  final library = <String, List<Map<String, dynamic>>>{};
  final fromFile = data['youtubeLibrary'];
  if (selectedGroups.contains('youtube') && fromFile is Map) {
    for (final name in youtubeLibraryStores.keys) {
      final list = _entries(fromFile[name]);
      if (list.isNotEmpty) library[name] = list;
    }
  }

  final session = ref.read(sessionControllerProvider.notifier);
  final addresses = selectedGroups.contains('servers')
      ? serverAddressChanges(data, session.accounts)
      : const <ServerAddressChange>[];

  // A TV keeps its side menu open, so its names can be read from the couch.
  final sideMenuOpen =
      selectedGroups.contains('appearance') && !isTvDevice
      ? data['sideMenuOpen']
      : null;

  // Write.
  if (sideMenuOpen is bool) {
    await ref
        .read(secureStorageProvider)
        .write(key: RailExtended.storageKey, value: sideMenuOpen ? '1' : '0');
    ref.invalidate(railExtendedProvider);
  }
  if (merged != null) {
    final restored = merged;
    await ref.read(preferencesProvider.notifier).edit((_) => restored);
  }
  if (stations != null) {
    await ref.read(radioControllerProvider.notifier).importAll(stations);
  }
  if (library.isNotEmpty) {
    final storage = ref.read(secureStorageProvider);
    for (final entry in library.entries) {
      final key = youtubeLibraryStores[entry.key]!;
      final local = _entries(await storage.read(key: key));
      await storage.write(
        key: key,
        value: jsonEncode(mergedById(local, entry.value)),
      );
    }
    ref.invalidate(youtubeSubscriptionsProvider);
    ref.invalidate(youtubeFeedGroupsProvider);
    ref.invalidate(youtubeLocalPlaylistsProvider);
    ref.invalidate(youtubeSavedPlaylistsProvider);
  }
  for (final change in addresses) {
    await session.setAddressesFor(
      change.accountKey,
      internal: change.internal,
      external: change.external,
    );
  }

  return ImportSummary(
    preferences: merged != null,
    radioStations: stations?.length ?? 0,
    servers: [for (final c in addresses) c.label],
  );
}
