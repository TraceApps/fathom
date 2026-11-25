import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/admin_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/error_view.dart';
import '../widgets/search_field.dart';
import '../widgets/tv_keyboard.dart';
import '../widgets/user_avatar.dart';
import '../widgets/ui_common.dart';
import 'settings_search.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../api/jellyfin_client.dart';

/// Server administration (visible only to administrators): users, libraries,
/// scheduled tasks, active sessions, and the activity log. A search box jumps
/// straight to any admin section or setting.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final searching = _query.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(l.adminTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              controller: _searchCtrl,
              hint: l.adminSearchHint,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: searching ? _results(context) : _hub(context),
          ),
        ],
      ),
    );
  }

  Widget _results(BuildContext context) {
    final results = searchSettings(adminSettingsIndex(AppLocalizations.of(context)), _query);
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(AppLocalizations.of(context).adminNoMatch(_query.trim()),
              style: TextStyle(color: Theme.of(context).hintColor)),
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final r = results[i];
        return ListTile(
          leading: Icon(r.icon),
          title: Text(r.title),
          subtitle: Text(r.section),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            setState(() {
              _query = '';
              _searchCtrl.clear();
            });
            context.push(r.route);
          },
        );
      },
    );
  }

  Widget _hub(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListView(
        children: [
          // Grouped by concern: server config, then who/what has access, then
          // Live TV, then maintenance. Previously scattered — Scheduled Tasks
          // sat under Plugins, the two "what happened" views (Activity, Logs)
          // lived in different groups, and Users was buried in Server.
          SettingsSectionHeader(l.adminSectionServerConfig, first: true),
          _tile(context, Icons.tune_rounded, l.adminGeneralTitle,
              l.adminGeneralSubtitle, '/admin/general'),
          _tile(context, Icons.play_circle_outline_rounded, l.adminPlaybackTitle,
              l.adminPlaybackSubtitle, '/admin/playback'),
          _tile(context, Icons.brush_rounded, l.adminBrandingTitle,
              l.adminBrandingSubtitle, '/admin/branding'),
          _tile(context, Icons.lan_rounded, l.adminNetworkingTitle,
              l.adminNetworkingSubtitle, '/admin/network'),
          _tile(context, Icons.key_rounded, l.adminApiKeysTitle,
              l.adminApiKeysSubtitle, '/admin/apikeys'),
          SettingsSectionHeader(l.adminSectionContentAccess),
          _tile(context, Icons.video_library_rounded, l.adminLibrariesTitle,
              l.adminLibrariesSubtitle, '/admin/libraries'),
          _tile(context, Icons.people_alt_rounded, l.adminUsersTitle,
              l.adminUsersSubtitle, '/admin/users'),
          _tile(context, Icons.devices_other_rounded, l.adminDevicesTitle,
              l.adminDevicesSubtitle, '/admin/devices'),
          _tile(context, Icons.wifi_tethering_rounded, l.adminSessionsTitle,
              l.adminSessionsSubtitle, '/admin/sessions'),
          SettingsSectionHeader(l.adminSectionLiveTv),
          _tile(context, Icons.live_tv_rounded, l.adminLiveTvTitle,
              l.adminLiveTvSubtitle, '/admin/livetv'),
          _tile(context, Icons.fiber_dvr_rounded, l.adminDvrTitle,
              l.adminDvrSubtitle, '/admin/dvr'),
          SettingsSectionHeader(l.adminSectionMaintenance),
          _tile(context, Icons.schedule_rounded, l.adminTasksTitle,
              l.adminTasksSubtitle, '/admin/tasks'),
          _tile(context, Icons.history_rounded, l.adminActivityTitle,
              l.adminActivitySubtitle, '/admin/activity'),
          _tile(context, Icons.description_outlined, l.adminLogsTitle,
              l.adminLogsSubtitle, '/admin/logs'),
          _tile(context, Icons.inventory_2_outlined, l.adminBackupsTitle,
              l.adminBackupsSubtitle, '/admin/backups'),
          _tile(context, Icons.dns_rounded, l.adminSystemTitle,
              l.adminSystemSubtitle, '/admin/system'),
          SettingsSectionHeader(l.adminSectionExtensions),
          _tile(context, Icons.extension_rounded, l.adminPluginsTitle,
              l.adminPluginsSubtitle, '/admin/plugins'),
          const SizedBox(height: 24),
        ],
      );
  }

  Widget _tile(BuildContext context, IconData icon, String title,
          String subtitle, String route) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push(route),
      );
}

