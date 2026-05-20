import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/core/providers/config_provider.dart';
import 'package:ai_assistant/features/settings/providers/settings_provider.dart';

/// 显示自定义添加对话框
void showDiyAddDialog(BuildContext context) {
  final settingsProvider = context.read<SettingsProvider>();
  settingsProvider.clearDiyControllers();

  showDialog(
    context: context,
    builder:
        (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '添加服务',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '基础信息',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: settingsProvider.newDiyNameController,
                    decoration: const InputDecoration(
                      labelText: '服务名称 *',
                      hintText: '例如：家庭助理',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '服务器配置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller:
                        settingsProvider.newDiyWebsocketUrlController,
                    decoration: const InputDecoration(
                      labelText: '服务器地址 *',
                      hintText: '例如：ws://192.168.1.10:8080',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: settingsProvider.newDiyMacAddressController,
                    decoration: const InputDecoration(
                      labelText: 'MAC地址',
                      hintText: '例如：00:1B:44:11:3A:B7',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: settingsProvider.newDiyTokenController,
                    decoration: const InputDecoration(
                      labelText: 'Token',
                      hintText: '认证令牌（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '自定义服务需要提供有效的WebSocket地址',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      final name =
                          settingsProvider.newDiyNameController.text.trim();
                      final url =
                          settingsProvider.newDiyWebsocketUrlController.text
                              .trim();

                      if (name.isEmpty || url.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请填写必填字段')),
                        );
                        return;
                      }

                      settingsProvider.addDiyConfig(
                        context.read<ConfigProvider>(),
                      );
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ),
        ),
  );
}

/// 显示Dify添加对话框
void showDifyAddDialog(BuildContext context) {
  final settingsProvider = context.read<SettingsProvider>();
  settingsProvider.clearDifyControllers();

  showDialog(
    context: context,
    builder:
        (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '添加服务',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '基础信息',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: settingsProvider.newDifyNameController,
                    decoration: const InputDecoration(
                      labelText: '服务名称 *',
                      hintText: '例如：Dify助手',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Dify配置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: settingsProvider.newDifyApiUrlController,
                    decoration: const InputDecoration(
                      labelText: 'API地址 *',
                      hintText: 'https://api.dify.ai/v1',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: settingsProvider.newDifyApiKeyController,
                    decoration: const InputDecoration(
                      labelText: 'API Key *',
                      hintText: 'app-xxxxxxxxxxxx',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Dify服务需要提供有效的API地址和密钥',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      final name =
                          settingsProvider.newDifyNameController.text.trim();
                      final apiUrl =
                          settingsProvider.newDifyApiUrlController.text.trim();
                      final apiKey =
                          settingsProvider.newDifyApiKeyController.text.trim();

                      if (name.isEmpty || apiUrl.isEmpty || apiKey.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请填写所有必填字段')),
                        );
                        return;
                      }

                      settingsProvider.addDifyConfig(
                        context.read<ConfigProvider>(),
                      );
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ),
        ),
  );
}
