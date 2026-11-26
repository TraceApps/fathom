import 'package:flutter/material.dart';
import '../api/error_text.dart';

/// The tone of a snackbar, which picks its icon and accent.
enum SnackKind { info, success, error }

/// App-wide messenger key. Attached to [MaterialApp.router] so code with no
/// BuildContext (background notification handlers fired from providers) can
/// still surface the same in-app snackbar via [showGlobalSnack].
final globalScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

SnackBar _buildSnack(
  BuildContext context,
  String message,
  SnackKind kind, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  final scheme = Theme.of(context).colorScheme;
  final (IconData icon, Color color) = switch (kind) {
    SnackKind.success => (Icons.check_circle_rounded, scheme.primary),
    SnackKind.error => (Icons.error_rounded, scheme.error),
    SnackKind.info => (Icons.info_rounded, scheme.primary),
  };
  return SnackBar(
    duration: duration ??
        (kind == SnackKind.error
            ? const Duration(seconds: 5)
            : const Duration(seconds: 3)),
    content: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ],
    ),
    // Load-bearing. Flutter defaults persist to `action != null`
    // (snack_bar.dart: `persist = persist ?? action != null`), so an offer to
    // undo would otherwise sit there until it's taken or the route is gone.
    persist: false,
    action: (actionLabel != null && onAction != null)
        ? SnackBarAction(label: actionLabel, onPressed: onAction)
        : null,
  );
}

/// One consistent snackbar for the whole app: an icon + tone, an optional
/// action, and sensible durations. Replaces scattered raw
/// `ScaffoldMessenger...showSnackBar(SnackBar(content: Text(...)))` calls so
/// feedback looks and behaves the same everywhere. Clears any current snackbar
/// first so they don't stack.
void showSnack(
  BuildContext context,
  String message, {
  SnackKind kind = SnackKind.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(_buildSnack(context, message, kind,
        actionLabel: actionLabel, onAction: onAction, duration: duration));
}

/// The same styled snackbar, for the common pattern of grabbing the messenger
/// *before* an await and showing the result after it (where the original
/// BuildContext may no longer be mounted).
void showSnackOn(
  ScaffoldMessengerState messenger,
  String message, {
  SnackKind kind = SnackKind.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  if (!messenger.mounted) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(_buildSnack(messenger.context, message, kind,
        actionLabel: actionLabel, onAction: onAction, duration: duration));
}

/// [showSnackOn] for the common error case.
void showErrorOn(ScaffoldMessengerState messenger, Object error,
        {String? prefix}) =>
    showSnackOn(messenger,
        prefix == null ? errorText(error) : '$prefix: ${errorText(error)}',
        kind: SnackKind.error);

/// The same styled snackbar, fired through the app-wide messenger so it works
/// without a BuildContext (e.g. a notification arriving while the app is
/// focused). No-op if the messenger isn't mounted yet.
void showGlobalSnack(String message, {SnackKind kind = SnackKind.info}) {
  final messenger = globalScaffoldMessengerKey.currentState;
  final context = messenger?.context;
  if (messenger == null || context == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(_buildSnack(context, message, kind));
}

/// Convenience for the common error case.
void showError(BuildContext context, Object error, {String? prefix}) {
  final msg = errorText(error);
  showSnack(context, prefix == null ? msg : '$prefix: $msg',
      kind: SnackKind.error);
}
