import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/tv_keyboard.dart';
import '../api/error_text.dart';
import '../l10n/generated/app_localizations.dart';
import '../state/library_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/user_avatar.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/ui_common.dart';
import '../api/jellyfin_client.dart';

/// The signed-in user's profile: large avatar with change / remove actions.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _busy = false;

  Future<void> _changePhoto() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final user = ref.read(currentUserProvider).asData?.value;
    if (session == null || user == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final bytes = await file.readAsBytes();

    final ext = (file.extension ?? 'jpg').toLowerCase();
    final mime = switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

    setState(() => _busy = true);
    try {
      await ref.read(jellyfinClientProvider).uploadUserImage(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            userId: user.id,
            bytes: bytes,
            contentType: mime,
          );
      ref.invalidate(currentUserProvider);
      showSnackOn(messenger, l.profilePictureUpdated, kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final user = ref.read(currentUserProvider).asData?.value;
    if (session == null || user == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(jellyfinClientProvider).deleteUserImage(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            userId: user.id,
          );
      ref.invalidate(currentUserProvider);
      showSnackOn(messenger, l.profilePictureRemoved, kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Self-service password change for the signed-in user. Sends the current
  /// password (CurrentPw) so the server can verify it; it rejects a wrong
  /// current password or an account where self-service changes are disabled,
  /// and the error is surfaced in the dialog.
  Future<void> _changePassword() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final user = ref.read(currentUserProvider).asData?.value;
    if (session == null || user == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        String? error;
        var submitting = false;
        return StatefulBuilder(
          builder: (ctx, setSt) {
            Widget field(String label, TextEditingController c) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TvField(child: TextField(
                    controller: c,
                    obscureText: true,
                    autofillHints: const [],
                    decoration: InputDecoration(
                        labelText: label, border: const OutlineInputBorder()),
                  )),
                );
            Future<void> submit() async {
              if (newCtrl.text != confirmCtrl.text) {
                setSt(() => error = l.profilePasswordMismatch);
                return;
              }
              // An empty new password is allowed (the same "remove password"
              // the official Jellyfin clients offer) for a regular user, but
              // Jellyfin's server flatly refuses it for an administrator
              // account, so catch that here instead of a round-trip 400.
              if (newCtrl.text.isEmpty && user.isAdministrator) {
                setSt(() => error = l.profileAdminNeedsPassword);
                return;
              }
              if (newCtrl.text.isEmpty) {
                final confirmed = await confirm(ctx,
                    title: l.profileNoPasswordTitle,
                    message: l.profileNoPasswordBody,
                    confirmLabel: l.profileNoPasswordConfirm,
                    destructive: true);
                if (!confirmed) return;
              }
              setSt(() {
                submitting = true;
                error = null;
              });
              try {
                await ref.read(jellyfinClientProvider).setUserPassword(
                      baseUrl: session.baseUrl,
                      token: session.accessToken,
                      userId: user.id,
                      currentPassword: currentCtrl.text,
                      newPassword: newCtrl.text,
                    );
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                setSt(() {
                  submitting = false;
                  error = errorText(e);
                });
              }
            }

            return AlertDialog(
              title: Text(l.profileChangePassword),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  field(l.profileCurrentPassword, currentCtrl),
                  field(l.profileNewPassword, newCtrl),
                  field(l.profileConfirmPassword, confirmCtrl),
                  if (error != null)
                    Text(error!,
                        style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      submitting ? null : () => Navigator.pop(ctx, false),
                  child: Text(l.commonCancel),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? AppSpinner.inline()
                      : Text(l.commonSave),
                ),
              ],
            );
          },
        );
      },
    );
    disposeAfterDialog([currentCtrl, newCtrl, confirmCtrl]);
    if (ok == true) {
      showSnackOn(messenger, l.profilePasswordChanged);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final user = ref.watch(currentUserProvider).asData?.value;
    final hasPhoto = user?.primaryImageTag != null;

    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.profileTitle)),
      body: Stack(
        children: [
          // Ambient accent band behind the avatar.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 240,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.primary.withValues(alpha: 0.22),
                    scheme.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Center(
        // The app's buttons stretch to their row: with no room either side
        // they ran edge to edge of the screen.
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.5), width: 3),
                    boxShadow: [
                      BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.3),
                          blurRadius: 30,
                          spreadRadius: 2),
                    ],
                  ),
                  child: const UserAvatar(radius: 64),
                ),
                Material(
                  color: Theme.of(context).colorScheme.primary,
                  shape: const CircleBorder(),
                  child: Semantics(button: true, label: AppLocalizations.of(context).profileChangePhoto, child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _busy ? null : _changePhoto,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.photo_camera_rounded,
                          size: 20,
                          color: Theme.of(context).colorScheme.onPrimary),
                    ),
                  )),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(user?.name ?? session?.userName ?? '-',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(session?.serverName ?? '',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 28),
            if (_busy)
              const AppSpinner()
            else ...[
              FilledButton.icon(
                onPressed: _changePhoto,
                icon: const Icon(Icons.upload_rounded),
                label: Text(l.profileChangePhoto),
              ),
              if (hasPhoto)
                TextButton.icon(
                  onPressed: _removePhoto,
                  icon: Icon(Icons.delete_outline_rounded,
                      color: Theme.of(context).colorScheme.error),
                  label: Text(l.profileRemovePhoto,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _changePassword,
              icon: const Icon(Icons.password_rounded),
              label: Text(l.profileChangePassword),
            ),
          ],
        ),
        ),
        ),
          ),
        ],
      ),
    );
  }
}
