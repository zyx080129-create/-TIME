// ============================================================
// 【第一步 · 数据层】DatabaseService
// 面试讲解要点：
// 1. Isar 为什么要用 open() 而不是单例？ -> Isar 实例是轻量的，但仍需
//    全局持有以复用连接；这里封装为 Service，通过 Riverpod 提供单例。
// 2. 读写都用 WriteTxn / Txn：Isar 强事务模型，一次写入要么全成功要么全失败。
// 3. 查询为何用 .filter()...findAll()？ -> Isar 在编译期生成索引代码，
//    查询走 B+ 树索引，性能远超 Sqflite 的全表扫描。
// ============================================================

import 'dart:io';

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/task_model.dart';

/// Isar 数据库服务：封装所有 Task 相关的 CRUD 操作
///
/// 设计原则：
/// - UI 层绝对不能直接操作 Isar 实例，必须通过本 Service
/// - 所有方法返回 Future，方便 Riverpod AsyncNotifier 监听
/// - 抛出异常让调用方（Provider）决定如何处理（展示 SnackBar / 重试）
class DatabaseService {
  static Isar? _sharedIsar;
  static bool _sharedInitialized = false;

  Isar get _isar {
    if (_sharedIsar == null) {
      throw StateError('DatabaseService not initialized. Call init() first.');
    }
    return _sharedIsar!;
  }

  /// 初始化 Isar 数据库
  /// - 必须在 runApp() 前（或至少在第一次使用前）调用
  /// - 通过 path_provider 获取应用沙盒目录，避免权限问题
  Future<void> init() async {
    if (_sharedInitialized) return;

    // 1. 获取应用文档目录（Android: /data/data/.../files, iOS: Documents/）
    //    这一步是必须的，因为不同平台默认路径不一致。
    final Directory dir = await getApplicationDocumentsDirectory();

    // 2. 打开 Isar 数据库
    //    - schemas: 传入所有用 @collection 注解的模型的 Schema（代码生成产物）
    //    - directory: 数据库文件存放路径
    //    - inspector: debug 模式下开启 Isar Inspector（浏览器查看数据库）
    _sharedIsar = await Isar.open(
      [TaskModelSchema],
      directory: dir.path,
      inspector: true,
    );
    _sharedInitialized = true;
  }

  // =============================================================
  // 增 —— 写入新任务
  // =============================================================
  /// 插入一条新任务，返回 Isar 分配的主键 id
  Future<Id> addTask(TaskModel task) async {
    // writeTxn: 开启写事务（读+写）
    // 注意：所有"写入"操作必须在 writeTxn 中执行，否则 Isar 会抛异常。
    return _isar.writeTxn(() async {
      return _isar.taskModels.put(task);
    });
  }

  // =============================================================
  // 删 —— 按 id 删除
  // =============================================================
  /// 根据主键 id 删除任务
  Future<bool> deleteTask(Id id) async {
    return _isar.writeTxn(() async {
      return _isar.taskModels.delete(id);
    });
  }

  // =============================================================
  // 改 —— 更新整条任务
  // =============================================================
  /// 更新任务（主键 id 必须已存在，否则会覆盖同 id 的记录）
  Future<Id> updateTask(TaskModel task) async {
    return _isar.writeTxn(() async {
      return _isar.taskModels.put(task); // put = insert or update
    });
  }

  /// 快捷方法：切换"完成状态"
  Future<void> toggleComplete(TaskModel task) async {
    await _isar.writeTxn(() async {
      task.isCompleted = !task.isCompleted;
      // put 返回值不需要时可以忽略
      await _isar.taskModels.put(task);
    });
  }

  // =============================================================
  // 查 —— 各种条件查询
  // =============================================================
  /// 查所有任务（按触发时间升序，最近的在最前）
  /// 面试要点：sortByDateTime() 是编译期生成的排序方法，
  /// 因为 TaskModel.dateTime 被 @collection 注解了，Isar 为其建了索引。
  Future<List<TaskModel>> getAllTasks() async {
    return _isar.taskModels
        .where()
        .sortByDateTime() // 按触发时间升序
        .findAll();
  }

  /// 查"未完成"的任务（用于启动时重新注册通知）
  /// 面试要点：filter() 里的条件都会走索引查询，性能 O(log n)。
  Future<List<TaskModel>> getPendingTasks() async {
    return _isar.taskModels
        .where()
        .filter()
        .isCompletedEqualTo(false) // 只取未完成
        .sortByDateTime()
        .findAll();
  }

  /// 按主键 id 查单条任务（找不到返回 null）
  Future<TaskModel?> getTaskById(Id id) async {
    return _isar.taskModels.get(id);
  }

  /// 按 notificationId 查任务（通知点击回调时要用）
  /// 面试要点：因为 notificationId 不是主键，我们用 filter 来查。
  /// 如果以后量大，可以加 @Index() 注解在 TaskModel.notificationId 上。
  Future<TaskModel?> getTaskByNotificationId(int notificationId) async {
    return _isar.taskModels
        .where()
        .filter()
        .notificationIdEqualTo(notificationId)
        .findFirst();
  }

  // =============================================================
  // 工具方法
  // =============================================================
  /// 关闭数据库（一般在 dispose 调用，MVP 阶段可以忽略）
  Future<void> close() async {
    if (_sharedIsar != null) {
      await _sharedIsar!.close();
      _sharedIsar = null;
      _sharedInitialized = false;
    }
  }
}