Widget _async(
  BuildContext context,
  AsyncValue<List<Map<String, dynamic>>> async,
  Widget Function(List<Map<String, dynamic>>) builder, {
  required VoidCallback onRetry,
}) {
  return async.when(
    loading: () => const Center(child: AppSpinner()),
    error: (e, _) => ErrorView(message: '$e', onRetry: onRetry),
    data: (list) => list.isEmpty
        ? Center(child: Text(AppLocalizations.of(context).adminNothingHere))
        : builder(list),
  );
}

class _SystemTab extends ConsumerWidget {
  const _SystemTab();

  Future<void> _control(BuildContext context, WidgetRef ref, bool restart) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirm(
      context,
      title: restart
          ? l.adminRestartServerConfirmTitle
          : l.adminShutDownServerConfirmTitle,
      message: restart
          ? l.adminRestartServerConfirmBody
          : l.adminShutDownServerConfirmBody,
      confirmLabel: restart ? l.adminRestart : l.adminShutDown,
      destructive: true,
    );
    if (!ok) return;
    try {
      final client = ref.read(jellyfinClientProvider);
      if (restart) {
        await client.restartServer(baseUrl: s.baseUrl, token: s.accessToken);
      } else {
        await client.shutdownServer(baseUrl: s.baseUrl, token: s.accessToken);
      }
      showSnackOn(messenger,
          restart ? l.adminRestartRequested : l.adminShutdownRequested,
          kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final info = ref.watch(adminSystemProvider);
    return info.when(
      loading: () => const Center(child: AppSpinner()),
      error: (e, _) => ErrorView(
        message: '$e',
        onRetry: () => ref.invalidate(adminSystemProvider),
      ),
      data: (m) => ListView(
        children: [
          ListTile(
              leading: const Icon(Icons.dns_rounded),
              title: Text(l.adminServerLabel),
              subtitle: Text('${m['ServerName'] ?? '—'}')),
          ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(l.adminVersionLabel),
              subtitle: Text('${m['Version'] ?? '—'}')),
          ListTile(
              leading: const Icon(Icons.computer_rounded),
              title: Text(l.adminOperatingSystemLabel),
              subtitle: Text('${m['OperatingSystem'] ?? '—'}')),
          ListTile(
              leading: const Icon(Icons.memory_rounded),
              title: Text(l.adminArchitectureLabel),
              subtitle: Text('${m['SystemArchitecture'] ?? '—'}')),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _control(context, ref, true),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(l.adminRestart),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _control(context, ref, false),
                    style: OutlinedButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).colorScheme.error),
                    icon: const Icon(Icons.power_settings_new_rounded),
                    label: Text(l.adminShutDown),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps a section body in its own screen (the admin landing pushes these).
class AdminSectionScreen extends StatelessWidget {
  final String title;
  final Widget child;
  const AdminSectionScreen({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: child,
      );
}

class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  Future<void> _createUser(BuildContext context, WidgetRef ref) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nameCtrl = TextEditingController();
    final pwCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminCreateUser),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvTextField(
              controller: nameCtrl,
              autofocus: true,
              label: l.adminUsername,
            ),
            const SizedBox(height: 12),
            TvTextField(
              controller: pwCtrl,
              obscure: true,
              label: l.adminPasswordOptional,
            ),
          ],
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
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    try {
      final client = ref.read(jellyfinClientProvider);
      final created = await client.createUser(
        baseUrl: s.baseUrl,
        token: s.accessToken,
        name: nameCtrl.text.trim(),
        password: pwCtrl.text.isEmpty ? null : pwCtrl.text,
      );
      ref.invalidate(adminUsersProvider);
      showSnackOn(messenger,
          l.adminCreatedUser('${created['Name'] ?? nameCtrl.text}'),
          kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final users = ref.watch(adminUsersProvider);
    return _async(context, users, (list) {
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminUsersProvider),
        child: ListView.separated(
          itemCount: list.length + 1,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == 0) {
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: const Icon(Icons.person_add_alt_1_rounded),
                ),
                title: Text(l.adminCreateUser),
                onTap: () => _createUser(context, ref),
              );
            }
            final u = list[i - 1];
            final policy = (u['Policy'] as Map?) ?? const {};
            final isAdmin = policy['IsAdministrator'] == true;
            final disabled = policy['IsDisabled'] == true;
            return ListTile(
              leading: JellyfinAvatar(
                userId: '${u['Id']}',
                name: '${u['Name'] ?? '?'}',
                tag: u['PrimaryImageTag'] as String?,
                radius: 20,
              ),
              title: Text('${u['Name'] ?? '—'}'),
              subtitle: Text(disabled
                  ? l.adminUserDisabled
                  : (isAdmin ? l.adminUserAdministrator : l.adminUser)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/admin/user', extra: u['Id'] as String),
            );
          },
        ),
      );
    }, onRetry: () => ref.invalidate(adminUsersProvider),
    );
  }
}

