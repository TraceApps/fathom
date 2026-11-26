import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tv_mode.dart';
import 'providers.dart';

/// Whether the navigation rail is expanded (icons + labels) or collapsed
/// (icons only). Toggled from the rail's menu button. The user's choice is
/// remembered across screens, in/out of the player, and app restarts; only the
/// FIRST-ever launch defaults (expanded on a TV so labels read from the couch,
/// collapsed elsewhere).
class RailExtended extends Notifier<bool> {
  static const _key = 'fathom_rail_extended';

  /// Where the choice is kept, for Backup & Restore.
  static const storageKey = _key;

  @override
  bool build() {
    _load();
    return isTvDevice;
  }

  Future<void> _load() async {
    final raw = await ref.read(secureStorageProvider).read(key: _key);
    if (raw != null) state = raw == '1';
  }

  Future<void> toggle() async {
    state = !state;
    await ref
        .read(secureStorageProvider)
        .write(key: _key, value: state ? '1' : '0');
  }
}

final railExtendedProvider =
    NotifierProvider<RailExtended, bool>(RailExtended.new);

/// Whether the Libraries item in the sidebar is expanded to list the user's
/// libraries inline.
class LibrariesNavExpanded extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final librariesNavExpandedProvider =
    NotifierProvider<LibrariesNavExpanded, bool>(LibrariesNavExpanded.new);

/// Whether the Browse item in the sidebar is expanded to list Genres, Studios,
/// Artists, Playlists and Downloads inline.
class BrowseNavExpanded extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final browseNavExpandedProvider =
    NotifierProvider<BrowseNavExpanded, bool>(BrowseNavExpanded.new);
