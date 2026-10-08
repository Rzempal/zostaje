package app.michalrapala.zostaje

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Sejf na kod odzyskiwania kopii - kod wedruje na nowy telefon
        // razem z kontem Google (Block Store). Mostek do Lokalnego Silnika AI
        // (skan paragonow) zniknal razem z zakladka Biezace (ADR-035).
        val keyVault = KeyVaultBridge(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KeyVaultBridge.CHANNEL)
            .setMethodCallHandler(keyVault::handle)
    }
}
