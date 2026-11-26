
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/admin_providers.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/app_spinner.dart';
import '../../api/jellyfin_client.dart';


/// Log files: pick one to view its contents.
class AdminLogsScreen extends ConsumerWidget {
  const AdminLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final logs = ref.watch(adminLogFilesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.adminLogsTitle)),
      body: logs.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => ErrorView(
            message: '$e',
            onRetry: () => ref.invalidate(adminLogFilesProvider)),
        data: (list) => list.isEmpty
            ? EmptyState(icon: Icons.article_outlined, title: l.adminNoLogFiles)
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final l = list[i];
                  final name = '${l['Name'] ?? ''}';
                  final size = (l['Size'] as num?)?.toInt() ?? 0;
                  return ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(name),
                    subtitle: Text('${(size / 1024).toStringAsFixed(1)} KB'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () =>
                        context.push('/admin/logs/view', extra: name),
                  );
                },
              ),
      ),
    );
  }
}

/// Read-only viewer for a single log file.
class AdminLogViewScreen extends ConsumerStatefulWidget {
  final String name;
  const AdminLogViewScreen({super.key, required this.name});
  @override
  ConsumerState<AdminLogViewScreen> createState() => _AdminLogViewState();
}

class _AdminLogViewState extends ConsumerState<AdminLogViewScreen> {
  String? _content;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    try {
      final text = await ref.read(jellyfinClientProvider).getLogContent(
          baseUrl: s.baseUrl, token: s.accessToken, name: widget.name);
      if (mounted) setState(() => _content = text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: () {
              setState(() => _error = null);
              _load();
            })
          : _content == null
              ? const Center(child: AppSpinner())
              : Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        _content!,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ),
                ),
    );
  }
}
