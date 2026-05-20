import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// 隐私政策页面
///
/// 展示应用的隐私政策内容
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  /// 隐私政策内容
  static const String _privacyPolicyContent = '''
# 隐私政策

**最后更新于：2026年02月22日**
**生效日期：2026年02月22日**

---

## 引言

欢迎使用"零知"移动应用程序（以下简称"本应用"）。本应用是由"零知"团队（以下简称"我们"）开发并提供的客户端软件产品。

本隐私政策（以下简称"本政策"）旨在向本应用的用户（以下简称"您"或"用户"）说明本应用在用户个人信息收集、使用、存储等方面的立场和做法。请您在使用本应用前仔细阅读并充分理解本政策的全部内容。

**一旦您开始使用本应用，即表示您已充分理解并同意接受本政策的约束。** 如您不同意本政策的任何条款，请立即停止使用本应用。

---

## 第一条 数据收集声明

**1.1 本应用不收集任何用户数据。**

1.1.1 本应用是一款纯客户端软件，所有数据处理均在您的设备本地完成，我们不会收集、传输或存储您的任何个人信息至外部服务器。

1.1.2 具体而言，本应用明确承诺：

（一）不会收集您的姓名、电话、电子邮箱等个人身份信息；

（二）不会收集您的设备型号、操作系统版本、设备标识符等设备信息；

（三）不会收集您的应用使用行为、操作日志等使用信息；

（四）不会收集您通过本应用输入的文字、语音等聊天记录或对话数据；

（五）不会收集您的地理位置信息；

（六）不会使用任何Cookie、网络信标、跟踪像素等跟踪技术；

（七）不会集成任何第三方统计分析工具或数据收集服务。

---

## 第二条 后端服务说明

**2.1 服务模式**

2.1.1 本应用为客户端软件，需要您自行配置后端服务地址后方可正常使用全部功能。

2.1.2 本应用本身不提供任何托管式后端服务，所有后端服务均需由您自行部署或开发。

**2.2 官方开源后端**

2.2.1 我们提供了开源免费的后端源码服务程序，您可以选择以下方式之一获取后端服务：

（一）直接部署我们提供的官方开源后端服务程序；

（二）根据项目公开的API接口文档，自行开发符合接口规范的后端服务。

2.2.2 官方开源后端源码地址：请于本应用"关于"页面查看GitHub仓库地址。

**2.3 重要声明**

2.3.1 后端服务的数据处理行为由该服务的部署者或开发者全权负责，与本应用客户端无关。

2.3.2 我们建议您在使用任何后端服务前，自行审核服务提供方的身份资质及其隐私政策。

2.3.3 因后端服务的数据收集、使用、存储行为所产生的任何责任，由该服务的提供方独立承担，我们不承担任何连带责任或法律责任。

---

## 第三条 本地数据存储

**3.1 本地存储范围**

3.1.1 本应用可能在您的设备本地存储以下数据：

（一）应用设置和偏好设置；

（二）您配置的服务器地址及连接参数；

（三）对话历史记录。

**3.2 本地存储说明**

3.2.1 上述数据完全存储在您的设备本地，不会上传至任何外部服务器。

3.2.2 您可以随时通过本应用的设置功能清除上述本地存储数据。

3.2.3 卸载本应用后，上述本地存储数据将被一并删除。

---

## 第四条 未成年人保护

**4.1** 若您为未满18周岁的未成年人，建议您在监护人的指导下使用本应用。

**4.2** 监护人应当正确履行监护职责，保护未成年人的合法权益。

---

## 第五条 隐私政策的更新

**5.1** 我们保留随时修改本政策的权利。

**5.2** 如本政策发生变更，我们将在本应用内以适当方式向您发出通知。

**5.3** 修订后的政策将在本应用内公布后立即生效。如您在政策变更后继续使用本应用，即视为您已接受修订后的政策。

---

## 第六条 联系我们

**6.1** 如您对本政策有任何疑问、意见或建议，可通过以下方式与我们联系：

（一）电子邮箱：lingzhi0211@163.com

**6.2** 我们将在收到您的反馈后尽快予以回复。

---

## 第七条 其他条款

**7.1** 本政策的标题仅供阅读方便，不影响本政策条款的含义或解释。

**7.2** 如本政策任一条款被有管辖权的法院或机构认定为无效或不可执行，该无效或不可执行不影响本政策其他条款的效力。

**7.3** 我们未行使或延迟行使本政策项下的任何权利，不构成对该权利的放弃。

---

**"零知"团队**

2026年02月22日
''';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          '隐私政策',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectionArea(
            child: MarkdownBody(
              data: _privacyPolicyContent,
              styleSheet: MarkdownStyleSheet(
                h1: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                h2: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                h3: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
                p: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
                listBullet: TextStyle(
                  fontSize: 15,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
                blockquote: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontStyle: FontStyle.italic,
                ),
                strong: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                horizontalRuleDecoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: theme.dividerColor, width: 1),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