class _LibrariesTab extends ConsumerWidget {
  const _LibrariesTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);
    final libs = ref.watch(adminLibrariesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () async {
              final s = ref.read(sessionControllerProvider).asData?.value;
              if (s == null) return;
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(jellyfinClientProvider).scanAllLibraries(
                    baseUrl: s.baseUrl, token: s.accessToken);
                showSnackOn(messenger, loc.adminLibraryScanStarted,
                    kind: SnackKind.success);
              } catch (e) {
                showErrorOn(messenger, e);
              }
            },
            icon: const Icon(Icons.sync_rounded),
            label: Text(loc.adminScanAllLibraries),
          ),
        ),
        Expanded(
          child: _async(context, libs, (list) {
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final l = list[i];
                final locations = (l['Locations'] as List?)?.length ?? 0;
                final id = l['ItemId'] as String?;
                return ListTile(
                  leading: const Icon(Icons.video_library_rounded),
                  title: Text('${l['Name'] ?? '—'}'),
                  subtitle: Text(loc.adminLibrarySubtitle(
                      '${l['CollectionType'] ?? loc.adminCollectionTypeMixed}',
                      locations)),
                  trailing: id == null
                      ? null
                      : IconButton(
                          tooltip: loc.adminScanThisLibrary,
                          icon: const Icon(Icons.sync_rounded),
                          onPressed: () async {
                            final s = ref
                                .read(sessionControllerProvider)
                                .asData
                                ?.value;
                            if (s == null) return;
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await ref.read(jellyfinClientProvider).refreshItem(
                                  baseUrl: s.baseUrl,
                                  token: s.accessToken,
                                  itemId: id);
                              showSnackOn(
                                  messenger,
                                  loc.adminScanningLibrary(
                                      '${l['Name'] ?? loc.adminLibraryFallback}'),
                                  kind: SnackKind.success);
                            } catch (e) {
                              showErrorOn(messenger, e);
                            }
                          },
                        ),
                );
              },
            );
          }, onRetry: () => ref.invalidate(adminLibrariesProvider),
    ),
        ),
      ],
    );
  }
}

class _TasksTab extends ConsumerWidget {
  const _TasksTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tasks = ref.watch(adminTasksProvider);
    return _async(context, tasks, (list) {
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminTasksProvider),
        child: ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final t = list[i];
            final state = '${t['State'] ?? 'Idle'}';
            final running = state == 'Running';
            return ListTile(
              title: Text('${t['Name'] ?? '—'}'),
              subtitle: Text(state),
              trailing: IconButton(
                tooltip: l.adminRunNow,
                icon: Icon(running
                    ? Icons.hourglass_top_rounded
                    : Icons.play_arrow_rounded),
                onPressed: running
                    ? null
                    : () async {
                        final s = ref
                            .read(sessionControllerProvider)
                            .asData
                            ?.value;
                        if (s == null) return;
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref.read(jellyfinClientProvider).runScheduledTask(
                              baseUrl: s.baseUrl,
                              token: s.accessToken,
                              taskId: '${t['Id']}');
                          showSnackOn(messenger,
                              l.adminTaskStarted('${t['Name']}'),
                              kind: SnackKind.success);
                          ref.invalidate(adminTasksProvider);
                        } catch (e) {
                          showErrorOn(messenger, e);
                        }
                      },
              ),
            );
          },
        ),
      );
    }, onRetry: () => ref.invalidate(adminTasksProvider),
    );
  }
}

