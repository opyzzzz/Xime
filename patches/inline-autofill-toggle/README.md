# Inline Autofill Toggle Patch

本目录提供一个面向当前 `main` 的独立补丁包。它不会把旧功能分支的提交历史合并进来，也不会整体替换 IME 自动填充请求函数。

## 补丁内容

- `SettingsPreferences.kt`：新增偏好 Key、读取和写入方法，默认开启以保持现有行为。
- `LayoutDisplaySettingsScreen.kt`：在“候选词”设置区域增加“内联自动填充建议”开关。
- `XimeInputMethodService.kt`：在 API 版本检查之后、管理器空值检查之前增加开关判断；保留 main 当前的管理器初始化、主题更新和响应处理逻辑。

每个插入块均带有 `BEGIN/END INLINE_AUTOFILL_TOGGLE` 标记。应用脚本会验证唯一锚点、检查重复标记，并在全部检查通过后写入文件；回滚脚本只移除这五个标记块。

## 在 main 上应用

先确保本地 main 已更新且工作区干净：

```bash
git switch main
git pull --ff-only origin main
git status --short
```

从补丁分支取出独立脚本并执行：

```bash
git show patch/inline-autofill-toggle:patches/inline-autofill-toggle/apply.sh > /tmp/apply-inline-autofill-toggle.sh
bash /tmp/apply-inline-autofill-toggle.sh
```

然后检查并编译：

```bash
git diff --check
./gradlew assembleDebug
```

验证通过后，再由维护者决定是否提交功能改动。

## 回滚

确保工作区干净后：

```bash
git show patch/inline-autofill-toggle:patches/inline-autofill-toggle/rollback.sh > /tmp/rollback-inline-autofill-toggle.sh
bash /tmp/rollback-inline-autofill-toggle.sh
```

回滚脚本要求五个补丁标记块全部存在；若只发现部分标记，会停止而不写入文件。

## 安全约束

- 默认只允许在当前分支为 `main` 时应用或回滚。
- 要在临时测试分支验证时，可显式设置 `ALLOW_NON_MAIN=1`。
- 工作区必须干净；补丁不会覆盖未提交的本地改动。
- 脚本只做文本插入，不会自动提交、推送或创建 PR。

## 上游 Tag 自动同步 Action

工作流文件：`.github/workflows/sync-upstream-tags.yml`

- 上游固定为 `https://github.com/ximeiorg/Xime.git`。
- 只读取上游符合 `vMAJOR.MINOR.PATCH` / 预发布格式的版本 Tag；基线为稳定版 `v3.5.0`，因此更早版本以及 `v3.5.0-rc` 等同版本预发布 Tag 不会同步。
- 不同步上游分支，也不把上游提交合并到 fork 的 `main`。
- 缺失的上游 Tag 会原样推送到 fork；若 fork 已有同名 Tag 且指向不同提交，工作流会失败并拒绝覆盖。
- 每个合格 Tag 会独立创建 `upstream-patched/<tag>` 分支，并在该 Tag 的代码上应用本目录的补丁；已存在的补丁分支会跳过。
- 支持手动触发和每日定时检查（03:17 UTC）。

工作流从 `patch/inline-autofill-toggle` 分支读取补丁脚本。要启用 GitHub 定时触发，需先将该工作流文件合入仓库默认分支；手动运行时可在 Actions 页面选择包含此工作流的分支。
