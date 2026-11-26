import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/status_colors.dart';
import '../api/error_text.dart';
import '../api/arr_client.dart';
import '../api/bazarr_client.dart';
import '../api/download_clients.dart';
import '../api/mdblist_client.dart';
import '../api/seerr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../models/download_client.dart';
import '../services/tv_mode.dart';
import '../state/arr_providers.dart';
import '../state/arr_servers.dart';
import '../state/download_providers.dart';
import '../state/preferences.dart';
import '../theme/app_theme.dart';
import 'arr_add_screen.dart';
import 'seerr_settings_screen.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_servers_ui.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_keyboard.dart';

// Connections: what's connected, each with how it's doing, and Add
// Connection for the rest. Seerr, the Manage apps, the download clients and
// MDBList are all here. A connection opens on a page of its own (beside
// the list in a wide window), with its address, its sign-in, and what else
// belongs to it. A second server of an app (a 4K Radarr) is a row of its
// own.

/// Everything Fathom can connect to here.
enum ConnApp {
  seerr,
  sonarr,
  radarr,
  lidarr,
  prowlarr,
  bazarr,
  qbittorrent,
  sabnzbd,
  mdblist;

  String get appName => switch (this) {
    seerr => 'Seerr',
    mdblist => MdbListClient.appName,
    sonarr => ArrKind.sonarr.appName,
    radarr => ArrKind.radarr.appName,
    lidarr => ArrKind.lidarr.appName,
    prowlarr => ProwlarrClient.appName,
    bazarr => BazarrClient.appName,
    qbittorrent => DownloadClientKind.qbittorrent.appName,
    sabnzbd => DownloadClientKind.sabnzbd.appName,
  };

  /// The library app, for the ones that can have more than one server.
  ArrKind? get kind => switch (this) {
    sonarr => ArrKind.sonarr,
    radarr => ArrKind.radarr,
    lidarr => ArrKind.lidarr,
    _ => null,
  };

  bool get isDownloadClient => this == qbittorrent || this == sabnzbd;

  /// Where it stands in the list and in Add Connection.
  ConnGroup get group => switch (this) {
    seerr => ConnGroup.requests,
    qbittorrent || sabnzbd => ConnGroup.clients,
    mdblist => ConnGroup.ratings,
    _ => ConnGroup.apps,
  };

  /// MDBList is a web service: a key, and no address of the user's own.
  bool get hasAddress => this != mdblist;

  IconData get icon => switch (this) {
    seerr => Icons.travel_explore_rounded,
    mdblist => Icons.star_rounded,
    sonarr => Icons.live_tv_rounded,
    radarr => Icons.movie_rounded,
    lidarr => Icons.library_music_rounded,
    prowlarr => Icons.manage_search_rounded,
    bazarr => Icons.subtitles_rounded,
    qbittorrent => Icons.hub_rounded,
    sabnzbd => Icons.dns_rounded,
  };

  /// The port it answers on out of the box (as the address hints show).
  int get port => switch (this) {
    seerr => 5055,
    mdblist => 443,
    sonarr => 8989,
    radarr => 7878,
    lidarr => 8686,
    prowlarr => 9696,
    bazarr => 6767,
    qbittorrent => 8080,
    sabnzbd => 8085,
  };

  String forWhat(AppLocalizations l) => switch (this) {
    seerr => l.connForRequests,
    mdblist => l.connForRatings,
    sonarr => l.arrForShows,
    radarr => l.arrForMovies,
    lidarr => l.arrForMusic,
    prowlarr => l.arrForIndexers,
    bazarr => l.arrForSubtitles,
    qbittorrent => l.dlForTorrents,
    sabnzbd => l.dlForUsenet,
  };

  static ConnApp of(ArrKind k) => switch (k) {
    ArrKind.sonarr => sonarr,
    ArrKind.radarr => radarr,
    ArrKind.lidarr => lidarr,
  };
}

enum ConnGroup {
  requests,
  apps,
  clients,
  ratings;

  String title(AppLocalizations l) => switch (this) {
    requests => l.connGroupRequests,
    apps => l.arrConnApps,
    clients => l.dlSettingsHeading,
    ratings => l.connGroupRatings,
  };
}

/// In a Seerr connection's [Conn.user]: signed in with an account, so
/// [Conn.secret] is that session and not an API key.
const seerrSession = 'session';

