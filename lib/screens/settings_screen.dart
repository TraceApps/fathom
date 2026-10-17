import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/session.dart';
import '../services/tv_mode.dart';
import '../state/app_info.dart';
import '../state/preferences.dart';
import '../state/session_controller.dart';
import '../widgets/app_logo.dart';
import '../widgets/search_field.dart';
import '../widgets/tv_keyboard.dart';
import '../widgets/user_avatar.dart';
import 'settings_search.dart';
import 'support_screen.dart';

/// The form factor this build is running on, for the About row's pill. Not
/// localized — these are platform proper nouns (Android TV, Windows, …). TV is a
/// runtime distinction from plain Android (same APK).
String platformLabel() {
  if (isTvDevice) return 'Android TV';
  if (Platform.isAndroid) return 'Android';
  if (Platform.isWindows) return 'Windows';
  if (Platform.isLinux) return 'Linux';
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isIOS) return 'iOS';
  return 'Unknown';
}

/// Account, server, and app info, plus a search box that jumps straight to any
/// setting. A home for future prefs (playback, subtitles, theme).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _open(SettingResult r) {
    // Clear the search so returning here lands on the full hub, then navigate.
    setState(() {
      _query = '';
      _searchCtrl.clear();
    });
    context.push(r.route, extra: r.extra);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final theme = Theme.of(context);
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              controller: _searchCtrl,
              hint: l.settingsSearchHint,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: searching
                ? _results(context)
                : ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: _hub(context, session, theme),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _results(BuildContext context) {
    final results = searchSettings(userSettingsIndex(AppLocalizations.of(context)), _query);
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
              AppLocalizations.of(context).settingsNoMatch(_query.trim()),
              style: TextStyle(color: Theme.of(context).hintColor)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final r = results[i];
        return ListTile(
          leading: _leading(context, r.icon),
          title: Text(r.title),
          subtitle: Text(r.section),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _open(r),
        );
      },
    );
  }

  List<Widget> _hub(
      BuildContext context, dynamic session, ThemeData theme) {
    final l = AppLocalizations.of(context);
    final version = ref.watch(appVersionProvider).asData?.value ?? '…';
    return [
      _sectionLabel(context, l.settingsSectionPreferences),
      ListTile(
        leading: _leading(context, Icons.settings_rounded),
        title: Text(l.settingsGeneral),
        subtitle: Text(l.settingsGeneralSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/preferences', extra: 'general'),
      ),
      ListTile(
        leading: _leading(context, Icons.palette_outlined),
        title: Text(l.settingsAppearance),
        subtitle: Text(l.settingsAppearanceSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/preferences', extra: 'appearance'),
      ),
      ListTile(
        leading: _leading(context, Icons.dashboard_outlined),
        title: Text(l.settingsHome),
        subtitle: Text(l.settingsHomeSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/preferences', extra: 'home'),
      ),
      ListTile(
        leading: _leading(context, Icons.play_circle_outline_rounded),
        title: Text(l.settingsPlayer),
        subtitle: Text(l.settingsPlayerSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/preferences', extra: 'player'),
      ),
      ListTile(
        leading: _leading(context, Icons.subtitles_outlined),
        title: Text(l.settingsAudioSubtitles),
        subtitle: Text(l.settingsAudioSubtitlesSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/preferences', extra: 'audio'),
      ),
      ListTile(
        leading: _leading(context, Icons.star_half_rounded),
        title: Text(l.settingsRatings),
        subtitle: Text(l.settingsRatingsSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/preferences', extra: 'ratings'),
      ),
      // Desktop only: a phone/tablet has no hardware keyboard to bind, and a
      // TV remote's few buttons aren't rebindable keys either.
      if (!Platform.isAndroid && !Platform.isIOS)
        ListTile(
          leading: _leading(context, Icons.keyboard_rounded),
          title: Text(l.settingsShortcuts),
          subtitle: Text(l.settingsShortcutsSubtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push('/shortcuts'),
        ),
      const Divider(height: 24),
      _sectionLabel(context, l.settingsSectionIntegrations),
      ListTile(
        leading: _leading(context, Icons.travel_explore_rounded),
        title: Text(l.settingsSeerr),
        subtitle: Text(l.settingsSeerrSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/seerr-settings'),
      ),
      ListTile(
        leading: _leading(context, Icons.smart_display_rounded),
        title: Text(l.settingsYouTube),
        subtitle: Text(l.settingsYouTubeSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/preferences', extra: 'youtube'),
      ),
      SwitchListTile(
        secondary: _leading(context, Icons.radio_rounded),
        title: Text(l.settingsRadio),
        subtitle: Text(l.settingsRadioSubtitle),
        value: ref.watch(preferencesProvider
            .select((p) => p.asData?.value.radioEnabled ?? false)),
        onChanged: (v) => ref
            .read(preferencesProvider.notifier)
            .edit((x) => x.copyWith(radioEnabled: v)),
      ),
      SwitchListTile(
        secondary: _leading(context, Icons.groups_rounded),
        title: Text(l.settingsWatchTogether),
        subtitle: Text(l.settingsWatchTogetherSubtitle),
        value: ref.watch(preferencesProvider
            .select((p) => p.asData?.value.syncPlayEnabled ?? true)),
        onChanged: (v) => ref
            .read(preferencesProvider.notifier)
            .edit((x) => x.copyWith(syncPlayEnabled: v)),
      ),
      SwitchListTile(
        secondary: _leading(context, Icons.movie_filter_rounded),
        title: Text(l.settingsMovieWheel),
        subtitle: Text(l.settingsMovieWheelSubtitle),
        value: ref.watch(preferencesProvider
            .select((p) => p.asData?.value.movieWheelEnabled ?? true)),
        onChanged: (v) => ref
            .read(preferencesProvider.notifier)
            .edit((x) => x.copyWith(movieWheelEnabled: v)),
      ),
      const Divider(height: 24),
      _sectionLabel(context, l.settingsSectionAccount),
      ListTile(
        leading: const UserAvatar(radius: 22),
        title: Text(session?.userName ?? '—'),
        subtitle: Text(l.settingsProfileSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/profile'),
      ),
      ListTile(
        leading: _leading(context, Icons.switch_account_rounded),
        title: Text(l.settingsAccounts),
        subtitle: Text(l.settingsAccountsSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/accounts'),
      ),
      _serverTile(context, session as Session?, theme),
      const Divider(height: 24),
      _sectionLabel(context, l.settingsSectionSystem),
      ListTile(
        leading: _leading(context, Icons.system_update_alt_rounded),
        title: Text(l.settingsUpdates),
        subtitle: Text(l.settingsUpdatesSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/updates'),
      ),
      ListTile(
        leading: _leading(context, Icons.settings_backup_restore_rounded),
        title: Text(l.settingsBackup),
        subtitle: Text(l.settingsBackupSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/backup'),
      ),
      ListTile(
        leading: _leading(context, Icons.bug_report_rounded),
        title: Text(l.diagnosticsTitle),
        subtitle: Text(l.diagnosticsSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/diagnostics'),
      ),
      const Divider(height: 24),
      _sectionLabel(context, l.settingsSectionAbout),
      ListTile(
        leading: const SizedBox(
            width: 38, height: 38, child: FathomLogo(size: 38)),
        title: Text(l.appName),
        // Who makes it, as a byline under the name, as Periscope's About has it.
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              link: true,
              child: InkWell(
                onTap: SupportScreen.openTraceApps,
                borderRadius: BorderRadius.circular(4),
                child: Text(l.settingsFromTraceApps),
              ),
            ),
            const SizedBox(height: 2),
            Text(l.settingsVersion(version)),
          ],
        ),
        // A pill naming the platform this build runs on (Fladder-style), so a
        // tester can tell at a glance which form factor they're on — Android TV
        // and plain Android share one APK but read differently here.
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            platformLabel(),
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
      ListTile(
        leading: _leading(context, Icons.volunteer_activism_rounded),
        title: Text(l.settingsSupport),
        subtitle: Text(l.settingsSupportSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/support'),
      ),
      ListTile(
        leading: _leading(context, Icons.description_outlined),
        title: Text(l.settingsLicenses),
        subtitle: Text(l.settingsLicensesSubtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showLicensePage(
          context: context,
          applicationName: l.appName,
          applicationVersion: version,
          applicationIcon: const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 48, height: 48, child: FathomLogo(size: 48)),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: OutlinedButton.icon(
          onPressed: () =>
              ref.read(sessionControllerProvider.notifier).signOut(),
          icon: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
          label: Text(l.settingsSignOut,
              style: TextStyle(color: theme.colorScheme.error)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: BorderSide(color: theme.colorScheme.error),
          ),
        ),
      ),
    ];
  }

  /// The Server row: current address plus, when both Home and Remote are
  /// configured, a live badge for which one the app is actually on right now.
  /// The resolver mutates the session's baseUrl, so this updates automatically.
  Widget _serverTile(BuildContext context, Session? s, ThemeData theme) {
    final l = AppLocalizations.of(context);
    final scheme = theme.colorScheme;
    // Only when BOTH addresses are set is "Home vs Remote" meaningful.
    String? label;
    if (s != null && s.internalUrl != null && s.externalUrl != null) {
      if (s.baseUrl == s.internalUrl) {
        label = l.serverAddressHome;
      } else if (s.baseUrl == s.externalUrl) {
        label = l.serverAddressRemote;
      }
    }
    final url = s?.baseUrl ?? '—';
    return ListTile(
      leading: _leading(context, Icons.dns_rounded),
      title: Text(s?.serverName ?? l.settingsServer),
      // Inline rich text so the address shows in full and wraps (with the pill
      // flowing after it) instead of hard-truncating; only clips past 2 lines,
      // which realistically only a very long DNS on a narrow phone would hit.
      subtitle: label == null
          ? Text(url)
          : Text.rich(
              TextSpan(children: [
                TextSpan(text: url),
                const WidgetSpan(child: SizedBox(width: 8)),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(label,
                        style: TextStyle(
                            color: scheme.primary,
                            fontSize: 11,
                            height: 1.0,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: s == null ? null : () => _editServerAddresses(context, s),
    );
  }

  /// Edit the active account's home (internal) and remote (external) addresses.
  /// The resolver then keeps the app on whichever is reachable.
  Future<void> _editServerAddresses(
      BuildContext context, Session session) async {
    final l = AppLocalizations.of(context);
    final internalCtrl =
        TextEditingController(text: session.internalUrl ?? '');
    final externalCtrl = TextEditingController(
        text: session.externalUrl ?? session.baseUrl);
    String clean(String s) => s.trim().replaceAll(RegExp(r'/+$'), '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.serverAddressesTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TvTextField(
                controller: internalCtrl,
                keyboardType: TextInputType.url,
                label: l.serverAddressInternalLabel,
                hint: l.serverAddressInternalHint,
                icon: Icons.home_rounded,
              ),
              const SizedBox(height: 14),
              TvTextField(
                controller: externalCtrl,
                keyboardType: TextInputType.url,
                label: l.serverAddressExternalLabel,
                hint: l.serverAddressExternalHint,
                icon: Icons.public_rounded,
              ),
              const SizedBox(height: 16),
              Text(l.serverAddressHelp,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonSave)),
        ],
      ),
    );

    if (saved == true) {
      final internal = clean(internalCtrl.text);
      final external = clean(externalCtrl.text);
      await ref.read(sessionControllerProvider.notifier).setServerAddresses(
            internal: internal.isEmpty ? null : internal,
            external: external.isEmpty ? session.baseUrl : external,
          );
    }
    internalCtrl.dispose();
    externalCtrl.dispose();
  }

  /// A tinted rounded-square icon for settings rows (a more finished, app-like
  /// look than a bare glyph).
  Widget _leading(BuildContext context, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: scheme.primary, size: 21),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700)),
      );
}
