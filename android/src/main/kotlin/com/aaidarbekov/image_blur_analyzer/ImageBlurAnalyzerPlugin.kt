package com.aaidarbekov.image_blur_analyzer

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import android.util.Size
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max

class ImageBlurAnalyzerPlugin : FlutterPlugin, MethodCallHandler {

    private companion object {
        const val TAG = "ImageBlurAnalyzer"
        const val CHANNEL_NAME = "imageBlurAnalyzer"

        // Target thumbnail size — same as iOS (128x128).
        const val THUMB_SIZE = 128

        // Empirical default threshold for variance of Laplacian on
        // 0..255 grayscale. Lower variance → fewer sharp edges → image
        // is blurry. Caller can override per-call via the `threshold`
        // method-channel argument.
        const val DEFAULT_BLUR_THRESHOLD = 300.0

        // Progress logging step.
        const val PROGRESS_LOG_STEP = 100
    }

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "scanForBlurryPhotos" -> {
                val threshold = (call.argument<Double>("threshold")) ?: DEFAULT_BLUR_THRESHOLD
                scope.launch { scanForBlurryPhotos(result, threshold) }
            }
            else -> result.notImplemented()
        }
    }

    private suspend fun scanForBlurryPhotos(result: Result, threshold: Double) {
        val ids: List<Long> = try {
            queryAllImageIds()
        } catch (e: SecurityException) {
            withContext(Dispatchers.Main) {
                result.error(
                    "PERMISSION_DENIED",
                    "READ_MEDIA_IMAGES permission is required",
                    e.message
                )
            }
            return
        } catch (e: Exception) {
            withContext(Dispatchers.Main) {
                result.error("QUERY_FAILED", "Failed to query MediaStore", e.message)
            }
            return
        }

        if (ids.isEmpty()) {
            withContext(Dispatchers.Main) { result.success(emptyList<String>()) }
            return
        }

        val total = ids.size
        val processed = AtomicInteger(0)
        val startTime = System.currentTimeMillis()

        val blurredIds = analyzeAll(ids, total, processed, threshold)

        val duration = (System.currentTimeMillis() - startTime) / 1000.0
        Log.d(
            TAG,
            "Blur analysis finished in ${duration}s. " +
                "Threshold=$threshold, blurred: ${blurredIds.size}/$total"
        )

        withContext(Dispatchers.Main) { result.success(blurredIds) }
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    private suspend fun analyzeAll(
        ids: List<Long>,
        total: Int,
        processed: AtomicInteger,
        threshold: Double
    ): List<String> {
        val maxConcurrency = max(2, Runtime.getRuntime().availableProcessors())
        val ioDispatcher = Dispatchers.IO.limitedParallelism(maxConcurrency)

        return withContext(ioDispatcher) {
            ids.map { id ->
                async {
                    val isBlurry = analyzeOne(id, threshold)
                    val done = processed.incrementAndGet()
                    if (done % PROGRESS_LOG_STEP == 0 || done == total) {
                        val percent = (done.toDouble() / total * 100).toInt()
                        Log.d(TAG, "Blur analysis progress: $percent% ($done/$total)")
                    }
                    if (isBlurry) id.toString() else null
                }
            }.awaitAll().filterNotNull()
        }
    }

    private fun analyzeOne(id: Long, threshold: Double): Boolean {
        val uri = ContentUris.withAppendedId(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            id
        )
        var bitmap: Bitmap? = null
        return try {
            bitmap = loadThumbnail(uri) ?: return false
            isBlurred(bitmap, threshold)
        } catch (e: Exception) {
            // Skip unreadable images — don't fail the whole scan.
            Log.w(TAG, "Skipping id=$id: ${e.message}")
            false
        } finally {
            bitmap?.recycle()
        }
    }

    private fun loadThumbnail(uri: Uri): Bitmap? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appContext.contentResolver.loadThumbnail(
                uri,
                Size(THUMB_SIZE, THUMB_SIZE),
                null
            )
        } else {
            decodeSampledBitmap(uri, THUMB_SIZE)
        }
    }

    /**
     * Pre-Q fallback: decode bitmap with inSampleSize so it's downscaled
     * close to THUMB_SIZE without loading the full image into memory.
     */
    private fun decodeSampledBitmap(uri: Uri, reqSize: Int): Bitmap? {
        val resolver = appContext.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, bounds)
        }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sample = 1
        while (bounds.outWidth / (sample * 2) >= reqSize &&
            bounds.outHeight / (sample * 2) >= reqSize
        ) {
            sample *= 2
        }

        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, opts)
        }
    }

    /**
     * Variance of Laplacian blur detector.
     *
     * Converts bitmap to grayscale, applies a 3x3 Laplacian kernel,
     * returns true when the variance of the response is below `threshold`.
     */
    private fun isBlurred(bitmap: Bitmap, threshold: Double): Boolean {
        val w = bitmap.width
        val h = bitmap.height
        if (w < 3 || h < 3) return false

        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)

        val gray = IntArray(w * h)
        for (i in pixels.indices) {
            val p = pixels[i]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF
            // Standard Rec. 601 luma.
            gray[i] = (r * 299 + g * 587 + b * 114) / 1000
        }

        val innerCount = (w - 2) * (h - 2)
        var sum = 0.0
        var sumSq = 0.0

        for (y in 1 until h - 1) {
            val rowAbove = (y - 1) * w
            val row = y * w
            val rowBelow = (y + 1) * w
            for (x in 1 until w - 1) {
                val center = gray[row + x]
                val laplacian = (
                    gray[rowAbove + x] +
                        gray[rowBelow + x] +
                        gray[row + x - 1] +
                        gray[row + x + 1] -
                        4 * center
                    ).toDouble()
                sum += laplacian
                sumSq += laplacian * laplacian
            }
        }

        val mean = sum / innerCount
        val variance = sumSq / innerCount - mean * mean
        return variance < threshold
    }

    private fun queryAllImageIds(): List<Long> {
        val collection: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val projection = arrayOf(MediaStore.Images.Media._ID)
        val sortOrder = "${MediaStore.Images.Media.DATE_TAKEN} ASC"

        val ids = ArrayList<Long>()
        appContext.contentResolver.query(
            collection,
            projection,
            null,
            null,
            sortOrder
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            while (cursor.moveToNext()) {
                ids.add(cursor.getLong(idColumn))
            }
        }
        return ids
    }
}
