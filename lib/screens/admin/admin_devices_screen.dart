
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/admin_providers.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../../widgets/page_width.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/error_view.dart';
import '../../widgets/ui_common.dart';
import '../../widgets/app_spinner.dart';
import '../../api/jellyfin_client.dart';


/// Client devices that have connected to the server, with deauthorize.
class AdminDevicesScreen extends ConsumerWidget {
  const AdminDevicesScreen({super.key});

  Future<void> _delete(WidgetRef ref, String id) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    await ref
        .read(jellyfinClientProvider)
        .deleteDevice(baseUrl: s.baseUrl, token: s.accessToken, id: id);
    ref.invalidate(adminDevicesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final devices = ref.watch(adminDevicesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.adminDevicesTitle)),
      body: devices.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => ErrorView(
            message: '$e', onRetry: () => ref.invalidate(adminDevicesProvider)),
        data: (list) => list.isEmpty
            ? EmptyState(icon: Icons.devices_rounded, title: l.adminNoDevices)
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(adminDevicesProvider),
                child: PageWidth(builder: (c, inset) => ListView.separated(
                  padding: pageInsetsSafe(c, inset),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = list[i];
                    final user = '${d['LastUserName'] ?? ''}';
                    final app = '${d['AppName'] ?? ''}'
                        '${d['AppVersion'] != null ? ' ${d['AppVersion']}' : ''}';
                    return ListTile(
                      leading: const Icon(Icons.devices_other_rounded),
                      title: Text('${d['Name'] ?? d['CustomName'] ?? '—'}'),
                      subtitle: Text(
                          [app, user].where((x) => x.isNotEmpty).join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        tooltip: l.commonRemove,
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await confirm(
                            context,
                            title: l.adminRemoveDeviceTitle,
                            message: l.adminRemoveDeviceBody(
                              '${d['Name'] ?? d['CustomName'] ?? ''}',
                            ),
                            confirmLabel: l.commonRemove,
                            destructive: true,
                          );
                          if (!ok) return;
                          try {
                            await _delete(ref, '${d['Id'] ?? ''}');
                          } catch (e) {
                            showErrorOn(messenger, e);
                          }
                        },
                      ),
                    );
                  },
                )),
              ),
      ),
    );
  }
}