/// One saved connection.
class Conn {
  final ConnApp app;

  /// The server, for an app that can have more than one; null otherwise.
  final String? serverId;

  /// What the user called the server ("4K"); empty for none.
  final String name;
  final String url;

  /// qBittorrent's username; [seerrSession] for a Seerr account sign-in;
  /// empty for the others.
  final String user;

  /// The API key, or qBittorrent's password.
  final String secret;

  /// The server of its app in use (always, for the apps with one).
  final bool active;

  /// How many servers its app has.
  final int servers;

  const Conn({
    required this.app,
    this.serverId,
    this.name = '',
    required this.url,
    this.user = '',
    required this.secret,
    this.active = true,
    this.servers = 1,
  });

  /// Has what it needs to try: a server brought back by a backup has no key
  /// yet (qBittorrent can go without a password, but not with only a
  /// username).
  bool get ready => app == ConnApp.qbittorrent
      ? user.isEmpty || secret.isNotEmpty
      : secret.isNotEmpty;

  /// What its row and page are called: the app, with the server's name once
  /// there's more than one or it was given one.
  String title(AppLocalizations l) => app.kind != null &&
          (servers > 1 || name.trim().isNotEmpty)
      ? '${app.appName}: ${name.trim().isEmpty ? l.arrServerMain : name.trim()}'
      : app.appName;

  /// What to check, for [connCheckProvider].
  ConnCheck get check =>
      (app: app, url: url, user: user, secret: secret, active: active);
}

/// Every saved connection, the library apps' servers each on their own.
List<Conn> connectionsOf(Prefs p) => [
  if (p.seerrUrl.isNotEmpty)
    p.seerrAuthMode == 'cookie'
        ? Conn(
            app: ConnApp.seerr,
            url: p.seerrUrl,
            user: seerrSession,
            secret: p.seerrCookie,
          )
        : Conn(app: ConnApp.seerr, url: p.seerrUrl, secret: p.seerrApiKey),
  for (final k in ArrKind.values)
    for (final s in arrServersByName(arrServersOf(p, k)))
      Conn(
        app: ConnApp.of(k),
        serverId: s.id,
        name: s.name,
        url: s.url,
        secret: s.apiKey,
        active: s.active,
        servers: arrServersOf(p, k).length,
      ),
  if (p.prowlarrUrl.isNotEmpty)
    Conn(app: ConnApp.prowlarr, url: p.prowlarrUrl, secret: p.prowlarrApiKey),
  if (p.bazarrUrl.isNotEmpty)
    Conn(app: ConnApp.bazarr, url: p.bazarrUrl, secret: p.bazarrApiKey),
  if (p.qbitUrl.isNotEmpty)
    Conn(
      app: ConnApp.qbittorrent,
      url: p.qbitUrl,
      user: p.qbitUsername,
      secret: p.qbitPassword,
    ),
  if (p.sabUrl.isNotEmpty)
    Conn(app: ConnApp.sabnzbd, url: p.sabUrl, secret: p.sabApiKey),
  if (p.mdbListApiKey.isNotEmpty)
    Conn(app: ConnApp.mdblist, url: '', secret: p.mdbListApiKey),
];

/// The saved connection [app] / [serverId] names, if it's still there.
Conn? findConn(Prefs p, ConnApp app, String? serverId) => connectionsOf(p)
    .where((c) => c.app == app && (app.kind == null || c.serverId == serverId))
    .firstOrNull;

/// How many connections there are, for Settings.
final connCountProvider = Provider<int>((ref) {
  final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
  return connectionsOf(p).length;
});

typedef ConnCheck = ({
  ConnApp app,
  String url,
  String user,
  String secret,
  bool active,
});

/// Asks [app] at an address what version it is (nothing, for MDBList, which
/// has none to tell); throws when it isn't that app or won't take the key.
Future<String> testConnection(
  ConnApp app,
  String url,
  String user,
  String secret,
) => switch (app) {
  ConnApp.sonarr || ConnApp.radarr || ConnApp.lidarr => arrCheckServer(
    app.kind!,
    url,
    secret,
  ),
  ConnApp.prowlarr => ProwlarrClient(url, secret).status().then((s) => s.version),
  ConnApp.bazarr => BazarrClient(url, secret).version(),
  ConnApp.qbittorrent => QbitClient(url, user, secret).version(),
  ConnApp.sabnzbd => SabClient(url, secret).version(),
  ConnApp.seerr => user == seerrSession
      ? SeerrClient(url, '', cookie: secret).version()
      : SeerrClient(url, secret).version(),
  ConnApp.mdblist => MdbListClient(secret).check().then((_) => ''),
};

