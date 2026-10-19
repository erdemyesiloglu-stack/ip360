#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${1:?Kullanım: bash tool/prepare_android.sh /tam/yol/build}"
if [ -e "$build_dir" ]; then
  echo 'Hedef klasör zaten var. Yeni, boş bir hedef yolu kullanın.' >&2
  exit 1
fi
flutter create --platforms=android --org com.erdemyesiloglu --project-name ip360 "$build_dir"
rm -rf "$build_dir/lib" "$build_dir/test"
cp -R "$source_dir/lib" "$build_dir/lib"
cp -R "$source_dir/test" "$build_dir/test"
cp -R "$source_dir/tool" "$build_dir/tool"
cp -R "$source_dir/branding" "$build_dir/branding"
cp "$source_dir/pubspec.yaml" "$build_dir/pubspec.yaml"
cp "$source_dir/analysis_options.yaml" "$build_dir/analysis_options.yaml"
cd "$build_dir"
flutter pub get
dart run tool/configure_android.dart
