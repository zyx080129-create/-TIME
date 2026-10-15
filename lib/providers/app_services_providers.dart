// ============================================================
// Providers: 数据库、通知、启动恢复服务
// 面试讲解要点：
// 1. Riverpod Provider 是什么？ -> 编译时安全的依赖注入容器
//    UI 层不直接 new Service，而是通过 ref.read/watch 获取实例。
// 2. @Riverpod(keepAlive: true) 的作用？
//    -> 保持服务单例常驻（默认 Provider 没人用时会 dispose，
//       但数据库/通知服务需要整个 App 生命周期存在）
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/boot_reschedule_service.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

// 代码生成：运行 flutter pub run build_runner build
part 'app_services_providers.g.dart';

// =============================================================
// 数据库服务 —— 全局单例
// =============================================================
@Riverpod(keepAlive: true)
DatabaseService databaseService(DatabaseServiceRef ref) {
  return DatabaseService();
}

// =============================================================
// 通知服务 —— 全局单例
// =============================================================
@Riverpod(keepAlive: true)
NotificationService notificationService(NotificationServiceRef ref) {
  return NotificationService();
}

// =============================================================
// 启动恢复服务 —— 依赖上面两个服务
// Riverpod 自动处理依赖顺序，ref.watch 会在依赖变化时重建
// =============================================================
@Riverpod(keepAlive: true)
BootRescheduleService bootRescheduleService(BootRescheduleServiceRef ref) {
  return BootRescheduleService(
    ref.watch(databaseServiceProvider),
    ref.watch(notificationServiceProvider),
  );
}

// =============================================================
// 应用初始化 Provider：
//   在 main.dart 中等待它完成后再 runApp
//   返回 Future<void>，通过 AsyncValue.when 展示启动屏
// =============================================================
@Riverpod(keepAlive: true)
Future<void> appInitialize(AppInitializeRef ref) async {
  // 1. 初始化数据库
  await ref.read(databaseServiceProvider).init();

  // 2. 通知服务是平台相关能力，可能在某些环境下初始化失败；
  //    这里不能让它导致整个 App 启动失败。应用仍然可以正常管理任务。
  try {
    await ref.read(notificationServiceProvider).init();
  } catch (error, stackTrace) {
    debugPrint('[AppInit] 通知服务初始化失败，已降级继续启动: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  // 3. 启动时重新注册所有未完成任务的通知
  //    若通知服务不可用，直接忽略并继续启动，不影响任务列表功能。
  try {
    await ref.read(bootRescheduleServiceProvider).rescheduleAllPendingTasks();
  } catch (error, stackTrace) {
    debugPrint('[AppInit] 重新注册通知失败，已忽略: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
