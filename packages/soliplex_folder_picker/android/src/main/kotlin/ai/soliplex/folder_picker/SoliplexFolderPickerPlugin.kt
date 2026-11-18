package ai.soliplex.folder_picker

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.io.InputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * The Android side of `SoliplexFolderPicker`; the Dart class documents the
 * channel contract.
 *
 * The folder comes from `ACTION_OPEN_DOCUMENT_TREE`, and is walked and read
 * through the tree it grants. Its file-system path would not do: scoped
 * storage hides other apps' files under it from this app.
 */
class SoliplexFolderPickerPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var resolver: ContentResolver
    private var activity: ActivityPluginBinding? = null
    private var pendingPick: Result? = null

    // Cached, not single: uploads read several files at once.
    private val io: ExecutorService = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private val streams = ConcurrentHashMap<Int, InputStream>()
    private val nextHandle = AtomicInteger()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        resolver = binding.applicationContext.contentResolver
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        streams.values.forEach { runCatching { it.close() } }
        streams.clear()
        io.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activity?.removeActivityResultListener(this)
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "pick" -> pick(result)
            "open" -> {
                val uri = call.argument<String>("uri")!!
                background(result, "open_failed", "Could not open $uri") {
                    val stream = resolver.openInputStream(Uri.parse(uri))
                        ?: error("the provider returned no stream")
                    val handle = nextHandle.incrementAndGet()
                    streams[handle] = stream
                    handle
                }
            }
            "read" -> {
                val handle = call.argument<Int>("handle")!!
                val max = call.argument<Int>("max")!!
                background(result, "read_failed", "Could not read file $handle") {
                    val stream = streams[handle] ?: error("no open file $handle")
                    val buffer = ByteArray(max)
                    val count = stream.read(buffer)
                    when {
                        count < 0 -> null
                        count == max -> buffer
                        else -> buffer.copyOf(count)
                    }
                }
            }
            "close" -> {
                runCatching { streams.remove(call.argument<Int>("handle")!!)?.close() }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun pick(result: Result) {
        val binding = activity
        if (binding == null) {
            result.error("no_activity", "The folder picker needs a foreground activity", null)
            return
        }
        if (pendingPick != null) {
            result.error("already_active", "A folder pick is already open", null)
            return
        }
        pendingPick = result
        binding.activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success(null)
            return true
        }
        background(result, "list_failed", "Could not list $tree") { walk(tree) }
        return true
    }

    private fun walk(tree: Uri): Map<String, Any?> {
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val name = displayName(DocumentsContract.buildDocumentUriUsingTree(tree, rootId))
        val files = mutableListOf<Map<String, Any?>>()
        // Iterative, so a deep tree cannot overflow the stack.
        val pending = ArrayDeque(listOf(rootId to ""))
        while (pending.isNotEmpty()) {
            val (parentId, prefix) = pending.removeFirst()
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
            resolver.query(children, COLUMNS, null, null, null)?.use { row ->
                while (row.moveToNext()) {
                    val id = row.getString(0)
                    val path = prefix + row.getString(1)
                    if (row.getString(2) == Document.MIME_TYPE_DIR) {
                        pending.add(id to "$path/")
                    } else {
                        files += mapOf(
                            "path" to path,
                            "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                            "size" to if (row.isNull(3)) null else row.getLong(3),
                        )
                    }
                }
            } ?: error("the provider could not list $children")
        }
        return mapOf("name" to name, "files" to files)
    }

    private fun displayName(document: Uri): String =
        resolver.query(document, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
            ?: document.lastPathSegment.orEmpty().substringAfterLast(':').substringAfterLast('/')

    /** Runs [work] off the main thread and answers [result] on it. */
    private fun background(result: Result, code: String, message: String, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error(code, "$message: ${e.message ?: e.javaClass.name}", null) }
            }
        }
    }

    private companion object {
        const val CHANNEL = "ai.soliplex/folder_picker"
        const val REQUEST = 0x50F0
        val COLUMNS = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE,
        )
    }
}
