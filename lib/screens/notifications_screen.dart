import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/app_notification.dart';
import '../state/notifications_controller.dart';
import '../widgets/page_width.dart';
import '../widgets/empty_state.dart';

/// The in-app notification centre: request status changes and finished
/// downloads, newest first. Opening it clears the unread badge.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final list =
        ref.watch(notificationsProvider).asData?.value ?? const <AppNotif>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appNotifications),
        actions: [
          if (list.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(notificationsProvider.notifier).clear(),
              child: Text(l.appClearAll),
            ),
        ],
      ),
      body: list.isEmpty
          ? EmptyState(
              icon: Icons.notifications_none_rounded,
              title: l.appNoNotifications)
          : PageWidth(builder: (_, inset) => ListView.separated(
              padding: pageInsets(inset, const EdgeInsets.symmetric(vertical: 8)),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = list[i];
                return Dismissible(
                  key: ValueKey(n.id),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) =>
                      ref.read(notificationsProvider.notifier).remove(n.id),
                  background: ColoredBox(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: const Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: 20),
                        child: Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                  ),
                  child: ListTile(
                    leading: _icon(context, n.kind),
                    title: Text(n.title),
                    subtitle: n.body.isEmpty ? null : Text(n.body),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_ago(l, n.time),
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          tooltip: l.appDismiss,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => ref
                              .read(notificationsProvider.notifier)
                              .remove(n.id),
                        ),
                      ],
                    ),
                    onTap: n.route == null
                        ? null
                        : () => context.push(n.route!, extra: n.routeExtra),
                  ),
                );
              },
            )),
    );
  }

  Widget _icon(BuildContext context, AppNotifKind k) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (k) {
      AppNotifKind.seerrNewRequest => (Icons.add_task_rounded, scheme.primary),
      AppNotifKind.seerrApproved => (Icons.check_circle_rounded, Colors.green),
      AppNotifKind.seerrDeclined => (Icons.cancel_rounded, scheme.error),
      AppNotifKind.seerrAvailable => (
          Icons.movie_filter_rounded,
          scheme.primary
        ),
      AppNotifKind.downloadComplete => (
          Icons.download_done_rounded,
          scheme.primary
        ),
      AppNotifKind.updateAvailable => (
          Icons.system_update_rounded,
          scheme.primary
        ),
      AppNotifKind.info => (Icons.info_rounded, scheme.onSurfaceVariant),
      AppNotifKind.arrImported => (Icons.download_done_rounded, Colors.green),
      AppNotifKind.arrFailed => (Icons.error_outline_rounded, scheme.error),
      AppNotifKind.arrGrabbed => (Icons.file_download_rounded, scheme.primary),
      AppNotifKind.arrHealth => (Icons.health_and_safety_rounded, Colors.orange),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(icon, color: color, size: 20),
    );
  }

  static String _ago(AppLocalizations l, DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return l.appTimeNow;
    if (d.inMinutes < 60) return l.appTimeMinutes(d.inMinutes);
    if (d.inHours < 24) return l.appTimeHours(d.inHours);
    return l.appTimeDays(d.inDays);
  }
}
