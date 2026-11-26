import 'dart:io';

import 'package:flutter/services.dart';

/// Android only: puts finished downloads where other apps can see them, and
/// opens or shares a file. The native side is SharedFiles.kt.
///
/// Downloads are written to Fathom's own folder first (the merge runs there),
/// which Android 11+ hides from the Files app and the gallery. [publish] moves
/// the finished file into shared storage.
class SharedFiles {
  SharedFiles._();

  static const _channel = MethodChannel('app.fathom.player/files');

  static bool? _canPublish;

  /// Whether finished downloads can be moved into shared storage: Android 11
  /// and newer. Older Android keeps them in Fathom's own folder, as before.
  static Future<bool> canPublish() async {
    if (_canPublish != null) return _canPublish!;
    if (!Platform.isAndroid) return _canPublish = false;
    try {
      return _canPublish =
          await _channel.invokeMethod<bool>('canPublish') ?? false;
    } catch (_) {
      return _canPublish = false;
    }
  }

  /// The public folder a download lands in when none is chosen.
  static String defaultDir({required bool audio}) =>
      audio ? 'Music/Fathom' : 'Movies/Fathom';

  /// A folder picked in settings, as a path relative to shared storage
  /// ("Download/Videos"), or null when it isn't in shared storage at all (an
  /// SD card, say), which MediaStore can't write to.
  static String? relativeDir(String pickedPath) {
    const root = '/storage/emulated/0/';
    if (!pickedPath.startsWith(root)) return null;
    final rel = pickedPath.substring(root.length).replaceAll(RegExp(r'/+$'), '');
    return rel.isEmpty ? null : rel;
  }

  /// The MIME type for a downloaded file, from its extension.
  static String mimeFor(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'mp4' => 'video/mp4',
      'mkv' => 'video/x-matroska',
      'webm' => 'video/webm',
      'm4a' => 'audio/mp4',
      'mp3' => 'audio/mpeg',
      'opus' || 'ogg' => 'audio/ogg',
      _ => 'application/octet-stream',
    };
  }

  /// Moves [file] into shared storage under [relativeDir] and returns where it
  /// ended up. Throws if MediaStore refuses, leaving [file] where it was.
  static Future<String> publish(File file, String relativeDir) async {
    final path = await _channel.invokeMethod<String>('publish', {
      'path': file.path,
      'relativeDir': relativeDir,
      'mime': mimeFor(file.path),
    });
    if (path == null) throw Exception('Publishing returned no path');
    return path;
  }

  /// Moves a download (published or not) to [relativeDir] in shared storage
  /// and returns where it ended up. Throws if that isn't possible, leaving the
  /// file where it was.
  static Future<String> move(String path, String relativeDir) async {
    final moved = await _channel.invokeMethod<String>('move', {
      'path': path,
      'relativeDir': relativeDir,
      'mime': mimeFor(path),
    });
    if (moved == null) throw Exception('Moving returned no path');
    return moved;
  }

  /// The absolute folder [relativeDir] stands for in shared storage.
  static String absoluteDir(String relativeDir) =>
      '/storage/emulated/0/$relativeDir';

  /// Offers [path] to the apps that can play or view it.
  static Future<void> open(String path) => _channel
      .invokeMethod<void>('open', {'path': path, 'mime': mimeFor(path)});

  /// Opens the share sheet for [path].
  static Future<void> share(String path) => _channel
      .invokeMethod<void>('share', {'path': path, 'mime': mimeFor(path)});
}
