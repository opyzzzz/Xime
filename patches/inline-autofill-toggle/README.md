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
