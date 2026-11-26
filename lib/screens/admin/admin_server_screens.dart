
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/admin_providers.dart';
import '../../state/library_providers.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../../widgets/page_width.dart';
import '../../widgets/error_view.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/app_spinner.dart';

import 'config_editor.dart';
import '../../api/jellyfin_client.dart';

/// General server settings: name, metadata language/country, Quick Connect.
class AdminGeneralScreen extends ConsumerStatefulWidget {
  const AdminGeneralScreen({super.key});
  @override
  ConsumerState<AdminGeneralScreen> createState() => _AdminGeneralState();
}

class _AdminGeneralState extends ConfigEditorState<AdminGeneralScreen> {
  @override
  String title(AppLocalizations l) => l.adminGeneralTitle;

  @override
  Future<Map<String, dynamic>> load(client, session) => client
      .getServerConfiguration(baseUrl: session.baseUrl, token: session.accessToken);

  @override
  Future<void> save(client, session, cfg) async {
    await client.updateServerConfiguration(
        baseUrl: session.baseUrl, token: session.accessToken, config: cfg);
    ref.invalidate(adminServerConfigProvider);
  }

  @override
  List<Widget> fields(BuildContext context) {
    final l = AppLocalizations.of(context);
    return [
      sectionLabel(l.adminSectionServer),
      textField('ServerName', l.adminServerName),
      sectionLabel(l.adminSectionMetadata),
      textField('PreferredMetadataLanguage', l.adminPreferredMetadataLanguage,
          hint: l.adminMetadataLanguageHint),
      textField('MetadataCountryCode', l.adminCountry, hint: l.adminCountryHint),
      sectionLabel(l.adminSectionLibraryDisplay),
      switchField('EnableFolderView', l.adminShowFolderView,
          subtitle: l.adminShowFolderViewSubtitle),
      switchField('SaveMetadataHidden', l.adminSaveMetadataHidden),
      switchField('EnableExternalContentInSuggestions',
          l.adminExternalContentSuggestions),
      sectionLabel(l.adminSectionResume),
      intField('MinResumePct', l.adminMinResumePct),
      intField('MaxResumePct', l.adminMaxResumePct),
      intField('MinResumeDurationSeconds', l.adminMinResumeDuration),
      sectionLabel(l.adminSectionAccess),
      switchField('QuickConnectAvailable', l.adminQuickConnect,
          subtitle: l.adminQuickConnectSubtitle),
    ];
  }
}

/// Branding: the login disclaimer and custom CSS, nested under the server
/// configuration's Branding object.
class AdminBrandingScreen extends ConsumerStatefulWidget {
  const AdminBrandingScreen({super.key});
  @override
  ConsumerState<AdminBrandingScreen> createState() => _AdminBrandingState();
}

