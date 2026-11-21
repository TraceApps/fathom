import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/seerr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/seerr_detail.dart';
import '../models/seerr_request.dart';
import '../state/seerr_providers.dart';
import 'app_snack.dart';
import 'seerr_avatar.dart';
import 'seerr_edit_request_dialog.dart';
import 'ui_common.dart';

/// Opens Jellyseerr's "Manage Movie/Series" panel as a right-docked sheet:
/// per-request approve/decline/edit plus the Advanced actions (mark available,
/// clear data). Only meaningful for a user with the Manage Requests permission;
/// the caller is expected to gate on that before opening.
Future<void> showSeerrManageDialog(BuildContext context, SeerrDetail detail) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppLocalizations.of(context).detailDismiss,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => Align(
      alignment: Alignment.centerRight,
      child: _ManageSheet(
        mediaType: detail.mediaType,
        tmdbId: detail.tmdbId,
        title: detail.title,
      ),
    ),
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .animate(curved),
        child: child,
      );
    },
  );
}

class _ManageSheet extends ConsumerStatefulWidget {
  final String mediaType;
  final int tmdbId;
  final String title;
  const _ManageSheet(
      {required this.mediaType, required this.tmdbId, required this.title});

  @override
  ConsumerState<_ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends ConsumerState<_ManageSheet> {
  bool _busy = false;

  ({String mediaType, int tmdbId}) get _key =>
      (mediaType: widget.mediaType, tmdbId: widget.tmdbId);

  /// Refresh the detail (so this sheet's own request list updates) and every
  /// list that shows request/availability state.
  void _invalidate() {
    ref.invalidate(seerrDetailProvider(_key));
    ref.invalidate(seerrRequestsProvider);
    ref.invalidate(seerrRecentRequestsProvider);
    ref.invalidate(seerrPendingRequestsProvider);
    ref.invalidate(seerrTrendingProvider);
    ref.invalidate(seerrMoviesProvider);
    ref.invalidate(seerrTvProvider);
    ref.invalidate(seerrSearchProvider);
    ref.invalidate(seerrRecentlyAddedProvider);
  }

  Future<void> _run(
      Future<void> Function(SeerrClient c) action, String done) async {
    final client = ref.read(seerrClientProvider);
    if (client == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action(client);
      _invalidate();
      if (mounted) showSnack(context, done, kind: SnackKind.success);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) =>
      confirm(context,
          title: title,
          message: message,
          confirmLabel: action,
          destructive: true);

  Future<void> _edit(SeerrRequest r) async {
    final ok = await showSeerrEditRequestDialog(context, r);
    if (ok) _invalidate();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final kind = widget.mediaType == 'tv' ? l.detailSeries : l.detailMovie;
    final kindLower = widget.mediaType == 'tv'
        ? l.detailKindSeriesLower
        : l.detailKindMovieLower;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detail = ref.watch(seerrDetailProvider(_key)).asData?.value;
    final requests = detail?.requests ?? const <SeerrRequest>[];
    final mediaId = detail?.mediaId;
    final width = math.min(MediaQuery.sizeOf(context).width * 0.94, 440.0);
    final canAct = mediaId != null && !_busy;

    return Material(
      color: scheme.surface,
      elevation: 12,
      child: SafeArea(
        left: false,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.detailManageKind(kind),
                              style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary)),
                          const SizedBox(height: 2),
                          Text(widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: AppLocalizations.of(context).commonClose,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  children: [
                    if (requests.isNotEmpty) ...[
                      _heading(theme, l.detailRequests),
                      const SizedBox(height: 12),
                      for (final r in requests) ...[
                        _RequestRow(
                          request: r,
                          busy: _busy,
                          onApprove: () => _run((c) => c.approveRequest(r.id),
                              l.detailApprovedTitle(widget.title)),
                          onDecline: () => _run((c) => c.declineRequest(r.id),
                              l.detailDeclinedTitle(widget.title)),
                          onEdit: () => _edit(r),
                          onRetry: () => _run((c) => c.retryRequest(r.id),
                              l.detailRetryingTitle(widget.title)),
                          onDelete: () async {
                            if (await _confirm(l.detailDeleteRequest,
                                l.detailRemoveRequestConfirm, l.commonDelete)) {
                              await _run((c) => c.deleteRequest(r.id),
                                  l.detailDeletedRequestTitle(widget.title));
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 16),
                    ],
                    _heading(theme, l.detailAdvanced),
                    const SizedBox(height: 12),
                    _BigAction(
                      color: const Color(0xFF22C55E),
                      icon: Icons.check_circle_rounded,
                      label: l.detailMarkAvailable,
                      onTap: canAct
                          ? () => _run(
                              (c) => c.setMediaStatus(mediaId, 'available'),
                              l.detailMarkedAvailableTitle(widget.title))
                          : null,
                    ),
                    const SizedBox(height: 10),
                    _BigAction(
                      color: scheme.error,
                      icon: Icons.delete_forever_rounded,
                      label: l.detailClearData,
                      onTap: canAct
                          ? () async {
                              final nav = Navigator.of(context);
                              final ok = await _confirm(
                                l.detailClearData,
                                l.detailClearDataConfirm(kindLower),
                                l.detailClearData,
                              );
                              if (!ok) return;
                              await _run((c) => c.clearMediaData(mediaId),
                                  l.detailClearedDataTitle(widget.title));
                              if (mounted) nav.pop();
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.detailClearDataNote(kindLower),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(ThemeData theme, String text) => Text(text,
      style:
          theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800));
}

/// A single request inside the Manage sheet: requester + status on top, action
/// buttons (approve/decline/edit for a pending one, otherwise remove) opposite,
/// and the requested date beneath.
class _RequestRow extends ConsumerWidget {
  final SeerrRequest request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDecline;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRetry;
  const _RequestRow({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onDecline,
    required this.onEdit,
    required this.onDelete,
    required this.onRetry,
  });

  (String, Color) _status(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = request;
    if (r.isDeclined) {
      return (l.detailStatusDeclined, Theme.of(context).colorScheme.error);
    }
    if (r.isFailed) return (l.detailStatusFailed, const Color(0xFFEF4444));
    if (r.isPending) return (l.detailStatusPending, const Color(0xFFF59E0B));
    return (l.detailStatusApproved, const Color(0xFF22C55E));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = request;
    final (label, color) = _status(context);
    final baseUrl = ref.read(seerrClientProvider)?.baseUrl ?? '';
    final name = r.requestedBy ?? l.detailSomeone;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    SeerrAvatar(
                      name: name,
                      avatarUrl: seerrAvatarUrl(baseUrl, r.requestedByAvatar),
                      radius: 12,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (r.isPending) ...[
                _SquareBtn(
                    color: const Color(0xFF22C55E),
                    icon: Icons.check_rounded,
                    tooltip: l.detailApprove,
                    onTap: busy ? null : onApprove),
                const SizedBox(width: 6),
                _SquareBtn(
                    color: scheme.error,
                    icon: Icons.close_rounded,
                    tooltip: l.detailDecline,
                    onTap: busy ? null : onDecline),
                const SizedBox(width: 6),
                _SquareBtn(
                    color: const Color(0xFFCA8A04),
                    icon: Icons.edit_rounded,
                    tooltip: l.commonEdit,
                    onTap: busy ? null : onEdit),
              ] else ...[
                if (r.isFailed) ...[
                  _SquareBtn(
                      color: scheme.primary,
                      icon: Icons.refresh_rounded,
                      tooltip: l.commonRetry,
                      onTap: busy ? null : onRetry),
                  const SizedBox(width: 6),
                ],
                _SquareBtn(
                    color: scheme.error,
                    icon: Icons.delete_outline_rounded,
                    tooltip: l.detailDeleteRequestTooltip,
                    onTap: busy ? null : onDelete),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(20)),
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
              if (r.mediaType == 'tv' && r.seasons.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(l.detailSeasonList(r.seasons.join(', ')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ],
              const Spacer(),
              if (_fmtDate(r.createdAt) case final date?) ...[
                Icon(Icons.calendar_today_rounded,
                    size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(date,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SquareBtn extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _SquareBtn(
      {required this.color,
      required this.icon,
      required this.tooltip,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onTap == null ? color.withValues(alpha: 0.4) : color,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 34,
            child: Icon(icon, color: Colors.white, size: 19),
          ),
        ),
      ),
    );
  }
}

class _BigAction extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _BigAction(
      {required this.color,
      required this.icon,
      required this.label,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// "July 21, 2026" from an ISO string, or null when unparseable.
String? _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final d = DateTime.tryParse(iso);
  if (d == null) return null;
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}
