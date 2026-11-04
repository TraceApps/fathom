import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/preferences.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/tv_keyboard.dart';

/// Connect Sonarr and Radarr: an address and an API key each, checked on save.
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
        ],
      ),
    );
  }
}

class _ArrConnectionCard extends ConsumerStatefulWidget {
  final ArrKind kind;
  const _ArrConnectionCard({required this.kind});

  @override
  ConsumerState<_ArrConnectionCard> createState() => _ArrConnectionCardState();
}

class _ArrConnectionCardState extends ConsumerState<_ArrConnectionCard> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  bool _busy = false;
  // What the last check said: "Sonarr 4.0.14", or null before any check.
  String? _version;

  bool get _sonarr => widget.kind == ArrKind.sonarr;

  @override
  void initState() {
    super.initState();
    final p = ref.read(preferencesProvider).asData?.value ?? const Prefs();
    _url = TextEditingController(text: _sonarr ? p.sonarrUrl : p.radarrUrl);
    _key = TextEditingController(
      text: _sonarr ? p.sonarrApiKey : p.radarrApiKey,
    );
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

  ArrClient _client(String url, String key) =>
      _sonarr ? SonarrClient(url, key) : RadarrClient(url, key);

  /// Asks the server what it is. Quiet on open, so a saved connection just
  /// shows its version without a message.
  Future<void> _check({bool quiet = false}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final s = await _client(_url.text.trim(), _key.text.trim()).status();
      if (!mounted) return;
      setState(() => _version = s.version);
      if (!quiet) {
        showSnackOn(
          messenger,
          l.arrConnectedTo(widget.kind.appName, s.version),
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
    await ref
        .read(preferencesProvider.notifier)
        .edit(
          (p) => _sonarr
              ? p.copyWith(sonarrUrl: address, sonarrApiKey: key)
              : p.copyWith(radarrUrl: address, radarrApiKey: key),
        );
    await _check();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _disconnect() async {
    final l = AppLocalizations.of(context);
    await ref
        .read(preferencesProvider.notifier)
        .edit(
          (p) => _sonarr
              ? p.copyWith(sonarrUrl: '', sonarrApiKey: '')
              : p.copyWith(radarrUrl: '', radarrApiKey: ''),
        );
    if (!mounted) return;
    _url.clear();
    _key.clear();
    setState(() => _version = null);
    showSnack(context, l.arrDisconnected(widget.kind.appName));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final saved = ref.watch(
      preferencesProvider.select((p) {
        final v = p.asData?.value;
        return _sonarr
            ? (v?.sonarrUrl.isNotEmpty ?? false)
            : (v?.radarrUrl.isNotEmpty ?? false);
      }),
    );
    final status = !saved
        ? l.arrNotConnected
        : _version != null
        ? l.arrConnectedTo(widget.kind.appName, _version!)
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
                  _sonarr ? Icons.live_tv_rounded : Icons.movie_rounded,
                  color: scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.kind.appName,
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
              hint: _sonarr
                  ? 'http://192.168.1.10:8989'
                  : 'http://192.168.1.10:7878',
              icon: Icons.link_rounded,
            ),
            const SizedBox(height: 14),
            TvTextField(
              controller: _key,
              obscure: true,
              label: l.arrApiKey,
              helperText: l.arrApiKeyHelp(widget.kind.appName),
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
          ],
        ),
      ),
    );
  }
}
