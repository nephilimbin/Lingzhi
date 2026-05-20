# Issue Tracker

本仓库使用本地 Markdown 文件系统作为问题跟踪器。

## 位置

问题存放在仓库根目录的 `.scratch/` 目录中：

```
.scratch/
└── <feature-name>/
    ├── issue.md          # 问题描述
    ├── plan.md           # 实现计划
    ├── research.md       # 研究笔记
    └── ...
```

## 工作流

- 创建问题：在 `.scratch/` 下创建新目录并添加 `issue.md`
- 查看问题：列出 `.scratch/` 下的所有目录
- 更新问题：编辑相应的 Markdown 文件

## 相关技能

- `to-issues` - 将计划转换为问题
- `triage` - 分类和处理问题
- `to-prd` - 创建 PRD 文档
