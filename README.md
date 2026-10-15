# 强效提醒与专注管理

一款使用 Flutter 编写的本地待办与定时提醒应用。用户可以创建带有提醒时间的任务，并选择普通提醒或强提醒模式。任务数据保存在设备本地，不依赖远程服务。

## 功能

- 创建任务，填写标题和可选描述
- 使用快捷时间或自定义日期、时间设置提醒
- 查看待办和已完成任务，并切换完成状态或删除任务
- 普通本地通知，以及用于重要事项的强提醒模式
- 查看通知权限状态，并在需要时申请通知和精确闹钟权限
- 应用启动时从本地数据库恢复未完成任务的提醒
- Android 强提醒支持选择系统铃声或自定义音频

强提醒涉及全屏提示、持续响铃、锁屏显示等系统能力，具体表现会因平台版本、系统设置和权限状态而异。铃声选择及原生闹钟通道由 Android 原生代码提供；其他平台不保证具备相同的强提醒行为。

## 技术栈

- Flutter / Dart
- Riverpod：状态管理与服务依赖注入
- Isar：本地任务数据库
- `flutter_local_notifications`、`timezone`：本地通知调度和时区处理
- Android Kotlin：强提醒铃声、原生闹钟接收器与前台服务

## 环境要求

- Flutter SDK（项目要求 Dart SDK `^3.13.2`）
- Android Studio 或 Xcode，按目标平台安装对应的原生构建工具

## 运行

在项目根目录执行：

```bash
flutter pub get
flutter run
```

如果代码生成文件缺失，或修改了 Isar 模型、Riverpod 注解定义，先运行：

```bash
dart run build_runner build --delete-conflicting-outputs
```

运行测试：

```bash
flutter test
```

## 平台权限提示

Android 需要通知、精确闹钟等权限才能按预期调度提醒；强提醒还依赖系统允许全屏通知及后台响铃。应用会在创建任务时请求相关权限，用户也可以从主页检查权限状态。若未授予权限，任务仍可保存，但通知可能无法按时送达。

iOS 需要用户授权通知。系统可能限制通知的展示和声音行为，因此强提醒不等同于系统闹钟。

## 项目结构

```text
lib/
  models/       任务数据模型
  providers/    Riverpod 服务和任务状态
  services/     数据库、通知及启动恢复服务
  utils/        时区等工具
  views/        任务列表和添加任务界面
android/        Android 原生强提醒实现
ios/            iOS Runner 配置
test/           Flutter 测试
```
