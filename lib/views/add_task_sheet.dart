// ============================================================
// AddTaskSheet - 添加任务的底部弹窗
// ============================================================
// 面试交互讲解要点：
// 1. 首次点"保存"时会主动调用 requestPermissions() 申请通知权限
//    —— 因为用户如果不给权限，注册了也白注册，还会让他误以为 APP 有 bug。
// 2. 时间快捷按钮（1小时后/明天早上8点/自定义）提升了操作效率，
//    面试时可以讲"我注重用户体验"。
// 3. 强提醒 Switch 下面的说明文案和 Dialog 二次确认，
//    让用户理解"开了这个会很吵"，避免误操作投诉。
// 4. 保存用 Form + GlobalKey 做校验：标题不能空 + 时间必须在未来
//    —— 这是 MVP 级别的"输入防御性编程"。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/app_services_providers.dart';
import '../providers/task_list_provider.dart';
import '../services/notification_service.dart';
import '../services/native_alarm_service.dart';

class AddTaskSheet extends ConsumerStatefulWidget {
  const AddTaskSheet({super.key});

  /// 静态便捷方法：显示底部 Sheet（可从任意页面调用）
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AddTaskSheet(),
    );
  }

  @override
  ConsumerState<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<AddTaskSheet> {
  // ---- 表单与控制器 ----
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  // ---- 用户选中的状态 ----
  // 默认"1 小时后"（一个理性的默认值）
  late DateTime _selectedDateTime = DateTime.now().add(
    const Duration(hours: 1),
  );
  bool _isHighPriority = false;
  String _ringtoneTitle = '系统默认闹钟铃声';
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // =============================================================
  // 快捷时间按钮：5 分钟后 / 15 分钟后 / 30 分钟后
  // =============================================================
  void _applyPreset(int presetIndex) {
    final DateTime now = DateTime.now();
    late DateTime t;
    switch (presetIndex) {
      case 0: // 5 分钟后
        t = now.add(const Duration(minutes: 5));
        break;
      case 1: // 15 分钟后
        t = now.add(const Duration(minutes: 15));
        break;
      case 2: // 30 分钟后
        t = now.add(const Duration(minutes: 30));
        break;
    }
    setState(() => _selectedDateTime = t);
  }

  Future<void> _pickCustomTime() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
      helpText: '选择提醒时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _selectedDateTime = DateTime(
        _selectedDateTime.year,
        _selectedDateTime.month,
        _selectedDateTime.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _pickCustomDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '选择提醒日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (pickedDate == null || !mounted) return;

    setState(() {
      _selectedDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        _selectedDateTime.hour,
        _selectedDateTime.minute,
      );
    });
  }

  // =============================================================
  // 强提醒开关切换（开之前弹确认，让用户想清楚）
  // =============================================================
  Future<void> _onToggleHighPriority(bool newValue) async {
    if (newValue && !_isHighPriority) {
      // 从关闭 → 打开：弹二次确认
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          icon: Icon(
            Icons.warning_amber_rounded,
            size: 44,
            color: Colors.red.shade700,
          ),
          title: const Text('开启强提醒？'),
          content: const Text(
            '开启后：\n'
            '• 通知会持续响铃，无法轻易划掉\n'
            '• 触发时会全屏弹窗，甚至覆盖锁屏\n'
            '• 适合：重要考试、会议、吃药等绝对不能忘的事项',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认开启'),
            ),
          ],
        ),
      );
      if (ok == true) {
        setState(() => _isHighPriority = true);
      }
    } else {
      // 关闭高优先级：直接关
      setState(() => _isHighPriority = newValue);
    }
  }

  Future<void> _pickRingtone() async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('选择手机系统铃声'),
              onTap: () async {
                final result = await NativeAlarmService.pickSystemRingtone();
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext, result?['title']);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('选择自定义音频文件'),
              onTap: () async {
                final result = await NativeAlarmService.pickCustomRingtone();
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext, result?['title']);
                }
              },
            ),
          ],
        ),
      ),
    );
    if (choice != null && mounted) setState(() => _ringtoneTitle = choice);
  }

  // =============================================================
  // 提交保存（核心）
  // 流程：校验表单 → 校验时间 → 申请通知权限 → 调 Provider addTask → 成功关闭
  // =============================================================
  Future<void> _submit() async {
    // 1. 表单校验
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 2. 时间校验（必须在未来）
    final DateTime now = DateTime.now();
    if (_selectedDateTime.isBefore(now) ||
        _selectedDateTime.millisecondsSinceEpoch ==
            now.millisecondsSinceEpoch) {
      _showSnackBar('提醒时间必须在未来', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      // 3. 申请通知权限（一次没授权以后也不让他填了，直接告诉他去设置里开）
      //    申请失败我们也不阻塞保存，只是弹警告提醒他去开权限
      final NotificationService notifService = ref.read(
        notificationServiceProvider,
      );
      try {
        final bool granted = await notifService.requestPermissions();
        if (!granted && mounted) {
          _showSnackBar(
            '通知/精确闹钟权限未授予，可能无法准时提醒，请在系统设置中开启',
            isError: true,
            long: true,
          );
        }
      } catch (permErr) {
        debugPrint('申请权限出错：$permErr');
      }

      // 4. 调 Provider：写数据库 + 注册通知
      await ref
          .read(taskListNotifierProvider.notifier)
          .addTask(
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            dateTime: _selectedDateTime,
            isHighPriority: _isHighPriority,
          );

      // 5. 成功：关闭弹窗 + 提示
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar(
          '✅ 任务已添加！将于 ${DateFormat('MM-dd HH:mm').format(_selectedDateTime)} 提醒',
        );
      }
    } catch (e, s) {
      debugPrintStack(label: '保存任务异常：$e', stackTrace: s);
      if (mounted) _showSnackBar('保存失败：$e', isError: true, long: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // =============================================================
  // 辅助：弹一个统一的 SnackBar
  // =============================================================
  void _showSnackBar(String text, {bool isError = false, bool long = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? Colors.redAccent : Colors.greenAccent,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
        duration: long
            ? const Duration(seconds: 5)
            : const Duration(seconds: 2),
        backgroundColor: isError ? Colors.grey.shade900 : null,
      ),
    );
  }

  // =============================================================
  // UI 构建
  // =============================================================
  @override
  Widget build(BuildContext context) {
    final DateFormat dateFmt = DateFormat('yyyy年MM月dd日');
    final DateFormat timeFmt = DateFormat('HH:mm');
    final EdgeInsets viewInsets = MediaQuery.of(context).viewInsets;
    final ThemeData theme = Theme.of(context);

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- 顶部小横条（用户一看就知道可以往下拉） ----
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ---- 标题 + 关闭按钮 ----
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '添加新任务',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: theme.dividerColor.withAlpha((0.3 * 255).round())),
            const SizedBox(height: 18),

            // ---- 1. 标题输入 ----
            Text('任务标题 *', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            TextFormField(
              controller: _titleCtrl,
              maxLength: 60,
              enabled: !_submitting,
              decoration: InputDecoration(
                hintText: '如：复习数据结构期末考试',
                prefixIcon: const Icon(Icons.title_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (String? v) {
                if (v == null || v.trim().isEmpty) return '请输入任务标题';
                if (v.trim().length < 2) return '标题至少 2 个字';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ---- 2. 详细描述输入 ----
            Text('详细描述（可选）', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descCtrl,
              maxLength: 200,
              maxLines: 3,
              minLines: 2,
              enabled: !_submitting,
              decoration: InputDecoration(
                hintText: '如：重点看红黑树、B树、哈希冲突章节',
                prefixIcon: const Icon(Icons.description_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ---- 3. 提醒时间 ----
            Text('提醒时间 *', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),

            // 大卡片：日期 + 时间并排
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(
                  (0.5 * 255).round(),
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  // 日期块
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📅  日期',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onPrimaryContainer
                                .withAlpha((0.7 * 255).round()),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFmt.format(_selectedDateTime),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: theme.dividerColor.withAlpha((0.4 * 255).round()),
                  ),
                  const SizedBox(width: 14),
                  // 时间块
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '⏰  时间',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onPrimaryContainer
                                .withAlpha((0.7 * 255).round()),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          timeFmt.format(_selectedDateTime),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 快捷时间按钮
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildPresetChip(0, '5 分钟后'),
                _buildPresetChip(1, '15 分钟后'),
                _buildPresetChip(2, '30 分钟后'),
              ],
            ),
            const SizedBox(height: 10),

            // 自定义日期与时间按钮保持相同尺寸，并分别只修改对应部分
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _submitting ? null : _pickCustomTime,
                    icon: const Icon(Icons.access_time),
                    label: const Text('自定义时间'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _submitting ? null : _pickCustomDate,
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('自定义日期'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // 距离现在多久（给用户一个直观反馈）
            const SizedBox(height: 10),
            Text(
              '  约 ${_buildCountdown(_selectedDateTime)} 提醒你',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 22),

            // ---- 4. 强提醒模式开关 ----
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              decoration: BoxDecoration(
                color: _isHighPriority
                    ? Colors.red.withAlpha((0.06 * 255).round())
                    : theme.colorScheme.surfaceContainerHighest.withAlpha(
                        (0.3 * 255).round(),
                      ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isHighPriority
                      ? Colors.redAccent
                      : theme.dividerColor,
                  width: _isHighPriority ? 1.4 : 0.6,
                ),
              ),
              child: Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile(
                      value: _isHighPriority,
                      onChanged: _submitting ? null : _onToggleHighPriority,
                      activeThumbColor: Colors.red,
                      activeTrackColor: Colors.red.shade100,
                      secondary: Icon(
                        _isHighPriority
                            ? Icons.flash_on
                            : Icons.flash_on_outlined,
                        color: _isHighPriority ? Colors.red : null,
                        size: 28,
                      ),
                      title: const Text(
                        '强提醒模式',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _isHighPriority
                            ? '已开启：全屏弹窗 + 持续响铃 + 无法划掉'
                            : '开启后会用"最强烈"的方式提醒你',
                        style: TextStyle(
                          fontSize: 12,
                          color: _isHighPriority
                              ? Colors.red.shade700
                              : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                  if (_isHighPriority)
                    ListTile(
                      leading: const Icon(Icons.music_note),
                      title: const Text('强提醒铃声'),
                      subtitle: Text(_ringtoneTitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _submitting ? null : _pickRingtone,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 温馨提示
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                '💡 小提示：建议只在绝对不能忘的重要事项开启强提醒（如：考试、面试、吃药、赶飞机）',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ---- 5. 保存按钮 ----
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  backgroundColor: _isHighPriority
                      ? Colors.redAccent.shade700
                      : theme.colorScheme.primary,
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Icon(_isHighPriority ? Icons.flash_on : Icons.check),
                label: Text(
                  _submitting
                      ? '保存中...'
                      : (_isHighPriority ? '保存（强提醒）' : '保存任务'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: _submitting ? null : () => Navigator.pop(context),
                child: Text(
                  '取消',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================================================
  // UI 子组件构建辅助方法
  // =============================================================

  /// 快捷时间 Chip
  Widget _buildPresetChip(int index, String label) {
    return FilterChip(
      label: Text(label),
      onSelected: _submitting ? null : (bool _) => _applyPreset(index),
      backgroundColor: Theme.of(context).colorScheme.surface,
      selectedColor: Theme.of(context).colorScheme.primary
          .withAlpha((0.15 * 255).round()),
      shape: StadiumBorder(
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary
              .withAlpha((0.3 * 255).round()),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  /// 计算"还有多久提醒"的人类可读文本
  String _buildCountdown(DateTime t) {
    final Duration diff = t.difference(DateTime.now());
    if (diff.isNegative) return '已过期（请重新选择）';
    if (diff.inDays >= 30) return '${diff.inDays ~/ 30} 个月后';
    if (diff.inDays >= 1) return '${diff.inDays} 天 ${diff.inHours % 24} 小时后';
    if (diff.inHours >= 1) {
      return '${diff.inHours} 小时 ${diff.inMinutes % 60} 分钟后';
    }
    if (diff.inMinutes >= 1) return '${diff.inMinutes} 分钟后';
    return '马上';
  }
}