typedef ConnTester =
    Future<String> Function(ConnApp app, String url, String user, String secret);

/// How a connection is tried: [testConnection], or a stand-in in tests.
final connTesterProvider = Provider<ConnTester>((_) => testConnection);

/// A saved connection's version, asked when its row or page shows.
final connCheckProvider = FutureProvider.autoDispose.family<String, ConnCheck>((
  ref,
  c,
) {
  // qBittorrent through the app's own client: one it has refused isn't
  // sent to sign in again (repeated failures get a device banned).
  if (c.app == ConnApp.qbittorrent) {
    final q = ref.read(qbitClientProvider);
    if (q != null && q.baseUrl == c.url) return q.version();
  }
  return ref.read(connTesterProvider)(c.app, c.url, c.user, c.secret);
  // Asked once: a retry would be another sign-in qBittorrent may count
  // against the device. Opening the page again asks again.
}, retry: (_, _) => null);

/// What a connection shows for how it's doing: a word and its color.
enum ConnState { connected, checking, failed, needsKey }

ConnState connStateOf(Conn c, AsyncValue<String>? check) {
  if (!c.ready) return ConnState.needsKey;
  if (check == null || check.isLoading && !check.hasValue) {
    return ConnState.checking;
  }
  return check.hasValue && !check.hasError ? ConnState.connected : ConnState.failed;
}

const _green = Color(0xFF22C55E);