class _AdminBrandingState extends ConsumerState<AdminBrandingScreen> {
  Map<String, dynamic>? _config; // the full server config
  final _disclaimer = TextEditingController();
  final _css = TextEditingController();
  bool _splashEnabled = false;
  bool _saving = false;
  bool _busyImage = false;
  int _imgNonce = 0; // bust the splash preview cache after upload/delete
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disclaimer.dispose();
    _css.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    try {
      // Branding has its own endpoint: ServerConfiguration carries no
      // 'Branding' key, so reading it from there always came back empty and
      // showed a blank form regardless of what the server actually had set.
      final branding = await ref
          .read(jellyfinClientProvider)
          .getBrandingConfiguration(baseUrl: s.baseUrl, token: s.accessToken);
      _disclaimer.text = '${branding['LoginDisclaimer'] ?? ''}';
      _css.text = '${branding['CustomCss'] ?? ''}';
      _splashEnabled = branding['SplashscreenEnabled'] == true;
      if (mounted) setState(() => _config = branding);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null || _config == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final saved = AppLocalizations.of(context).adminSaved;
    setState(() => _saving = true);
    try {
      final branding = <String, dynamic>{
        ..._config!,
        'LoginDisclaimer': _disclaimer.text,
        'CustomCss': _css.text,
        'SplashscreenEnabled': _splashEnabled,
      };
      await ref.read(jellyfinClientProvider).updateBrandingConfiguration(
          baseUrl: s.baseUrl, token: s.accessToken, branding: branding);
      _config = branding;
      ref.invalidate(adminServerConfigProvider);
      showSnackOn(messenger, saved, kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadSplash() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final ext = (file.extension ?? 'png').toLowerCase();
    final contentType = ext == 'jpg' || ext == 'jpeg'
        ? 'image/jpeg'
        : (ext == 'webp' ? 'image/webp' : 'image/png');
    setState(() => _busyImage = true);
    try {
      await ref.read(jellyfinClientProvider).uploadSplashscreen(
            baseUrl: s.baseUrl,
            token: s.accessToken,
            bytes: bytes,
            contentType: contentType,
          );
      if (mounted) setState(() => _imgNonce++);
    } catch (e) {
      showErrorOn(messenger, e);
    } finally {
      if (mounted) setState(() => _busyImage = false);
    }
  }

  Future<void> _deleteSplash() async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyImage = true);
    try {
      await ref.read(jellyfinClientProvider).deleteSplashscreen(
          baseUrl: s.baseUrl, token: s.accessToken);
      if (mounted) setState(() => _imgNonce++);
    } catch (e) {
      showErrorOn(messenger, e);
    } finally {
      if (mounted) setState(() => _busyImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(sessionControllerProvider).asData?.value;
    final headers = ref.watch(imageHeadersProvider);
    final client = ref.watch(jellyfinClientProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.adminBrandingTitle)),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: () {
              setState(() => _error = null);
              _load();
            })
          : _config == null || s == null
              ? const Center(child: AppSpinner())
              : PageWidth(builder: (_, inset) => ListView(
                  padding: pageInsets(inset, const EdgeInsets.all(20)),
                  children: [
                    Text(l.adminSplashScreen,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          '${client.splashscreenUrl(baseUrl: s.baseUrl)}?v=$_imgNonce',
                          fit: BoxFit.cover,
                          headers: headers,
                          errorBuilder: (context, _, _) => Container(
                            color:
                                Theme.of(context).colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(Icons.image_outlined,
                                size: 40,
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.adminSplashHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busyImage ? null : _uploadSplash,
                            icon: const Icon(Icons.upload_rounded),
                            label: Text(l.adminUpload),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busyImage ? null : _deleteSplash,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: Text(l.commonDelete),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.adminEnableSplashImage),
                      value: _splashEnabled,
                      onChanged: (v) => setState(() => _splashEnabled = v),
                    ),
                    const Divider(height: 32),
                    TextField(
                      controller: _disclaimer,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: l.adminLoginDisclaimer,
                        helperText: l.adminLoginDisclaimerHelper,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _css,
                      minLines: 5,
                      maxLines: 16,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13),
                      decoration: InputDecoration(
                        labelText: l.adminCustomCss,
                        alignLabelWithHint: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? AppSpinner.inline()
                          : const Icon(Icons.save_rounded),
                      label: Text(l.commonSave),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                    ),
                  ],
                )),
    );
  }
}

/// Playback / transcoding (encoding configuration).
class AdminPlaybackScreen extends ConsumerStatefulWidget {
  const AdminPlaybackScreen({super.key});
  @override
  ConsumerState<AdminPlaybackScreen> createState() => _AdminPlaybackState();
}

class _AdminPlaybackState extends ConfigEditorState<AdminPlaybackScreen> {
  @override
  String title(AppLocalizations l) => l.adminPlaybackTitle;

  @override
  Future<Map<String, dynamic>> load(client, session) => client.getNamedConfiguration(
      baseUrl: session.baseUrl, token: session.accessToken, key: 'encoding');

  @override
  Future<void> save(client, session, cfg) async {
    await client.updateNamedConfiguration(
        baseUrl: session.baseUrl,
        token: session.accessToken,
        key: 'encoding',
        config: cfg);
    ref.invalidate(adminEncodingConfigProvider);
  }

