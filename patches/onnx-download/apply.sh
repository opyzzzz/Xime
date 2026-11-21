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

begin = "// BEGIN ONNX_DOWNLOAD_PATCH:ARCHIVE_HEADERS"
end = "// END ONNX_DOWNLOAD_PATCH:ARCHIVE_HEADERS"
if begin in text and end in text:
    print("ONNX download patch is already applied.")
    raise SystemExit(0)
if begin in text or end in text:
    raise SystemExit("Incomplete ONNX patch markers; refusing to modify the file.")

old_base = 'val onnxHeadersBase = "https://raw.githubusercontent.com/microsoft/onnxruntime/v${onnxVersion}/include/onnxruntime"'
if text.count(old_base) != 1:
    raise SystemExit("ONNX header URL anchor changed; patch not applied.")
text = text.replace(
    old_base,
    'val onnxHeadersArchiveUrl = "https://github.com/microsoft/onnxruntime/archive/refs/heads/rel-${onnxVersion}.zip"',
    1,
)

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
new_loop = '''        // BEGIN ONNX_DOWNLOAD_PATCH:ARCHIVE_HEADERS
        // Fetch the complete, version-matched source archive instead of individual raw URLs.
        val headersZip = File(buildDir, "onnxruntime-${onnxVersion}-headers.zip")
        fun isValidZip(file: File): Boolean {
            return try {
                val bytes = file.inputStream().use { input -> ByteArray(4).also { input.read(it) } }
                bytes.size == 4 && bytes[0] == 0x50.toByte() && bytes[1] == 0x4b.toByte() &&
                    bytes[2] == 0x03.toByte() && bytes[3] == 0x04.toByte()
            } catch (_: Exception) {
                false
            }
        }
        val archiveUrls = listOf(
            onnxHeadersArchiveUrl,
            "https://codeload.github.com/microsoft/onnxruntime/legacy.zip/refs/heads/rel-${onnxVersion}"
        )
        var archiveDownloaded = false
        for (url in archiveUrls) {
            headersZip.delete()
            if (downloadWithMirrors(listOf(url), headersZip, buildDir, "ONNX Runtime v${onnxVersion} source archive") &&
                isValidZip(headersZip)) {
                archiveDownloaded = true
                break
            }
            headersZip.delete()
        }
        if (!archiveDownloaded) {
            throw GradleException("Failed to download a valid ONNX Runtime v${onnxVersion} source archive")
        }

        val archiveDir = File(buildDir, "onnxruntime-${onnxVersion}-headers")
        archiveDir.deleteRecursively()
        try {
            copy {
                from(zipTree(headersZip))
                into(archiveDir)
            }
        } catch (e: Exception) {
            throw GradleException("Failed to extract ONNX Runtime source archive: ${e.message}")
        }
        val sourceInclude = archiveDir.walkTopDown().firstOrNull {
            it.isDirectory && it.name == "onnxruntime" &&
                File(it, "core/session/onnxruntime_c_api.h").isFile
        } ?: throw GradleException("ONNX Runtime archive does not contain include/onnxruntime headers")

        for (rel in headersToFetch) {
            val source = File(sourceInclude, rel)
            if (!source.isFile) {
                throw GradleException("ONNX Runtime v${onnxVersion} archive is missing required header: $rel")
            }
            val target = File(dstHeaders, rel.substringAfterLast("/"))
            source.copyTo(target, overwrite = true)
            println("Header ok: ${target.name}")
        }
        val requiredHeaders = listOf("onnxruntime_c_api.h", "onnxruntime_ep_c_api.h", "onnxruntime_error_code.h")
        val missingHeaders = requiredHeaders.filterNot { File(dstHeaders, it).isFile }
        if (missingHeaders.isNotEmpty()) {
            throw GradleException("Required ONNX Runtime headers missing after extraction: ${missingHeaders.joinToString()}")
        }
        // END ONNX_DOWNLOAD_PATCH:ARCHIVE_HEADERS
'''
if text.count(old_loop) != 1:
    raise SystemExit("ONNX header download loop changed; patch not applied.")
text = text.replace(old_loop, new_loop, 1)

# Write only after all compatibility checks and transformations succeeded.
path.write_text(text, encoding="utf-8")
print("ONNX patch applied: version-matched GitHub source archive, ZIP validation, and fail-fast header verification.")
PY
