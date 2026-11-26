import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/error_text.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/admin_providers.dart';
import '../../state/library_providers.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../../widgets/page_width.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/tv_keyboard.dart';
import '../../widgets/ui_common.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/app_spinner.dart';
import '../../api/jellyfin_client.dart';


/// Plugins: installed extensions, the catalog from configured repositories, and
/// repository management.
class AdminPluginsScreen extends StatelessWidget {
  const AdminPluginsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.adminPluginsTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l.adminTabInstalled),
              Tab(text: l.adminTabCatalog),
              Tab(text: l.adminTabRepositories),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _InstalledPlugins(),
            _PluginCatalog(),
            _PluginRepositories(),
          ],
        ),
      ),
    );
  }
}

class _InstalledPlugins extends ConsumerWidget {
  const _InstalledPlugins();

  Future<void> _uninstall(
      BuildContext context, WidgetRef ref, String id, String name) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirm(context,
        title: l.adminUninstallConfirm(name),
        message: l.adminUninstallBody,
        confirmLabel: l.adminUninstall,
        destructive: true);
    if (!ok) return;
    try {
      await ref.read(jellyfinClientProvider).uninstallPlugin(
          baseUrl: s.baseUrl, token: s.accessToken, pluginId: id);
      ref.invalidate(adminPluginsProvider);
      showSnackOn(messenger, l.adminUninstalledPlugin(name));
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final plugins = ref.watch(adminPluginsProvider);
    // Watched once here (not inside itemBuilder, which runs lazily outside build).
    final pkgs = ref.watch(adminPackagesProvider).asData?.value;
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final client = ref.watch(jellyfinClientProvider);
    final headers = ref.watch(imageHeadersProvider);
    return plugins.when(
      loading: () => const Center(child: AppSpinner()),
      error: (e, _) => ErrorView(
          message: errorText(e), onRetry: () => ref.invalidate(adminPluginsProvider)),
      data: (list) => list.isEmpty
          ? EmptyState(icon: Icons.extension_rounded, title: l.adminNoPlugins)
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(adminPluginsProvider),
              child: PageWidth(builder: (c, inset) => ListView.separated(
                padding: pageInsetsSafe(c, inset),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final p = list[i];
                  final id = '${p['Id'] ?? ''}';
                  final name = '${p['Name'] ?? '-'}';
                  return ListTile(
                    leading: _pluginLogo(
                      context,
                      catalogUrl:
                          _pluginCatalogImageUrl(pkgs, guid: id, name: name),
                      serverUrl: session != null && id.isNotEmpty
                          ? client.pluginImageUrl(
                              baseUrl: session.baseUrl,
                              pluginId: id,
                              version: p['Version'] as String?)
                          : null,
                      headers: headers,
                      height: 40,
                      radius: 8,
                      maxWidth: 84,
                    ),
                    title: Text(name),
                    subtitle: Text('v${p['Version'] ?? '?'}'
                        '${p['Status'] != null ? '  ·  ${p['Status']}' : ''}'),
                    trailing: IconButton(
                      tooltip: l.adminUninstall,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: id.isEmpty
                          ? null
                          : () => _uninstall(context, ref, id, name),
                    ),
                    onTap: () =>
                        context.push('/admin/plugins/installed', extra: p),
                  );
                },
              )),
            ),
    );
  }
}

class _PluginCatalog extends ConsumerWidget {
  const _PluginCatalog();

