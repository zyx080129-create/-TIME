// ============================================================
// 【第二步 · 核心服务】NotificationService
// 面试讲解要点（重中之重）：
//
// 一、为什么用 zonedSchedule 而不是 schedule？
//   -> schedule 用的是 "距离现在多少毫秒后触发"，
//      如果设备重启/进程被杀，时间会偏差；
//      zonedSchedule 用的是"时区绝对时间点"，更准确。
//
// 二、Android 精准闹钟权限 (SCHEDULE_EXACT_ALARM)：
//   -> Android 12+ 必须动态申请，否则 zonedSchedule 设置的时间
//      只在"大概那个时间"触发（Doze 模式下延迟最多几分钟）。
//      本代码包含权限申请逻辑。
//
// 三、iOS 通知为什么不用 App 侧后台保活？
//   -> iOS 不允许 App 在后台无限保活，本地通知是由系统级进程
//      (UserNotifications.framework) 维护的，App 进程死了也能触发。
//
// 四、高优先级任务的强提醒怎么实现？
//   -> 通过 NotificationDetails.android.fullScreenIntent 启动一个
//      全屏 Intent（即使锁屏也会弹窗），并设置 ongoing=true 让通知
//      无法被划掉，直到用户点击。
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/task_model.dart';
import 'native_alarm_service.dart';
import '../utils/timezone_helper.dart';

/// 通知渠道 ID（Android 8.0+ 必须为通知分配渠道）
/// 面试要点：不同重要级别的通知要走不同渠道，用户可以在系统设置里
/// 单独关掉"普通提醒"但保留"强提醒"。
class NotificationChannels {
  static const String highPriority = 'high_priority_tasks'; // 强提醒渠道
  static const String normal = 'normal_tasks'; // 普通提醒渠道
}

