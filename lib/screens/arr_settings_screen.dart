import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/arr_client.dart';
import '../api/bazarr_client.dart';
import '../api/download_clients.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../models/download_client.dart';
import '../state/arr_providers.dart';
import '../state/arr_servers.dart';
import '../state/download_providers.dart';
import '../state/preferences.dart';
import '../theme/app_theme.dart';
import 'arr_add_screen.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_servers_ui.dart';
import '../widgets/tv_keyboard.dart';

/// Connect Sonarr, Radarr, Lidarr and Prowlarr (an address and an API key
/// each) and the download clients, each checked on save.
class ArrSettingsScreen extends StatelessWidget {
  const ArrSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsArr)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            l.arrSettingsIntro,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          const _ArrConnectionCard(kind: ArrKind.sonarr),
          const SizedBox(height: 16),
          const _ArrConnectionCard(kind: ArrKind.radarr),
          const SizedBox(height: 16),
          const _ArrConnectionCard(kind: ArrKind.lidarr),
          const SizedBox(height: 16),
          const _ArrConnectionCard(kind: null),
          const SizedBox(height: 16),
          const _ArrConnectionCard(kind: null, bazarr: true),
          const SizedBox(height: 28),
          Text(
            l.dlSettingsHeading,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const _DownloadClientCard(kind: DownloadClientKind.qbittorrent),
          const SizedBox(height: 16),
          const _DownloadClientCard(kind: DownloadClientKind.sabnzbd),
        ],
      ),
    );
  }
}

class _ArrConnectionCard extends ConsumerStatefulWidget {
  /// The app; null for Prowlarr or Bazarr, which aren't library apps.
  final ArrKind? kind;

  /// With no kind: Bazarr rather than Prowlarr.
  final bool bazarr;
  const _ArrConnectionCard({required this.kind, this.bazarr = false});

  @override
  ConsumerState<_ArrConnectionCard> createState() => _ArrConnectionCardState();
}