  Future<void> _install(BuildContext context, WidgetRef ref,
      String name, String guid) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(jellyfinClientProvider).installPackage(
          baseUrl: s.baseUrl, token: s.accessToken, name: name, guid: guid);
      ref.invalidate(adminPluginsProvider);
      showSnackOn(messenger, l.adminInstallingPlugin(name));
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final packages = ref.watch(adminPackagesProvider);
    return packages.when(
      loading: () => const Center(child: AppSpinner()),
      error: (e, _) => ErrorView(
          message: errorText(e), onRetry: () => ref.invalidate(adminPackagesProvider)),
      data: (list) => list.isEmpty
          ? Center(
              child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                  l.adminNoPackages,
                  textAlign: TextAlign.center),
            ))
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(adminPackagesProvider),
              child: PageWidth(builder: (c, inset) => ListView.separated(
                padding: pageInsetsSafe(c, inset),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final p = list[i];
                  final name = '${p['name'] ?? '-'}';
                  final guid = '${p['guid'] ?? ''}';
                  final overview = '${p['overview'] ?? p['description'] ?? ''}';
                  final imageUrl = '${p['imageUrl'] ?? ''}';
                  return ListTile(
                    leading: SizedBox(
                      width: 40,
                      height: 40,
                      child: imageUrl.isEmpty
                          ? _pluginPlaceholder(context)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, _, _) =>
                                      _pluginPlaceholder(context)),
                            ),
                    ),
                    title: Text(name),
                    subtitle: overview.isEmpty
                        ? Text('${p['category'] ?? ''}')
                        : Text(overview,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: TextButton(
                      onPressed: guid.isEmpty
                          ? null
                          : () => _install(context, ref, name, guid),
                      child: Text(l.adminInstall),
                    ),
                    onTap: () =>
                        context.push('/admin/plugins/package', extra: p),
                  );
                },
              )),
            ),
    );
  }
}

class _PluginRepositories extends ConsumerWidget {
  const _PluginRepositories();

  Future<void> _save(BuildContext context, WidgetRef ref,
      List<Map<String, dynamic>> repos) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(jellyfinClientProvider).setRepositories(
          baseUrl: s.baseUrl, token: s.accessToken, repositories: repos);
      ref.invalidate(adminRepositoriesProvider);
      ref.invalidate(adminPackagesProvider);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref,
      List<Map<String, dynamic>> current) async {
    final l = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminAddRepository),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvTextField(
              controller: nameCtrl,
              autofocus: true,
              label: l.adminName,
            ),
            const SizedBox(height: 12),
            TvTextField(
              controller: urlCtrl,
              label: l.adminManifestUrl,
              hint: 'https://.../manifest.json',
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonAdd)),
        ],
      ),
    );
    if (ok != true || urlCtrl.text.trim().isEmpty) return;
    final next = [
      ...current,
      {
        'Name': nameCtrl.text.trim(),
        'Url': urlCtrl.text.trim(),
        'Enabled': true,
      },
    ];
    if (context.mounted) await _save(context, ref, next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repos = ref.watch(adminRepositoriesProvider);
    return repos.when(
      loading: () => const Center(child: AppSpinner()),
      error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(adminRepositoriesProvider)),
      data: (list) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _add(context, ref, list),
          icon: const Icon(Icons.add_rounded),
          label: Text(l.adminAddRepository),
        ),
        body: list.isEmpty
            ? EmptyState(icon: Icons.source_rounded, title: l.adminNoRepositories)
            : PageWidth(builder: (c, inset) => ListView.separated(
                padding: pageInsetsSafe(c, inset),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final r = list[i];
                  return ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: Text('${r['Name'] ?? r['Url'] ?? '-'}'),
                    subtitle: Text('${r['Url'] ?? ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: l.commonRemove,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () {
                        final next = [...list]..removeAt(i);
                        _save(context, ref, next);
                      },
                    ),
                  );
                },
              )),
      ),
    );
  }
}

/// Detail for an installed plugin: art, version, status, and (for plugins that
/// expose one) a raw configuration editor, plus uninstall.
class AdminInstalledPluginScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> plugin;
  const AdminInstalledPluginScreen({super.key, required this.plugin});
  @override
  ConsumerState<AdminInstalledPluginScreen> createState() =>
      _AdminInstalledPluginState();
}

