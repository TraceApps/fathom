import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../api/seerr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../state/preferences.dart';
import '../state/session_controller.dart';
import '../widgets/tv_keyboard.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/tv_focus.dart';
import 'arr_settings_screen.dart';

/// Configure the Seerr connection: an admin API key, or sign in so requests are
/// attributed to you, either with your Jellyfin account or a local Seerr one.
///
/// One of the connections: it opens from the Connections list (beside it, in
/// a wide window) and works as the others do. Save & Test tries the key
/// before saving it, and Disconnect asks first.
class SeerrSettingsScreen extends ConsumerStatefulWidget {
  /// Beside the Connections list, rather than a page of its own.
  final bool embedded;

  /// Saved or signed in, for the list beside it.
  final VoidCallback? onSaved;

  /// Done with it: disconnected.
  final void Function(BuildContext page)? onClose;

  const SeerrSettingsScreen({
    super.key,
    this.embedded = false,
    this.onSaved,
    this.onClose,
  });

  @override
  ConsumerState<SeerrSettingsScreen> createState() =>
      _SeerrSettingsScreenState();
}

class _SeerrSettingsScreenState extends ConsumerState<SeerrSettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  late final TextEditingController _username;
  late final TextEditingController _email;
  late final TextEditingController _password;
  String _mode = 'apikey';
  // Which sign-in method: 'jellyfin' (Jellyfin account) or 'local' (Seerr account).
  String _loginKind = 'jellyfin';
  bool _busy = false;

  /// Opened with nothing saved: the cursor starts on what's left to fill.
  bool _isNew = false;

  /// Why the last Save & Test failed; nothing was saved.
  String? _failed;

  @override
  void initState() {
    super.initState();
    final p = ref.read(preferencesProvider).asData?.value ?? const Prefs();
    // A new one starts on the computer the other apps are on, at Seerr's
    // usual port, as the other connections do.
    _isNew = p.seerrUrl.isEmpty;
    _url = TextEditingController(
      text: _isNew
          ? suggestAddress(connectionsOf(p), ConnApp.seerr)
          : p.seerrUrl,
    );
    _key = TextEditingController(text: p.seerrApiKey);
    // Pre-fill the Jellyfin username from the active session so signing in to
    // Seerr with the Jellyfin account is one password entry away.
    _username = TextEditingController(
        text: ref.read(sessionControllerProvider).asData?.value?.userName ?? '');
    _email = TextEditingController();
    _password = TextEditingController();
    _mode = p.seerrAuthMode;
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// A bare host:port is the usual thing to type.
  String get _address {
    final raw = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    return raw.isEmpty || raw.contains('://') ? raw : 'http://$raw';
  }

  Future<void> _saveApiKey({bool anyway = false}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final url = _address;
    final key = _key.text.trim();
    final lastFailure = _failed;
    if (url.isEmpty || key.isEmpty) {
      showSnack(context, l.arrEnterBoth);
      return;
    }
    _url.text = url;
    setState(() {
      _busy = true;
      _failed = null;
    });
    // Kept before the wait: the page may be left while Seerr answers, and
    // what was asked is still saved.
    final tester = ref.read(connTesterProvider);
    final notifier = ref.read(preferencesProvider.notifier);
    String? version;
    if (!anyway) {
      try {
        version = await tester(ConnApp.seerr, url, '', key);
      } catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _failed = e.toString();
          });
        } else {
          showSnackOn(
            messenger,
            'Seerr: ${l.arrTestFailed(e.toString())}',
            kind: SnackKind.error,
          );
        }
        return;
      }
    }
    await notifier.edit((x) => x.copyWith(
          seerrUrl: url,
          seerrApiKey: key,
          seerrAuthMode: 'apikey',
        ));
    if (mounted) {
      setState(() => _busy = false);
      widget.onSaved?.call();
    }
    showSnackOn(
      messenger,
      version != null
          ? l.arrConnectedTo('Seerr', version)
          : l.arrSavedTestFailed(lastFailure ?? l.arrStatusFailed),
      kind: version != null ? SnackKind.success : SnackKind.info,
    );
  }

  Future<void> _disconnect() async {
    final l = AppLocalizations.of(context);
    if (!await confirmDisconnect(context, 'Seerr') || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(preferencesProvider.notifier).edit((x) => x.copyWith(
          seerrUrl: '',
          seerrApiKey: '',
          seerrCookie: '',
          seerrAuthMode: 'apikey',
        ));
    showSnackOn(messenger, l.arrDisconnected('Seerr'));
    if (!mounted) return;
    _url.clear();
    _key.clear();
    setState(() => _failed = null);
    widget.onClose?.call(context);
  }

  Future<void> _signIn() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final url = _address;
    final local = _loginKind == 'local';
    final user = _username.text.trim();
    final email = _email.text.trim();
    final pass = _password.text;
    if (url.isEmpty || pass.isEmpty || (local ? email.isEmpty : user.isEmpty)) {
      showSnackOn(messenger,
          local ? l.seerrEnterCredentialsLocal : l.seerrEnterCredentials);
      return;
    }
    _url.text = url;
    setState(() => _busy = true);
    final notifier = ref.read(preferencesProvider.notifier);
    try {
      final cookie = local
          ? await seerrLocalLogin(url, email: email, password: pass)
          : await seerrJellyfinLogin(url, username: user, password: pass);
      final name = await SeerrClient(url, '', cookie: cookie).me();
      await notifier.edit((x) => x.copyWith(
            seerrUrl: url,
            seerrAuthMode: 'cookie',
            seerrCookie: cookie,
          ));
      showSnackOn(
        messenger,
        l.seerrSignedInAs(name ?? (local ? email : user)),
        kind: SnackKind.success,
      );
      if (!mounted) return;
      widget.onSaved?.call();
      // Let the password manager offer to save these credentials before we
      // clear the field.
      TextInput.finishAutofillContext();
      _password.clear();
    } catch (e) {
      showErrorOn(messenger, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(preferencesProvider.notifier).edit((x) => x.copyWith(
        seerrAuthMode: 'apikey', seerrCookie: ''));
    if (mounted) {
      final l = AppLocalizations.of(context);
      showSnack(context, l.seerrSignedOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final signedIn = p.seerrAuthMode == 'cookie' && p.seerrCookie.isNotEmpty;
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = findConn(p, ConnApp.seerr, null);
    final check = c != null && c.ready
        ? ref.watch(connCheckProvider(c.check))
        : null;
    final state = c == null ? null : connStateOf(c, check);
    final body = ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Icon(ConnApp.seerr.icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.embedded)
                      Text(
                        'Seerr',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Text(
                      state == ConnState.connected && check?.value != null
                          ? 'Seerr ${check!.value!}'
                          : l.seerrIntro,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (state != null) ...[
                const SizedBox(width: 12),
                ConnStateChip(state),
              ],
            ],
          ),
          if (state == ConnState.failed && check?.error != null) ...[
            const SizedBox(height: 12),
            Text(
              '${check!.error}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 20),
          TvTextField(
            controller: _url,
            keyboardType: TextInputType.url,
            label: l.arrServerAddress,
            hint: 'http://192.168.1.10:5055',
            icon: Icons.link_rounded,
            autofocus: _isNew && _url.text.isEmpty,
          ),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                  value: 'apikey',
                  label: Text(l.seerrApiKeySegment),
                  icon: const Icon(Icons.key_rounded)),
              ButtonSegment(
                  value: 'cookie',
                  label: Text(l.commonSignIn),
                  icon: const Icon(Icons.person_rounded)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 20),
          if (_mode == 'apikey') ...[
            TvTextField(
              controller: _key,
              obscure: true,
              label: l.seerrApiKeyLabel,
              helperText: l.seerrApiKeyHelper,
              icon: Icons.key_rounded,
              autofocus: _isNew && _url.text.isNotEmpty,
              onSubmitted: (_) => _busy ? null : _saveApiKey(),
            ),
            if (_failed != null) ...[
              const SizedBox(height: 16),
              ConnFailedBox(_failed!),
            ],
            const SizedBox(height: 18),
            // As on the other connections: busy, the buttons ignore presses
            // rather than switch off (that drops the TV remote's focus), and
            // they are keyed, as the error above them comes and goes.
            FilledButton(
              key: const ValueKey('save'),
              onPressed: _busy ? () {} : _saveApiKey,
              child: _busy ? _spinner() : Text(l.arrSaveTest),
            ),
            if (_failed != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('anyway'),
                onPressed: _busy ? () {} : () => _saveApiKey(anyway: true),
                child: Text(l.arrSaveAnyway),
              ),
            ],
          ] else ...[
            if (signedIn)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF22C55E)),
                  title: Text(l.seerrSignedIn),
                  subtitle: Text(l.seerrRequestsAttributed),
                  trailing: TextButton(
                      onPressed: _busy ? null : _signOut,
                      child: Text(l.commonSignOut)),
                ),
              )
            else ...[
              _ProviderButton(
                asset: 'assets/jellyfin.svg',
                label: l.seerrLoginWithJellyfin,
                selected: _loginKind == 'jellyfin',
                onTap: () => setState(() => _loginKind = 'jellyfin'),
              ),
              const SizedBox(height: 10),
              _ProviderButton(
                asset: 'assets/seerr.svg',
                label: l.seerrLoginWithSeerr,
                selected: _loginKind == 'local',
                onTap: () => setState(() => _loginKind = 'local'),
              ),
              const SizedBox(height: 18),
              Text(
                  _loginKind == 'local'
                      ? l.seerrLocalSignInHelp
                      : l.seerrSignInHelp,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loginKind == 'local')
                      TvTextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        label: l.seerrEmailLabel,
                        autofillHints: const [AutofillHints.email],
                        icon: Icons.alternate_email_rounded,
                      )
                    else
                      TvTextField(
                        controller: _username,
                        label: l.seerrUsernameLabel,
                        autofillHints: const [AutofillHints.username],
                        icon: Icons.person_outline_rounded,
                      ),
                    const SizedBox(height: 14),
                    TvTextField(
                      controller: _password,
                      obscure: true,
                      label: l.seerrPasswordLabel,
                      autofillHints: const [AutofillHints.password],
                      icon: Icons.lock_outline_rounded,
                      onSubmitted: (_) => _busy ? null : _signIn(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _signIn,
                child: _busy ? _spinner() : Text(l.commonSignIn),
              ),
            ],
          ],
          if (c != null) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            TvFocusRing(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.link_off_rounded,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  l.arrDisconnect,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                enabled: !_busy,
                onTap: _disconnect,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            l.arrKeysStayHere,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
    );
    // The same form width as the other connections.
    final page = TvFocusKeeper(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: body,
        ),
      ),
    );
    if (widget.embedded) return page;
    return Scaffold(
      appBar: AppBar(title: const Text('Seerr')),
      body: page,
    );
  }

  Widget _spinner() => AppSpinner.inline();
}

/// A sign-in method choice, branded with the provider's logo tinted to the
/// theme accent. Selected state is shown with an accent border, wash, and tick.
class _ProviderButton extends StatelessWidget {
  final String asset;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ProviderButton({
    required this.asset,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                asset,
                width: 22,
                height: 22,
                colorFilter:
                    ColorFilter.mode(scheme.primary, BlendMode.srcIn),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded,
                    color: scheme.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