class _SessionsTab extends ConsumerWidget {
  const _SessionsTab();

  Future<void> _message(
      BuildContext context, WidgetRef ref, String sessionId) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminSendMessage),
        content: TvTextField(
          controller: controller,
          autofocus: true,
          label: l.adminMessageHint,
          hint: l.adminMessageHint,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(l.adminSend)),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      await ref.read(jellyfinClientProvider).sendSessionMessage(
            baseUrl: s.baseUrl,
            token: s.accessToken,
            sessionId: sessionId,
            header: l.adminMessageFrom(s.userName),
            text: text.trim(),
          );
      showSnackOn(messenger, l.adminMessageSent, kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sessions = ref.watch(adminSessionsProvider);
    return _async(context, sessions, (list) {
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminSessionsProvider),
        child: ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final s = list[i];
            final nowPlaying = (s['NowPlayingItem'] as Map?)?['Name'];
            return ListTile(
              leading: const Icon(Icons.devices_rounded),
              title: Text('${s['UserName'] ?? l.adminUnknownUser}'),
              subtitle: Text('${s['Client'] ?? ''} · ${s['DeviceName'] ?? ''}'
                  '${nowPlaying != null ? '\n▶ $nowPlaying' : ''}'),
              isThreeLine: nowPlaying != null,
              trailing: IconButton(
                tooltip: l.adminSendMessage,
                icon: const Icon(Icons.message_rounded),
                onPressed: () => _message(context, ref, '${s['Id']}'),
              ),
            );
          },
        ),
      );
    }, onRetry: () => ref.invalidate(adminSessionsProvider),
    );
  }
}

class _ActivityTab extends ConsumerWidget {
  const _ActivityTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(adminActivityProvider);
    return _async(context, activity, (list) {
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminActivityProvider),
        child: ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final a = list[i];
            final severity = '${a['Severity'] ?? ''}';
            return ListTile(
              leading: Icon(
                severity == 'Error'
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
                color: severity == 'Error'
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
              title: Text('${a['Name'] ?? '—'}',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle:
                  a['ShortOverview'] != null ? Text('${a['ShortOverview']}') : null,
              trailing: Text(_shortDate(a['Date'] as String?),
                  style: Theme.of(context).textTheme.bodySmall),
            );
          },
        ),
      );
    }, onRetry: () => ref.invalidate(adminActivityProvider),
    );
  }
}

String _shortDate(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$mm/$dd $hh:$min';
}

// Public wrappers so the admin landing can route to each section as its own
// screen (the section bodies stay private to this library).
class AdminSystemScreen extends StatelessWidget {
  const AdminSystemScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSectionScreen(
      title: AppLocalizations.of(context).adminSystemTitle,
      child: const _SystemTab());
}

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSectionScreen(
      title: AppLocalizations.of(context).adminUsersTitle,
      child: const _UsersTab());
}

class AdminLibrariesScreen extends StatelessWidget {
  const AdminLibrariesScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSectionScreen(
      title: AppLocalizations.of(context).adminLibrariesTitle,
      child: const _LibrariesTab());
}

class AdminTasksScreen extends StatelessWidget {
  const AdminTasksScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSectionScreen(
      title: AppLocalizations.of(context).adminTasksTitle,
      child: const _TasksTab());
}

class AdminSessionsScreen extends StatelessWidget {
  const AdminSessionsScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSectionScreen(
      title: AppLocalizations.of(context).adminSessionsTitle,
      child: const _SessionsTab());
}

class AdminActivityScreen extends StatelessWidget {
  const AdminActivityScreen({super.key});
  @override
  Widget build(BuildContext context) => AdminSectionScreen(
      title: AppLocalizations.of(context).adminActivityTitle,
      child: const _ActivityTab());
}

