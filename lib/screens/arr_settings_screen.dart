import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_providers.dart';
import '../state/preferences.dart';
import '../theme/app_theme.dart';
import 'arr_add_screen.dart';
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
            if (saved && _version != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              _DefaultsTile(kind: widget.kind),
            ],
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
