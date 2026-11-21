#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "请在 Xime Git 工作区内执行。" >&2
  exit 1
}
BRANCH="$(git -C "$ROOT" branch --show-current)"
if [[ "$BRANCH" != "main" && "${ALLOW_NON_MAIN:-0}" != "1" ]]; then
  echo "为避免误改功能分支，默认只允许在 main 上应用补丁（当前：$BRANCH）。" >&2
  echo "如需在其他分支测试，可设置 ALLOW_NON_MAIN=1。" >&2
  exit 1
fi
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  echo "工作区不干净；请先提交或暂存现有改动。" >&2
  exit 1
fi

python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
files = {
    "prefs": root / "app/src/main/java/com/kingzcheung/xime/settings/SettingsPreferences.kt",
    "ui": root / "app/src/main/java/com/kingzcheung/xime/ui/settings/LayoutDisplaySettingsScreen.kt",
    "service": root / "app/src/main/java/com/kingzcheung/xime/service/XimeInputMethodService.kt",
}
for path in files.values():
    if not path.is_file():
        raise SystemExit(f"目标文件不存在：{path}")

contents = {key: path.read_text(encoding="utf-8") for key, path in files.items()}
markers = [
    "INLINE_AUTOFILL_TOGGLE:PREF_KEY",
    "INLINE_AUTOFILL_TOGGLE:PREF_ACCESSORS",
    "INLINE_AUTOFILL_TOGGLE:UI_STATE",
    "INLINE_AUTOFILL_TOGGLE:UI_CONTROL",
    "INLINE_AUTOFILL_TOGGLE:SERVICE_GATE",
]
all_text = "\n".join(contents.values())
present = [m for m in markers if f"// BEGIN {m}" in all_text]
if len(present) == len(markers):
    print("补丁已完整应用，无需重复操作。")
    raise SystemExit(0)
if present:
    raise SystemExit("检测到不完整的补丁标记；为避免破坏文件，已停止。请先检查或回滚。")

def insert_once(text, anchor, addition, label):
    count = text.count(anchor)
    if count != 1:
        raise SystemExit(f"{label}：定位锚点应恰好出现 1 次，实际 {count} 次；未写入文件。")
    return text.replace(anchor, anchor + addition, 1)

contents["prefs"] = insert_once(
    contents["prefs"],
    '    const val KEY_HARDWARE_KEYBOARD_DETECTION_ENABLED = "hardware_keyboard_detection_enabled"\n',
    '''
    // BEGIN INLINE_AUTOFILL_TOGGLE:PREF_KEY
    const val KEY_INLINE_AUTOFILL_SUGGESTIONS_ENABLED = "inline_autofill_suggestions_enabled"
    // END INLINE_AUTOFILL_TOGGLE:PREF_KEY
''',
    "Preferences Key",
)

prefs_anchor = '''    fun setHardwareKeyboardDetectionEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit().putBoolean(KEY_HARDWARE_KEYBOARD_DETECTION_ENABLED, enabled).apply()
    }
'''
contents["prefs"] = insert_once(
    contents["prefs"],
    prefs_anchor,
    '''
    // BEGIN INLINE_AUTOFILL_TOGGLE:PREF_ACCESSORS
    fun isInlineAutofillSuggestionsEnabled(context: Context): Boolean =
        getPrefs(context).getBoolean(KEY_INLINE_AUTOFILL_SUGGESTIONS_ENABLED, true)

    fun setInlineAutofillSuggestionsEnabled(context: Context, enabled: Boolean) {
        getPrefs(context).edit()
            .putBoolean(KEY_INLINE_AUTOFILL_SUGGESTIONS_ENABLED, enabled)
            .apply()
    }
    // END INLINE_AUTOFILL_TOGGLE:PREF_ACCESSORS
''',
    "Preferences accessors",
)

ui_state_anchor = '''    var showComments by remember {
        mutableStateOf(SettingsPreferences.showCandidateComments(context))
    }
'''
contents["ui"] = insert_once(
    contents["ui"],
    ui_state_anchor,
    '''
    // BEGIN INLINE_AUTOFILL_TOGGLE:UI_STATE
    var inlineAutofillSuggestionsEnabled by remember {
        mutableStateOf(SettingsPreferences.isInlineAutofillSuggestionsEnabled(context))
    }
    // END INLINE_AUTOFILL_TOGGLE:UI_STATE
''',
    "Settings UI state",
)

ui_control_anchor = '''                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp)
                    ) {
'''
contents["ui"] = insert_once(
    contents["ui"],
    ui_control_anchor,
    '''
                    // BEGIN INLINE_AUTOFILL_TOGGLE:UI_CONTROL
                    SectionDivider()
                    SettingsToggleItem(
                        icon = Icons.AutoMirrored.TwoTone.Input,
                        title = "内联自动填充建议",
                        subtitle = "控制是否显示密码管理器提供的内联自动填充建议",
                        checked = inlineAutofillSuggestionsEnabled,
                        onCheckedChange = { enabled ->
                            inlineAutofillSuggestionsEnabled = enabled
                            SettingsPreferences.setInlineAutofillSuggestionsEnabled(context, enabled)
                        }
                    )
                    // END INLINE_AUTOFILL_TOGGLE:UI_CONTROL
''',
    "Settings UI control",
)

service_anchor = '''        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        if (inlineSuggestionManager == null) return null
'''
contents["service"] = insert_once(
    contents["service"],
    service_anchor,
    '''        // BEGIN INLINE_AUTOFILL_TOGGLE:SERVICE_GATE
        if (!SettingsPreferences.isInlineAutofillSuggestionsEnabled(this)) return null
        // END INLINE_AUTOFILL_TOGGLE:SERVICE_GATE
''',
    "Inline suggestions service gate",
)

# 所有定位和重复执行检查均通过后才写文件，避免部分应用。
for key, path in files.items():
    path.write_text(contents[key], encoding="utf-8", newline="")

print("补丁已应用：Preferences、设置界面、IME 请求入口。")
print("建议执行：./gradlew assembleDebug")
PY
