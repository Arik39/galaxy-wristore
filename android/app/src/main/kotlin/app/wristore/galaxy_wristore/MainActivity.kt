package app.wristore.galaxy_wristore

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The Flutter host, plus the one thing Flutter has no plugin for: Android 17's permission to use the local network,
 * which the app needs before it can look for the watch or talk to it over Wi-Fi.
 */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "request" -> request(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun request(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < LOCAL_NETWORK_API || checkSelfPermission(PERMISSION) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        pending?.success(false)
        pending = result
        requestPermissions(arrayOf(PERMISSION), REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_CODE) return
        pending?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        pending = null
    }

    private companion object {
        const val CHANNEL = "app.wristore/local_network"
        const val PERMISSION = "android.permission.ACCESS_LOCAL_NETWORK"
        const val LOCAL_NETWORK_API = 37
        const val REQUEST_CODE = 37
    }
}
