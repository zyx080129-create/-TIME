// ============================================================
// TaskListNotifier: MVVM 架构中的 ViewModel
// 面试讲解要点：
// 1. AsyncNotifier 的状态是什么？
//    -> AsyncValue<List<TaskModel>>
//       - AsyncLoading: 加载中（展示 CircularProgressIndicator）
//       - AsyncData:    加载成功（展示列表）
//       - AsyncError:   加载失败（展示错误提示 + 重试按钮）
// 2. 为什么所有"写操作"都要返回 Future？
//    -> 因为写数据库 + 注册通知都是异步操作，
//       UI 层通过 ref.invalidate / Future.then 来更新状态。
// 3. 写操作后为什么要调用 state = AsyncData(...)？
//    -> 为了让 Riverpod 通知监听者（UI 层）重新渲染，
//       相当于 setState，但范围更精确。
// ============================================================

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../models/task_model.dart';
import 'app_services_providers.dart';

part 'task_list_provider.g.dart';

// Uuid 单例：用于生成 notificationId（int32）
// 注意：uuid.v4() 生成的是 128 位字符串，我们取其 hashCode，
// hashCode 在 Dart VM 中是 32 位 int，正好适配 notificationId。
const Uuid _uuid = Uuid();
int _nextNotificationId() => _uuid.v4().hashCode & 0x7fffffff;

// =============================================================
// 任务列表 ViewModel
// =============================================================
@riverpod
class TaskListNotifier extends _$TaskListNotifier {
  @override
  Future<List<TaskModel>> build() async {
    // build() = Provider 初始化时执行，返回初始状态
    // 这里直接从数据库加载所有任务
    return ref.watch(databaseServiceProvider).getAllTasks();
  }

  // =============================================================
  // 操作 1：新增任务
  // 流程：写数据库 -> 注册通知 -> 刷新状态
  // =============================================================
  Future<void> addTask({
    required String title,
    String? description,
    required DateTime dateTime,
    required bool isHighPriority,
  }) async {
    // 1. 构造 TaskModel 实体
    final TaskModel task = TaskModel.create(
      title: title,
      description: description,
      dateTime: dateTime,
      isHighPriority: isHighPriority,
      notificationId: _nextNotificationId(),
    );

    // 2. 写入数据库
    final db = ref.read(databaseServiceProvider);
    await db.addTask(task);

    // 3. 注册本地通知
    final notifications = ref.read(notificationServiceProvider);
    await notifications.scheduleTaskNotification(task);

    // 4. 刷新状态：重新读库（最简单的做法，也可以手动拼接 list）
    state = AsyncData(await db.getAllTasks());
    debugPrint('[TaskList] 新增任务成功: $task');
  }

  // =============================================================
  // 操作 2：删除任务
  // 流程：取消通知 -> 删数据库 -> 刷新状态
  // =============================================================
  Future<void> deleteTask(TaskModel task) async {
    final db = ref.read(databaseServiceProvider);
    final notifications = ref.read(notificationServiceProvider);

    // 1. 先取消通知（如果不取消，就算删了任务，到点还是会响）
    await notifications.cancelNotification(task.notificationId);

    // 2. 再删数据库
    await db.deleteTask(task.id);

    // 3. 刷新状态
    state = AsyncData(await db.getAllTasks());
    debugPrint('[TaskList] 删除任务成功: id=${task.id}');
  }

  // =============================================================
  // 操作 3：切换完成状态
  // - 如果被标记为"已完成" -> 取消待触发的通知
  // - 如果被标记为"未完成" -> 重新注册通知（但过期的就不注册了）
  // =============================================================
  Future<void> toggleComplete(TaskModel task) async {
    final db = ref.read(databaseServiceProvider);
    final notifications = ref.read(notificationServiceProvider);

    // 1. 切换状态并写入数据库
    await db.toggleComplete(task);

    // 2. 处理通知
    if (task.isCompleted) {
      // 已完成 -> 取消未来的通知（到点了就不响了）
      await notifications.cancelNotification(task.notificationId);
    } else {
      // 重新设为未完成 -> 尝试重新注册（如果时间还没过期）
      await notifications.scheduleTaskNotification(task);
    }

    // 3. 刷新
    state = AsyncData(await db.getAllTasks());
    debugPrint('[TaskList] 切换完成状态: id=${task.id}, completed=${task.isCompleted}');
  }

  // =============================================================
  // 操作 4：编辑任务（MVP 阶段可以先简化，编辑 = 删旧的 + 加新的）
  // =============================================================
  Future<void> updateTask({
    required TaskModel oldTask,
    required String newTitle,
    String? newDescription,
    required DateTime newDateTime,
    required bool newIsHighPriority,
  }) async {
    final db = ref.read(databaseServiceProvider);
    final notifications = ref.read(notificationServiceProvider);

    // 1. 取消旧的通知（因为时间/优先级都可能变了）
    await notifications.cancelNotification(oldTask.notificationId);

    // 2. 更新实体字段
    oldTask
      ..title = newTitle
      ..description = newDescription
      ..dateTime = newDateTime
      ..isHighPriority = newIsHighPriority;

    // 3. 写回数据库
    await db.updateTask(oldTask);

    // 4. 注册新的通知
    await notifications.scheduleTaskNotification(oldTask);

    // 5. 刷新
    state = AsyncData(await db.getAllTasks());
    debugPrint('[TaskList] 编辑任务成功: id=${oldTask.id}');
  }

  // =============================================================
  // 操作 5：手动刷新（用户下拉刷新用）
  // =============================================================
  Future<void> refresh() async {
    final db = ref.read(databaseServiceProvider);
    state = AsyncData(await db.getAllTasks());
  }
}
