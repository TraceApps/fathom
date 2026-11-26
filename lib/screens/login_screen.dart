import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/error_text.dart';
import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/authentication_result.dart';
import '../models/server_connection.dart';
import '../models/session.dart';
import '../services/tv_mode.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/error_banner.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_keyboard.dart';
import '../widgets/app_spinner.dart';

/// Step 2 of sign-in: authenticate against the connected server.
class LoginScreen extends ConsumerStatefulWidget {
  final ServerConnection connection;
  const LoginScreen({super.key, required this.connection});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _qcLoading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final l = AppLocalizations.of(context);
    if (!isTvDevice) FocusScope.of(context).unfocus();
    if (_userCtrl.text.trim().isEmpty) {
      setState(() => _error = l.appEnterUsername);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(jellyfinClientProvider);
      final auth = await client.authenticateByName(
        baseUrl: widget.connection.baseUrl,
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
      );
      await _completeSession(auth);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = l.appUnexpectedError(errorText(e)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Turns an authentication result (from a password or Quick Connect) into a
  /// stored session and enters the app.
  Future<void> _completeSession(AuthenticationResult auth) async {
    final session = Session(
      baseUrl: widget.connection.baseUrl,
      accessToken: auth.accessToken,
      userId: auth.user.id,
      userName: auth.user.name,
      serverName: widget.connection.serverName,
      serverId: auth.serverId,
      isAdmin: auth.user.isAdministrator,
      canDelete: auth.user.enableContentDeletion || auth.user.isAdministrator,
    );
    await ref.read(sessionControllerProvider.notifier).signIn(session);
    // Commit the autofill context so the OS/password manager offers to save the
    // credentials just entered. No-op for the Quick Connect path (no fields).
    TextInput.finishAutofillContext();
    if (mounted) context.go('/home');
  }

  Future<void> _quickConnect() async {
    final l = AppLocalizations.of(context);
    if (!isTvDevice) FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _qcLoading = true;
    });
    final client = ref.read(jellyfinClientProvider);
    final baseUrl = widget.connection.baseUrl;
    try {
      if (!await client.quickConnectEnabled(baseUrl)) {
        if (mounted) {
          setState(() => _error = l.appQuickConnectNotEnabled);
        }
        return;
      }
      final init = await client.quickConnectInitiate(baseUrl);
      if (!mounted) return;
      final auth = await showDialog<AuthenticationResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _QuickConnectDialog(
          baseUrl: baseUrl,
          code: init.code,
          secret: init.secret,
        ),
      );
      if (auth != null) await _completeSession(auth);
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = l.appUnexpectedError(errorText(e)));
    } finally {
      if (mounted) setState(() => _qcLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final serverLabel = widget.connection.serverName ?? widget.connection.baseUrl;
    return Scaffold(
      appBar: AppBar(elevation: 0),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.commonSignIn,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.dns_rounded,
                        size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(serverLabel,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                // On TV the system keyboard can't be driven by the remote, so use
                // the D-pad-friendly TvTextField (focusable tile -> on-screen
                // keyboard sheet). Elsewhere keep the native fields inside an
                // AutofillGroup so password managers treat them as one login.
                if (isTvDevice) ...[
                  TvTextField(
                    controller: _userCtrl,
                    label: l.appUsername,
                    icon: Icons.person_outline_rounded,
                    enabled: !_loading,
                    autofocus: true,
                  ),
                  const SizedBox(height: 14),
                  TvTextField(
                    controller: _passCtrl,
                    label: l.appPassword,
                    icon: Icons.lock_outline_rounded,
                    obscure: true,
                    enabled: !_loading,
                  ),
                ] else
                  AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _userCtrl,
                          autofocus: true,
                          enabled: !_loading,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: l.appUsername,
                            prefixIcon:
                                const Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passCtrl,
                          enabled: !_loading,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _loading ? null : _signIn(),
                          decoration: InputDecoration(
                            labelText: l.appPassword,
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscure ? AppLocalizations.of(context).loginShowPassword : AppLocalizations.of(context).loginHidePassword,
                              icon: Icon(_obscure
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  ErrorBanner(_error!),
                ],
                const SizedBox(height: 24),
                TvFocusAura(
                  builder: (node) => FilledButton(
                    focusNode: node,
                    onPressed: _loading ? null : _signIn,
                    child: _loading
                        ? AppSpinner.inline()
                        : Text(l.commonSignIn),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Divider(color: scheme.outlineVariant)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(l.appOr,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                    Expanded(child: Divider(color: scheme.outlineVariant)),
                  ],
                ),
                const SizedBox(height: 12),
                TvFocusAura(
                  builder: (node) => OutlinedButton.icon(
                    focusNode: node,
                    onPressed: (_loading || _qcLoading) ? null : _quickConnect,
                    icon: _qcLoading
                        ? AppSpinner.inline()
                        : const Icon(Icons.qr_code_2_rounded),
                    label: Text(l.appUseQuickConnect),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the Quick Connect code and polls until the user approves it on an
/// already-signed-in device, then pops with the resulting authentication.
class _QuickConnectDialog extends ConsumerStatefulWidget {
  final String baseUrl;
  final String code;
  final String secret;
  const _QuickConnectDialog({
    required this.baseUrl,
    required this.code,
    required this.secret,
  });

  @override
  ConsumerState<_QuickConnectDialog> createState() =>
      _QuickConnectDialogState();
}

class _QuickConnectDialogState extends ConsumerState<_QuickConnectDialog> {
  Timer? _timer;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    final client = ref.read(jellyfinClientProvider);
    try {
      final approved =
          await client.quickConnectPoll(widget.baseUrl, widget.secret);
      if (!approved) {
        _busy = false;
        return;
      }
      final auth = await client.authenticateWithQuickConnect(
        baseUrl: widget.baseUrl,
        secret: widget.secret,
      );
      _timer?.cancel();
      if (mounted) Navigator.of(context).pop(auth);
    } on JellyfinException catch (e) {
      _timer?.cancel();
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.appQuickConnect),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error == null) ...[
            Text(
              l.appQuickConnectInstructions,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SelectableText(
              widget.code,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 10,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppSpinner.inline(),
                const SizedBox(width: 12),
                Text(l.appWaitingForApproval,
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ] else
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_error == null ? l.commonCancel : l.commonClose),
        ),
      ],
    );
  }
}
