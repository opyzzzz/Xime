# ONNX Download Compatibility Patch

This optional patch hardens ONNX Runtime header acquisition in `app/build-logic/tasks-native.gradle.kts`.

- Fetches the source archive matching the pinned ONNX Runtime version rather than relying on individual raw-file URLs.
- Validates that the response is a ZIP before extraction.
- Verifies every required header exists and fails the Gradle dependency task early if the archive is incomplete.
- Keeps the AAR version pinned to the same `onnxVersion` as the headers.

The patch is deliberately independent of the inline-autofill patch. The tag sync workflow attempts this patch first; incompatibility is reported as a warning and does not block publication, while failure of the required inline-autofill patch does block publication.

## Manual application

Run in a clean Xime working tree:

```bash
ALLOW_NON_MAIN=1 bash patches/onnx-download/apply.sh
```

The script is idempotent and checks exact source anchors before writing. If upstream restructures the ONNX download block, it exits without changing the file.

## Scope

This patch changes Gradle dependency-download logic only. It does not edit or replace `.github/workflows/release.yml`, and APK builds remain handled by the workflow included in each published tag.
