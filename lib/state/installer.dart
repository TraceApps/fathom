import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/error_text.dart';
import '../services/app_installer.dart';
import '../services/app_updates.dart';

/// Download + install progress for the Updates screen.
class InstallProgress {
  final bool busy;
  final double progress; // 0..1 during download
  final String? error;
  const InstallProgress({this.busy = false, this.progress = 0, this.error});
}

/// Drives the in-app self-update: download the platform asset with progress,
/// then replace + relaunch (which ends this process). Surfaces any pre-relaunch
/// failure as [InstallProgress.error].
class InstallController extends Notifier<InstallProgress> {
  @override
  InstallProgress build() => const InstallProgress();

  Future<void> install(ReleaseAsset asset, {required String version}) async {
    if (state.busy) return;
    state = const InstallProgress(busy: true);
    try {
      await downloadAndInstall(asset,
          version: version,
          onProgress: (p) => state = InstallProgress(busy: true, progress: p));
      // On desktop the process is replaced by a fresh launch and never gets
      // here. On Android the system installer has taken over; returning means
      // nothing more to do here, so settle back to idle.
      state = const InstallProgress();
    } catch (e) {
      state = InstallProgress(error: errorText(e));
    } finally {
      // The button's Install / Download & Install label follows what's on disk.
      ref.invalidate(updateStagedProvider);
    }
  }
}

/// Whether the Android update for a release is already downloaded, so the
/// Updates screen can offer Install instead of Download & Install.
final updateStagedProvider = FutureProvider.autoDispose
    .family<bool, ({ReleaseAsset asset, String version})>(
        (ref, r) => isUpdateStaged(r.asset, r.version));

final installControllerProvider =
    NotifierProvider<InstallController, InstallProgress>(InstallController.new);
