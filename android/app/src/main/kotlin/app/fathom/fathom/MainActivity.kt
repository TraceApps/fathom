package app.fathom.fathom

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.media.MediaCodecList
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Extends AudioServiceActivity (not FlutterActivity) so media-button intents and
// the audio_service media session route to the Flutter engine correctly.
//
// Also wires system Picture-in-Picture: while a video is playing (the Flutter
// side flags it via [pipActive]), pressing Home floats the video into a PiP
// window, and PiP-mode changes are reported back so the player can hide its
// controls.
class MainActivity : AudioServiceActivity() {
    private var pipActive = false
    private var channel: MethodChannel? = null

    // The PiP window's own buttons (back, play/pause, forward). Without them
    // Android shows the app's media session controls instead, which belong to
    // the music player, so taps there never reached the video. Set by the
    // video screen; a tap comes back over [controls] as "action".
    private var controls: MethodChannel? = null
    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.getStringExtra(EXTRA_PIP_ACTION) ?: return
            controls?.invokeMethod("action", action)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ContextCompat.registerReceiver(
            this, pipReceiver, IntentFilter(ACTION_PIP_CONTROL),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(pipReceiver)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    private var castBridge: CastBridge? = null
    private var wheelSfx: WheelSfx? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Native Media3 ExoPlayer video surface (the tunneled Android TV backend,
        // selectable alongside media_kit).
        flutterEngine.platformViewsController.registry.registerViewFactory(
            ExoVideoPlayerFactory.VIEW_TYPE,
            ExoVideoPlayerFactory(flutterEngine.dartExecutor.binaryMessenger),
        )
        // Native Google Cast bridge (Chromecast).
        castBridge = CastBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        // SoundPool for the wheel's peg ticks (see WheelSfx).
        wheelSfx = WheelSfx(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
            io.flutter.FlutterInjector.instance().flutterLoader(),
        )
        // Downloads: publish to shared storage, Open With, Share.
        SharedFiles(this, flutterEngine.dartExecutor.binaryMessenger)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.fathom.player/pip",
        )
        controls = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.fathom.player/pip_controls",
        )
        controls?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setButtons" -> {
                    pipButtons = call.arguments as? Map<*, *>
                    updatePipParams()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setActive" -> {
                    pipActive = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                "enter" -> {
                    enterPip()
                    result.success(null)
                }
                "isTelevision" -> {
                    // UiModeManager.currentModeType is the "official" TV signal but
                    // it is unreliable on cold boot for some (cheap Amlogic) TV boxes
                    // — it can report NORMAL before the system settles, which made the
                    // app start up in phone/desktop mode (wrong sidebar, no D-pad
                    // handlers). FEATURE_LEANBACK is a STATIC device feature (Google's
                    // recommended Android-TV check) that is correct even during boot,
                    // so treat either signal as "this is a TV".
                    val ui = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                    val pm = packageManager
                    val isTv =
                        ui.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
                            pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                            pm.hasSystemFeature("android.hardware.type.television")
                    result.success(isTv)
                }
                // Media commands as Android delivered them to the playback service
                // (third_party/audio_service), for the Diagnostics report.
                "mediaEvents" -> {
                    result.success(com.ryanheise.audioservice.AudioService.fathomEvents())
                }
                "hardwareVideoCodecs" -> {
                    result.success(hardwareVideoCodecs())
                }
                // In-app update: hand the downloaded APK to the system installer.
                // Done here rather than through a plugin because this handler is
                // re-registered with every new activity; the engine is cached by
                // AudioServiceActivity and outlives the activity, and open_filex
                // dropped its channel when the activity was recreated, so updates
                // failed after reopening the app while its media session lived on.
                "installApk" -> {
                    try {
                        val file = File(call.arguments as String)
                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.files", file)
                        val intent = Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("install", e.toString(), null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // The Jellyfin (ffmpeg) codec names for which this device has a HARDWARE
    // video decoder. The Dart side uses this to advertise only these codecs as
    // direct-play, so anything without hardware support (notably AV1 on cheaper
    // TV sticks) transcodes to h264 server-side instead of grinding through a
    // software decoder and stuttering.
    private fun hardwareVideoCodecs(): List<String> {
        // MediaCodec MIME -> ffmpeg/Jellyfin codec name.
        val mimeToCodec = mapOf(
            "video/avc" to "h264",
            "video/hevc" to "hevc",
            "video/x-vnd.on2.vp8" to "vp8",
            "video/x-vnd.on2.vp9" to "vp9",
            "video/av01" to "av1",
            "video/mpeg2" to "mpeg2video",
            "video/mp4v-es" to "mpeg4",
        )
        val supported = mutableSetOf<String>()
        try {
            val codecs = MediaCodecList(MediaCodecList.ALL_CODECS)
            for (info in codecs.codecInfos) {
                if (info.isEncoder) continue
                // API 29+ reports this directly; below that, treat known
                // software decoders (Google/"sw"/OMX.google) as non-hardware.
                val isHardware = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    info.isHardwareAccelerated
                } else {
                    val n = info.name.lowercase()
                    !n.contains("google") && !n.contains(".sw.") && !n.startsWith("omx.google")
                }
                if (!isHardware) continue
                for (type in info.supportedTypes) {
                    mimeToCodec[type.lowercase()]?.let { supported.add(it) }
                }
            }
        } catch (_: Exception) {
        }
        return supported.toList()
    }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            enterPictureInPictureMode(pipParams())
        }
    }

    private fun pipParams(): PictureInPictureParams {
        val b = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9))
        // An empty list falls back to the system's default controls.
        b.setActions(pipActions())
        return b.build()
    }

    // Refresh the window's buttons (play turns to pause and back) while it's
    // open; outside PiP this just primes the next entry.
    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            setPictureInPictureParams(pipParams())
        } catch (_: Exception) {
        }
    }

    private fun pipActions(): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()
        val b = pipButtons ?: return emptyList()
        val playing = b["playing"] == true
        val list = mutableListOf<RemoteAction>()
        fun add(id: String, icon: Int, label: String?, code: Int) {
            val text = label ?: id
            val intent = Intent(ACTION_PIP_CONTROL)
                .setPackage(packageName)
                .putExtra(EXTRA_PIP_ACTION, id)
            val pending = PendingIntent.getBroadcast(
                this, code, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            list.add(RemoteAction(Icon.createWithResource(this, icon), text, text, pending))
        }
        add("back", android.R.drawable.ic_media_rew, b["backLabel"] as? String, 1)
        if (playing) {
            add("pause", android.R.drawable.ic_media_pause, b["playPauseLabel"] as? String, 2)
        } else {
            add("play", android.R.drawable.ic_media_play, b["playPauseLabel"] as? String, 2)
        }
        add("forward", android.R.drawable.ic_media_ff, b["forwardLabel"] as? String, 3)
        // Some devices allow fewer than three buttons; keep play/pause.
        val max = maxPipActions()
        return if (list.size <= max) list else listOf(list[1])
    }

    private fun maxPipActions(): Int = try {
        maxNumPictureInPictureActions
    } catch (_: Exception) {
        3
    }

    // Fired when the user leaves the app (e.g. Home). Enter PiP if a video is
    // active, so playback floats instead of pausing/backgrounding.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipActive) enterPip()
    }

    companion object {
        // Kept here, not on the activity, so a recreated activity still shows
        // the buttons the video set (the Flutter engine outlives it).
        private var pipButtons: Map<*, *>? = null
        private const val ACTION_PIP_CONTROL = "app.fathom.player.PIP_CONTROL"
        private const val EXTRA_PIP_ACTION = "action"
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
    }
}