  /// How this server spells "no hardware acceleration" and "automatic encoder
  /// preset". Jellyfin 10.10 turned both settings into fixed lists, spelled
  /// `none` and `auto` (still so on 12.1); older servers stored an empty
  /// string. Offering the wrong spelling makes the dropdown write a value the
  /// server rejects, so it follows whatever the server sent. Read once, from
  /// the loaded settings, before any edit can change them.
  late final String _noAcceleration =
      _unsetSpelling('HardwareAccelerationType', 'none');
  late final String _autoPreset = _unsetSpelling('EncoderPreset', 'auto');

  String _unsetSpelling(String key, String modern) {
    final loaded = draft?[key];
    return (loaded == null || '$loaded'.isEmpty) ? '' : modern;
  }

  /// Ensures the nested TrickplayOptions object exists and is mutable, then
  /// returns it so the trickplay fields can bind to it.
  Map<String, dynamic> _trickplay() {
    final existing = draft!['TrickplayOptions'];
    if (existing is Map<String, dynamic>) return existing;
    final m = existing is Map
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{};
    draft!['TrickplayOptions'] = m;
    return m;
  }

  /// Kicks off the server's trickplay image generation task, so enabling
  /// trickplay here actually produces the thumbnails without leaving the app.
  Future<void> _generateTrickplay() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final client = ref.read(jellyfinClientProvider);
    if (session == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final tasks = await client.getScheduledTasks(
          baseUrl: session.baseUrl, token: session.accessToken);
      final task = tasks.firstWhere(
        (t) => '${t['Key'] ?? ''}${t['Name'] ?? ''}'
            .toLowerCase()
            .contains('trickplay'),
        orElse: () => const {},
      );
      final id = task['Id'] as String?;
      if (id == null) {
        showSnackOn(messenger, l.adminNoTrickplayTask);
        return;
      }
      await client.runScheduledTask(
          baseUrl: session.baseUrl, token: session.accessToken, taskId: id);
      showSnackOn(messenger, l.adminGeneratingTrickplay);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  @override
  List<Widget> fields(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tp = _trickplay();
    return [
      sectionLabel(l.adminSectionHardwareAccel),
      dropdownField('HardwareAccelerationType', l.adminAcceleration, {
        _noAcceleration: l.adminAccelNone,
        'amf': 'AMD AMF',
        'nvenc': 'Nvidia NVENC',
        'qsv': 'Intel QuickSync',
        'vaapi': 'VAAPI',
        'videotoolbox': 'Apple VideoToolbox',
        'rkmpp': 'Rockchip MPP',
        'v4l2m2m': 'V4L2 M2M',
      }),
      switchField('EnableHardwareEncoding', l.adminEnableHwEncoding),
      switchField('EnableTonemapping', l.adminEnableToneMapping),
      switchField('EnableVppTonemapping', l.adminEnableVppToneMapping),
      switchField('AllowHevcEncoding', l.adminAllowHevcEncoding),
      switchField('AllowAv1Encoding', l.adminAllowAv1Encoding),
      sectionLabel(l.adminSectionEncoding),
      dropdownField('EncoderPreset', l.adminEncoderPreset, {
        _autoPreset: l.adminPresetAuto,
        'ultrafast': 'ultrafast',
        'superfast': 'superfast',
        'veryfast': 'veryfast',
        'faster': 'faster',
        'fast': 'fast',
        'medium': 'medium',
        'slow': 'slow',
        'slower': 'slower',
        'veryslow': 'veryslow',
      }),
      intField('H264Crf', l.adminH264Crf),
      intField('H265Crf', l.adminH265Crf),
      intField('EncodingThreadCount', l.adminTranscodeThreadCount),
      switchField('EnableSubtitleExtraction', l.adminEnableSubtitleExtraction),
      sectionLabel(l.adminSectionThrottling),
      switchField('EnableThrottling', l.adminThrottleTranscodes,
          subtitle: l.adminThrottleTranscodesSubtitle),
      intField('ThrottleDelaySeconds', l.adminThrottleDelay),
      sectionLabel(l.adminSectionTrickplay),
      switchFieldIn(tp, 'EnableHwAcceleration', l.adminTrickplayHwGeneration),
      switchFieldIn(tp, 'EnableHwEncoding', l.adminTrickplayHwEncoding),
      switchFieldIn(tp, 'EnableKeyFrameOnlyExtraction',
          l.adminKeyframeOnlyExtraction,
          subtitle: l.adminKeyframeOnlyExtractionSubtitle),
      dropdownFieldIn(tp, 'ScanBehavior', l.adminScanBehavior, {
        'NonBlocking': l.adminScanBehaviorNonBlocking,
        'Blocking': l.adminScanBehaviorBlocking,
      }),
      dropdownFieldIn(tp, 'ProcessPriority', l.adminProcessPriority, {
        'High': l.adminPriorityHigh,
        'AboveNormal': l.adminPriorityAboveNormal,
        'Normal': l.adminPriorityNormal,
        'BelowNormal': l.adminPriorityBelowNormal,
        'Idle': l.adminPriorityIdle,
      }),
      intFieldIn(tp, 'Interval', l.adminInterval, hint: 'e.g. 10000'),
      intListFieldIn(tp, 'WidthResolutions', l.adminWidthResolutions,
          hint: l.adminWidthResolutionsHint),
      intFieldIn(tp, 'TileWidth', l.adminTileWidth),
      intFieldIn(tp, 'TileHeight', l.adminTileHeight),
      intFieldIn(tp, 'JpegQuality', l.adminJpegQuality),
      intFieldIn(tp, 'ProcessThreads', l.adminProcessThreads),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: OutlinedButton.icon(
          onPressed: _generateTrickplay,
          icon: const Icon(Icons.movie_filter_outlined),
          label: Text(l.adminGenerateTrickplayNow),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Text(
          l.adminTrickplayGenerateHint,
          style: const TextStyle(fontSize: 12.5, color: Colors.grey),
        ),
      ),
      sectionLabel(l.adminSectionPaths),
      textField('TranscodingTempPath', l.adminTranscodingTempPath,
          hint: l.adminHintLeaveBlankDefault),
    ];
  }
}

/// Networking (network configuration).
class AdminNetworkScreen extends ConsumerStatefulWidget {
  const AdminNetworkScreen({super.key});
  @override
  ConsumerState<AdminNetworkScreen> createState() => _AdminNetworkState();
}

class _AdminNetworkState extends ConfigEditorState<AdminNetworkScreen> {
  @override
  String title(AppLocalizations l) => l.adminNetworkingTitle;

