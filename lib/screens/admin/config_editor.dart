
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/error_text.dart';
import '../../api/jellyfin_client.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/session.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../../widgets/page_width.dart';
import '../../widgets/error_view.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/app_spinner.dart';

/// Shared scaffolding for a server-config editor: loads a config map, gives the
/// subclass a mutable [draft] to bind fields to, and a Save that writes it back.
abstract class ConfigEditorState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  Map<String, dynamic>? draft;
  bool saving = false;
  String? loadError;

  /// The localized AppBar title for this editor.
  String title(AppLocalizations l);

  /// Reads the config section to edit.
  ///
  /// Typed, and subclasses inherit the types: the client's methods are
  /// extensions, which a dynamic call can't reach at runtime.
  Future<Map<String, dynamic>> load(JellyfinClient client, Session session);

  /// Writes the edited config section back.
  Future<void> save(
      JellyfinClient client, Session session, Map<String, dynamic> cfg);

  /// The editor fields, bound to [draft].
  List<Widget> fields(BuildContext context);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final client = ref.read(jellyfinClientProvider);
    if (session == null) return;
    try {
      final cfg = await load(client, session);
      if (mounted) setState(() => draft = cfg);
    } catch (e) {
      if (mounted) setState(() => loadError = errorText(e));
    }
  }

  Future<void> _save() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final client = ref.read(jellyfinClientProvider);
    if (session == null || draft == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final saved = AppLocalizations.of(context).adminSaved;
    setState(() => saving = true);
    try {
      await save(client, session, draft!);
      showSnackOn(messenger, saved, kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title(l))),
      body: loadError != null
          ? ErrorView(message: loadError!, onRetry: () {
              setState(() => loadError = null);
              _load();
            })
          : draft == null
              ? const Center(child: AppSpinner())
              : PageWidth(builder: (_, inset) => ListView(
                  padding: pageInsets(inset, const EdgeInsets.symmetric(vertical: 8)),
                  children: [
                    ...fields(context),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: FilledButton.icon(
                        onPressed: saving ? null : _save,
                        icon: saving
                            ? AppSpinner.inline()
                            : const Icon(Icons.save_rounded),
                        label: Text(l.commonSave),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                )),
    );
  }

  // ---- field builders shared by the editors ----

  Widget textField(String key, String label, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextFormField(
        initialValue: '${draft![key] ?? ''}',
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) => draft![key] = v,
      ),
    );
  }

  Widget intField(String key, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextFormField(
        initialValue: '${draft![key] ?? ''}',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null) draft![key] = n;
        },
      ),
    );
  }

  Widget switchField(String key, String label, {String? subtitle}) {
    return SwitchListTile(
      title: Text(label),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: draft![key] == true,
      onChanged: (v) => setState(() => draft![key] = v),
    );
  }

  Widget dropdownField(
      String key, String label, Map<String, String> options) {
    final current = '${draft![key] ?? options.keys.first}';
    final value = options.containsKey(current) ? current : options.keys.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final e in options.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) setState(() => draft![key] = v);
        },
      ),
    );
  }

  /// A comma-separated list of strings stored as a JSON array (e.g. known
  /// proxies, LAN subnets, published URIs).
  Widget strListField(String key, String label, {String? hint}) {
    final current = (draft![key] as List?)?.join(', ') ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextFormField(
        initialValue: current,
        decoration: InputDecoration(
            labelText: label, hintText: hint, border: const OutlineInputBorder()),
        onChanged: (v) {
          draft![key] = v
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        },
      ),
    );
  }

  Widget sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700)),
      );

  // ---- variants that bind to a nested config object rather than draft ----

  Widget switchFieldIn(Map<String, dynamic> m, String key, String label,
      {String? subtitle}) {
    return SwitchListTile(
      title: Text(label),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: m[key] == true,
      onChanged: (v) => setState(() => m[key] = v),
    );
  }

  Widget intFieldIn(Map<String, dynamic> m, String key, String label,
      {String? hint}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextFormField(
        initialValue: '${m[key] ?? ''}',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
            labelText: label, hintText: hint, border: const OutlineInputBorder()),
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null) m[key] = n;
        },
      ),
    );
  }

  Widget dropdownFieldIn(Map<String, dynamic> m, String key, String label,
      Map<String, String> options) {
    final current = '${m[key] ?? options.keys.first}';
    final value = options.containsKey(current) ? current : options.keys.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final e in options.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) setState(() => m[key] = v);
        },
      ),
    );
  }

  /// A comma-separated list of ints (e.g. trickplay WidthResolutions).
  Widget intListFieldIn(Map<String, dynamic> m, String key, String label,
      {String? hint}) {
    final current = (m[key] as List?)?.join(', ') ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextFormField(
        initialValue: current,
        decoration: InputDecoration(
            labelText: label, hintText: hint, border: const OutlineInputBorder()),
        onChanged: (v) {
          final list = v
              .split(',')
              .map((e) => int.tryParse(e.trim()))
              .whereType<int>()
              .toList();
          m[key] = list;
        },
      ),
    );
  }
}