class _AdminInstalledPluginState
    extends ConsumerState<AdminInstalledPluginScreen> {
  // Live copy of the plugin's config, edited in place by the form. Dart Maps
  // keep insertion order, so fields render in the plugin's own order.
  Map<String, dynamic> _cfg = {};
  final _json = TextEditingController(); // raw-JSON fallback editor
  // Text controllers for text/number/nested-JSON fields, and the per-list
  // "add" inputs — keyed by config key so they survive rebuilds.
  final Map<String, TextEditingController> _fieldCtrls = {};
  final Map<String, TextEditingController> _addCtrls = {};
  bool _configLoaded = false;
  bool _hasConfig = false;
  bool _saving = false;
  bool _rawMode = false;

  String get _id => '${widget.plugin['Id'] ?? ''}';
  String get _name => '${widget.plugin['Name'] ?? 'Plugin'}';

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _json.dispose();
    for (final c in _fieldCtrls.values) {
      c.dispose();
    }
    for (final c in _addCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null || _id.isEmpty) {
      setState(() => _configLoaded = true);
      return;
    }
    try {
      final cfg = await ref.read(jellyfinClientProvider).getPluginConfiguration(
          baseUrl: s.baseUrl, token: s.accessToken, pluginId: _id);
      if (!mounted) return;
      setState(() {
        _cfg = cfg;
        _hasConfig = cfg.isNotEmpty;
        _json.text = const JsonEncoder.withIndent('  ').convert(cfg);
        _configLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _configLoaded = true);
    }
  }

  /// Turns a PascalCase / camelCase config key into a readable label, e.g.
  /// "SettledSeasonDelayHours" → "Settled Season Delay Hours".
  String _humanize(String key) {
    final spaced = key
        .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ')
        .replaceAllMapped(RegExp(r'(?<=[A-Z])(?=[A-Z][a-z])'), (_) => ' ');
    if (spaced.isEmpty) return key;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  TextEditingController _ctrl(String key, String initial) =>
      _fieldCtrls.putIfAbsent(key, () => TextEditingController(text: initial));

  /// Switches between the typed form and the raw-JSON editor, carrying edits
  /// across in both directions.
  void _toggleRaw(bool raw) {
    if (raw) {
      _json.text = const JsonEncoder.withIndent('  ').convert(_cfg);
    } else {
      try {
        _cfg = Map<String, dynamic>.from(jsonDecode(_json.text) as Map);
      } catch (_) {
        showSnack(context, AppLocalizations.of(context).adminInvalidJson);
        return;
      }
      // Rebuild field controllers from the (possibly) new values.
      for (final c in _fieldCtrls.values) {
        c.dispose();
      }
      _fieldCtrls.clear();
    }
    setState(() => _rawMode = raw);
  }

  Future<void> _saveConfig() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Map<String, dynamic> parsed;
    if (_rawMode) {
      try {
        parsed = Map<String, dynamic>.from(jsonDecode(_json.text) as Map);
      } catch (_) {
        showSnackOn(messenger, l.adminInvalidJson);
        return;
      }
    } else {
      parsed = _cfg;
    }
    setState(() => _saving = true);
    try {
      await ref.read(jellyfinClientProvider).updatePluginConfiguration(
          baseUrl: s.baseUrl,
          token: s.accessToken,
          pluginId: _id,
          config: parsed);
      showSnackOn(messenger, l.adminSaved, kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- Typed field builders -------------------------------------------------

  Widget _configForm(ThemeData theme, AppLocalizations l) {
    final entries = _cfg.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries) ...[
          _field(theme, l, e.key, e.value),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _field(ThemeData theme, AppLocalizations l, String key, dynamic value) {
    final label = _humanize(key);
    if (value is bool) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label),
        value: value,
        onChanged: (v) => setState(() => _cfg[key] = v),
      );
    }
    if (value is num) {
      final c = _ctrl(key, '$value');
      return TvField(child: TextField(
        controller: c,
        keyboardType:
            TextInputType.numberWithOptions(decimal: value is double),
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        onChanged: (t) {
          final n = value is int ? int.tryParse(t) : num.tryParse(t);
          if (n != null) _cfg[key] = n;
        },
      ));
    }
    if (value is String) {
      final c = _ctrl(key, value);
      return TvField(child: TextField(
        controller: c,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        onChanged: (t) => _cfg[key] = t,
      ));
    }
    if (value is List &&
        value.every((e) => e is String || e is num || e is bool)) {
      return _listField(theme, l, key, label, value);
    }
    // Nested object or complex list → edit as JSON inline.
    return _jsonField(theme, l, key, label);
  }

  Widget _listField(ThemeData theme, AppLocalizations l, String key,
      String label, List<dynamic> list) {
    final add = _addCtrls.putIfAbsent(key, () => TextEditingController());
    void addEntry() {
      final t = add.text.trim();
      if (t.isEmpty) return;
      setState(() {
        list.add(t);
        add.clear();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(l.adminNoEntries,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (var i = 0; i < list.length; i++)
                InputChip(
                  label: Text('${list[i]}'),
                  onDeleted: () => setState(() => list.removeAt(i)),
                ),
            ],
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TvField(child: TextField(
                controller: add,
                decoration: const InputDecoration(
                    isDense: true, border: OutlineInputBorder()),
                onSubmitted: (_) => addEntry(),
              )),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: addEntry, child: Text(l.commonAdd)),
          ],
        ),
      ],
    );
  }

  Widget _jsonField(
      ThemeData theme, AppLocalizations l, String key, String label) {
    final c = _ctrl(
        key, const JsonEncoder.withIndent('  ').convert(_cfg[key]));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        Text(l.adminAdvancedJson,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        TvField(child: TextField(
          controller: c,
          minLines: 2,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (t) {
            try {
              _cfg[key] = jsonDecode(t);
            } catch (_) {
              // Keep the last valid value until the JSON parses again.
            }
          },
        )),
      ],
    );
  }

  Future<void> _uninstall() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final ok = await confirm(context,
        title: l.adminUninstallConfirm(_name),
        message: l.adminUninstallBody,
        confirmLabel: l.adminUninstall,
        destructive: true);
    if (!ok) return;
    try {
      await ref.read(jellyfinClientProvider).uninstallPlugin(
          baseUrl: s.baseUrl, token: s.accessToken, pluginId: _id);
      ref.invalidate(adminPluginsProvider);
      showSnackOn(messenger, l.adminUninstalledPlugin(_name));
      nav.pop();
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(sessionControllerProvider).asData?.value;
    final headers = ref.watch(imageHeadersProvider);
    final client = ref.watch(jellyfinClientProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_name)),
      body: PageWidth(builder: (_, inset) => ListView(
        padding: pageInsets(inset, const EdgeInsets.all(20)),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _pluginLogo(
                context,
                catalogUrl: _pluginCatalogImageUrl(
                    ref.watch(adminPackagesProvider).asData?.value,
                    guid: _id,
                    name: _name),
                serverUrl: s != null && _id.isNotEmpty
                    ? client.pluginImageUrl(
                        baseUrl: s.baseUrl,
                        pluginId: _id,
                        version: widget.plugin['Version'] as String?)
                    : null,
                headers: headers,
                height: 84,
                radius: 14,
                maxWidth: 220,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                        l.adminPluginVersion(
                            '${widget.plugin['Version'] ?? '?'}'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    if (widget.plugin['Status'] != null)
                      Text('${widget.plugin['Status']}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          if ('${widget.plugin['Description'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('${widget.plugin['Description']}',
                style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 24),
          if (!_configLoaded)
            const Center(child: AppSpinner())
          else if (_hasConfig) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_rawMode ? l.adminConfigJson : l.adminPluginSettings,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        _rawMode
                            ? l.adminConfigJsonHint
                            : l.adminPluginSettingsHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.adminEditAsJson,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    Switch(value: _rawMode, onChanged: _toggleRaw),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_rawMode)
              TvField(child: TextField(
                controller: _json,
                minLines: 6,
                maxLines: 24,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ))
            else
              _configForm(theme, l),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _saveConfig,
              icon: _saving
                  ? AppSpinner.inline()
                  : const Icon(Icons.save_rounded),
              label: Text(l.adminSaveConfiguration),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ] else
            Text(l.adminNoEditableConfig,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _id.isEmpty ? null : _uninstall,
            icon: Icon(Icons.delete_outline_rounded,
                color: theme.colorScheme.error),
            label: Text(l.adminUninstall,
                style: TextStyle(color: theme.colorScheme.error)),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: BorderSide(color: theme.colorScheme.error)),
          ),
        ],
      )),
    );
  }
}

