# Inline Autofill Toggle Patch

本目录只保留内联自动填充建议开关的补丁工具。

## 补丁内容

- \`SettingsPreferences.kt\`：新增偏好 Key、读取和写入方法，默认开启，保持原有行为。
- \`LayoutDisplaySettingsScreen.kt\`：增加「内联自动填充建议」设置开关。
- \`XimeInputMethodService.kt\`：在 Android 版本检查后增加开关判断，保留上游原有请求处理逻辑。

每个插入块都有 \`BEGIN/END INLINE_AUTOFILL_TOGGLE\` 标记。脚本会检查锚点唯一性、重复应用和工作区状态；回滚脚本只移除本补丁的标记块。

## 手动应用

在干净的工作区中运行：

\`\`\`bash
git show main:patches/inline-autofill-toggle/apply.sh > /tmp/apply-inline-autofill-toggle.sh
ALLOW_NON_MAIN=1 bash /tmp/apply-inline-autofill-toggle.sh
\`\`\`

脚本默认只允许在本地 \`main\` 分支执行；在上游 Tag 的 detached HEAD 上应用时，需要设置 \`ALLOW_NON_MAIN=1\`。

## 回滚

\`\`\`bash
git show main:patches/inline-autofill-toggle/rollback.sh > /tmp/rollback-inline-autofill-toggle.sh
ALLOW_NON_MAIN=1 bash /tmp/rollback-inline-autofill-toggle.sh
\`\`\`

## 自动同步

工作流：\`.github/workflows/sync-upstream-tags.yml\`

- 上游仓库：\`ximeiorg/Xime\`。
- 同步上游 \`main\` 到 fork 的 \`main\`。
- 仅同步稳定版 \`v3.5.0\` 及之后的语义化版本 Tag。
- 对每个上游 Tag 应用本补丁，并把补丁后的提交推送为 fork 中的同名 Tag。
- 不创建补丁分支，不修改上游 Tag。
- 支持手动触发和每日定时运行。
- 使用仓库 Secret \`SYNC_PAT\`，需要有本仓库 Contents 读写权限。

APK 构建完全交由各 Tag 自带的上游 GitHub Actions 工作流处理。本补丁与同步工作流不修改、不复制、不注入任何构建工作流，也不自行构建 APK。
