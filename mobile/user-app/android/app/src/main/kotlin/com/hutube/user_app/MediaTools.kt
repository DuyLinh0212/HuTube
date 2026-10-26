package com.hutube.user_app

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.media.MediaMetadataRetriever
import android.os.Bundle
import android.os.Build
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors

/** Android framework APIs keep metadata, frame extraction and PDF fonts offline. */
class MediaTools(private val activity: Activity, messenger: BinaryMessenger) {
    private val executor = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(messenger, "hutube/media_tools")
    init {
        channel.setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            if (call.method !in listOf("inspectVideo", "extractFrame", "exportPolicy", "printPolicy")) {
                result.notImplemented()
            } else executor.execute {
                try {
                    when (call.method) {
                        "extractFrame" -> {
                            val path = frame(args["source"] as String, (args["seconds"] as Number).toDouble())
                            activity.runOnUiThread { result.success(path) }
                        }
                        "inspectVideo" -> {
                            val data = inspect(args["path"] as String)
                            activity.runOnUiThread { result.success(data) }
                        }
                        else -> {
                            val title = args["title"] as? String ?: "HuTube"
                            val (file, pages) = pdf(title, args["body"] as? String ?: "")
                            activity.runOnUiThread {
                                try {
                                    if (call.method == "printPolicy") print(file, pages, title)
                                    result.success(file.absolutePath)
                                } catch (e: Exception) { result.error("PRINT_ERROR", e.message, null) }
                            }
                        }
                    }
                } catch (e: Exception) {
                    activity.runOnUiThread { result.error("MEDIA_ERROR", e.message, null) }
                }
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    private fun inspect(path: String): Map<String, Any> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            fun meta(key: Int) = retriever.extractMetadata(key)?.toLongOrNull() ?: 0L
            val duration = meta(MediaMetadataRetriever.METADATA_KEY_DURATION)
            var width = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH).toInt()
            var height = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT).toInt()
            val rotation = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION).toInt()
            if (rotation == 90 || rotation == 270) { val swap = width; width = height; height = swap }
            require(duration > 0 && width > 0 && height > 0) { "Invalid video metadata" }
            val frames = mutableListOf<String>()
            for (fraction in listOf(0.12, 0.42, 0.76)) {
                try {
                    val time = (duration * fraction * 1000).toLong()
                    val targetScale = minOf(1.0, 640.0 / width)
                    val frame = if (Build.VERSION.SDK_INT >= 27) {
                        retriever.getScaledFrameAtTime(time, MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                            (width * targetScale).toInt().coerceAtLeast(1), (height * targetScale).toInt().coerceAtLeast(1))
                    } else retriever.getFrameAtTime(time, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    if (frame == null) continue
                    val scale = minOf(1.0, 640.0 / frame.width)
                    val scaled = Bitmap.createScaledBitmap(frame, (frame.width * scale).toInt().coerceAtLeast(1), (frame.height * scale).toInt().coerceAtLeast(1), true)
                    val file = File(activity.cacheDir, "hutube-frame-${UUID.randomUUID()}.jpg")
                    FileOutputStream(file).use { scaled.compress(Bitmap.CompressFormat.JPEG, 85, it) }
                    if (scaled !== frame) scaled.recycle()
                    frame.recycle()
                    frames.add(file.absolutePath)
                } catch (_: Exception) { /* Metadata is still usable; custom thumbnail remains available. */ }
            }
            return mapOf("durationMs" to duration, "width" to width, "height" to height, "rotation" to rotation, "thumbnails" to frames)
        } finally { retriever.release() }
    }

    private fun frame(source: String, seconds: Double): String {
        require(seconds.isFinite() && seconds >= 0) { "Invalid frame time" }
        val retriever = MediaMetadataRetriever()
        try {
            if (source.startsWith("https://") || source.startsWith("http://")) {
                retriever.setDataSource(source, emptyMap<String, String>())
            } else retriever.setDataSource(source)
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val time = (seconds * 1_000_000).toLong().coerceAtMost((durationMs * 1000 - 1).coerceAtLeast(0L))
            val bitmap = retriever.getFrameAtTime(time, MediaMetadataRetriever.OPTION_CLOSEST)
                ?: throw IllegalStateException("Frame unavailable")
            try {
                val factor = minOf(1.0, 1280.0 / bitmap.width)
                val scaled = Bitmap.createScaledBitmap(bitmap, (bitmap.width * factor).toInt().coerceAtLeast(1), (bitmap.height * factor).toInt().coerceAtLeast(1), true)
                try {
                    val file = File(activity.cacheDir, "hutube-frame-${UUID.randomUUID()}.jpg")
                    FileOutputStream(file).use { require(scaled.compress(Bitmap.CompressFormat.JPEG, 90, it)) }
                    return file.absolutePath
                } finally { if (scaled !== bitmap) scaled.recycle() }
            } finally { bitmap.recycle() }
        } finally { retriever.release() }
    }

    private fun pdf(title: String, body: String): Pair<File, Int> {
        val document = PdfDocument()
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 12f; typeface = Typeface.create("sans-serif", Typeface.NORMAL) }
        val lines = mutableListOf<String>()
        for (paragraph in (title + "\n\n" + body).split('\n')) {
            var remaining = paragraph.trimEnd()
            if (remaining.isEmpty()) lines.add("")
            while (remaining.isNotEmpty()) {
                var count = paint.breakText(remaining, true, 515f, null).coerceAtLeast(1)
                if (count < remaining.length) {
                    val space = remaining.lastIndexOf(' ', count - 1)
                    if (space > 0) count = space
                }
                lines.add(remaining.substring(0, count))
                remaining = remaining.substring(count).trimStart()
            }
        }
        val pages = lines.chunked(42)
        try {
            for ((index, pageLines) in pages.withIndex()) {
                val page = document.startPage(PdfDocument.PageInfo.Builder(595, 842, index + 1).create())
                pageLines.forEachIndexed { line, value -> page.canvas.drawText(value, 40f, 55f + line * 17f, paint) }
                page.canvas.drawText("HuTube · ${index + 1}/${pages.size}", 40f, 815f, paint)
                document.finishPage(page)
            }
            val file = File(activity.cacheDir, "HuTube-policy-${UUID.randomUUID()}.pdf")
            FileOutputStream(file).use { document.writeTo(it) }
            return file to pages.size
        } finally { document.close() }
    }

    private fun print(file: File, pageCount: Int, title: String) {
        val manager = activity.getSystemService(Activity.PRINT_SERVICE) as PrintManager
        manager.print(title, object : PrintDocumentAdapter() {
            override fun onLayout(old: PrintAttributes?, attributes: PrintAttributes?, signal: CancellationSignal?, callback: LayoutResultCallback, extras: Bundle?) {
                if (signal?.isCanceled == true) { callback.onLayoutCancelled(); return }
                callback.onLayoutFinished(PrintDocumentInfo.Builder(file.name).setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT).setPageCount(pageCount).build(), true)
            }
            override fun onWrite(pages: Array<out PageRange>?, destination: ParcelFileDescriptor, signal: CancellationSignal, callback: WriteResultCallback) {
                executor.execute {
                    try {
                        if (signal.isCanceled) { callback.onWriteCancelled(); return@execute }
                        file.inputStream().use { input -> FileOutputStream(destination.fileDescriptor).use { output -> input.copyTo(output) } }
                        if (signal.isCanceled) callback.onWriteCancelled() else callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                    } catch (e: Exception) { callback.onWriteFailed(e.message) }
                }
            }
        }, null)
    }
}
