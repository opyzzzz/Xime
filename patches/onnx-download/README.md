# ONNX Download Compatibility Patch

This optional patch hardens ONNX Runtime header acquisition in `app/build-logic/tasks-native.gradle.kts`.

- Fetches each required ONNX header directly from the matching ONNX Runtime release tag (`v<version>`) using `raw.githubusercontent.com`. The Android AAR remains pinned to the numeric `onnxVersion`.
- Rejects missing, empty, and HTML error responses instead of silently accepting invalid headers.
- Verifies every required header downloads successfully and fails the Gradle dependency task immediately if any header is missing.
- Keeps the AAR and headers pinned to the same numeric `onnxVersion`.

The patch is deliberately independent of the inline-autofill patch. The tag sync workflow attempts this patch first; incompatibility is reported as a warning and does not block publication, while failure of the required inline-autofill patch does block publication.

## Manual application

Run in a clean Xime working tree:

```bash
ALLOW_NON_MAIN=1 bash patches/onnx-download/apply.sh
```

The script is idempotent and checks exact source anchors before writing. If upstream restructures the ONNX download block, it exits without changing the file.

## Scope

This patch changes Gradle dependency-download logic only. It does not edit or replace `.github/workflows/release.yml`, and APK builds remain handled by the workflow included in each published tag.
