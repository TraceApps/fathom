import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_servers.dart';
import '../state/preferences.dart';
import 'app_snack.dart';
import 'context_menu.dart';

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
