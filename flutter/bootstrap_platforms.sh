#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v flutter >/dev/null 2>&1 || { echo "Flutter SDK is required."; exit 1; }
# Generate platform runner boilerplate (including iOS) while preserving lib/ and pubspec.yaml.
flutter create --platforms=android,ios --org com.example .
flutter pub get
echo "Platform scaffolding generated. Review the diff before committing."
