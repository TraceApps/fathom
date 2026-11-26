import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/diagnostics.dart';
import '../state/app_info.dart';
import '../state/preferences.dart';
import '../state/session_controller.dart';
import '../widgets/page_width.dart';
import '../widgets/app_snack.dart';

/// App-wide troubleshooting. Turning on Diagnostic Logging records global
/// errors, app logs, and (during playback) a verbose libmpv trace into one
/// buffer the user can copy into a bug report. Lives under Settings > About
/// because it is not specific to any one feature.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final prefs = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final c = ref.read(preferencesProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.diagnosticsTitle)),
      body: PageWidth(builder: (_, inset) => ListView(
        padding: pageInsets(inset, const EdgeInsets.all(20)),
        children: [
          Text(l.diagnosticsIntro,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.bug_report_rounded),
                  title: Text(l.prefsDiagnosticLogging),
                  subtitle: Text(l.prefsDiagnosticLoggingSub),
                  value: prefs.diagnosticLogging,
                  onChanged: (v) {
                    Diagnostics.instance.enabled = v;
                    c.edit((x) => x.copyWith(diagnosticLogging: v));
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.content_copy_rounded),
                  title: Text(l.prefsCopyDiagnostics),
                  subtitle: Text(l.prefsCopyDiagnosticsSub),
                  onTap: () => _copy(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(l.diagnosticsClear),
                  onTap: () {
                    Diagnostics.instance.clear();
                    showSnack(context, l.diagnosticsCleared,
                        kind: SnackKind.success);
                  },
                ),
              ],
            ),
          ),
        ],
      )),
    );
  }

  Future<void> _copy(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final mediaEvents = await _androidMediaEvents();
    if (Diagnostics.instance.isEmpty && mediaEvents.isEmpty) {
      showSnackOn(messenger, l.prefsDiagnosticsEmpty);
      return;
    }
    final version = ref.read(appVersionProvider).asData?.value ?? '?';
    final session = ref.read(sessionControllerProvider).asData?.value;
    final prefs = ref.read(preferencesProvider).asData?.value;
    final report = Diagnostics.instance.report({
      'App version': version,
      'Server': session?.serverName ?? '(none)',
      'Server address': session?.baseUrl ?? '(none)',
      'Display sync': prefs?.displaySync ?? false,
      'Hardware decoding': prefs?.hardwareDecoding ?? true,
    });
    // What Android handed Fathom's playback service (notification, lock screen,
    // earbud and headset presses), recorded natively whether or not diagnostic
    // logging is on. Nothing here for a press means Android sent it elsewhere.
    final text = mediaEvents.isEmpty
        ? report
        : '$report\n--- Android media commands (${mediaEvents.length}) ---\n'
            '${mediaEvents.join('\n')}\n';
    await Clipboard.setData(ClipboardData(text: text));
    showSnackOn(messenger, l.prefsDiagnosticsCopied, kind: SnackKind.success);
  }

  static Future<List<String>> _androidMediaEvents() async {
    if (!Platform.isAndroid) return const [];
    try {
      return await const MethodChannel('app.fathom.player/pip')
              .invokeListMethod<String>('mediaEvents') ??
          const [];
    } catch (_) {
      return const [];
    }
  }
}
