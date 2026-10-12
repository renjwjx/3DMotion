#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_dir="$project_dir/dist/关节-肌群解析.app"
contents_dir="$app_dir/Contents"
if [[ ! -f "$project_dir/Sources/Body3DMac/Resources/Web/static/data/processed_data.json" ]]; then
  print -u2 "离线资源不存在，请先运行 Scripts/download_assets.py"
  exit 1
fi

cd "$project_dir"
xcodebuild \
  -project Body3DMac.xcodeproj \
  -scheme Body3DMac \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$project_dir/.build/DerivedData-macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build

product="$project_dir/.build/DerivedData-macOS/Build/Products/Release/Body3DMac.app"
mkdir -p "$project_dir/dist"
ditto "$product" "$app_dir"
codesign --force --deep --sign - "$app_dir" >/dev/null
print "$app_dir"
