import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/session_controller.dart';
import '../widgets/ui_common.dart';

/// Manage signed-in accounts across servers and users: switch, add, remove.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sessionControllerProvider); // rebuild when the active account changes
    final controller = ref.read(sessionControllerProvider.notifier);
    final accounts = controller.accounts;
    final activeKey = controller.activeKey;
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.accountTitle)),
      body: ListView(
        children: [
          for (final s in accounts)
            Builder(builder: (context) {
              final isActive = '${s.baseUrl}|${s.userId}' == activeKey;
              return ListTile(
                selected: isActive,
                selectedTileColor: scheme.primary.withValues(alpha: 0.08),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor:
                      isActive ? scheme.primary : scheme.surfaceContainerHighest,
                  child: Icon(Icons.person_rounded,
                      color: isActive ? scheme.onPrimary : null),
                ),
                title: Text(s.userName),
                subtitle: Text(s.serverName ?? s.baseUrl,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: isActive
                    ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                    : IconButton(
                        tooltip: l.commonRemove,
                        icon: const Icon(Icons.logout_rounded),
                        onPressed: () async {
                          final ok = await confirm(
                            context,
                            title: l.accountsRemoveTitle,
                            message: l.accountsRemoveBody(
                              s.userName,
                              s.serverName ?? s.baseUrl,
                            ),
                            confirmLabel: l.commonRemove,
                            destructive: true,
                          );
                          if (ok) await controller.removeAccount(s);
                        },
                      ),
                onTap: isActive ? null : () => controller.switchTo(s),
              );
            }),
          const Divider(height: 24),
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: scheme.primary.withValues(alpha: 0.14),
              child: Icon(Icons.add_rounded, color: scheme.primary),
            ),
            title: Text(l.accountAdd),
            subtitle: Text(l.accountAddSubtitle),
            onTap: () => context.push('/connect'),
          ),
        ],
      ),
    );
  }
}
