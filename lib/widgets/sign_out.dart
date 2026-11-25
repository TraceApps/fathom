import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/session_controller.dart';
import 'ui_common.dart';

/// Sign Out, wherever it's offered: asked first, since it forgets the
/// account on this device and the way back is typing the password again.
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final session = ref.read(sessionControllerProvider).asData?.value;
  final ok = await confirm(
    context,
    title: l.signOutTitle,
    message: l.signOutBody(
      session?.serverName ?? session?.baseUrl ?? '',
    ),
    confirmLabel: l.commonSignOut,
    destructive: true,
  );
  if (ok) await ref.read(sessionControllerProvider.notifier).signOut();
}
