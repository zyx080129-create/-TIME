import 'package:flutter/services.dart';

class NativeAlarmService {
  static const MethodChannel _channel = MethodChannel(
    'focus_reminder/native_alarm',
  );

  static Future<Map<String, String>?> pickSystemRingtone() async {
    final Map<Object?, Object?>? result = await _channel.invokeMethod(
      'pickSystemRingtone',
    );
    return _asStringMap(result);
  }

  static Future<Map<String, String>?> pickCustomRingtone() async {
    final Map<Object?, Object?>? result = await _channel.invokeMethod(
      'pickCustomRingtone',
    );
    return _asStringMap(result);
  }

  static Future<void> schedule({
    required int notificationId,
    required DateTime dateTime,
  }) async {
    await _channel.invokeMethod('scheduleAlarm', <String, Object>{
      'id': notificationId,
      'triggerAtMillis': dateTime.millisecondsSinceEpoch,
    });
  }

  static Future<void> cancel(int notificationId) async {
    await _channel.invokeMethod('cancelAlarm', <String, Object>{
      'id': notificationId,
    });
  }

  static Map<String, String>? _asStringMap(Map<Object?, Object?>? value) {
    if (value == null) return null;
    return value.map((Object? key, Object? item) => MapEntry('$key', '$item'));
  }
}
