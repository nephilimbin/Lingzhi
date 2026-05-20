# Triage Labels

本仓库使用标准的五个分类标签。

## 标签映射

| 角色 | 标签名称 | 描述 |
|------|---------|------|
| 需要评估 | `needs-triage` | 维护者需要评估此问题 |
| 等待信息 | `needs-info` | 等待报告者提供更多信息 |
| 代理就绪 | `ready-for-agent` | 完全规范，AFK 代理可以接手 |
| 人工就绪 | `ready-for-human` | 需要人工实现 |
| 不予修复 | `wontfix` | 不会执行此问题 |

## 使用方式

对于本地 Markdown 问题跟踪器，标签在文件 frontmatter 中表示：

```markdown
---
title: 问题标题
labels: [needs-triage, bug]
---
```
