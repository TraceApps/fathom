import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/radio_station.dart';
import '../state/preferences.dart';
import '../state/radio.dart';
import '../state/session_controller.dart';

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
};

const _appearanceKeys = <String>{
  'themeMode', 'accentColor', 'amoled', 'showGreeting',
  'homeBanner', 'showContinueWatching', 'showNextUp', 'showRecentlyAdded',
  'showMyMedia', 'showLibraryLatest', 'showGenreRows', 'homeRowOrder',
  'navOrder', 'navHidden', 'cardRating', 'libraryViewMode', 'interfaceScale',
  'showRtCritics', 'showRtAudience', 'showImdbRating', 'showCommunityRating',
  'showLetterboxd', 'showMetacritic', 'showMetacriticUser', 'showTrakt',
  'showRogerEbert', 'showMyAnimeList',
};

const _playerKeys = <String>{
  'audioLanguage', 'subtitleLanguage', 'subtitleScale', 'subtitleTextColor',
  'subtitleBackgroundOpacity', 'subtitlePosition', 'autoplayNext',
  'maxBitrateMbps', 'playbackSpeed', 'volume', 'showLyricsAutomatically',
  'lookUpMissingLyrics', 'hardwareDecoding', 'displaySync',
  'previewThumbnailsWhileSeeking', 'autoSkipIntro', 'autoSkipCredits',
  'keyBindings', 'playerFit', 'playerBarStyle', 'miniPlayerX', 'miniPlayerY',
  'miniPlayerSize', 'rememberTracks', 'trailerQuality', 'syncPlayEnabled',
  'movieWheelEnabled',
};

/// Which group a preference key belongs to. YouTube is prefix-matched so new
/// `youtube*` settings are grouped automatically; anything unclaimed is general.
String _prefGroup(String key) {
  if (key.startsWith('youtube')) return 'youtube';
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
Map<String, dynamic> buildSettingsExport(
    WidgetRef ref, String appVersion, Set<String> groups) {
  final prefsJson =
      (ref.read(preferencesProvider).asData?.value ?? const Prefs()).toJson();
  final exportedPrefs = <String, dynamic>{};
  for (final entry in prefsJson.entries) {
    if (secretPrefKeys.contains(entry.key)) continue;
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

  if (groups.contains('radio')) {
    final radio = ref.read(radioControllerProvider).asData?.value ?? const [];
    result['radio'] = radio.map((s) => s.toJson()).toList();
  }
  if (groups.contains('servers')) {
    final accounts = ref.read(sessionControllerProvider.notifier).accounts;
    result['servers'] = [
      for (final s in accounts)
        {
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

/// The groups a backup file actually contains, for the import checklist.
Set<String> groupsInBackup(Map<String, dynamic> data) {
  final found = <String>{};
  final prefs = data['preferences'];
  if (prefs is Map) {
    for (final key in prefs.keys) {
      if (key is String && !secretPrefKeys.contains(key)) {
        found.add(_prefGroup(key));
      }
    }
  }
  final radio = data['radio'];
  if (radio is List && radio.isNotEmpty) found.add('radio');
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

/// Applies only the [selectedGroups] from [data]. Preferences MERGE over the
/// current ones (so importing just one group leaves the others untouched);
/// radio replaces the library; servers re-apply home/remote addresses to a
/// matching signed-in account. Secrets are ignored even if present.
Future<ImportSummary> applySettingsImport(
    WidgetRef ref, Map<String, dynamic> data, Set<String> selectedGroups) async {
  var prefsChanged = false;
  final prefsJson = data['preferences'];
  if (prefsJson is Map) {
    final current =
        (ref.read(preferencesProvider).asData?.value ?? const Prefs()).toJson();
    for (final entry in Map<String, dynamic>.from(prefsJson).entries) {
      if (secretPrefKeys.contains(entry.key)) continue;
      if (selectedGroups.contains(_prefGroup(entry.key))) {
        current[entry.key] = entry.value;
        prefsChanged = true;
      }
    }
    if (prefsChanged) {
      final merged = Prefs.fromJson(current);
      await ref.read(preferencesProvider.notifier).edit((_) => merged);
    }
  }

  var radioCount = 0;
  if (selectedGroups.contains('radio') && data['radio'] is List) {
    final stations = (data['radio'] as List)
        .whereType<Map>()
        .map((e) => RadioStation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    await ref.read(radioControllerProvider.notifier).importAll(stations);
    radioCount = stations.length;
  }

  final servers = <String>[];
  if (selectedGroups.contains('servers') && data['servers'] is List) {
    final active = ref.read(sessionControllerProvider).asData?.value;
    for (final e in (data['servers'] as List).whereType<Map>()) {
      final m = Map<String, dynamic>.from(e);
      final name = (m['serverName'] as String?)?.trim();
      final base = (m['baseUrl'] as String?) ?? '';
      final user = (m['userName'] as String?) ?? '';
      servers.add('${name != null && name.isNotEmpty ? name : base}'
          '${user.isNotEmpty ? ' ($user)' : ''}');
      final matches = active != null &&
          (active.baseUrl == base ||
              (name != null && active.serverName == name));
      if (matches && (m['internalUrl'] != null || m['externalUrl'] != null)) {
        await ref.read(sessionControllerProvider.notifier).setServerAddresses(
              internal: m['internalUrl'] as String?,
              external: m['externalUrl'] as String?,
            );
      }
    }
  }

  return ImportSummary(
    preferences: prefsChanged,
    radioStations: radioCount,
    servers: servers,
  );
}
