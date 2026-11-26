import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/app_updates.dart';
import '../state/app_info.dart';
import '../state/installer.dart';
import '../state/preferences.dart';
import '../state/updates.dart';
import '../widgets/page_width.dart';
import '../widgets/app_spinner.dart';

/// In-app update checking: shows the current version, the release channel, and
/// the result of a GitHub Releases check. Phase 1 links out to the release page
/// to download; it does not self-replace the binary.
class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final prefs = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final async = ref.watch(updateControllerProvider);
    final ctrl = ref.read(updateControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.updatesTitle)),
      body: PageWidth(builder: (_, inset) => ListView(
        padding: pageInsets(inset, const EdgeInsets.all(20)),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline_rounded, color: scheme.primary),
            title: Text(l.updateCurrentVersion(
                ref.watch(appVersionProvider).asData?.value ?? '…')),
          ),
          const SizedBox(height: 8),
          Text(l.updateChannelLabel,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                  value: 'stable',
                  label: Text(l.updateChannelStable),
                  icon: const Icon(Icons.verified_outlined)),
              ButtonSegment(
                  value: 'beta',
                  label: Text(l.updateChannelBeta),
                  icon: const Icon(Icons.science_outlined)),
            ],
            selected: {prefs.updateChannel},
            onSelectionChanged: (s) async {
              await ref
                  .read(preferencesProvider.notifier)
                  .edit((x) => x.copyWith(updateChannel: s.first));
              await ctrl.check(force: true);
            },
          ),
          const SizedBox(height: 6),
          Text(l.updateChannelHelp,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.updateAutoCheckLabel),
            value: prefs.updateCheckOnStartup,
            onChanged: (v) => ref
                .read(preferencesProvider.notifier)
                .edit((x) => x.copyWith(updateCheckOnStartup: v)),
          ),
          if (prefs.updateCheckOnStartup) ...[
            const SizedBox(height: 8),
            Text(l.updateFrequencyLabel,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                    value: 'launch', label: Text(l.updateFrequencyLaunch)),
                ButtonSegment(
                    value: 'daily', label: Text(l.updateFrequencyDaily)),
                ButtonSegment(
                    value: 'weekly', label: Text(l.updateFrequencyWeekly)),
              ],
              selected: {prefs.updateCheckFrequency},
              onSelectionChanged: (s) => ref
                  .read(preferencesProvider.notifier)
                  .edit((x) => x.copyWith(updateCheckFrequency: s.first)),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: async.isLoading ? null : () => ctrl.check(force: true),
            icon: async.isLoading
                ? AppSpinner.inline()
                : const Icon(Icons.refresh_rounded),
            label: Text(async.isLoading ? l.updateChecking : l.updateCheckNow),
          ),
          const SizedBox(height: 20),
          _result(context, ref, l, scheme, async),
        ],
      )),
    );
  }

  Widget _result(BuildContext context, WidgetRef ref, AppLocalizations l,
      ColorScheme scheme, AsyncValue<UpdateStatus?> async) {
    if (async.isLoading) return const SizedBox.shrink();
    if (async.hasError) {
      return Text(l.updateCheckFailedNote,
          style: Theme.of(context).textTheme.bodyMedium);
    }
    final status = async.asData?.value;
    if (status == null) return const SizedBox.shrink();
    final latest = status.latest;
    if (latest == null || !status.updateAvailable) {
      return Row(
        children: [
          Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(l.updateUpToDate,
                  style: Theme.of(context).textTheme.bodyLarge)),
        ],
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.updateAvailableHeadline(latest.version),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (latest.body.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l.updateReleaseNotes,
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: _releaseNotes(context, latest.body),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _actions(context, ref, l, latest),
          ],
        ),
      ),
    );
  }

  /// Install + view actions. Offers in-app "Download & Install" only when the
  /// build can replace itself (AppImage / portable Windows) and the release has
  /// a matching asset; otherwise just links to the release page.
  Widget _actions(BuildContext context, WidgetRef ref, AppLocalizations l,
      GithubRelease latest) {
    final asset = latest.platformAsset;
    final install = ref.watch(installControllerProvider);

    Widget viewOnGitHub({bool filled = true}) {
      final child = Text(l.updateViewOnGitHub);
      void open() => launchUrl(Uri.parse(latest.htmlUrl),
          mode: LaunchMode.externalApplication);
      return filled
          ? FilledButton.icon(
              onPressed: open,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: child)
          : TextButton.icon(
              onPressed: open,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: child);
    }

    if (!canSelfInstall || asset == null) return viewOnGitHub();

    if (install.busy) {
      final pct = (install.progress * 100).clamp(0, 100).toStringAsFixed(0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.updateDownloading(pct),
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: install.progress > 0 ? install.progress : null),
          ),
        ],
      );
    }

    // Stack the buttons full-width in a stretched Column: bare buttons in a Row
    // get unbounded width from the theme's full-width style and don't paint.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (install.error != null) ...[
          Text(l.updateInstallFailed,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.error)),
          // The reason, so a report says more than "it failed".
          SelectableText(install.error!.replaceFirst('Bad state: ', ''),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
        ],
        // Already downloaded (the install screen was left and reopened, say):
        // say so, since tapping it just opens the installer again.
        Builder(builder: (context) {
          final staged = ref
                  .watch(updateStagedProvider(
                      (asset: asset, version: latest.version)))
                  .asData
                  ?.value ??
              false;
          return FilledButton.icon(
            onPressed: () => ref
                .read(installControllerProvider.notifier)
                .install(asset, version: latest.version),
            icon: Icon(
                staged ? Icons.install_mobile_rounded : Icons.download_rounded,
                size: 18),
            label: Text(staged ? l.updateInstallDownloaded : l.updateDownloadInstall),
          );
        }),
        const SizedBox(height: 8),
        viewOnGitHub(filled: false),
      ],
    );
  }

  /// A minimal Markdown renderer for GitHub release notes: turns `#`/`##`/`###`
  /// headings into bold lines, `- `/`* ` into bullets, and strips inline `**`
  /// and backticks. Enough for our notes without pulling in a Markdown package.
  Widget _releaseNotes(BuildContext context, String body) {
    final text = Theme.of(context).textTheme;
    final rows = <Widget>[];
    for (final raw in body.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        rows.add(const SizedBox(height: 8));
        continue;
      }
      if (line.startsWith('###')) {
        rows.add(Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(_clean(line.substring(3)),
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700))));
      } else if (line.startsWith('##')) {
        rows.add(Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Text(_clean(line.substring(2)),
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700))));
      } else if (line.startsWith('#')) {
        rows.add(Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(_clean(line.substring(1)),
                style:
                    text.titleMedium?.copyWith(fontWeight: FontWeight.w800))));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        rows.add(Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: text.bodyMedium),
                Expanded(
                    child: Text(_clean(line.substring(2)),
                        style: text.bodyMedium)),
              ],
            )));
      } else {
        rows.add(Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(_clean(line), style: text.bodyMedium)));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  String _clean(String s) => s.trim().replaceAll('**', '').replaceAll('`', '');
}