Widget _pluginPlaceholder(BuildContext context) => Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.extension_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
    );

/// The plugin's logo from the repository catalog (what the Jellyfin dashboard
/// shows), matched to an installed plugin by GUID then name. Returns null if
/// the catalog isn't loaded or has no image for it.
String? _pluginCatalogImageUrl(List<dynamic>? pkgs,
    {String? guid, String? name}) {
  if (pkgs == null) return null;
  final g = guid?.replaceAll('-', '').toLowerCase();
  if (g != null && g.isNotEmpty) {
    for (final p in pkgs) {
      final m = p as Map;
      if ('${m['guid'] ?? ''}'.replaceAll('-', '').toLowerCase() == g) {
        final img = '${m['imageUrl'] ?? ''}';
        return img.isEmpty ? null : img;
      }
    }
  }
  if (name != null && name.isNotEmpty) {
    final n = name.toLowerCase();
    for (final p in pkgs) {
      final m = p as Map;
      if ('${m['name'] ?? ''}'.toLowerCase() == n) {
        final img = '${m['imageUrl'] ?? ''}';
        return img.isEmpty ? null : img;
      }
    }
  }
  return null;
}

/// A plugin logo sized to the image itself (fixed [height], natural width) with
/// rounded corners — the catalog logos carry their own background, so we hug
/// the image rather than pad it inside a big tile. Falls back catalog → server
/// thumb → a small rounded puzzle square.
Widget _pluginLogo(
  BuildContext context, {
  required String? catalogUrl,
  required String? serverUrl,
  required Map<String, String> headers,
  required double height,
  double radius = 12,
  double? maxWidth,
}) {
  final cs = Theme.of(context).colorScheme;
  Widget placeholder() => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: height,
          height: height,
          color: cs.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(Icons.extension_rounded,
              color: cs.onSurfaceVariant, size: height * 0.55),
        ),
      );
  Widget net(String url,
      {Map<String, String>? h, required Widget Function() onErr}) {
    Widget image = Image.network(url,
        height: height,
        fit: BoxFit.contain,
        headers: h,
        errorBuilder: (_, _, _) => onErr());
    if (maxWidth != null) {
      image = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth), child: image);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
  if (catalogUrl != null && catalogUrl.isNotEmpty) {
    return net(catalogUrl,
        onErr: () => (serverUrl != null && serverUrl.isNotEmpty)
            ? net(serverUrl, h: headers, onErr: placeholder)
            : placeholder());
  }
  if (serverUrl != null && serverUrl.isNotEmpty) {
    return net(serverUrl, h: headers, onErr: placeholder);
  }
  return placeholder();
}

