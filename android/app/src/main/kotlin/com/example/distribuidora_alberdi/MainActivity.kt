package com.distribuidoraalberdi.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

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