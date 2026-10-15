// ============================================================
// 【工具层】TimezoneHelper
// 面试讲解要点（极其重要，面试官必问）：
// 1. 为什么不能直接用 DateTime.now() 加 Duration？
//    -> 因为夏令时切换、跨时区旅行会导致 DateTime 与真实时间差 1 小时，
//       用户设置的"明早 8 点"可能实际在 7 点或 9 点响。
// 2. timezone 包原理：
//    -> 用 IANA 时区数据库（tzdb），把"本地 DateTime"转换为"带时区信息的
//       TZDateTime"，zonedSchedule 内部会用 TZDateTime 来调度。
// ============================================================

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// 时区相关的辅助工具
/// 必须在 runApp() 前调用 TimezoneHelper.init()
class TimezoneHelper {
  static late final String _localTimezoneName;
  static late final tz.Location _localLocation;

  /// 是否已初始化（防止重复初始化）
  static bool _initialized = false;

  /// 初始化时区数据库 + 加载本地时区
  /// 必须在 App 启动时调用一次（main.dart 中）
  static Future<void> init() async {
    if (_initialized) return;

    // 1. 加载 IANA 时区数据库（包含所有国家的夏令时规则）
    tz.initializeTimeZones();

    // 2. 通过 Flutter 平台通道获取设备本地时区名称，例如 "Asia/Shanghai"
    //    不能直接读 DateTime.now().timeZoneName，因为某些 Android 设备
    //    返回的是缩写（如 "CST"），不是 IANA 标准名。
    _localTimezoneName = await FlutterTimezone.getLocalTimezone();

    // 3. 缓存 Location 对象，供后续 toLocal() 使用
    _localLocation = tz.getLocation(_localTimezoneName);
    tz.setLocalLocation(_localLocation);

    _initialized = true;
  }

  /// 把普通的 DateTime（用户选择的本地日期时间）
  /// 转换为带时区信息的 TZDateTime（zonedSchedule 要求的入参）
  ///
  /// 面试要点：
  ///   DateTime(2026, 9, 3, 8, 0, 0) 在上海时区就是 2026-09-03 08:00 UTC+8
  ///   转换后即使设备飞到其他时区，也会按"原设置时区的 8 点"触发吗？
  ///   -> 不会。zonedSchedule 会按"设备当前本地时区的那个时间点"触发，
  ///      这正是用户想要的效果：设置的是"当地早上 8 点"。
  ///      如果你需要"绝对 UTC 时间点"，用 TZDateTime.utc()。
  static tz.TZDateTime toLocalTZDateTime(DateTime dateTime) {
    if (!_initialized) {
      throw StateError('TimezoneHelper not initialized. Call init() first.');
    }
    // 要点：用 Location 从 DateTime 的"年月日时分秒"重建一个带时区的值，
    // 而不是用 TZDateTime.from(dateTime, location)，
    // 因为 from() 会做 UTC 换算，结果是错的。
    return tz.TZDateTime(
      _localLocation,
      dateTime.year,
      dateTime.month,
      dateTime.day,
      dateTime.hour,
      dateTime.minute,
      dateTime.second,
    );
  }

  /// 获取本地当前时间的 TZDateTime（用于比较"是否已过期"）
  static tz.TZDateTime get nowLocal => tz.TZDateTime.now(_localLocation);

  /// 判断任务触发时间是否已过期（系统重启重排时需要跳过过期任务）
  static bool isExpired(DateTime dateTime) {
    final tzDateTime = toLocalTZDateTime(dateTime);
    return tzDateTime.isBefore(nowLocal);
  }
}