/// Detail for a catalog package: art, overview, versions, and install.
class AdminPackageScreen extends ConsumerWidget {
  final Map<String, dynamic> package;
  const AdminPackageScreen({super.key, required this.package});

  Future<void> _install(BuildContext context, WidgetRef ref,
      {String? version}) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(jellyfinClientProvider).installPackage(
            baseUrl: s.baseUrl,
            token: s.accessToken,
            name: '${package['name'] ?? ''}',
            guid: '${package['guid'] ?? ''}',
            version: version,
          );
      ref.invalidate(adminPluginsProvider);
      showSnackOn(messenger, l.adminInstallingPlugin('${package['name']}'));
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = '${package['name'] ?? 'Plugin'}';
    final imageUrl = '${package['imageUrl'] ?? ''}';
    final overview = '${package['overview'] ?? package['description'] ?? ''}';
    final versions = (package['versions'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: PageWidth(builder: (_, inset) => ListView(
        padding: pageInsets(inset, const EdgeInsets.all(20)),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: imageUrl.isEmpty
                      ? _pluginPlaceholder(context)
                      : Image.network(imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, _, _) =>
                              _pluginPlaceholder(context)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    if ('${package['owner'] ?? ''}'.isNotEmpty)
                      Text(l.adminPackageBy('${package['owner']}'),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    if ('${package['category'] ?? ''}'.isNotEmpty)
                      Text('${package['category']}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _install(context, ref),
            icon: const Icon(Icons.download_rounded),
            label: Text(l.adminInstallLatest),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          if (overview.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(overview, style: theme.textTheme.bodyMedium),
          ],
          if (versions.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(l.adminVersions,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            for (final v in versions.whereType<Map>())
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${v['version'] ?? '?'}'),
                subtitle: '${v['changelog'] ?? ''}'.isEmpty
                    ? null
                    : Text('${v['changelog']}',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: TextButton(
                  onPressed: () => _install(context, ref,
                      version: '${v['version'] ?? ''}'),
                  child: Text(l.adminInstall),
                ),
              ),
          ],
        ],
      )),
    );
  }
}
