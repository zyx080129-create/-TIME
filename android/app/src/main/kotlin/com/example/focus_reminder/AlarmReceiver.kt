package com.example.focus_reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == RingtoneService.ACTION_STOP) {
            context.stopService(Intent(context, RingtoneService::class.java))
            return
        }
        val serviceIntent = Intent(context, RingtoneService::class.java).apply {
            putExtra(RingtoneService.EXTRA_ID, intent.getIntExtra(RingtoneService.EXTRA_ID, 0))
        }
        context.startForegroundService(serviceIntent)
    }
}
