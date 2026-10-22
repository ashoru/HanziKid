#!/bin/bash
# 构建 iPad 模拟器版本（DerivedData 放在项目内）
#
# 说明：当前沙箱禁止嵌套 sandbox-exec，Xcode 的宏插件子进程（SwiftData @Model / SwiftUI 宏）
# 起不来，因此必须加 -disable-sandbox。换一台正常权限的机器可以去掉这一项。
set -euo pipefail

cd "$(dirname "$0")/.."

DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPad Pro 11-inch (M5)}"

xcodebuild build \
  -project HanziKid.xcodeproj \
  -scheme HanziKid \
  -destination "$DESTINATION" \
  -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' \
  | grep -E "error:|warning: |BUILD (SUCCEEDED|FAILED)" || true

test "${PIPESTATUS[0]}" = "0"