class ConnStateChip extends StatelessWidget {
  final ConnState state;
  const ConnStateChip(this.state, {super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (state) {
      ConnState.connected => (l.arrStatusConnected, _green),
      ConnState.checking => (l.arrStatusChecking, scheme.onSurfaceVariant),
      ConnState.failed => (l.arrStatusFailed, scheme.error),
      ConnState.needsKey => (l.arrStatusNeedsKey, const Color(0xFFF59E0B)),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          switch (state) {
            ConnState.connected => Icons.check_circle_rounded,
            ConnState.checking => Icons.more_horiz_rounded,
            ConnState.failed => Icons.error_rounded,
            ConnState.needsKey => Icons.key_off_rounded,
          },
          size: 16,
          color: statusInk(context, color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: statusInk(context, color),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Why a Save & Test failed, above the buttons.
class ConnFailedBox extends StatelessWidget {
  final String error;
  const ConnFailedBox(this.error, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).arrTestFailed(error),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks before a connection is removed; true to go ahead.
Future<bool> confirmDisconnect(BuildContext context, String title) async {
  final l = AppLocalizations.of(context);
  final yes = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(l.arrDisconnectTitle(title)),
      content: Text(l.arrDisconnectBody),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(d, false),
          child: Text(MaterialLocalizations.of(d).cancelButtonLabel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: () => Navigator.pop(d, true),
          child: Text(l.arrDisconnect),
        ),
      ],
    ),
  );
  return yes == true;
}

/// One connection's page on its own, for a link from elsewhere in Settings
/// (Ratings to MDBList).
class ConnectionScreen extends ConsumerWidget {
  final ConnApp app;
  const ConnectionScreen(this.app, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Once the settings are read: before that, a saved one looks new.
    final p = ref.watch(preferencesProvider).asData?.value;
    if (p == null) return const Scaffold(body: Center(child: AppSpinner()));
    return _ConnectionPage(
      app: app,
      serverId: null,
      isNew: findConn(p, app, null) == null,
      onClose: (page) => Navigator.of(page).maybePop(),
    );
  }
}

/// A connection, as the list and the pane name it.
typedef _Open = ({ConnApp app, String? serverId, bool isNew});

class ArrSettingsScreen extends ConsumerStatefulWidget {
  const ArrSettingsScreen({super.key});

  @override
  ConsumerState<ArrSettingsScreen> createState() => _ArrSettingsScreenState();
}

class _ArrSettingsScreenState extends ConsumerState<ArrSettingsScreen> {
  /// What the pane beside the list shows, in a wide window.
  _Open? _open;

  /// A new one for each pick, so the pane starts over for it.
  int _pick = 0;

  /// Whether the window has room for the pane: a TV keeps to pages, where
  /// the remote's focus can't get lost between two.
  static bool _wide(BoxConstraints box) => !isTvDevice && box.maxWidth >= 900;

  void _show(BuildContext context, bool wide, _Open o) {
    if (wide) {
      setState(() {
        _open = o;
        _pick++;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => o.app == ConnApp.seerr
            ? SeerrSettingsScreen(
                onClose: (page) => Navigator.of(page).maybePop(),
              )
            : _ConnectionPage(
                app: o.app,
                serverId: o.serverId,
                isNew: o.isNew,
                onClose: (page) => Navigator.of(page).maybePop(),
              ),
      ),
    );
  }

  Future<void> _add(BuildContext context, bool wide) async {
    final p = ref.read(preferencesProvider).asData?.value ?? const Prefs();
    final app = await showDialog<ConnApp>(
      context: context,
      builder: (_) => _AddDialog(saved: connectionsOf(p)),
    );
    if (app == null || !context.mounted) return;
    // An app with room for one: the one there is.
    final there = app.kind == null ? findConn(p, app, null) : null;
    _show(
      context,
      wide,
      (app: app, serverId: there?.serverId, isNew: there == null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsArr)),
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = _wide(box);
          final list = _List(
            selected: wide ? _open : null,
            onOpen: (o) => _show(context, wide, o),
            onAdd: () => _add(context, wide),
          );
          if (!wide) return list;
          final open = _open;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: (box.maxWidth * 0.42).clamp(340, 460), child: list),
              const VerticalDivider(width: 1),
              Expanded(
                child: open == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            l.arrPickConnection,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      )
                    : open.app == ConnApp.seerr
                    ? SeerrSettingsScreen(
                        key: ValueKey(_pick),
                        embedded: true,
                        onSaved: () => setState(
                          () => _open = (
                            app: ConnApp.seerr,
                            serverId: null,
                            isNew: false,
                          ),
                        ),
                        onClose: (_) => setState(() => _open = null),
                      )
                    : _ConnectionPage(
                        key: ValueKey(_pick),
                        app: open.app,
                        serverId: open.serverId,
                        isNew: open.isNew,
                        embedded: true,
                        onSaved: (o) => setState(() => _open = o),
                        onClose: (_) => setState(() => _open = null),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The connections, by kind, with Add Connection under them.
class _List extends ConsumerWidget {
  final _Open? selected;
  final ValueChanged<_Open> onOpen;
  final VoidCallback onAdd;
  const _List({
    required this.selected,
    required this.onOpen,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final all = connectionsOf(p);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    Widget group(List<Conn> conns) => Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, c) in conns.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            _Row(
              key: ValueKey('${c.app.name}/${c.serverId}'),
              conn: c,
              selected:
                  selected != null &&
                  !selected!.isNew &&
                  selected!.app == c.app &&
                  selected!.serverId == c.serverId,
              onTap: () =>
                  onOpen((app: c.app, serverId: c.serverId, isNew: false)),
            ),
          ],
        ],
      ),
    );
    // On TV, back from a page that changed the list (one added, one gone),
    // the remote lands on what now stands nearest instead of on nothing.
    return TvFocusKeeper(
      child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (all.isEmpty) ...[
          Text(l.arrSettingsIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
        ],
        for (final g in ConnGroup.values)
          if (all.any((c) => c.app.group == g)) ...[
            heading(g.title(l)),
            KeyedSubtree(
              key: ValueKey(g.name),
              child: group([for (final c in all) if (c.app.group == g) c]),
            ),
            const SizedBox(height: 20),
          ],
        // Keyed, as are the groups: the intro above comes and goes, and an
        // element that moves keeps its focus only by its key.
        Align(
          key: const ValueKey('add'),
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            autofocus: all.isEmpty,
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: Text(l.arrAddConnection),
          ),
        ),
        if (all.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            l.arrKeysStayHere,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  final Conn conn;
  final bool selected;
  final VoidCallback onTap;
  const _Row({
    super.key,
    required this.conn,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final check = conn.ready ? ref.watch(connCheckProvider(conn.check)) : null;
    final state = connStateOf(conn, check);
    final version = state == ConnState.connected && (check?.value ?? '') != ''
        ? _shortVersion(check?.value)
        : null;
    // On TV the row's own focus tint is too faint across a room.
    return TvFocusRing(
      child: ListTile(
      selected: selected,
      onTap: onTap,
      leading: Icon(conn.app.icon, color: theme.colorScheme.primary),
      title: Row(
        children: [
          Flexible(
            child: Text(conn.title(l), overflow: TextOverflow.ellipsis),
          ),
          if (conn.servers > 1 && conn.active) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l.arrServerInUse,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        [
          conn.app.hasAddress ? _shortUrl(conn.url) : _mdblistSite,
          ?version,
        ].join(' · '),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ConnStateChip(state),
      ),
    );
  }
}

/// Where MDBList is, shown where the others show their address.
const _mdblistSite = 'mdblist.com';

/// A version as far as people tell them apart: 5.28.0, not 5.28.0.10274.
String? _shortVersion(String? v) =>
    v?.split('.').take(3).join('.');

/// An address without what every one of them has.
String _shortUrl(String url) =>
    url.replaceFirst(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/+$'), '');

/// Add Connection: every app, what it's for, and whether it's there.
class _AddDialog extends StatelessWidget {
  final List<Conn> saved;
  const _AddDialog({required this.saved});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget option(ConnApp app) {
      final there = saved.any((c) => c.app == app);
      return TvFocusRing(
        child: ListTile(
        // On TV the list opens with the remote on its first app; left to
        // itself, nothing is under the remote until Down is pressed.
        autofocus: isTvDevice && app == ConnApp.values.first,
        leading: Icon(app.icon, color: theme.colorScheme.primary),
        title: Text(app.appName),
        subtitle: Text(
          !there
              ? app.forWhat(l)
              : app.kind != null
              ? l.arrServersHint
              : l.arrStatusConnected,
        ),
        trailing: there && app.kind == null
            ? const Icon(Icons.check_rounded, color: _green)
            : null,
        onTap: () => Navigator.pop(context, app),
        ),
      );
    }

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return AlertDialog(
      title: Text(l.arrAddConnection),
      contentPadding: const EdgeInsets.only(top: 8, bottom: 8),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final g in ConnGroup.values) ...[
                heading(g.title(l)),
                for (final a in ConnApp.values)
                  if (a.group == g) option(a),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
      ],
    );
  }
}

/// A new connection's address, from the ones there are: the same computer,
/// at the app's usual port. Only from an address that is a computer and a
/// port; behind a reverse proxy ("/sonarr") the next app's place can't be
/// guessed.
String suggestAddress(List<Conn> saved, ConnApp app) {
  final taken = {for (final c in saved) _shortUrl(c.url).toLowerCase()};
  for (final c in saved) {
    final u = Uri.tryParse(c.url);
    if (u == null || !u.hasPort || u.host.isEmpty) continue;
    if (u.path.isNotEmpty && u.path != '/') continue;
    final guess = '${u.scheme}://${u.host}:${app.port}';
    if (taken.contains(_shortUrl(guess).toLowerCase())) continue;
    return guess;
  }
  return '';
}

/// A connection's own page: its address and sign-in, Save & Test, and what
/// belongs to it (Defaults for New Titles, Use This One, Disconnect). For a
/// new one, it becomes that connection once saved.
class _ConnectionPage extends ConsumerStatefulWidget {
  final ConnApp app;
  final String? serverId;
  final bool isNew;

  /// Beside the list, rather than a page of its own.
  final bool embedded;

  /// A new one was saved, as this.
  final ValueChanged<_Open>? onSaved;

  /// Done with it: disconnected.
  final void Function(BuildContext page) onClose;

  const _ConnectionPage({
    super.key,
    required this.app,
    required this.serverId,
    required this.isNew,
    this.embedded = false,
    this.onSaved,
    required this.onClose,
  });

  @override
  ConsumerState<_ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends ConsumerState<_ConnectionPage> {
  late final _name = TextEditingController();
  late final _url = TextEditingController();
  late final _user = TextEditingController();
  late final _secret = TextEditingController();
  late String? _serverId = widget.serverId;
  late bool _isNew = widget.isNew;
  bool _busy = false;

  /// Why the last Save & Test failed; nothing was saved.
  String? _failed;

  ConnApp get _app => widget.app;
  bool get _qbit => _app == ConnApp.qbittorrent;

  /// Beside the list, the page's own focus: a new connection's first
  /// empty field takes the cursor, not Add Connection, where focus goes back
  /// when its list closes.
  late final _scope = FocusScopeNode(debugLabel: 'connection page');

  @override
  void initState() {
    super.initState();
    if (widget.embedded && _isNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scope.requestFocus();
      });
    }
    final p = ref.read(preferencesProvider).asData?.value ?? const Prefs();
    final c = _isNew ? null : findConn(p, _app, _serverId);
    if (c != null) {
      _name.text = c.name;
      _url.text = c.url;
      _user.text = c.user;
      _secret.text = c.secret;
    } else {
      _url.text = suggestAddress(connectionsOf(p), _app);
    }
  }

  @override
  void dispose() {
    _scope.dispose();
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _secret.dispose();
    super.dispose();
  }

  Prefs _withSingle(Prefs p, String url, String user, String secret) =>
      switch (_app) {
        ConnApp.prowlarr => p.copyWith(
          prowlarrUrl: url,
          prowlarrApiKey: secret,
        ),
        ConnApp.bazarr => p.copyWith(bazarrUrl: url, bazarrApiKey: secret),
        ConnApp.qbittorrent => p.copyWith(
          qbitUrl: url,
          qbitUsername: user,
          qbitPassword: secret,
        ),
        ConnApp.sabnzbd => p.copyWith(sabUrl: url, sabApiKey: secret),
        ConnApp.mdblist => p.copyWith(mdbListApiKey: secret),
        _ => p,
      };

  Future<void> _save({bool anyway = false}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final kind = _app.kind;
    final name = _name.text.trim();
    final raw = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    final user = _user.text.trim();
    // A password is kept as typed: spaces can be part of it.
    final secret = _qbit ? _secret.text : _secret.text.trim();
    final lastFailure = _failed;
    if ((_app.hasAddress && raw.isEmpty) || (!_qbit && secret.isEmpty)) {
      showSnack(
        context,
        !_app.hasAddress
            ? l.connEnterKey
            : _qbit
            ? l.dlEnterAddress
            : _app == ConnApp.sabnzbd
            ? l.dlEnterSabBoth
            : l.arrEnterBoth,
      );
      return;
    }
    // A bare host:port is the usual thing to type; the apps speak plain
    // HTTP on a home network unless set up otherwise.
    final url = raw.isEmpty || raw.contains('://') ? raw : 'http://$raw';
    _url.text = url;
    if (kind != null) {
      final others = ref
          .read(arrServersProvider(kind))
          .where((s) => _isNew || s.id != _serverId);
      // Each by a name of its own, or two read "Main" in Switch Server.
      final label = (name.isEmpty ? l.arrServerMain : name).toLowerCase();
      if (others.any((o) => arrServerName(l, o).toLowerCase() == label)) {
        showSnack(context, l.arrServerNameTaken, kind: SnackKind.error);
        return;
      }
      final same = others.where((o) => o.url == url).firstOrNull;
      if (same != null) {
        showSnack(
          context,
          l.arrUrlTaken(arrServerName(l, same)),
          kind: SnackKind.error,
        );
        return;
      }
    }
    setState(() {
      _busy = true;
      _failed = null;
    });
    // Everything from here on is kept before the wait: the page may be
    // left (another connection picked, Back) while the app answers, and
    // what was asked is still saved.
    final tester = ref.read(connTesterProvider);
    final notifier = ref.read(preferencesProvider.notifier);
    final app = _app;
    final isNew = _isNew;
    final serverId = _serverId;
    String? version;
    if (!anyway) {
      try {
        version = await tester(app, url, user, secret);
      } catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _failed = errorText(e);
          });
        } else {
          // Left before the answer: nothing saved, and said so.
          showSnackOn(
            messenger,
            '${app.appName}: ${l.arrTestFailed(errorText(e))}',
            kind: SnackKind.error,
          );
        }
        return;
      }
    }
    Prefs? after;
    await notifier.edit((p) {
      final next = kind == null
          ? _withSingle(p, url, user, secret)
          : isNew
          ? arrAddServer(p, kind, name: name, url: url, apiKey: secret)
          : arrEditServer(
              p,
              kind,
              serverId!,
              name: name,
              url: url,
              apiKey: secret,
            );
      return after = next;
    });
    final newId = isNew && kind != null && after != null
        ? arrServersOf(after!, kind).where((s) => s.url == url).firstOrNull?.id
        : serverId;
    if (mounted) {
      setState(() {
        _busy = false;
        _isNew = false;
        _serverId = newId;
      });
      widget.onSaved?.call((app: app, serverId: newId, isNew: false));
    }
    showSnackOn(
      messenger,
      version != null
          ? l.arrConnectedTo(app.appName, version).trim()
          : l.arrSavedTestFailed(lastFailure ?? l.arrStatusFailed),
      kind: version != null ? SnackKind.success : SnackKind.info,
    );
  }

  Future<void> _disconnect(Conn c) async {
    final l = AppLocalizations.of(context);
    final title = c.title(l);
    final yes = await confirmDisconnect(context, title);
    if (!yes || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final kind = _app.kind;
    // The server in use: another saved server of the app takes its place.
    await ref
        .read(preferencesProvider.notifier)
        .edit(
          (p) => kind == null
              ? _withSingle(p, '', '', '')
              : c.active
              ? arrDisconnectActive(p, kind)
              : arrRemoveServer(p, c.serverId!),
        );
    showSnackOn(messenger, l.arrDisconnected(title));
    if (mounted) widget.onClose(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final kind = _app.kind;
    final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final c = _isNew ? null : findConn(p, _app, _serverId);
    final check = c != null && c.ready
        ? ref.watch(connCheckProvider(c.check))
        : null;
    final state = c == null ? null : connStateOf(c, check);
    final server = kind == null || c == null
        ? null
        : arrServersOf(p, kind).where((s) => s.id == c.serverId).firstOrNull;
    final title = c?.title(l) ?? _app.appName;
    final hint = 'http://192.168.1.10:${_app.port}';
    final body = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Icon(_app.icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.embedded)
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    state == ConnState.connected && (check?.value ?? '') != ''
                        ? '${_app.appName} ${check!.value!}'
                        : _app.forWhat(l),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (state != null) ConnStateChip(state),
          ],
        ),
        if (state == ConnState.failed && check?.error != null) ...[
          const SizedBox(height: 12),
          Text(
            '${check!.error}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (_app.hasAddress) ...[
          TvTextField(
            controller: _url,
            keyboardType: TextInputType.url,
            label: l.arrServerAddress,
            hint: hint,
            icon: Icons.link_rounded,
            autofocus: _isNew && _url.text.isEmpty,
          ),
          const SizedBox(height: 14),
        ],
        if (_qbit) ...[
          TvTextField(
            controller: _user,
            label: l.dlUsername,
            icon: Icons.person_rounded,
            autofillHints: const [AutofillHints.username],
          ),
          const SizedBox(height: 14),
        ],
        TvTextField(
          controller: _secret,
          obscure: true,
          label: _qbit ? l.dlPassword : l.arrApiKey,
          helperText: switch (_app) {
            ConnApp.qbittorrent => l.dlQbitHelp,
            ConnApp.sabnzbd => l.dlSabKeyHelp,
            ConnApp.mdblist => l.connMdblistKeyHelp,
            _ => l.arrApiKeyHelp(_app.appName),
          },
          icon: _qbit ? Icons.password_rounded : Icons.key_rounded,
          autofocus: _isNew && (_url.text.isNotEmpty || !_app.hasAddress),
          onSubmitted: (_) => _busy ? null : _save(),
        ),
        // What tells this server from the app's others (4K): last, as
        // there's usually only the one.
        if (kind != null) ...[
          const SizedBox(height: 14),
          TvTextField(
            controller: _name,
            label: l.arrServerName,
            hint: l.arrServerNameHint,
            icon: Icons.label_rounded,
          ),
        ],
        if (_failed != null) ...[
          const SizedBox(height: 16),
          ConnFailedBox(_failed!),
        ],
        const SizedBox(height: 18),
        // Busy, the buttons ignore presses rather than switch off: a button
        // that switches off drops the TV remote's focus on another field. And
        // keyed, as the error above them comes and goes: a button that moves
        // without its key is a new one, and the focus goes with the old.
        FilledButton(
          key: const ValueKey('save'),
          onPressed: _busy ? () {} : _save,
          child: _busy ? AppSpinner.inline() : Text(l.arrSaveTest),
        ),
        if (_failed != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('anyway'),
            onPressed: _busy ? () {} : () => _save(anyway: true),
            child: Text(l.arrSaveAnyway),
          ),
        ],
        if (c != null) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          if (server != null && !server.active && server.ready)
            TvFocusRing(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: Text(l.arrServerUse),
                onTap: () => arrUseServer(context, ref, server),
              ),
            ),
          // Defaults for New Titles: the server in use's, once it answers.
          if (kind != null &&
              server != null &&
              server.active &&
              state == ConnState.connected)
            TvFocusRing(child: _DefaultsTile(kind: kind)),
          TvFocusRing(
            child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.link_off_rounded,
              color: theme.colorScheme.error,
            ),
            title: Text(
              l.arrDisconnect,
              style: TextStyle(color: theme.colorScheme.error),
            ),
            enabled: !_busy,
            onTap: () => _disconnect(c),
            ),
          ),
        ],
      ],
    );
    // Fields and buttons at a width that reads as a form, however wide the
    // window or pane.
    final page = TvFocusKeeper(
      child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: body,
      ),
      ),
    );
    if (widget.embedded) return FocusScope(node: _scope, child: page);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: page,
    );
  }
}

