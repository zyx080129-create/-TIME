// ============================================================
// main.dart - 应用入口
// ============================================================
// 面试讲解要点：
// 1. 为什么 main() 要 async？
//    -> 因为 WidgetsFlutterBinding.ensureInitialized() + 初始化
//       数据库/通知服务 都是 async 操作，必须在 runApp() 前确保完成。
// 2. ProviderScope 的作用？
//    -> Riverpod 的依赖注入根容器。所有 ref.read/watch 都必须在
//       ProviderScope 的子树中才能访问 Providers。
// 3. appInitializeProvider 返回 AsyncValue，
//    我们用 AsyncValue.when 展示启动屏 / 错误页 / 主页。
// ============================================================
//
// ============================================================
// ⚠️  重要：首次运行前，请在项目根目录执行以下命令生成 .g.dart 文件
// ============================================================
//   1. flutter pub get
//   2. flutter pub run build_runner build --delete-conflicting-outputs
//
// 这条命令会生成以下文件（Isar + Riverpod 代码生成）：
//   - lib/models/task_model.g.dart
//   - lib/providers/app_services_providers.g.dart
//   - lib/providers/task_list_provider.g.dart
//
// 如果之后修改了 TaskModel 字段或 Provider 代码，需要重新跑第 2 步。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/app_services_providers.dart';
import 'utils/timezone_helper.dart';
import 'views/task_list_page.dart';

Future<void> main() async {
  // 1. 确保 Flutter 引擎绑定完成（必须在调用任何原生插件前执行）
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 初始化时区数据库（先于通知调度的任何调用）
  await TimezoneHelper.init();

  // 3. 启动 App —— 用 ProviderScope 包裹根组件
  //    ProviderScope 是 Riverpod 的全局容器，
  //    它会持有所有 Provider 的状态，直到 App 退出。
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听 appInitializeProvider（AsyncValue<void>）
    // 它会串行执行：DatabaseService.init -> NotificationService.init
    //             -> BootRescheduleService.rescheduleAll
    final AsyncValue<void> initState = ref.watch(appInitializeProvider);

    return MaterialApp(
      title: '强效提醒与专注管理',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blueAccent,
        useMaterial3: true,
        // 全局 ListTile 样式（第三步的 UI 会用到）
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
      ),
      home: initState.when(
        // 初始化中 -> 启动屏
        loading: () => const _SplashScreen(),
        // 初始化出错 -> 错误重试页（面试加分项：处理启动失败）
        error: (Object error, StackTrace stack) => _ErrorScreen(
          error: error,
          stack: stack,
          onRetry: () => ref.invalidate(appInitializeProvider),
        ),
        // 初始化成功 -> 进入主页（TaskListPage 留到第三步输出）
        data: (_) => const TaskListPage(),
      ),
    );
  }
}

// =============================================================
// 启动屏（Splash）：初始化服务时显示
// =============================================================
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              '正在启动...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// 错误重试页：初始化失败时展示（如数据库损坏、权限异常等）
// =============================================================
class _ErrorScreen extends StatelessWidget {
  final Object error;
  final StackTrace stack;
  final VoidCallback onRetry;

  const _ErrorScreen({
    required this.error,
    required this.stack,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                '启动失败',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
