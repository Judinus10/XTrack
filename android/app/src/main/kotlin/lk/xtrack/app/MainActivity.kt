package lk.xtrack.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterFragmentActivity() {
    private var pending: MethodChannel.Result? = null
    private var payload: ByteArray? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "xtrack/device").setMethodCallHandler { call, reply ->
            when (call.method) {
                "zone" -> reply.success(TimeZone.getDefault().id)
                "save", "open" -> {
                    if (pending != null) { reply.error("busy","File picker is open",null); return@setMethodCallHandler }
                    val save = call.method == "save"
                    val intent = Intent(if (save) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                    intent.addCategory(Intent.CATEGORY_OPENABLE)
                    intent.putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                    intent.type = if (save) "application/octet-stream" else "*/*"
                    if (save) intent.putExtra(Intent.EXTRA_TITLE, "XTrack.xtb")
                    pending = reply
                    payload = call.arguments as? ByteArray
                    try { startActivityForResult(intent, if (save) 701 else 702) }
                    catch (e: Exception) { pending = null; payload = null; reply.error("picker",e.message,null) }
                }
                else -> reply.notImplemented()
            }
        }
    }
    @Deprecated("Activity result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if (requestCode !in 701..702) return
        val reply = pending ?: return
        val bytes = payload
        pending = null
        payload = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { reply.success(null); return }
        Thread {
            try {
                val result: Any = if (requestCode == 701) {
                    requireNotNull(contentResolver.openOutputStream(uri,"wt")).use { it.write(requireNotNull(bytes)) }
                    true
                } else {
                    requireNotNull(contentResolver.openInputStream(uri)).use { stream ->
                        val out = java.io.ByteArrayOutputStream()
                        val buf = ByteArray(8192)
                        while (true) {
                            val count = stream.read(buf)
                            if (count == -1) break
                            require(out.size() + count <= 32 * 1024 * 1024) { "Backup exceeds 32 MB" }
                            out.write(buf,0,count)
                        }
                        out.toByteArray()
                    }
                }
                runOnUiThread { reply.success(result) }
            } catch (e: Exception) { runOnUiThread { reply.error("file",e.message,null) } }
        }.start()
    }
}
