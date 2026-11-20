package com.distribuidoraalberdi.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Guarda la imagen con precio en la galería (Imágenes/Alberdi).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alberdi/galeria")
            .setMethodCallHandler { call, result ->
                if (call.method != "guardarImagen") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val nombre = call.argument<String>("nombre") ?: "Alberdi.jpg"
                if (bytes == null) {
                    result.error("datos", "Sin imagen", null)
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    try {
                        guardarEnGaleria(bytes, nombre)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("fallo", e.message, null)
                    }
                } else {
                    result.error("antiguo", "Android anterior a 10", null)
                }
            }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun guardarEnGaleria(bytes: ByteArray, nombre: String) {
        val valores = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, nombre)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Alberdi")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, valores)
            ?: throw IllegalStateException("No se pudo crear la imagen")
        val salida = contentResolver.openOutputStream(uri)
            ?: throw IllegalStateException("No se pudo escribir la imagen")
        salida.use { it.write(bytes) }
        valores.clear()
        valores.put(MediaStore.Images.Media.IS_PENDING, 0)
        contentResolver.update(uri, valores, null, null)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val sonidoPredeterminado =
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build()

            val canal = NotificationChannel(
                "pedidos_importantes",
                "Pedidos nuevos",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Avisos cuando ingresa un nuevo pedido"
                enableVibration(true)
                setSound(sonidoPredeterminado, audioAttributes)
            }

            notificationManager.createNotificationChannel(canal)
        }
    }
}
