import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// Settings > Support. The only place the app asks for support: no banners,
/// popups or reminders anywhere else. Money and free ways to help share the
/// page, so everyone who opens it has something to do. Same layout as the
/// Support page in the Trace apps.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  /// Who makes Fathom ("from TraceApps", in About).
  static const traceApps = 'https://traceapps.github.io/docs/';
  static const _kofi = 'https://ko-fi.com/traceapps';
  static const _sponsors = 'https://github.com/sponsors/TraceApps?metadata_app=fathom&metadata_from=app';
  static const _repo = 'https://github.com/TraceApps/fathom';
  static const _newIssue = 'https://github.com/TraceApps/fathom/issues/new/choose';
  static const _translate =
      'https://traceapps.github.io/fathom/contributing/#translations';

  static void _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  static void openTraceApps() => _open(traceApps);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsSupport)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.volunteer_activism_rounded,
                      color: scheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.supportLead, style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SupportLinkButton(
                              icon: Icons.local_cafe_rounded,
                              label: 'Ko-fi',
                              onPressed: () => _open(_kofi),
                            ),
                            _SupportLinkButton(
                              icon: Icons.favorite_rounded,
                              label: l.settingsSponsor,
                              onPressed: () => _open(_sponsors),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(l.supportOtherWays,
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.primary, fontWeight: FontWeight.w700)),
                ),
                _HelpTile(
                  icon: Icons.star_rounded,
                  title: l.supportStar,
                  subtitle: l.supportStarSubtitle,
                  onTap: () => _open(_repo),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _HelpTile(
                  icon: Icons.bug_report_rounded,
                  title: l.supportReportBug,
                  subtitle: l.supportReportBugSubtitle,
                  onTap: () => _open(_newIssue),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _HelpTile(
                  icon: Icons.translate_rounded,
                  title: l.supportTranslate,
                  subtitle: l.supportTranslateSubtitle,
                  onTap: () => _open(_translate),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportLinkButton extends StatelessWidget {
  const _SupportLinkButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      // The theme's outlined buttons are full width; these two sit side by side.
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(
            fontFamily: kAppFontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  const _HelpTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.open_in_new_rounded,
          size: 18, color: scheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
