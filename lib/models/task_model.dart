// ============================================================
// 【第一步 · 数据模型】TaskModel
// 面试讲解要点：
// 1. 为什么用 Isar 注解？ -> 编译期生成索引/序列化代码，运行时零反射，性能极高
// 2. Id 类型为什么是 Id (int64)？ -> Isar 内部用 int64 主键，支持 .autoIncrement()
// 3. notificationId 为什么单独存？ -> 任务 ID ≠ 通知 ID，
//    flutter_local_notifications 用 int32 标识通知，我们用独立字段映射
// ============================================================

import 'package:isar/isar.dart';

// Isar 代码生成：在项目根目录运行
//   flutter pub run build_runner build --delete-conflicting-outputs
// 生成文件：task_model.g.dart
part 'task_model.g.dart';

/// 任务数据模型 —— 既是业务实体也是 Isar 数据库表结构
/// 注解 @collection 告诉 build_runner 为此类生成数据库适配代码
@collection
class TaskModel {
  TaskModel();

  // ---------- 主键字段 ----------
  /// Isar 主键（int64）。如果不赋值就写入，Isar 会自动分配自增 ID。
  /// 用 Id 类型（本质是 int）是 Isar 的约定。
  Id id = Isar.autoIncrement;

  // ---------- 业务字段 ----------
  /// 任务标题（展示在列表和通知标题中）
  late String title;

  /// 任务详情描述（可选，通知展开时显示）
  String? description;

  /// 任务触发时间（ DateTime 本地时区）
  /// 注意：这里存"用户所期望触发的本地时间 DateTime"，
  /// 真正调度通知时会用 timezone 包转为带时区信息的 TZDateTime。
  late DateTime dateTime;

  /// 是否为高优先级（强提醒）
  /// - true： 通知会持续响铃 + 点击后跳转到"强提醒完成页面"
  /// - false：普通通知，用户可一键划掉
  late bool isHighPriority;

  /// 是否已完成
  late bool isCompleted;

  // ---------- 通知映射字段 ----------
  /// flutter_local_notifications 要求使用 int32 作为通知 ID，
  /// 所以单独存此字段来关联 "Task <-> Notification"。
  /// 为什么不用 id？因为 Isar 的 id 是 int64，通知插件只认 int32，
  /// 极端情况下会溢出，而且解耦两者有利于以后换通知方案。
  late int notificationId;

  /// 创建时间（用于排序、历史追溯）
  late DateTime createdAt;

  // ---------- 便捷构造函数 ----------
  /// 创建新任务的便捷构造器
  TaskModel.create({
    required this.title,
    this.description,
    required this.dateTime,
    this.isHighPriority = false,
    this.isCompleted = false,
    required this.notificationId,
  }) : createdAt = DateTime.now();

  // ---------- 调试辅助 ----------
  @override
  String toString() {
    return 'TaskModel{id: $id, title: $title, dateTime: $dateTime, '
        'isHighPriority: $isHighPriority, isCompleted: $isCompleted, '
        'notificationId: $notificationId}';
  }
}
