import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'app_spinner.dart';

/// One thing the picking bar can do to what's picked.
class PickAction {
  final IconData icon;
  final String label;
  final VoidCallback? run; // null: not available now
  final bool danger;
  const PickAction(this.icon, this.label, this.run, {this.danger = false});
}

/// The bar shown while picking, wherever several things can be picked (a
/// Jellyfin library, Manage's library, queue, Wanted and blocklist, YouTube
/// downloads): Cancel, how many, Select All, and the actions, as buttons
/// when there's room and one menu when there isn't.
class PickBar extends StatelessWidget {
  final int count;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final List<PickAction> actions;

  const PickBar({
    super.key,
    required this.count,
    required this.onCancel,
    required this.onSelectAll,
    required this.actions,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final enabled = !busy && count > 0;
    PickAction live(PickAction a) =>
        enabled ? a : PickAction(a.icon, a.label, null, danger: a.danger);
    final shown = [for (final a in actions) live(a)];
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: LayoutBuilder(
        builder: (context, c) {
          // Cancel, the count and Select All take about 280 logical pixels
          // and each action button 48; narrower, the actions fold into one
          // menu (one or two still fit on a phone).
          final narrow = c.maxWidth < 280 + 48.0 * shown.length;
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: l.commonCancel,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: busy ? null : onCancel,
                ),
                Flexible(
                  child: Text(
                    l.selectionCount(count),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: AppSpinner.inline(),
                  ),
                if (narrow)
                  IconButton(
                    tooltip: l.selectionSelectAll,
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: busy ? null : onSelectAll,
                  )
                else
                  TextButton(
                    onPressed: busy ? null : onSelectAll,
                    child: Text(l.selectionSelectAll),
                  ),
                if (narrow)
                  PopupMenuButton<VoidCallback?>(
                    tooltip: l.commonMoreOptions,
                    enabled: enabled,
                    onSelected: (run) => run?.call(),
                    itemBuilder: (context) => [
                      for (final a in shown)
                        PopupMenuItem<VoidCallback?>(
                          value: a.run,
                          enabled: a.run != null,
                          child: Row(
                            children: [
                              Icon(
                                a.icon,
                                size: 20,
                                color: a.danger ? theme.colorScheme.error : null,
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  a.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: a.danger
                                      ? TextStyle(color: theme.colorScheme.error)
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                else
                  for (final a in shown)
                    IconButton(
                      tooltip: a.label,
                      icon: Icon(a.icon),
                      color: a.danger ? theme.colorScheme.error : null,
                      onPressed: a.run,
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}
