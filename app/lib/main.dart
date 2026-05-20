import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:ai_assistant/core/config/app_theme.dart';
import 'package:ai_assistant/core/config/theme_provider.dart';
import 'package:ai_assistant/core/providers/diy_service_provider.dart';
import 'package:ai_assistant/core/utils/app_logger.dart';
import 'package:ai_assistant/core/providers/conversation_provider.dart';
import 'package:ai_assistant/features/conversation/screens/home_screen.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/features/settings/providers/settings_provider.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:opus_dart/opus_dart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // === 必须在runApp前完成的快速初始化 ===

  // 初始化统一日志 (~几ms)
  await logger.init();

  // 应用系统UI样式 (同步调用, 立即生效)
  _applySystemUIStyle();

  // 设置状态栏颜色变化监听器，确保状态栏样式始终如一
  SystemChannels.lifecycle.setMessageHandler((msg) async {
    if (msg == AppLifecycleState.resumed.toString()) {
      // 应用回到前台时重新应用系统UI设置
      await _setupSystemUI();
    }
    return null;
  });

  // 配置图像缓存 (同步)
  if (Platform.isAndroid || Platform.isIOS) {
    PaintingBinding.instance.imageCache.maximumSize = 1000;
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        100 * 1024 * 1024; // 100 MB
  }

  // timeago本地化 (同步)
  timeago.setLocaleMessages('zh', timeago.ZhMessages());
  timeago.setDefaultLocale('zh');

  // 创建ConfigProvider (构造函数中已启动异步加载, 不阻塞启动)
  final configProvider = ConfigProvider();

  // 立即启动应用, 不等待任何非关键初始化
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: configProvider),
        ChangeNotifierProvider(create: (context) => ConversationProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProxyProvider2<
          ConfigProvider,
          ConversationProvider,
          DiyServiceProvider
        >(
          create:
              (context) => DiyServiceProvider(
                context.read<ConfigProvider>(),
                context.read<ConversationProvider>(),
              ),
          update:
              (context, configProvider, conversationProvider, previous) =>
                  previous ??
                  DiyServiceProvider(configProvider, conversationProvider),
        ),
      ],
      child: const MyApp(),
    ),
  );

  // 在runApp之后启动后台初始化 (不阻塞首帧渲染)
  _initializeBackgroundTasks();
}

/// 仅应用系统UI样式 (同步部分, 不含异步的setEnabledSystemUIMode)
void _applySystemUIStyle() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
}

/// 后台初始化所有非关键任务 (在首帧渲染后并行执行)
void _initializeBackgroundTasks() {
  Future(() async {
    logI('开始后台初始化任务...');
    final stopwatch = Stopwatch()..start();

    await Future.wait([
      _setupSystemUI(), // 异步系统UI设置 (边缘到边缘模式等)
      _initPermissions(), // 权限请求 (含网络权限触发, 最耗时)
      _initOpus(), // Opus音频编解码库
      _initDateFormatting(), // 日期格式化
      _initDisplayMode(), // Android高刷新率
      _checkEmulator(), // Android模拟器检测
    ]);

    stopwatch.stop();
    logI('后台初始化任务完成, 耗时: ${stopwatch.elapsedMilliseconds}ms');
  });
}

/// 初始化日期格式化
Future<void> _initDateFormatting() async {
  try {
    await initializeDateFormatting('zh_CN', null);
    logI('Date formatting initialized for zh_CN');
  } catch (e, st) {
    logE('Error initializing date formatting', e, st);
  }
}

/// 初始化Opus音频编解码库
Future<void> _initOpus() async {
  try {
    if (Platform.isMacOS) {
      logI('macOS 平台暂时跳过 Opus 初始化');
      return;
    }
    initOpus(await opus_flutter.load());
    logI('Opus 库初始化成功: ${getOpusVersion()}');
  } catch (e, st) {
    logE('Opus 库初始化失败', e, st);
  }
}

/// 请求应用所需权限
Future<void> _initPermissions() async {
  try {
    List<Permission> permissionsToRequest = [
      Permission.microphone,
      Permission.camera,
      Permission.locationWhenInUse,
      Permission.notification,
    ];

    if (Platform.isIOS) {
      permissionsToRequest.add(Permission.photos);
    } else if (Platform.isAndroid) {
      permissionsToRequest.addAll([
        Permission.storage,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ]);
    }

    // 先触发网络权限 (后台执行, 不阻塞UI)
    _triggerNetworkPermission();

    // 请求系统权限 (会弹出系统对话框)
    Map<Permission, PermissionStatus> statuses =
        await permissionsToRequest.request();

    statuses.forEach((permission, status) {
      if (status.isDenied) {
        logW('权限 ${permission.toString()} 被用户拒绝.');
      } else if (status.isPermanentlyDenied) {
        logW('权限 ${permission.toString()} 被永久拒绝.');
      }
    });
  } catch (e, st) {
    logE('请求权限时发生错误', e, st);
  }
}

/// 触发iOS/Android网络数据权限弹窗 (fire-and-forget, 不阻塞)
Future<void> _triggerNetworkPermission() async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);

    try {
      final request = await client.getUrl(Uri.parse('https://www.baidu.com'));
      final response = await request.close();
      await response.drain();
    } catch (e) {
      // 网络请求失败是正常的, 目的只是触发权限弹窗
    }

    client.close();

    try {
      final socket = await Socket.connect(
        '8.8.8.8',
        53,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
    } catch (e) {
      // Socket连接失败是正常的
    }
  } catch (e) {
    // 忽略所有错误
  }
}

/// 设置Android高刷新率
Future<void> _initDisplayMode() async {
  if (!Platform.isAndroid) return;

  try {
    final modes = await FlutterDisplayMode.supported;
    logI('支持的显示模式: ${modes.length}');
    await FlutterDisplayMode.setHighRefreshRate();

    final afterSet = await FlutterDisplayMode.active;
    logI('设置后模式: $afterSet');
  } catch (e, st) {
    logE('设置高刷新率失败', e, st);
  }
}

/// 检测Android模拟器
Future<void> _checkEmulator() async {
  if (!Platform.isAndroid || !kDebugMode) return;

  try {
    final bool isEmulator =
        Platform.environment['ANDROID_EMULATOR'] != null ||
        await Process.run('getprop', [
          'ro.kernel.qemu',
        ]).then((result) => result.stdout.toString().trim() == '1');

    if (isEmulator) {
      logI('检测到Android模拟器，启用软件渲染以避免OpenGL ES警告');
    }
  } catch (e, st) {
    logE('检测模拟器状态失败', e, st);
  }
}

// 设置系统UI沉浸式效果 (完整版, 含异步设置)
Future<void> _setupSystemUI() async {
  _applySystemUIStyle();

  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } else if (Platform.isIOS) {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Lingzhi',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeProvider.themeMode,
      home: const HomeScreen(),
      routes: {
        // '/test': (context) => const TestScreen(), // 已移除
      },
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        },
      ),
    );
  }
}
