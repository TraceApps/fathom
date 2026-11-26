import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/error_text.dart';
import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/server_connection.dart';
import '../services/server_discovery.dart';
import '../services/tv_mode.dart';
import '../state/providers.dart';
import '../widgets/app_logo.dart';
import '../widgets/error_banner.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_keyboard.dart';
import '../widgets/app_spinner.dart';

/// Step 1 of sign-in: enter a server address and validate it's a live
/// Jellyfin server before asking for credentials.
class ServerConnectScreen extends ConsumerStatefulWidget {
  const ServerConnectScreen({super.key});

  @override
  ConsumerState<ServerConnectScreen> createState() =>
      _ServerConnectScreenState();
}

class _ServerConnectScreenState extends ConsumerState<ServerConnectScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _scanning = false;
  List<DiscoveredServer> _found = const [];
  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Broadcasts for Jellyfin servers on the LAN and shows what answers, so the
  /// user (especially on a TV with no keyboard) can pick their server instead of
  /// typing an address.
  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    final servers = await discoverJellyfinServers();
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _scanned = true;
      _found = servers;
    });
  }

  /// Connects straight to a discovered server (its Address already carries the
  /// scheme + port).
  Future<void> _connectTo(DiscoveredServer server) async {
    _controller.text = server.address;
    await _connect();
  }

  Future<void> _connect() async {
    final l = AppLocalizations.of(context);
    if (!isTvDevice) FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(jellyfinClientProvider);
      // Resolves the scheme automatically (tries https then http) so a LAN
      // address like 10.0.1.3:8096 works without typing http://.
      final resolved = await client.resolvePublicServer(_controller.text);
      if (!mounted) return;
      context.push(
        '/login',
        extra: ServerConnection(
          baseUrl: resolved.baseUrl,
          serverName: resolved.info.serverName,
          serverId: resolved.info.id,
          version: resolved.info.version,
        ),
      );
    } on JellyfinException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = l.appUnexpectedError(errorText(e)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FathomLogo(size: 64),
                const SizedBox(height: 16),
                Text('Fathom',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(l.appConnectToServer,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant)),
                const SizedBox(height: 32),
                TvTextField(
                  controller: _controller,
                  label: l.appServerAddress,
                  hint: 'jellyfin.example.com',
                  icon: Icons.dns_rounded,
                  keyboardType: TextInputType.url,
                  enabled: !_loading,
                  autofocus: true,
                  onSubmitted: (_) => _loading ? null : _connect(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  ErrorBanner(_error!),
                ],
                const SizedBox(height: 20),
                TvFocusAura(
                  builder: (node) => FilledButton(
                    focusNode: node,
                    onPressed: _loading ? null : _connect,
                    child: _loading
                        ? AppSpinner.inline()
                        : Text(l.appConnect),
                  ),
                ),
                const SizedBox(height: 12),
                TvFocusAura(
                  builder: (node) => OutlinedButton.icon(
                    focusNode: node,
                    onPressed:
                        (_loading || _scanning) ? null : _scan,
                    icon: _scanning
                        ? AppSpinner.inline()
                        : const Icon(Icons.wifi_find_rounded),
                    label: Text(
                        _scanning ? l.appScanningServers : l.appFindServers),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                if (_found.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  for (final s in _found)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TvFocusable(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _connectTo(s),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading:
                                const Icon(Icons.dns_rounded),
                            title: Text(s.name),
                            subtitle: Text(s.address),
                            trailing:
                                const Icon(Icons.chevron_right_rounded),
                            onTap: () => _connectTo(s),
                          ),
                        ),
                      ),
                    ),
                ] else if (_scanned && !_scanning) ...[
                  const SizedBox(height: 12),
                  Text(l.appNoServersFound,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
