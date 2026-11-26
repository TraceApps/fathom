
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/error_text.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/admin_providers.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../../widgets/page_width.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/tv_keyboard.dart';
import '../../widgets/ui_common.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/app_spinner.dart';
import '../../api/jellyfin_client.dart';


/// API keys: list, create, and revoke app access tokens.
class AdminApiKeysScreen extends ConsumerWidget {
  const AdminApiKeysScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminNewApiKey),
        content: TvTextField(
          controller: ctrl,
          autofocus: true,
          label: l.adminAppName,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.adminCreate)),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await ref.read(jellyfinClientProvider).createApiKey(
          baseUrl: s.baseUrl, token: s.accessToken, appName: ctrl.text.trim());
      ref.invalidate(adminApiKeysProvider);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  Future<void> _revoke(
      BuildContext context, WidgetRef ref, String key) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirm(context,
        title: l.adminRevokeApiKeyConfirm,
        message: l.adminRevokeApiKeyBody,
        confirmLabel: l.adminRevoke,
        destructive: true);
    if (!ok) return;
    try {
      await ref.read(jellyfinClientProvider).deleteApiKey(
          baseUrl: s.baseUrl, token: s.accessToken, key: key);
      ref.invalidate(adminApiKeysProvider);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final keys = ref.watch(adminApiKeysProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.adminApiKeysTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.adminNewKey),
      ),
      body: keys.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => ErrorView(
            message: errorText(e), onRetry: () => ref.invalidate(adminApiKeysProvider)),
        data: (list) => list.isEmpty
            ? EmptyState(icon: Icons.key_rounded, title: l.adminNoApiKeys)
            : PageWidth(builder: (c, inset) => ListView.separated(
                padding: pageInsetsSafe(c, inset),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final k = list[i];
                  final token = '${k['AccessToken'] ?? ''}';
                  return ListTile(
                    leading: const Icon(Icons.key_rounded),
                    title: Text('${k['AppName'] ?? '-'}'),
                    subtitle: Text(token.length > 12
                        ? '${token.substring(0, 12)}…'
                        : token),
                    trailing: IconButton(
                      tooltip: l.adminRevoke,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => _revoke(context, ref, token),
                    ),
                  );
                },
              )),
      ),
    );
  }
}
