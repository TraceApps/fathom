import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_servers.dart';
import '../state/preferences.dart';
import '../theme/app_theme.dart';
import 'app_snack.dart';
import 'app_spinner.dart';
import 'context_menu.dart';
import 'tv_keyboard.dart';

/// A server's name as shown: what it was called, or "Main".
String arrServerName(AppLocalizations l, ArrServer s) =>
    s.name.trim().isEmpty ? l.arrServerMain : s.name.trim();

/// [servers] in an order that stays put when another is put in use: by
/// name, an unnamed one ("Main") first.
List<ArrServer> arrServersByName(List<ArrServer> servers) {
  String key(ArrServer s) => s.name.trim().toLowerCase();
  return [...servers]..sort((a, b) => key(a).compareTo(key(b)));
}

/// Checks [url] really is [kind] and takes [key]: its version, or throws.
Future<String> arrCheckServer(ArrKind kind, String url, String key) async {
  final s = await switch (kind) {
    ArrKind.sonarr => SonarrClient(url, key).status(),
    ArrKind.radarr => RadarrClient(url, key).status(),
    ArrKind.lidarr => LidarrClient(url, key).status(),
  };
  return s.version;
}

/// Puts the server [s] in use, saying so.
Future<void> arrUseServer(
  BuildContext context,
  WidgetRef ref,
  ArrServer s,
) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  await ref
      .read(preferencesProvider.notifier)
      .edit((p) => arrSwitchServer(p, s.kind, s.id));
  showSnackOn(
    messenger,
    l.arrServerUsing(arrServerName(l, s), s.kind.appName),
    kind: SnackKind.success,
  );
}

/// Manage's Switch Server: every app with more than one server, each
/// server by name, the one in use marked.
Future<void> showArrServerSwitch(
  BuildContext context,
  WidgetRef ref, {
  required Offset at,
}) {
  final l = AppLocalizations.of(context);
  return showContextMenu(
    context,
    at: at,
    title: l.arrServerSwitch,
    actions: [
      for (final k in ref.read(arrMultiServerKindsProvider))
        for (final s in arrServersByName(ref.read(arrServersProvider(k))))
          ContextMenuAction(
            icon: s.active
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            label: '${k.appName}: ${arrServerName(l, s)}',
            onTap: () {
              if (s.active) return;
              if (!s.ready) {
                showSnack(context, l.arrServerNeedsKey, kind: SnackKind.error);
                return;
              }
              arrUseServer(context, ref, s);
            },
          ),
    ],
  );
}

/// "Servers" on an app's Settings card: how many, which is in use, and
/// the way to add, name, switch and remove them.
class ArrServersTile extends ConsumerWidget {
  final ArrKind kind;
  const ArrServersTile({super.key, required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final servers = ref.watch(arrServersProvider(kind));
    final active = servers.where((s) => s.active).firstOrNull;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.dns_rounded),
      title: Text(l.arrServers),
      subtitle: Text(
        servers.length < 2 || active == null
            ? l.arrServersHint
            : l.arrServersCount(servers.length, arrServerName(l, active)),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => ArrServersDialog(kind: kind),
      ),
    );
  }
}

/// An app's servers: the one in use, the others with Use This One, and
/// Add Server.
class ArrServersDialog extends ConsumerWidget {
  final ArrKind kind;
  const ArrServersDialog({super.key, required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final servers = ref.watch(arrServersProvider(kind));
    return AlertDialog(
      title: Text(l.arrServersTitle(kind.appName)),
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in arrServersByName(servers))
                Builder(
                  key: ValueKey('server-${s.id}-${s.active}'),
                  builder: (row) => ListTile(
                  leading: Icon(
                    s.active
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: s.active ? scheme.primary : null,
                  ),
                  title: Text(arrServerName(l, s)),
                  subtitle: Text(
                    [
                      s.url,
                      if (s.active) l.arrServerInUse,
                      if (!s.ready) l.arrServerNeedsKey,
                    ].join(' · '),
                  ),
                  // Pressing one: what can be done with it, by name.
                  onTap: () => showContextMenu(
                    context,
                    at: contextMenuAnchor(row),
                    title: arrServerName(l, s),
                    actions: [
                      if (!s.active && s.ready)
                        ContextMenuAction(
                          icon: Icons.check_circle_outline_rounded,
                          label: l.arrServerUse,
                          onTap: () => arrUseServer(context, ref, s),
                        ),
                      ContextMenuAction(
                        icon: Icons.edit_rounded,
                        label: l.arrServerEdit,
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => _ServerForm(kind: kind, server: s),
                        ),
                      ),
                      if (!s.active)
                        ContextMenuAction(
                          icon: Icons.delete_outline_rounded,
                          label: l.arrRemove,
                          color: scheme.error,
                          onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await ref
                                .read(preferencesProvider.notifier)
                                .edit((p) => arrRemoveServer(p, s.id));
                            showSnackOn(
                              messenger,
                              l.arrServerRemoved(arrServerName(l, s)),
                            );
                          },
                        ),
                    ],
                  ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => _ServerForm(kind: kind),
          ),
          child: Text(l.arrServerAdd),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }
}

/// Add Server, or a saved server's name and key. A new one is checked
/// first: its address must answer as the app, with its key.
class _ServerForm extends ConsumerStatefulWidget {
  final ArrKind kind;

