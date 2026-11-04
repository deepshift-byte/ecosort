#!/bin/bash
# SessionStart hook for EcoSort cloud sessions: installs the Flutter SDK and the
# Dart/Flutter packages so `flutter analyze` and `flutter test` work.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}"

FLUTTER_VERSION=3.47.9
FLUTTER_HOME=/opt/sdk/flutter

# Global tool: the Flutter SDK, installed only when missing or the wrong version.
installed=""
if [ -x "$FLUTTER_HOME/bin/flutter" ]; then
  installed=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["frameworkVersion"])' \
    "$FLUTTER_HOME/bin/cache/flutter.version.json" 2>/dev/null || true)
fi
if [ "$installed" != "$FLUTTER_VERSION" ]; then
  rm -rf "$FLUTTER_HOME"
  mkdir -p "$(dirname "$FLUTTER_HOME")"
  curl -sSfL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C "$(dirname "$FLUTTER_HOME")"
  git config --global --add safe.directory "$FLUTTER_HOME"
  "$FLUTTER_HOME/bin/flutter" --disable-analytics >/dev/null 2>&1 || true
  "$FLUTTER_HOME/bin/flutter" --version >/dev/null
fi
export PATH="$FLUTTER_HOME/bin:$PATH"

# Dart packages: run `flutter pub get` only when the manifests changed.
# The hash file lives in .dart_tool/ (git-ignored), which pub get fills.
hashes=.dart_tool/.session-start.sha256
if ! sha256sum --check --status "$hashes" 2>/dev/null \
   || [ ! -f .dart_tool/package_config.json ] \
   || [ ! -d "${PUB_CACHE:-$HOME/.pub-cache}/hosted" ]; then
  rm -f "$hashes"
  flutter pub get
  sha256sum .claude/hooks/session-start.sh pubspec.yaml pubspec.lock > "$hashes" || rm -f "$hashes"
fi

# Make flutter/dart available to every command in the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$FLUTTER_HOME/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
