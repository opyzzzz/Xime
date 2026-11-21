#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "请在 Xime Git 工作区内执行。" >&2
  exit 1
}
BRANCH="$(git -C "$ROOT" branch --show-current)"
if [[ "$BRANCH" != "main" && "${ALLOW_NON_MAIN:-0}" != "1" ]]; then
  echo "为避免误改分支，默认只允许在 main 上回滚（当前：$BRANCH）。" >&2
  echo "如需在其他分支测试，可设置 ALLOW_NON_MAIN=1。" >&2
  exit 1
fi
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  echo "工作区不干净；请先提交或暂存现有改动。" >&2
  exit 1
fi

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
files = [
    root / "app/src/main/java/com/kingzcheung/xime/settings/SettingsPreferences.kt",
    root / "app/src/main/java/com/kingzcheung/xime/ui/settings/LayoutDisplaySettingsScreen.kt",
    root / "app/src/main/java/com/kingzcheung/xime/service/XimeInputMethodService.kt",
]
pattern = re.compile(
    r"^[ \t]*// BEGIN (INLINE_AUTOFILL_TOGGLE:[A-Z_]+)\r?\n"
    r".*?"
    r"^[ \t]*// END \1\r?\n?",
    re.MULTILINE | re.DOTALL,
)
updated = []
removed = 0
for path in files:
    if not path.is_file():
        raise SystemExit(f"目标文件不存在：{path}")
    text = path.read_text(encoding="utf-8")
    new_text, count = pattern.subn("", text)
    removed += count
    updated.append((path, new_text))

if removed == 0:
    print("未发现补丁标记，文件无需回滚。")
    raise SystemExit(0)
if removed != 5:
    raise SystemExit(f"只找到 {removed}/5 个补丁块；为避免不完整回滚，未写入文件。")

for path, text in updated:
    path.write_text(text, encoding="utf-8", newline="")
print("已移除全部 5 个补丁块。")
PY
