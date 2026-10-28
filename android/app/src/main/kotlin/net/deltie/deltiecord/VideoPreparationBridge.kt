package net.deltie.deltiecord

import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.effect.Crop
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.common.Effect
import androidx.media3.transformer.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Files stay in app-private cache. No content URI, network input or raw video
 * crosses the method channel. Codec/export work runs inside Media3 workers. */
@UnstableApi
internal class VideoPreparationBridge(private val context: Context, messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private var transformer: Transformer? = null
    private var pending: MethodChannel.Result? = null
    private val channel = MethodChannel(messenger, "net.deltie.deltiecord/video_prepare")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "cancel" -> {
                    transformer?.cancel()
                    transformer = null
                    pending?.error("canceled", "Video preparation canceled.", null)
                    pending = null
                    result.success(null)
                }
                "progress" -> {
                    val holder = ProgressHolder()
                    val state = transformer?.getProgress(holder)
                    result.success(if (state == Transformer.PROGRESS_STATE_AVAILABLE) holder.progress else 0)
                }
                "probe", "optimize" -> {
                    if (call.method == "optimize" && pending != null) {
                        result.error("busy", "Another video is being prepared.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val input = privateFile(call.argument<String>("input")!!)
                        if (call.method == "probe") {
                            executor.execute {
                                try {
                                    val metadata = probe(input)
                                    main.post { result.success(metadata) }
                                } catch (e: Exception) {
                                    main.post { result.error("probe", "Could not read video metadata.", null) }
                                }
                            }
                        } else {
                            val output = privateFile(call.argument<String>("output")!!)
                            require(!output.exists())
                            val bitrate = (call.argument<Int>("bitrate") ?: 2000000).coerceIn(250000, 20000000)
                            val edit = call.argument<Map<String, Any?>>("edit") ?: emptyMap()
                            val turns = ((edit["turns"] as? Number)?.toInt() ?: 0).mod(4)
                            val left = (edit["left"] as? Number)?.toDouble() ?: 0.0
                            val top = (edit["top"] as? Number)?.toDouble() ?: 0.0
                            val cropWidth = (edit["width"] as? Number)?.toDouble() ?: 1.0
                            val cropHeight = (edit["height"] as? Number)?.toDouble() ?: 1.0
                            require(left >= 0 && top >= 0 && cropWidth > 0 && cropHeight > 0 && left + cropWidth <= 1.000001 && top + cropHeight <= 1.000001)
                            val originalWidth = call.argument<Int>("width") ?: 1280
                            val originalHeight = call.argument<Int>("height") ?: 720
                            val width = ((if (turns % 2 == 0) originalWidth else originalHeight) * cropWidth).toInt().coerceAtLeast(2)
                            val height = ((if (turns % 2 == 0) originalHeight else originalWidth) * cropHeight).toInt().coerceAtLeast(2)
                            val scale = if (call.argument<Boolean>("resize") != false) minOf(1.0, 1280.0 / maxOf(width, height)) else 1.0
                            val targetWidth = maxOf(2, (width * scale / 2).toInt() * 2)
                            val targetHeight = maxOf(2, (height * scale / 2).toInt() * 2)
                            pending = result
                            val encoder = DefaultEncoderFactory.Builder(context)
                                .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(bitrate).build())
                                .build()
                            transformer = Transformer.Builder(context)
                                .setVideoMimeType(MimeTypes.VIDEO_H264)
                                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                                .setEncoderFactory(encoder)
                                .addListener(object : Transformer.Listener {
                                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                                        val callback = pending
                                        pending = null
                                        transformer = null
                                        callback?.success(null)
                                    }
                                    override fun onError(composition: Composition, exportResult: ExportResult, exception: ExportException) {
                                        val callback = pending
                                        pending = null
                                        transformer = null
                                        callback?.error("encode", "This device could not optimize the video. Try original quality.", null)
                                    }
                                }).build()
                            val media = MediaItem.Builder().setUri(input.toURI().toString())
                            val startMs = (edit["startMs"] as? Number)?.toLong() ?: 0L
                            val endMs = (edit["endMs"] as? Number)?.toLong()
                            if (startMs > 0 || endMs != null) {
                                require(startMs >= 0 && (endMs == null || endMs > startMs))
                                val clipping = MediaItem.ClippingConfiguration.Builder().setStartPositionMs(startMs)
                                if (endMs != null) clipping.setEndPositionMs(endMs)
                                media.setClippingConfiguration(clipping.build())
                            }
                            val effects = mutableListOf<Effect>()
                            if (turns != 0) effects.add(ScaleAndRotateTransformation.Builder().setRotationDegrees(-90f * turns).build())
                            if (left != 0.0 || top != 0.0 || cropWidth != 1.0 || cropHeight != 1.0) {
                                effects.add(Crop((2*left-1).toFloat(), (2*(left+cropWidth)-1).toFloat(),
                                    (1-2*(top+cropHeight)).toFloat(), (1-2*top).toFloat()))
                            }
                            effects.add(Presentation.createForWidthAndHeight(targetWidth, targetHeight, Presentation.LAYOUT_SCALE_TO_FIT))
                            val item = EditedMediaItem.Builder(media.build())
                                .setRemoveAudio(edit["muted"] == true)
                                .setFrameRate(30)
                                .setEffects(Effects(emptyList(), effects))
                                .build()
                            transformer!!.start(item, output.path)
                        }
                    } catch (e: Exception) {
                        if (pending === result) {
                            transformer?.cancel()
                            transformer = null
                            pending = null
                        }
                        result.error("prepare", "Could not prepare the video. Try original quality.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun privateFile(path: String): File {
        val file = File(path).canonicalFile
        require(file.path.startsWith(context.cacheDir.canonicalPath + File.separator))
        return file
    }

    private fun probe(file: File): Map<String, Any> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.path)
            val w = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toInt() ?: 0
            val h = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toInt() ?: 0
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toInt() ?: 0
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0
            require(w > 0 && h > 0)
            val metadata = mutableMapOf<String, Any>(
                "width" to if (rotation % 180 != 0) h else w,
                "height" to if (rotation % 180 != 0) w else h,
                "duration" to duration,
            )
            // Failure to decode a poster must not discard valid dimensions.
            try {
                val posterTimeUs = (duration / 10).coerceIn(0, 10000) * 1000
                val frame = if (android.os.Build.VERSION.SDK_INT >= 27)
                    retriever.getScaledFrameAtTime(posterTimeUs, MediaMetadataRetriever.OPTION_CLOSEST, 480, 480)
                    else retriever.getFrameAtTime(posterTimeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                if (frame != null) {
                    try {
                        val bytes = java.io.ByteArrayOutputStream()
                        frame.compress(android.graphics.Bitmap.CompressFormat.JPEG, 82, bytes)
                        if (bytes.size() <= 1024 * 1024) metadata["thumbnail"] = bytes.toByteArray()
                    } finally { frame.recycle() }
                }
            } catch (_: Exception) {}
            return metadata
        } finally { retriever.release() }
    }

    fun dispose() {
        transformer?.cancel()
        transformer = null
        pending?.error("canceled", "Video preparation interrupted.", null)
        pending = null
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
}