/// "Defaults for New Titles": what Add starts with, and a summary of it.
class _DefaultsTile extends ConsumerWidget {
  final ArrKind kind;
  const _DefaultsTile({required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final saved = ref.watch(
      preferencesProvider.select(
        (p) => arrSavedDefaults(p.asData?.value ?? const Prefs(), kind),
      ),
    );
    final profiles =
        ref.watch(arrQualityProfileListProvider(kind)).asData?.value ??
        const <ArrQualityProfile>[];
    String? profileName;
    for (final p in profiles) {
      if (p.id == saved.qualityProfileId) profileName = p.name;
    }
    final summary = saved.isEmpty
        ? l.arrNewTitleDefaultsLibrary
        : [?profileName, ?saved.rootFolder].join('  ·  ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.tune_rounded),
      title: Text(l.arrNewTitleDefaults),
      subtitle: Text(summary.isEmpty ? l.arrNewTitleDefaultsHelp : summary),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _DefaultsDialog(kind: kind, hasSaved: !saved.isEmpty),
      ),
    );
  }
}

class _DefaultsDialog extends ConsumerStatefulWidget {
  final ArrKind kind;
  final bool hasSaved;
  const _DefaultsDialog({required this.kind, required this.hasSaved});

  @override
  ConsumerState<_DefaultsDialog> createState() => _DefaultsDialogState();
}