  @override
  Future<Map<String, dynamic>> load(client, session) => client.getNamedConfiguration(
      baseUrl: session.baseUrl, token: session.accessToken, key: 'network');

  @override
  Future<void> save(client, session, cfg) async {
    await client.updateNamedConfiguration(
        baseUrl: session.baseUrl,
        token: session.accessToken,
        key: 'network',
        config: cfg);
    ref.invalidate(adminNetworkConfigProvider);
  }

  @override
  List<Widget> fields(BuildContext context) {
    final l = AppLocalizations.of(context);
    return [
      sectionLabel(l.adminSectionRemoteAccess),
      switchField('EnableRemoteAccess', l.adminAllowRemoteConnections),
      textField('BaseUrl', l.adminBaseUrl, hint: 'e.g. /jellyfin'),
      sectionLabel(l.adminSectionHttps),
      switchField('EnableHttps', l.adminEnableHttps),
      switchField('RequireHttps', l.adminRequireHttps),
      textField('CertificatePath', l.adminCertificatePath,
          hint: l.adminCertificatePathHint),
      textField('CertificatePassword', l.adminCertificatePassword),
      sectionLabel(l.adminSectionPorts),
      intField('InternalHttpPort', l.adminHttpPort),
      intField('InternalHttpsPort', l.adminHttpsPort),
      intField('PublicHttpPort', l.adminPublicHttpPort),
      intField('PublicHttpsPort', l.adminPublicHttpsPort),
      sectionLabel(l.adminSectionDiscovery),
      switchField('EnableUPnP', l.adminEnableUpnp),
      switchField('AutoDiscovery', l.adminEnableAutodiscovery),
      sectionLabel(l.adminSectionAdvanced),
      switchField('EnableIPv6', l.adminEnableIpv6),
      strListField('KnownProxies', l.adminKnownProxies,
          hint: l.adminKnownProxiesHint),
      strListField('LocalNetworkSubnets', l.adminLanNetworks,
          hint: l.adminLanNetworksHint),
    ];
  }
}
