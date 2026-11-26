import '../widgets/page_width.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/preferences.dart';

/// The customisable player actions, in display order, with localized labels.
List<(String, String)> _actions(AppLocalizations l) => <(String, String)>[
      ('playPause', l.shortcutsPlayPause),
      ('seekBackward', l.shortcutsSeekBackward),
      ('seekForward', l.shortcutsSeekForward),
      ('volumeUp', l.shortcutsVolumeUp),
      ('volumeDown', l.shortcutsVolumeDown),
      ('mute', l.shortcutsMute),
      ('fullscreen', l.shortcutsFullscreen),
    ];

/// A readable label for a LogicalKeyboardKey id.
String _keyLabel(int id) {
  final key = LogicalKeyboardKey(id);
  if (key.keyLabel.isNotEmpty) return key.keyLabel;
  return key.debugName ?? 'Key';
}

/// View and customise player keyboard shortcuts.
class KeyboardShortcutsScreen extends ConsumerWidget {
  const KeyboardShortcutsScreen({super.key});

  Future<void> _rebind(
      BuildContext context, WidgetRef ref, String action) async {
    final key = await showDialog<LogicalKeyboardKey>(
      context: context,
      builder: (_) => const _KeyCaptureDialog(),
    );
    if (key == null) return;
    final p = ref.read(preferencesProvider).asData?.value ?? const Prefs();
    ref.read(preferencesProvider.notifier).edit(
        (x) => x.copyWith(keyBindings: {...p.keyBindings, action: key.keyId}));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final keys = p.effectiveKeys;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.shortcutsTitle),
        actions: [
          if (p.keyBindings.isNotEmpty)
            TextButton(
              onPressed: () => ref
                  .read(preferencesProvider.notifier)
                  .edit((x) => x.copyWith(keyBindings: {})),
              child: Text(l.commonReset),
            ),
        ],
      ),
      body: PageWidth(builder: (c, inset) => ListView(
        padding: pageInsetsSafe(c, inset),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(l.shortcutsHelp),
          ),
          for (final (id, label) in _actions(l))
            ListTile(
              title: Text(label),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_keyLabel(keys[id]!),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              onTap: () => _rebind(context, ref, id),
            ),
        ],
      )),
    );
  }
}

/// Captures the next key press and returns it.
class _KeyCaptureDialog extends StatelessWidget {
  const _KeyCaptureDialog();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.shortcutsPressKey),
      content: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            // Ignore modifier-only presses.
            final k = event.logicalKey;
            if (k == LogicalKeyboardKey.shiftLeft ||
                k == LogicalKeyboardKey.controlLeft ||
                k == LogicalKeyboardKey.altLeft ||
                k == LogicalKeyboardKey.metaLeft) {
              return KeyEventResult.handled;
            }
            Navigator.pop(context, k);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SizedBox(
          height: 60,
          child: Center(child: Text(l.shortcutsWaiting)),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.commonCancel)),
      ],
    );
  }
}
