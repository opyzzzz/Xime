#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Run this script inside an Xime Git working tree." >&2
  exit 1
}
BRANCH="$(git -C "$ROOT" branch --show-current)"
if [[ "$BRANCH" != "main" && "${ALLOW_NON_MAIN:-0}" != "1" ]]; then
  echo "Refusing to patch a non-main branch without ALLOW_NON_MAIN=1 (current: $BRANCH)." >&2
  exit 1
fi
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  echo "Working tree is not clean; refusing to apply the ONNX patch." >&2
  exit 1
fi

python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
path = root / "app/build-logic/tasks-native.gradle.kts"
if not path.is_file():
    raise SystemExit(f"ONNX build file not found: {path}")
text = path.read_text(encoding="utf-8")

import re

begin = "// BEGIN ONNX_DOWNLOAD_PATCH:RAW_HEADERS"
end = "// END ONNX_DOWNLOAD_PATCH:RAW_HEADERS"

def restrict_headers(source: str) -> str:
    replacement = '''        val headersToFetch = listOf(
            "core/session/onnxruntime_c_api.h",
            "core/session/onnxruntime_error_code.h",
        )'''
    updated, count = re.subn(
        r"        val headersToFetch = listOf\\([\\s\\S]*?\\n        \\)",
        lambda _: replacement,
        source,
        count=1,
    )
    if count != 1:
        raise SystemExit("ONNX headersToFetch list changed; refusing to guess required headers.")
    return updated

if begin in text and end in text:
    updated = restrict_headers(text)
    if updated != text:
        path.write_text(updated, encoding="utf-8")
        print("Updated existing ONNX patch to fetch only the C API headers used by Xime.")
    else:
        print("ONNX download patch is already applied with the minimal required header set.")
    raise SystemExit(0)
if begin in text or end in text:
    raise SystemExit("Incomplete ONNX patch markers; refusing to modify the file.")

old_base = 'val onnxHeadersBase = "https://raw.githubusercontent.com/microsoft/onnxruntime/v${onnxVersion}/include/onnxruntime"'
if text.count(old_base) != 1:
    raise SystemExit("ONNX header URL anchor changed; patch not applied.")
text = text.replace(
    old_base,
    'val onnxHeadersBase = "https://raw.githubusercontent.com/microsoft/onnxruntime/rel-${onnxVersion}/include/onnxruntime"',
    1,
)

text = restrict_headers(text)

old_aar = 'if (!downloadWithMirrors(listOf(onnxAarUrl), aar, buildDir, "onnxruntime-android AAR")) {'
new_aar = '''val aarUrls = listOf(
            onnxAarUrl.replace("repo1.maven.org/maven2", "repo.maven.apache.org/maven2"),
            onnxAarUrl
        )
        if (!downloadWithMirrors(aarUrls, aar, buildDir, "onnxruntime-android AAR")) {'''
if text.count(old_aar) != 1:
    raise SystemExit("ONNX AAR download anchor changed; patch not applied.")
text = text.replace(old_aar, new_aar, 1)

old_loop = '''        for (rel in headersToFetch) {
            val target = java.io.File(dstHeaders, rel.substringAfterLast("/"))
            val url = "$onnxHeadersBase/$rel"
            if (downloadWithMirrors(githubUrls(url), target, buildDir, "onnxruntime header $rel")) {
                println("Header ok: ${target.name}")
            } else {
                System.err.println("WARNING: failed to fetch header $rel")
            }
        }
'''
new_loop = '''        // BEGIN ONNX_DOWNLOAD_PATCH:RAW_HEADERS
        // Fetch exact versioned headers from the ONNX Runtime release branch.
        for (rel in headersToFetch) {
            val target = File(dstHeaders, rel.substringAfterLast("/"))
            val url = "$onnxHeadersBase/$rel"
            target.delete()
            if (!downloadWithMirrors(githubUrls(url), target, buildDir, "onnxruntime header $rel")) {
                throw GradleException("Failed to download required ONNX Runtime v${onnxVersion} header: $rel")
            }
            if (!target.isFile || target.length() < 100L || target.readText().trimStart().startsWith("<")) {
                throw GradleException("Downloaded ONNX Runtime header is empty or missing: $rel")
            }
            println("Header ok: ${target.name} (${target.length()} bytes)")
        }
        // END ONNX_DOWNLOAD_PATCH:RAW_HEADERS
'''
if text.count(old_loop) != 1:
    raise SystemExit("ONNX header download loop changed; patch not applied.")
text = text.replace(old_loop, new_loop, 1)

# Write only after all compatibility checks and transformations succeeded.
path.write_text(text, encoding="utf-8")
print("ONNX patch applied: version-matched release-branch raw headers with fail-fast verification.")
PY