class _DefaultsDialogState extends ConsumerState<_DefaultsDialog> {
  ArrChoiceDraft? _draft;

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    await saveArrAddDefaults(
      ref,
      widget.kind,
      _draft!.toDefaults(kind: widget.kind),
    );
    if (!mounted) return;
    Navigator.pop(context);
    showSnack(context, l.arrDefaultsSaved, kind: SnackKind.success);
  }

  Future<void> _clear() async {
    await saveArrAddDefaults(ref, widget.kind, const ArrAddDefaults());
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(arrAddSetupProvider(widget.kind));
    final setup = async.asData?.value;
    if (setup != null) _draft ??= ArrChoiceDraft.from(setup.choice);
    final Widget content;
    if (setup == null && async.hasError) {
      content = Text(
        errorText(async.error!),
        style: TextStyle(color: theme.colorScheme.error),
      );
    } else if (setup == null) {
      content = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: AppSpinner()),
      );
    } else if (setup.roots.isEmpty) {
      content = Text(l.arrNoRootFolder(widget.kind.appName));
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.arrNewTitleDefaultsHelp,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ArrChoiceFields(
            kind: widget.kind,
            setup: setup,
            draft: _draft!,
            explainProfile: !widget.hasSaved,
            client: arrClient(ref, widget.kind),
            onChanged: () => setState(() {}),
          ),
        ],
      );
    }
    final ready = setup != null && setup.roots.isNotEmpty && _draft != null;
    return AlertDialog(
      title: Text('${widget.kind.appName}: ${l.arrNewTitleDefaults}'),
      scrollable: true,
      content: SizedBox(width: 480, child: content),
      actions: [
        if (widget.hasSaved)
          TextButton(onPressed: _clear, child: Text(l.arrClearDefaults)),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: ready ? _save : null,
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}