class _ArrConnectionCardState extends ConsumerState<_ArrConnectionCard> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  bool _busy = false;
  // What the last check said: "Sonarr 4.0.14", or null before any check.
  String? _version;

  @override
  void initState() {
    super.initState();
    final p = ref.read(preferencesProvider).asData?.value ?? const Prefs();
    final (url, key) = _saved(p);
    _url = TextEditingController(text: url);
    _key = TextEditingController(text: key);
    if (_url.text.isNotEmpty && _key.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? _check(quiet: true) : null,
      );
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  /// The address and key saved for this app.
  String get _app =>
      widget.kind?.appName ??
      (widget.bazarr ? BazarrClient.appName : ProwlarrClient.appName);

  (String, String) _saved(Prefs p) => switch (widget.kind) {
    null when widget.bazarr => (p.bazarrUrl, p.bazarrApiKey),
    null => (p.prowlarrUrl, p.prowlarrApiKey),
    ArrKind.sonarr => (p.sonarrUrl, p.sonarrApiKey),
    ArrKind.radarr => (p.radarrUrl, p.radarrApiKey),
    ArrKind.lidarr => (p.lidarrUrl, p.lidarrApiKey),
  };

  Prefs _withSaved(Prefs p, String url, String key) => switch (widget.kind) {
    null when widget.bazarr => p.copyWith(bazarrUrl: url, bazarrApiKey: key),
    null => p.copyWith(prowlarrUrl: url, prowlarrApiKey: key),
    ArrKind.sonarr => p.copyWith(sonarrUrl: url, sonarrApiKey: key),
    ArrKind.radarr => p.copyWith(radarrUrl: url, radarrApiKey: key),
    ArrKind.lidarr => p.copyWith(lidarrUrl: url, lidarrApiKey: key),
  };

  Future<ArrStatus> _status(String url, String key) => switch (widget.kind) {
    null when widget.bazarr => BazarrClient(url, key).version().then(
      (v) => ArrStatus(appName: BazarrClient.appName, version: v),
    ),
    null => ProwlarrClient(url, key).status(),
    ArrKind.sonarr => SonarrClient(url, key).status(),
    ArrKind.radarr => RadarrClient(url, key).status(),
    ArrKind.lidarr => LidarrClient(url, key).status(),
  };

  /// Asks the server what it is. Quiet on open, so a saved connection just
  /// shows its version without a message.
  Future<void> _check({bool quiet = false}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final s = await _status(_url.text.trim(), _key.text.trim());
      if (!mounted) return;
      setState(() => _version = s.version);
      if (!quiet) {
        showSnackOn(
          messenger,
          l.arrConnectedTo(_app, s.version),
          kind: SnackKind.success,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _version = null);
      if (!quiet) {
        showSnackOn(
          messenger,
          l.arrSavedTestFailed(e.toString()),
          kind: SnackKind.error,
        );
      }
    }
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final url = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    final key = _key.text.trim();
    if (url.isEmpty || key.isEmpty) {
      showSnack(context, l.arrEnterBoth);
      return;
    }
    // A bare host:port is the usual thing to type; the apps speak plain
    // HTTP on a home network unless set up otherwise.
    final address = url.contains('://') ? url : 'http://$url';
    _url.text = address;
    setState(() => _busy = true);
    final kind = widget.kind;
    await ref.read(preferencesProvider.notifier).edit((p) {
      // The address of another saved server of the app: that one, put in
      // use, rather than a second copy of it under this one's name.
      final saved = kind == null
          ? null
          : arrServersOf(
              p,
              kind,
            ).where((s) => !s.active && s.url == address).firstOrNull;
      if (saved == null || kind == null) return _withSaved(p, address, key);
      return arrSwitchServer(
        arrEditServer(p, kind, saved.id, apiKey: key),
        kind,
        saved.id,
      );
    });
    await _check();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _disconnect() async {
    final l = AppLocalizations.of(context);
    final kind = widget.kind;
    // Another saved server of the app takes the place of the one
    // disconnected.
    await ref
        .read(preferencesProvider.notifier)
        .edit(
          (p) => kind == null
              ? _withSaved(p, '', '')
              : arrDisconnectActive(p, kind),
        );
    if (!mounted) return;
    final p = ref.read(preferencesProvider).asData?.value ?? const Prefs();
    final (url, key) = _saved(p);
    _url.text = url;
    _key.text = key;
    setState(() => _version = null);
    if (url.isNotEmpty) _check(quiet: true);
    showSnack(context, l.arrDisconnected(_app));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = widget.kind;
    // Another server put in use (Manage's Switch Server, or the Servers
    // dialog): the fields and the check follow it.
    ref.listen(
      preferencesProvider.select((p) {
        final v = p.asData?.value;
        return v == null ? ('', '') : _saved(v);
      }),
      (before, now) {
        if (now.$1 == _url.text && now.$2 == _key.text) return;
        _url.text = now.$1;
        _key.text = now.$2;
        setState(() => _version = null);
        if (now.$1.isNotEmpty && now.$2.isNotEmpty) _check(quiet: true);
      },
    );
    final servers = kind == null
        ? const <ArrServer>[]
        : ref.watch(arrServersProvider(kind));
    final active = servers.where((s) => s.active).firstOrNull;
    // Its name, once there's more than one or it was given one.
    final title =
        active != null && (servers.length > 1 || active.name.isNotEmpty)
        ? '$_app: ${arrServerName(l, active)}'
        : _app;
    final saved = ref.watch(
      preferencesProvider.select((p) {
        final v = p.asData?.value;
        return v != null && _saved(v).$1.isNotEmpty;
      }),
    );
    final status = !saved
        ? l.arrNotConnected
        : _version != null
        ? l.arrConnectedTo(_app, _version!)
        : null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(switch (widget.kind) {
                  null when widget.bazarr => Icons.subtitles_rounded,
                  null => Icons.travel_explore_rounded,
                  ArrKind.sonarr => Icons.live_tv_rounded,
                  ArrKind.radarr => Icons.movie_rounded,
                  ArrKind.lidarr => Icons.library_music_rounded,
                }, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (status != null)
                        Text(
                          status,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _version != null
                                ? const Color(0xFF22C55E)
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TvTextField(
              controller: _url,
              keyboardType: TextInputType.url,
              label: l.arrServerAddress,
              hint: switch (widget.kind) {
                null when widget.bazarr => 'http://192.168.1.10:6767',
                null => 'http://192.168.1.10:9696',
                ArrKind.sonarr => 'http://192.168.1.10:8989',
                ArrKind.radarr => 'http://192.168.1.10:7878',
                ArrKind.lidarr => 'http://192.168.1.10:8686',
              },
              icon: Icons.link_rounded,
            ),
            const SizedBox(height: 14),
            TvTextField(
              controller: _key,
              obscure: true,
              label: l.arrApiKey,
              helperText: l.arrApiKeyHelp(_app),
              icon: Icons.key_rounded,
              onSubmitted: (_) => _busy ? null : _save(),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (saved)
                  TextButton(
                    onPressed: _busy ? null : _disconnect,
                    child: Text(l.arrDisconnect),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy ? AppSpinner.inline() : Text(l.arrSaveTest),
                ),
              ],
            ),
            if (saved && _version != null && widget.kind != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              ?switch (widget.kind) {
                final k? => _DefaultsTile(kind: k),
                // Prowlarr adds nothing: no defaults to set.
                null => null,
              },
            ],
            // More servers of the app (a 4K one), once it's connected.
            if (saved && kind != null) ArrServersTile(kind: kind),
          ],
        ),
      ),
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
        async.error.toString(),
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

/// A download client's connection: its address and sign-in (qBittorrent's
/// username and password, SABnzbd's API key), checked on save.
class _DownloadClientCard extends ConsumerStatefulWidget {
  final DownloadClientKind kind;
  const _DownloadClientCard({required this.kind});

  @override
  ConsumerState<_DownloadClientCard> createState() =>
      _DownloadClientCardState();
}

class _DownloadClientCardState extends ConsumerState<_DownloadClientCard> {
  late final TextEditingController _url;

  /// qBittorrent's username; unused for SABnzbd.
  late final TextEditingController _user;

  /// qBittorrent's password, or SABnzbd's API key.
  late final TextEditingController _secret;
  bool _busy = false;
  String? _version;

  bool get _qbit => widget.kind == DownloadClientKind.qbittorrent;
  String get _app => widget.kind.appName;

  (String, String, String) _saved(Prefs p) => _qbit
      ? (p.qbitUrl, p.qbitUsername, p.qbitPassword)
      : (p.sabUrl, '', p.sabApiKey);

  Prefs _withSaved(Prefs p, String url, String user, String secret) => _qbit
      ? p.copyWith(qbitUrl: url, qbitUsername: user, qbitPassword: secret)
      : p.copyWith(sabUrl: url, sabApiKey: secret);

  DownloadClient _client(String url, String user, String secret) => _qbit
      ? QbitClient(url, user, secret)
      : SabClient(url, secret);

  @override
  void initState() {
    super.initState();
    final p = ref.read(preferencesProvider).asData?.value ?? const Prefs();
    final (url, user, secret) = _saved(p);
    _url = TextEditingController(text: url);
    _user = TextEditingController(text: user);
    _secret = TextEditingController(text: secret);
    if (url.isNotEmpty && (_qbit || secret.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? _check(quiet: true) : null,
      );
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _check({bool quiet = false}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // On opening, the app's own client: one that qBittorrent has refused
      // isn't sent to sign in again (repeated failures get a device banned).
      final saved = quiet
          ? (_qbit ? ref.read(qbitClientProvider) : ref.read(sabClientProvider))
          : null;
      final v = await (saved ??
              _client(_url.text.trim(), _user.text.trim(), _secret.text))
          .version();
      if (!mounted) return;
      setState(() => _version = v);
      if (!quiet) {
        showSnackOn(
          messenger,
          l.arrConnectedTo(_app, v),
          kind: SnackKind.success,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _version = null);
      if (!quiet) {
        showSnackOn(
          messenger,
          l.arrSavedTestFailed(e.toString()),
          kind: SnackKind.error,
        );
      }
    }
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final url = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    final user = _user.text.trim();
    // A password is kept as typed: spaces can be part of it.
    final secret = _qbit ? _secret.text : _secret.text.trim();
    if (url.isEmpty || (!_qbit && secret.isEmpty)) {
      showSnack(context, _qbit ? l.dlEnterAddress : l.dlEnterSabBoth);
      return;
    }
    final address = url.contains('://') ? url : 'http://$url';
    _url.text = address;
    setState(() => _busy = true);
    await ref
        .read(preferencesProvider.notifier)
        .edit((p) => _withSaved(p, address, user, secret));
    await _check();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _disconnect() async {
    final l = AppLocalizations.of(context);
    await ref
        .read(preferencesProvider.notifier)
        .edit((p) => _withSaved(p, '', '', ''));
    if (!mounted) return;
    _url.clear();
    _user.clear();
    _secret.clear();
    setState(() => _version = null);
    showSnack(context, l.arrDisconnected(_app));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final saved = ref.watch(
      preferencesProvider.select((p) {
        final v = p.asData?.value;
        return v != null && _saved(v).$1.isNotEmpty;
      }),
    );
    final status = !saved
        ? l.arrNotConnected
        : _version != null
        ? l.arrConnectedTo(_app, _version!)
        : null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  _qbit ? Icons.hub_rounded : Icons.dns_rounded,
                  color: scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _app,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (status != null)
                        Text(
                          status,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _version != null
                                ? const Color(0xFF22C55E)
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TvTextField(
              controller: _url,
              keyboardType: TextInputType.url,
              label: l.arrServerAddress,
              hint: _qbit ? 'http://192.168.1.10:8080' : 'http://192.168.1.10:8085',
              icon: Icons.link_rounded,
            ),
            const SizedBox(height: 14),
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
              helperText: _qbit ? l.dlQbitHelp : l.dlSabKeyHelp,
              icon: _qbit ? Icons.password_rounded : Icons.key_rounded,
              onSubmitted: (_) => _busy ? null : _save(),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (saved)
                  TextButton(
                    onPressed: _busy ? null : _disconnect,
                    child: Text(l.arrDisconnect),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy ? AppSpinner.inline() : Text(l.arrSaveTest),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
