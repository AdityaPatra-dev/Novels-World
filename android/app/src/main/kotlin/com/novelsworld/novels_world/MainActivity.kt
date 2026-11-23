package com.novelsworld.novels_world

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.core.content.FileProvider
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
import com.googlecode.tesseract.android.TessBaseAPI
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : AudioServiceActivity() {
    private val UPDATER_CHANNEL = "com.novelsworld.novels_world/app_updater"
    private val PDF_CHANNEL = "com.novelsworld.novels_world/pdf_renderer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // App Updater channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val filePath = call.argument<String>("filePath")
                if (filePath != null) {
                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            this,
                            "${applicationContext.packageName}.fileprovider",
                            file
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "File path cannot be null", null)
                }
            } else {
                result.notImplemented()
            }
        }

        // Native PDF Renderer channel using Android's built-in PdfRenderer
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PDF_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPageCount" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("INVALID_ARGUMENT", "File path cannot be null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "PDF file not found at $filePath", null)
                            return@setMethodCallHandler
                        }
                        val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                        val renderer = PdfRenderer(pfd)
                        val count = renderer.pageCount
                        renderer.close()
                        pfd.close()
                        result.success(count)
                    } catch (e: Exception) {
                        result.error("RENDER_ERROR", e.message, null)
                    }
                }
                "renderPages" -> {
                    val filePath = call.argument<String>("filePath")
                    val outputDir = call.argument<String>("outputDir")
                    val dpi = call.argument<Int>("dpi") ?: 150
                    val maxPages = call.argument<Int>("maxPages") ?: 1000

                    if (filePath == null || outputDir == null) {
                        result.error("INVALID_ARGUMENT", "filePath and outputDir must not be null", null)
                        return@setMethodCallHandler
                    }

                    val mainHandler = Handler(Looper.getMainLooper())
                    Thread {
                        var pfd: ParcelFileDescriptor? = null
                        var renderer: PdfRenderer? = null
                        try {
                            val file = File(filePath)
                            if (!file.exists()) {
                                mainHandler.post { result.error("FILE_NOT_FOUND", "PDF file not found at $filePath", null) }
                                return@Thread
                            }
                            val outDir = File(outputDir)
                            if (!outDir.exists()) {
                                outDir.mkdirs()
                            }

                            pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                            renderer = PdfRenderer(pfd)
                            val totalPages = minOf(renderer.pageCount, maxPages)
                            val scale = dpi.toFloat() / 72.0f
                            val generatedPaths = ArrayList<String>()

                            for (i in 0 until totalPages) {
                                val page = renderer.openPage(i)
                                val width = (page.width * scale).toInt()
                                val height = (page.height * scale).toInt()

                                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                                bitmap.eraseColor(Color.WHITE)
                                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                page.close()

                                val outFile = File(outDir, "page_${i + 1}.jpg")
                                val fos = FileOutputStream(outFile)
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, fos)
                                fos.flush()
                                fos.close()
                                bitmap.recycle()

                                generatedPaths.add(outFile.absolutePath)
                            }

                            renderer.close()
                            renderer = null
                            pfd.close()
                            pfd = null

                            mainHandler.post { result.success(generatedPaths) }
                        } catch (e: Exception) {
                            try {
                                renderer?.close()
                                pfd?.close()
                            } catch (_: Exception) {}
                            mainHandler.post { result.error("RENDER_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "extractPagesWithOcr" -> {
                    val filePath = call.argument<String>("filePath")
                    val outputDir = call.argument<String>("outputDir")
                    val script = call.argument<String>("script") ?: "latin"
                    val dpi = call.argument<Int>("dpi") ?: 150
                    val maxPages = call.argument<Int>("maxPages") ?: 1000
                    val tessDataDir = call.argument<String>("tessDataDir") ?: ""

                    if (filePath == null || outputDir == null) {
                        result.error("INVALID_ARGUMENT", "filePath and outputDir must not be null", null)
                        return@setMethodCallHandler
                    }

                    val mainHandler = Handler(Looper.getMainLooper())
                    Thread {
                        var pfd: ParcelFileDescriptor? = null
                        var renderer: PdfRenderer? = null
                        var tess: TessBaseAPI? = null
                        var recognizer: com.google.mlkit.vision.text.TextRecognizer? = null
                        try {
                            val file = File(filePath)
                            if (!file.exists()) {
                                mainHandler.post { result.error("FILE_NOT_FOUND", "PDF file not found at $filePath", null) }
                                return@Thread
                            }
                            val outDir = File(outputDir)
                            if (!outDir.exists()) {
                                outDir.mkdirs()
                            }

                            val isTesseract = script.startsWith("ori") || (script.startsWith("hin") && tessDataDir.isNotEmpty() && File(tessDataDir, "tessdata/hin.traineddata").exists())

                            if (isTesseract && tessDataDir.isNotEmpty()) {
                                tess = TessBaseAPI()
                                val initialized = tess.init(tessDataDir, script)
                                if (!initialized) {
                                    tess.recycle()
                                    tess = null
                                }
                            }
                            if (tess == null) {
                                recognizer = if (script == "devanagari") {
                                    TextRecognition.getClient(DevanagariTextRecognizerOptions.Builder().build())
                                } else {
                                    TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                                }
                            }

                            pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                            renderer = PdfRenderer(pfd)
                            val totalPages = minOf(renderer.pageCount, maxPages)
                            val scale = dpi.toFloat() / 72.0f
                            val pagesResult = ArrayList<Map<String, Any>>()

                            for (i in 0 until totalPages) {
                                val page = renderer.openPage(i)
                                val width = (page.width * scale).toInt()
                                val height = (page.height * scale).toInt()

                                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                                bitmap.eraseColor(Color.WHITE)
                                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                page.close()

                                var extractedText = ""
                                try {
                                    val maxDim = maxOf(width, height)
                                    val ocrBitmap = if (maxDim > 1024) {
                                        val ocrScale = 1024.0f / maxDim.toFloat()
                                        Bitmap.createScaledBitmap(bitmap, (width * ocrScale).toInt(), (height * ocrScale).toInt(), true)
                                    } else {
                                        bitmap
                                    }

                                    if (tess != null) {
                                        tess.setImage(ocrBitmap)
                                        extractedText = tess.utF8Text
                                        tess.clear()
                                    } else if (recognizer != null) {
                                        val inputImage = InputImage.fromBitmap(ocrBitmap, 0)
                                        val visionText = Tasks.await(recognizer.process(inputImage))
                                        extractedText = visionText.text ?: ""
                                    }

                                    if (ocrBitmap != bitmap) {
                                        ocrBitmap.recycle()
                                    }
                                } catch (_: Exception) {}

                                var savedImagePath = ""
                                if (i == 0 || extractedText.trim().length < 50) {
                                    val outFile = File(outDir, "page_${i + 1}.jpg")
                                    val fos = FileOutputStream(outFile)
                                    bitmap.compress(Bitmap.CompressFormat.JPEG, 85, fos)
                                    fos.flush()
                                    fos.close()
                                    savedImagePath = outFile.absolutePath
                                }
                                bitmap.recycle()

                                val pageMap = HashMap<String, Any>()
                                pageMap["pageNumber"] = i + 1
                                pageMap["text"] = extractedText
                                if (savedImagePath.isNotEmpty()) {
                                    pageMap["imagePath"] = savedImagePath
                                }
                                pagesResult.add(pageMap)
                            }

                            tess?.recycle()
                            recognizer?.close()
                            renderer.close()
                            renderer = null
                            pfd.close()
                            pfd = null

                            mainHandler.post { result.success(pagesResult) }
                        } catch (e: Exception) {
                            try {
                                tess?.recycle()
                                recognizer?.close()
                                renderer?.close()
                                pfd?.close()
                            } catch (_: Exception) {}
                            mainHandler.post { result.error("OCR_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "extractTextFromImages" -> {
                    val imagePaths = call.argument<List<String>>("imagePaths") ?: emptyList()
                    val script = call.argument<String>("script") ?: "latin"
                    val tessDataDir = call.argument<String>("tessDataDir") ?: ""

                    val mainHandler = Handler(Looper.getMainLooper())
                    Thread {
                        var tess: TessBaseAPI? = null
                        var recognizer: com.google.mlkit.vision.text.TextRecognizer? = null
                        try {
                            val isTesseract = script.startsWith("ori") || (script.startsWith("hin") && tessDataDir.isNotEmpty() && File(tessDataDir, "tessdata/hin.traineddata").exists())
                            if (isTesseract && tessDataDir.isNotEmpty()) {
                                tess = TessBaseAPI()
                                val initialized = tess.init(tessDataDir, script)
                                if (!initialized) {
                                    tess.recycle()
                                    tess = null
                                }
                            }
                            if (tess == null) {
                                recognizer = if (script == "devanagari") {
                                    TextRecognition.getClient(DevanagariTextRecognizerOptions.Builder().build())
                                } else {
                                    TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                                }
                            }

                            val results = ArrayList<Map<String, Any>>()
                            for (path in imagePaths) {
                                val imgFile = File(path)
                                var text = ""
                                if (imgFile.exists()) {
                                    val bitmap = BitmapFactory.decodeFile(imgFile.absolutePath)
                                    if (bitmap != null) {
                                        val maxDim = maxOf(bitmap.width, bitmap.height)
                                        val ocrBitmap = if (maxDim > 1024) {
                                            val ocrScale = 1024.0f / maxDim.toFloat()
                                            Bitmap.createScaledBitmap(bitmap, (bitmap.width * ocrScale).toInt(), (bitmap.height * ocrScale).toInt(), true)
                                        } else {
                                            bitmap
                                        }

                                        try {
                                            if (tess != null) {
                                                tess.setImage(ocrBitmap)
                                                text = tess.utF8Text
                                                tess.clear()
                                            } else if (recognizer != null) {
                                                val inputImage = InputImage.fromBitmap(ocrBitmap, 0)
                                                val visionText = Tasks.await(recognizer.process(inputImage))
                                                text = visionText.text ?: ""
                                            }
                                        } catch (_: Exception) {}

                                        if (ocrBitmap != bitmap) {
                                            ocrBitmap.recycle()
                                        }
                                        bitmap.recycle()
                                    }
                                }
                                val item = HashMap<String, Any>()
                                item["imagePath"] = path
                                item["text"] = text
                                results.add(item)
                            }

                            tess?.recycle()
                            recognizer?.close()
                            mainHandler.post { result.success(results) }
                        } catch (e: Exception) {
                            try {
                                tess?.recycle()
                                recognizer?.close()
                            } catch (_: Exception) {}
                            mainHandler.post { result.error("OCR_ERROR", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }
}