/// 通知服务：封装初始化、注册、取消通知的所有操作
class NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// 是否已初始化
  bool _initialized = false;

  bool get _supportsScheduledNotifications =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// 通知点击回调（由上层注入，用于跳转详情页）
  void Function(int notificationId, String? payload)? onNotificationTap;

  // =============================================================
  // 初始化
  // =============================================================
  /// 初始化通知插件（必须在 main.dart runApp 前或启动时调用）
  Future<void> init() async {
    if (_initialized) return;
    if (!_supportsScheduledNotifications) {
      debugPrint('[NotificationService] 当前平台不支持定时通知，已跳过初始化');
      return;
    }

    try {
      // ---------- 1. Android 端初始化 ----------
      // @mipmap/ic_launcher 是 Flutter 默认生成的启动图标，
      // 通知栏小图标默认用它即可；如需自定义可替换。
      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // ---------- 2. iOS 端初始化 ----------
      // requestAlertPermission / requestSoundPermission 先不在这里申请，
      // 因为 iOS 第一次弹系统权限框非常关键，要在用户愿意授权的场景弹出。
      // 我们先"初始化配置"，真正的权限申请在 requestPermissions() 方法里。
      const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        // iOS 前台通知展示方式：弹窗 + 声音 + 角标
        defaultPresentAlert: true,
        defaultPresentSound: true,
        defaultPresentBadge: true,
      );

      // ---------- 3. 合并两端初始化配置 ----------
      const InitializationSettings initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      // ---------- 4. 执行初始化并注册点击回调 ----------
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // 通知点击时触发
          final int id = response.id ?? 0;
          final String? payload = response.payload;
          debugPrint('[Notification] 点击通知: id=$id, payload=$payload');
          onNotificationTap?.call(id, payload);
        },
      );

      // ---------- 5. 创建 Android 通知渠道（Android 8.0+ 需要） ----------
      // 普通渠道
      await _createAndroidChannel(
        id: NotificationChannels.normal,
        name: '普通提醒',
        description: '普通待办事项的提醒通知',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        enableVibration: true,
      );
      // 强提醒渠道（高优先级 + 全屏弹窗 + 持续响铃）
      await _createAndroidChannel(
        id: NotificationChannels.highPriority,
        name: '强提醒',
        description: '高优先级任务的强制提醒，无法轻易划掉',
        importance: Importance.max,
        priority: Priority.max,
        enableVibration: true,
        enableLights: true,
      );

      _initialized = true;
      debugPrint('[NotificationService] 初始化完成');
    } catch (error, stackTrace) {
      debugPrint('[NotificationService] 初始化失败，已降级使用：$error');
      debugPrintStack(stackTrace: stackTrace);
      _initialized = false;
      rethrow;
    }
  }

  /// 创建 Android 通知渠道（渠道创建一次后不会被覆盖，想改配置需要卸载重装）
  Future<void> _createAndroidChannel({
    required String id,
    required String name,
    required String description,
    required Importance importance,
    required Priority priority,
    bool enableVibration = false,
    bool enableLights = false,
  }) async {
    try {
      final AndroidNotificationChannel channel = AndroidNotificationChannel(
        id,
        name,
        description: description,
        importance: importance,
        enableVibration: enableVibration,
        enableLights: enableLights,
        showBadge: true,
      );
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    } catch (error, stackTrace) {
      debugPrint('[NotificationService] Android channel skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // =============================================================
  // 权限申请
  // =============================================================
  /// 动态申请通知权限 + 精确闹钟权限
  /// 返回值：用户是否"授予了所有必要权限"
  /// 建议在用户第一次添加任务时调用。
  Future<bool> requestPermissions() async {
    if (!_initialized) {
      return false;
    }

    bool allGranted = true;

    try {
      // ---------- Android ----------
      final AndroidFlutterLocalNotificationsPlugin? androidImpl =
          _notificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      if (androidImpl != null) {
        // 1. 普通通知权限（Android 13+ 需要 POST_NOTIFICATIONS）
        final bool? notificationGranted = await androidImpl
            .requestNotificationsPermission();
        debugPrint('[Notification] Android 通知权限: $notificationGranted');
        if (notificationGranted != true) allGranted = false;

        // 2. 精确闹钟权限（Android 12+ 需要 SCHEDULE_EXACT_ALARM）
        //    面试核心：没有这个权限，zonedSchedule 会在 Doze 模式下延迟，
        //    表现为"通知不准时"。
        await androidImpl.requestExactAlarmsPermission();
        final bool? exactAlarmGranted = await androidImpl
            .canScheduleExactNotifications();
        debugPrint('[Notification] Android 精确闹钟权限: $exactAlarmGranted');
        if (exactAlarmGranted != true) allGranted = false;
      }
    } catch (error, stackTrace) {
      debugPrint('[Notification] Android 权限申请失败，忽略: $error');
      debugPrintStack(stackTrace: stackTrace);
      allGranted = false;
    }

    try {
      // ---------- iOS ----------
      // 面试要点：iOS 端实现类名是 IOSFlutterLocalNotificationsPlugin，
      // 老版本的 DarwinFlutterLocalNotificationsPlugin 已经 deprecated 或不存在，
      // 用 dynamic 写法可以同时兼容新旧版本（如果都存在的话）。
      final dynamic iosImpl = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (iosImpl != null) {
        final bool granted = await iosImpl.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
          critical: false,
        );
        debugPrint('[Notification] iOS 通知权限: $granted');
        if (!granted) allGranted = false;
      }
    } catch (error, stackTrace) {
      debugPrint('[Notification] iOS 权限申请失败，忽略: $error');
      debugPrintStack(stackTrace: stackTrace);
      allGranted = false;
    }

    return allGranted;
  }

  // =============================================================
  // 注册定时通知（核心）
  // =============================================================
  /// 为某个任务注册精确时间点的本地通知
  ///
  /// [task] 任务信息，必须包含 notificationId 和 dateTime
  ///
  /// 面试要点：为什么返回 bool？
  ///   -> 如果任务时间已经过期，我们会返回 false 告诉调用方无需注册。
  Future<bool> scheduleTaskNotification(TaskModel task) async {
    if (!_initialized) {
      debugPrint(
        '[Notification] notification service not initialized, skip scheduling: ${task.title}',
      );
      return false;
    }

    try {
      // 1. 先判断是否过期，过期就不注册（省资源）
      if (TimezoneHelper.isExpired(task.dateTime)) {
        debugPrint('[Notification] 跳过过期任务: ${task.title}');
        return false;
      }

      // 2. 转成 TZDateTime（带时区信息的调度时间）
      final tz.TZDateTime scheduledTime = TimezoneHelper.toLocalTZDateTime(
        task.dateTime,
      );

      debugPrint(
        '[Notification] 注册通知: id=${task.notificationId}, '
        'title=${task.title}, time=$scheduledTime, '
        'highPriority=${task.isHighPriority}',
      );

      // 3. 根据是否高优先级构建不同的 NotificationDetails
      final NotificationDetails details = _buildNotificationDetails(
        task.isHighPriority,
      );

      // 4. 调用 zonedSchedule 注册精确时间点通知
      //    - androidScheduleMode: exactAllowWhileIdle = Doze 下也准时触发
      //    - uiLocalNotificationDateInterpretation: wallTime = 按"墙上挂钟"时间
      //    - payload: 序列化任务 id，点击通知时回传
      await _notificationsPlugin.zonedSchedule(
        task.notificationId,
        task.title,
        task.description ?? '点击查看详情',
        scheduledTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
        payload: task.id.toString(), // 点击通知时回传任务主键 id
      );

      if (task.isHighPriority &&
          defaultTargetPlatform == TargetPlatform.android) {
        await NativeAlarmService.schedule(
          notificationId: task.notificationId,
          dateTime: task.dateTime,
        );
      }

      return true;
    } catch (error, stackTrace) {
      debugPrint(
        '[Notification] scheduleTaskNotification failed, skipped: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  /// 构建通知详情（区分高优先级 / 普通）
  NotificationDetails _buildNotificationDetails(bool isHighPriority) {
    // ---- Android ----
    final AndroidNotificationDetails androidDetails;
    if (isHighPriority) {
      // 面试要点：高优先级 = 全屏意图 + 常驻通知 + 最大音量
      androidDetails = AndroidNotificationDetails(
        NotificationChannels.highPriority,
        '强提醒',
        channelDescription: '高优先级任务的强制提醒',
        importance: Importance.max,
        priority: Priority.max,
        // ongoing=true：通知常驻，用户不能划掉；只有 App 主动取消才能消失
        ongoing: true,
        // fullScreenIntent：即使设备锁屏也会弹出全屏页面替代锁屏页
        // （需要 AndroidManifest.xml 中配置 USE_FULL_SCREEN_INTENT 权限）
        fullScreenIntent: true,
        autoCancel: false, // 禁止点击后自动消失，等用户处理完再取消
        showWhen: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]), // 震动节奏
        playSound: true,
        // 不指定不存在的资源，使用系统默认通知音，避免强提醒注册失败。
        icon: '@mipmap/ic_launcher',
      );
    } else {
      androidDetails = AndroidNotificationDetails(
        NotificationChannels.normal,
        '普通提醒',
        channelDescription: '普通待办提醒',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        autoCancel: true, // 点击后自动消失
        showWhen: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 250, 500]),
        icon: '@mipmap/ic_launcher',
      );
    }

    // ---- iOS ----
    // iOS 高优先级通过 sound + interruptionLevel = critical 来体现
    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      // 使用系统默认声音，避免引用项目中不存在的音频资源。
      sound: null,
      // critical: true => 静音/勿扰模式下也响铃（需苹果特殊 entitlements）
      // 普通 MVP 可以设为 false，避免上架审核问题；面试时可以提一下思路。
      interruptionLevel: isHighPriority
          ? InterruptionLevel.timeSensitive
          : InterruptionLevel.active,
    );

    return NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  // =============================================================
  // 取消通知
  // =============================================================
  /// 根据 notificationId 取消已注册的通知（例如：任务完成 / 删除时调用）
  Future<void> cancelNotification(int notificationId) async {
    if (!_initialized) return;
    try {
      debugPrint('[Notification] 取消通知: id=$notificationId');
      await _notificationsPlugin.cancel(notificationId);
      if (defaultTargetPlatform == TargetPlatform.android) {
        await NativeAlarmService.cancel(notificationId);
      }
    } catch (error, stackTrace) {
      debugPrint('[Notification] cancelNotification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// 返回当前平台的通知权限状态，供设置页展示真实状态。
  Future<bool> arePermissionsGranted() async {
    if (!_initialized) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final AndroidFlutterLocalNotificationsPlugin? android =
            _notificationsPlugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >();
        final bool? enabled = await android?.areNotificationsEnabled();
        final bool? exact = await android?.canScheduleExactNotifications();
        return enabled == true && exact == true;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final dynamic ios = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        if (ios == null) return false;
        final bool? granted = await ios.requestPermissions(
          alert: false,
          badge: false,
          sound: false,
        );
        return granted == true;
      }
    } catch (error) {
      debugPrint('[Notification] 查询权限失败: $error');
    }
    return false;
  }

  /// 取消所有已注册的通知（调试用 / 清空所有调度）
  Future<void> cancelAllNotifications() async {
    if (!_initialized) return;
    try {
      debugPrint('[Notification] 取消全部通知');
      await _notificationsPlugin.cancelAll();
    } catch (error, stackTrace) {
      debugPrint('[Notification] cancelAllNotifications failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // =============================================================
  // 辅助：查看待触发的通知（调试用）
  // =============================================================
  Future<List<PendingNotificationRequest>> getPendingNotifications() =>
      _initialized
      ? _notificationsPlugin.pendingNotificationRequests()
      : Future<List<PendingNotificationRequest>>.value(const []);
}
