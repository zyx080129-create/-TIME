// ============================================================
// TaskListPage - 待办列表主页
// ============================================================
// UI 交互要点（面试可以讲）：
// 1. 任务排序：未完成在前 → 按触发时间升序；已完成在最后
//    为什么不直接让数据库排？—— Isar 多条件排序可以用 .sort()，
//    但 Dart 侧手动排可以让我们在面试时展示"业务逻辑分层"。
// 2. Dismissible 侧滑删除：Flutter 内置组件，无需第三方库
//    （如果需要更炫酷的左右两侧动作，可以上 flutter_slidable，面试时可提）
// 3. 高优先级任务用 Card + 红色左边界标识，一眼可辨
// 4. 用 Consumer 只包裹需要变化的局部（AppBar 计数），
//    避免整个列表重建（优化性能，面试加分点）
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:isar/isar.dart';

import '../models/task_model.dart';
import '../providers/task_list_provider.dart';
import '../providers/app_services_providers.dart';
import '../services/notification_service.dart';
import 'add_task_sheet.dart';

class TaskListPage extends ConsumerStatefulWidget {
  const TaskListPage({super.key});

  @override
  ConsumerState<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends ConsumerState<TaskListPage> {
  late final Timer _refreshTimer;
  final Set<int> _remindedTaskIds = <int>{};

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _showDueTaskReminder();
        ref.invalidate(taskListNotifierProvider);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  void _showDueTaskReminder() {
    final AsyncValue<List<TaskModel>> tasksState = ref.read(
      taskListNotifierProvider,
    );
    final List<TaskModel>? tasks = tasksState.valueOrNull;
    if (tasks == null) return;

    final DateTime now = DateTime.now();
    for (final TaskModel task in tasks) {
      if (task.isCompleted ||
          task.dateTime.isAfter(now) ||
          _remindedTaskIds.contains(task.id)) {
        continue;
      }

      _remindedTaskIds.add(task.id);
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useSafeArea: false,
        builder: (BuildContext dialogContext) => task.isHighPriority
            ? _FullScreenReminderDialog(task: task)
            : AlertDialog(
                icon: const Icon(Icons.alarm, size: 42),
                title: const Text('提醒时间到了'),
                content: Text(task.title),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('知道了'),
                  ),
                ],
              ),
      );
      break;
    }
  }

  Future<void> _checkNotificationPermissions() async {
    final NotificationService service = ref.read(notificationServiceProvider);
    final bool granted = await service.arePermissionsGranted();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('通知权限状态'),
        content: Text(
          granted
              ? '通知权限和精确闹钟权限已开启，任务可以按时提醒。'
              : '通知权限或精确闹钟权限未完全开启。点击“申请权限”后，请在系统页面允许通知和精确闹钟。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          if (!granted)
            FilledButton(
              onPressed: () async {
                await service.requestPermissions();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('申请权限'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 监听任务列表状态（AsyncValue = loading / data / error）
    final AsyncValue<List<TaskModel>> tasksAsync = ref.watch(
      taskListNotifierProvider,
    );
    final bool showFloatingAddButton = tasksAsync.maybeWhen(
      data: (List<TaskModel> tasks) => tasks.isNotEmpty,
      orElse: () => true,
    );

    return Scaffold(
      // =============== 顶部 AppBar ===============
      appBar: AppBar(
        title: const Text(
          '强效提醒与专注管理',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 2,
        scrolledUnderElevation: 4,
        actions: [
          IconButton(
            tooltip: '检查通知权限',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: _checkNotificationPermissions,
          ),
          // 待办统计 Chip：用 Consumer 局部刷新，避免整个 AppBar 重建
          Consumer(
            builder: (BuildContext ctx, WidgetRef localRef, _) {
              // 这里重新 watch 一次，只用来计算"未完成数量"
              final AsyncValue<List<TaskModel>> localTasks = localRef.watch(
                taskListNotifierProvider,
              );
              final int pendingCount = localTasks.maybeWhen(
                data: (List<TaskModel> list) =>
                    list.where((TaskModel t) => !t.isCompleted).length,
                orElse: () => 0,
              );
              // 只有有未完成任务时才显示 Chip
              if (pendingCount == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Chip(
                  avatar: const Icon(Icons.pending, size: 16),
                  label: Text('待完成 $pendingCount'),
                  backgroundColor: Theme.of(ctx).colorScheme.primaryContainer,
                  visualDensity: VisualDensity.compact,
                ),
              );
            },
          ),
          // 手动刷新按钮
          IconButton(
            tooltip: '刷新列表',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // invalidate 会让 Provider 重新执行 build()
              ref.invalidate(taskListNotifierProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('列表已刷新'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),

      // =============== 右下角悬浮按钮：添加任务 ===============
      floatingActionButton: showFloatingAddButton
          ? FloatingActionButton.extended(
              onPressed: () => AddTaskSheet.show(context),
              icon: const Icon(Icons.add_alarm_rounded),
              label: const Text(
                '添加任务',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              elevation: 6,
            )
          : null,

      // =============== 主体：AsyncValue 三态分支 ===============
      body: tasksAsync.when(
        // ---- 加载中 ----
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在加载任务列表...'),
            ],
          ),
        ),
        // ---- 错误 ----
        error: (Object error, StackTrace stack) {
          debugPrintStack(label: '列表加载错误', stackTrace: stack);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '加载失败',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => ref.invalidate(taskListNotifierProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新加载'),
                  ),
                ],
              ),
            ),
          );
        },
        // ---- 加载成功 ----
        data: (List<TaskModel> rawTasks) {
          if (rawTasks.isEmpty) {
            return _EmptyStateView(onAddTask: () => AddTaskSheet.show(context));
          }
          // 1. 排序：未完成在前 → 按触发时间升序；已完成在后 → 按完成时间（这里按创建时间倒序）
          final List<TaskModel> sorted = List<TaskModel>.from(rawTasks)
            ..sort((TaskModel a, TaskModel b) {
              if (a.isCompleted != b.isCompleted) {
                // 未完成(false=0) 排在 已完成(true=1) 前面
                return a.isCompleted ? 1 : -1;
              }
              if (!a.isCompleted) {
                // 都未完成：触发时间早的在前
                return a.dateTime.compareTo(b.dateTime);
              } else {
                // 都已完成：创建时间晚的在前（最近完成的在上面）
                return b.createdAt.compareTo(a.createdAt);
              }
            });

          // 2. 渲染列表
          return _TaskListView(tasks: sorted);
        },
      ),
    );
  }
}

class _FullScreenReminderDialog extends StatefulWidget {
  final TaskModel task;

  const _FullScreenReminderDialog({required this.task});

  @override
  State<_FullScreenReminderDialog> createState() =>
      _FullScreenReminderDialogState();
}

class _FullScreenReminderDialogState extends State<_FullScreenReminderDialog> {
  Timer? _unlockTimer;
  int _remainingSeconds = 5;

  bool get _canClose => _remainingSeconds == 0;

  @override
  void initState() {
    super.initState();
    _unlockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remainingSeconds = (_remainingSeconds - 1).clamp(0, 5);
      });
      if (_canClose) _unlockTimer?.cancel();
    });
  }

  @override
  void dispose() {
    _unlockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canClose,
      child: Scaffold(
        backgroundColor: Colors.red.shade900,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.warning_rounded,
                    color: Colors.white,
                    size: 96,
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    '强提醒时间到了',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.task.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 22),
                  ),
                  const SizedBox(height: 48),
                  FilledButton(
                    onPressed: _canClose ? () => Navigator.pop(context) : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(220, 54),
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade900,
                    ),
                    child: Text(
                      _canClose ? '关闭提醒' : '$_remainingSeconds 秒后可关闭',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// 空状态：无任务时展示
// =============================================================
class _EmptyStateView extends StatelessWidget {
  final VoidCallback onAddTask;

  const _EmptyStateView({required this.onAddTask});

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_available_rounded,
              size: 120,
              color: color.primary.withAlpha((0.35 * 255).round()),
            ),
            const SizedBox(height: 24),
            Text(
              '还没有任何任务',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color.onSurface.withAlpha((0.8 * 255).round()),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右下角的「添加任务」按钮，\n开始规划你的时间吧！',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: color.onSurface.withAlpha((0.55 * 255).round()),
              ),
            ),
            const SizedBox(height: 32),
            const Icon(
              Icons.arrow_downward_rounded,
              size: 36,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAddTask,
              icon: const Icon(Icons.add_alarm_rounded),
              label: const Text('添加任务'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// 任务列表 + RefreshIndicator 下拉刷新
// =============================================================
class _TaskListView extends ConsumerWidget {
  final List<TaskModel> tasks;
  const _TaskListView({required this.tasks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        // 下拉刷新：让 Provider 重新读库
        ref.invalidate(taskListNotifierProvider);
        // 等下一帧 AsyncValue 变成 data 就结束（RefreshIndicator 自动停止动画）
        await ref.read(taskListNotifierProvider.future);
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: tasks.length,
        itemBuilder: (BuildContext context, int index) {
          final TaskModel task = tasks[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: DismissibleTaskCard(task: task),
          );
        },
      ),
    );
  }
}

// =============================================================
// 可侧滑删除的任务卡片（Dismissible + Card）
// =============================================================
class DismissibleTaskCard extends ConsumerStatefulWidget {
  final TaskModel task;
  const DismissibleTaskCard({super.key, required this.task});

  @override
  ConsumerState<DismissibleTaskCard> createState() =>
      _DismissibleTaskCardState();
}

class _DismissibleTaskCardState extends ConsumerState<DismissibleTaskCard> {
  @override
  Widget build(BuildContext context) {
    final TaskModel task = widget.task;
    // Dismissible 的 Key 必须唯一，直接用 Isar 主键（int64 id）做 ValueKey
    final Key dismissKey = ValueKey<Id>(task.id);

    return Dismissible(
      key: dismissKey,
      direction: DismissDirection.endToStart,
      // 侧滑距离阈值：滑过 30% 就触发删除
      dismissThresholds: const <DismissDirection, double>{
        DismissDirection.endToStart: 0.30,
      },
      // 侧滑出来的"删除背景"（卡片右侧露出来的红色删除提示）
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_forever, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text(
              '删除',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      // 确认是否真的删除（滑动到阈值后会弹出来问）
      confirmDismiss: (DismissDirection direction) async {
        return showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade600),
                const SizedBox(width: 8),
                const Text('确认删除'),
              ],
            ),
            content: Text.rich(
              TextSpan(
                text: '确定要删除任务「',
                children: [
                  TextSpan(
                    text: task.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: '」吗？\n此操作无法撤销。'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  '删除',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
      // 用户确认删除后：删数据库 + 取消通知 + 弹 SnackBar
      onDismissed: (DismissDirection direction) async {
        await ref.read(taskListNotifierProvider.notifier).deleteTask(task);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已删除任务：${task.title}'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () {
                // 撤销：目前简单实现 = 重新刷新列表
                // 要真正的撤销可以把删除的 task 存下来，再调一个 undo 方法
                ref.invalidate(taskListNotifierProvider);
              },
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      },
      // Dismissible 里面包裹真正的"任务卡片 UI"
      child: _TaskCardBody(task: task),
    );
  }
}

// =============================================================
// 任务卡片主体：高优先级红色左边框 + 标题 + 时间 + Checkbox
// =============================================================
class _TaskCardBody extends ConsumerWidget {
  final TaskModel task;
  const _TaskCardBody({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final DateFormat dateFormatter = DateFormat('MM月dd日 HH:mm');

    // 计算"距离触发还有多久"的人类可读文案
    final String countdown = _buildCountdownText(task.dateTime, dateFormatter);

    // 高优先级 → 红色左边框 + 微红色背景
    final bool high = task.isHighPriority;
    final Color accentColor = high
        ? Colors.redAccent
        : theme.colorScheme.primary;
    final Color bgColor = task.isCompleted
        ? theme.colorScheme.surface
        : (high
              ? Colors.redAccent.withAlpha((0.05 * 255).round())
              : theme.colorScheme.surfaceContainerHighest.withAlpha(
                  (0.3 * 255).round(),
                ));

    return Card(
      elevation: task.isCompleted ? 0 : 2,
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          // 左边框颜色体现优先级
          color: task.isCompleted
              ? theme.dividerColor
              : (high ? Colors.redAccent : theme.colorScheme.primary),
          width: high ? 2.5 : 1.2,
        ),
      ),
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // 点击卡片 = 快捷切换完成状态（交互友好）
          ref.read(taskListNotifierProvider.notifier).toggleComplete(task);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----------- 左侧：勾选 Checkbox -----------
              Checkbox(
                value: task.isCompleted,
                activeColor: accentColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                onChanged: (bool? _) {
                  ref
                      .read(taskListNotifierProvider.notifier)
                      .toggleComplete(task);
                },
              ),
              const SizedBox(width: 4),
              // ----------- 中间：标题 + 描述 + 时间 -----------
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题（已完成 → 画删除线）
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: task.isCompleted ? Colors.grey : null,
                      ),
                    ),
                    // 描述
                    if (task.description != null &&
                        task.description!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          task.description!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withAlpha(
                              (0.6 * 255).round(),
                            ),
                            decoration: task.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    // 时间 + 倒计时 + 优先级标签（用 Wrap 自动换行）
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // 时间图标 + 日期
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: accentColor,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              dateFormatter.format(task.dateTime),
                              style: TextStyle(
                                fontSize: 12,
                                color: accentColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        // 倒计时（已完成不显示）
                        if (!task.isCompleted)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  _isUrgent(task.dateTime) && !task.isCompleted
                                  ? Colors.orange.withAlpha(
                                      (0.12 * 255).round(),
                                    )
                                  : theme.colorScheme.primary.withAlpha(
                                      (0.08 * 255).round(),
                                    ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              countdown,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color:
                                    _isUrgent(task.dateTime) &&
                                        !task.isCompleted
                                    ? Colors.orange.shade800
                                    : theme.colorScheme.primary.withAlpha(
                                        (0.85 * 255).round(),
                                      ),
                              ),
                            ),
                          ),
                        // 高优先级标签
                        if (high)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withAlpha(
                                (0.12 * 255).round(),
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.redAccent.withAlpha(
                                  (0.3 * 255).round(),
                                ),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.flash_on,
                                  size: 12,
                                  color: Colors.red.shade700,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '强提醒',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // 已完成标签
                        if (task.isCompleted)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(
                                (0.12 * 255).round(),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '已完成',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // ----------- 右侧：删除图标按钮 -----------
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                tooltip: '删除任务',
                onPressed: () async {
                  // 和侧滑同一个删除确认对话框
                  final bool? confirm = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      title: const Text('确认删除'),
                      content: Text('确定要删除任务「${task.title}」吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text(
                            '删除',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    await ref
                        .read(taskListNotifierProvider.notifier)
                        .deleteTask(task);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已删除：${task.title}')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 是否紧急（距离触发 < 1 小时 = 紧急）
  bool _isUrgent(DateTime dateTime) {
    final Duration diff = dateTime.difference(DateTime.now());
    return !diff.isNegative && diff.inMinutes <= 60;
  }

  // 构建倒计时文案，例如："还剩 2 小时"、"10 分钟后"、"已过期"
  String _buildCountdownText(DateTime dateTime, DateFormat dateFormatter) {
    final Duration diff = dateTime.difference(DateTime.now());
    if (diff.isNegative || diff.inSeconds < 0) {
      // 已过期 + 未完成 → 显示过期
      if (!task.isCompleted) return '已过期 ${_formatPastDuration(-diff)}';
      return dateFormatter.format(dateTime);
    }
    if (diff.inDays >= 1) {
      return '还剩 ${diff.inDays} 天';
    } else if (diff.inHours >= 1) {
      return '还剩 ${diff.inHours} 小时';
    } else if (diff.inMinutes >= 1) {
      return '${diff.inMinutes} 分钟后';
    } else {
      return '即将提醒';
    }
  }

  String _formatPastDuration(Duration d) {
    if (d.inDays >= 1) return '${d.inDays} 天';
    if (d.inHours >= 1) return '${d.inHours} 小时';
    return '${d.inMinutes} 分钟';
  }
}