  /// The server edited; null to add one.
  final ArrServer? server;
  const _ServerForm({required this.kind, this.server});

  @override
  ConsumerState<_ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends ConsumerState<_ServerForm> {
  late final _name = TextEditingController(text: widget.server?.name ?? '');
  late final _url = TextEditingController(text: widget.server?.url ?? '');
  late final _key = TextEditingController(text: widget.server?.apiKey ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final name = _name.text.trim();
    final key = _key.text.trim();
    final s = widget.server;
    var url = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (s == null && !url.contains('://') && url.isNotEmpty) {
      url = 'http://$url';
    }
    if ((s == null && url.isEmpty) || key.isEmpty) {
      showSnack(context, l.arrEnterBoth);
      return;
    }
    // Each by a name of its own, or two read "Main" in Switch Server.
    final taken = ref
        .read(arrServersProvider(widget.kind))
        .where((o) => o.id != s?.id || s == null)
        .any(
          (o) =>
              arrServerName(l, o).toLowerCase() ==
              (name.isEmpty ? l.arrServerMain : name).toLowerCase(),
        );
    if (taken) {
      showSnack(context, l.arrServerNameTaken, kind: SnackKind.error);
      return;
    }
    setState(() => _busy = true);
    try {
      // The key (and a new server's address) must work before it's kept.
      final version = await arrCheckServer(
        widget.kind,
        s?.url ?? url,
        key,
      );
      await ref
          .read(preferencesProvider.notifier)
          .edit(
            (p) => s == null
                ? arrAddServer(p, widget.kind, name: name, url: url, apiKey: key)
                : arrEditServer(p, widget.kind, s.id, name: name, apiKey: key),
          );
      showSnackOn(
        messenger,
        l.arrConnectedTo(widget.kind.appName, version),
        kind: SnackKind.success,
      );
      nav.pop();
    } catch (e) {
      if (mounted) {
        showSnack(context, e.toString(), kind: SnackKind.error);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final editing = widget.server != null;
    return AlertDialog(
      title: Text(editing ? l.arrServerEdit : l.arrServerAdd),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TvTextField(
                controller: _name,
                label: l.arrServerName,
                hint: l.arrServerNameHint,
                icon: Icons.label_rounded,
                autofocus: true,
              ),
              const SizedBox(height: 14),
              if (!editing) ...[
                TvTextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  label: l.arrServerAddress,
                  hint: switch (widget.kind) {
                    ArrKind.sonarr => 'http://192.168.1.10:8989',
                    ArrKind.radarr => 'http://192.168.1.10:7878',
                    ArrKind.lidarr => 'http://192.168.1.10:8686',
                  },
                  icon: Icons.link_rounded,
                ),
                const SizedBox(height: 14),
              ],
              TvTextField(
                controller: _key,
                obscure: true,
                label: l.arrApiKey,
                helperText: l.arrApiKeyHelp(widget.kind.appName),
                icon: Icons.key_rounded,
                onSubmitted: (_) => _busy ? null : _save(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: _busy ? null : _save,
          child: _busy ? AppSpinner.inline() : Text(l.arrSaveTest),
        ),
      ],
    );
  }
}
