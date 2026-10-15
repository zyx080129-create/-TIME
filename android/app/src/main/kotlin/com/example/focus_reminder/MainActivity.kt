package com.example.focus_reminder

import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val channelName = "focus_reminder/native_alarm"
	private val ringtoneRequestCode = 7001
	private var pendingRingtoneResult: MethodChannel.Result? = null
	private var pickingCustom = false

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
			when (call.method) {
				"pickSystemRingtone" -> pickRingtone(result, false)
				"pickCustomRingtone" -> pickRingtone(result, true)
				"scheduleAlarm" -> scheduleAlarm(call.argument<Int>("id")!!, call.argument<Long>("triggerAtMillis")!!, result)
				"cancelAlarm" -> cancelAlarm(call.argument<Int>("id")!!, result)
				else -> result.notImplemented()
			}
		}
	}

	private fun pickRingtone(result: MethodChannel.Result, custom: Boolean) {
		pendingRingtoneResult = result
		pickingCustom = custom
		val intent = if (custom) Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
			type = "audio/*"
			addCategory(Intent.CATEGORY_OPENABLE)
			addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
		} else Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
			putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
			putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "选择提醒铃声")
			putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
		}
		startActivityForResult(intent, ringtoneRequestCode)
	}

	override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		super.onActivityResult(requestCode, resultCode, data)
		if (requestCode != ringtoneRequestCode) return
		val uri = if (pickingCustom) data?.data else data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
		if (uri == null || resultCode != Activity.RESULT_OK) {
			pendingRingtoneResult?.success(null)
		} else {
			if (pickingCustom) contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
			getSharedPreferences(RingtoneService.PREFERENCES, MODE_PRIVATE).edit().putString(RingtoneService.KEY_URI, uri.toString()).apply()
			pendingRingtoneResult?.success(mapOf("uri" to uri.toString(), "title" to (RingtoneManager.getRingtone(this, uri)?.getTitle(this) ?: "自定义铃声")))
		}
		pendingRingtoneResult = null
	}

	private fun scheduleAlarm(id: Int, triggerAtMillis: Long, result: MethodChannel.Result) {
		val intent = Intent(this, AlarmReceiver::class.java).putExtra(RingtoneService.EXTRA_ID, id)
		val pending = PendingIntent.getBroadcast(this, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
		getSystemService(AlarmManager::class.java).setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pending)
		result.success(null)
	}

	private fun cancelAlarm(id: Int, result: MethodChannel.Result) {
		val pending = PendingIntent.getBroadcast(this, id, Intent(this, AlarmReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
		getSystemService(AlarmManager::class.java).cancel(pending)
		stopService(Intent(this, RingtoneService::class.java))
		result.success(null)
	}
}
