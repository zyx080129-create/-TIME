// ============================================================
// 【第二步 · 面试核心】BootRescheduleService
// ============================================================
// 面试讲解要点（讲好这一段能拿高分）：
//
// 一、为什么需要"重启恢复"？
//   -> 无论是 Android 还是 iOS，**设备重启后所有用 zonedSchedule 注册的
//      通知都会被系统清空**（因为它们只存在于系统内存的一张表里，没有持久化）。
//      所以必须在 App 启动或开机广播时，重新从数据库读未完成任务，
//      再重新注册一遍通知。
//
// 二、Android Boot Receiver：
//   -> 需要在 AndroidManifest.xml 里注册一个 BroadcastReceiver，
//      监听 RECEIVE_BOOT_COMPLETED 广播。广播触发时，
//      可以用 flutter_local_notifications 的 getNotificationAppLaunchDetails()
//      判断是否从重启广播唤起，如果是就跑 rescheduleAll。
//      （MVP 阶段可以先只做"App 启动时重新注册"，
//       面试时提一下 BroadcastReceiver 这一步作为进阶。）
//
// 三、iOS 端怎么处理？
//   -> iOS 没有 Boot Broadcast 的概念。但 iOS 会自动保留本地通知吗？
//      答案：iOS 在用户重启设备后，**会自动保留之前注册的本地通知**。
//      但有例外：如果用户升级 App、或 App 被卸载重装，通知会丢失。
//      所以 iOS 端仍然建议在 App 启动时做一次全量同步（幂等操作不会有副作用）。
//
// 四、什么叫"幂等"？为什么重要？
//   -> 幂等 = 执行 1 次和执行 N 次结果一样。
//      这里 rescheduleAll 每次都会先 cancelAll，再重新注册，
//      所以即使被重复调用也不会重复响铃。
// ============================================================

import 'package:flutter/material.dart';

import '../models/task_model.dart';
import 'database_service.dart';
import 'notification_service.dart';

/// 启动/重启后，把"数据库中未完成的任务"重新注册到通知系统
/// 设计原则：幂等（多次调用结果一致，不会重复注册）
class BootRescheduleService {
  final DatabaseService _database;
  final NotificationService _notifications;

  BootRescheduleService(this._database, this._notifications);

  /// 执行"全量重新注册"
  ///
  /// 执行流程（面试时要讲清楚这 4 步）：
  ///   1. 先取消当前所有待触发的通知（清空旧的，防重复）
  ///   2. 从数据库查出所有 isCompleted=false 的任务
  ///   3. 遍历每条任务：如果触发时间还没到 -> 注册通知；过期 -> 跳过
  ///   4. 日志统计（方便调试 + 面试展示）
  Future<RescheduleResult> rescheduleAllPendingTasks() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    debugPrint('[BootReschedule] ===== 开始重新注册通知 =====');

    // Step 1: 清空当前所有待触发通知（幂等的关键）
    await _notifications.cancelAllNotifications();

    // Step 2: 从数据库查未完成任务
    final List<TaskModel> pendingTasks = await _database.getPendingTasks();
    debugPrint('[BootReschedule] 数据库中未完成任务数: ${pendingTasks.length}');

    int scheduled = 0; // 成功注册数
    int skippedExpired = 0; // 过期跳过数

    // Step 3: 逐个注册
    for (final TaskModel task in pendingTasks) {
      final bool ok = await _notifications.scheduleTaskNotification(task);
      if (ok) {
        scheduled++;
      } else {
        skippedExpired++;
      }
    }

    stopwatch.stop();
    final RescheduleResult result = RescheduleResult(
      totalPending: pendingTasks.length,
      scheduled: scheduled,
      skippedExpired: skippedExpired,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );

    debugPrint('[BootReschedule] ===== 完成 ===== '
        '总数: ${result.totalPending}, '
        '注册成功: ${result.scheduled}, '
        '过期跳过: ${result.skippedExpired}, '
        '耗时: ${result.elapsedMs}ms');

    return result;
  }
}

/// 重注册结果统计（用于调试/SnackBar 展示）
class RescheduleResult {
  final int totalPending;
  final int scheduled;
  final int skippedExpired;
  final int elapsedMs;

  const RescheduleResult({
    required this.totalPending,
    required this.scheduled,
    required this.skippedExpired,
    required this.elapsedMs,
  });

  @override
  String toString() => 'RescheduleResult('
      'total: $totalPending, '
      'scheduled: $scheduled, '
      'expired: $skippedExpired, '
      'cost: ${elapsedMs}ms)';
}
