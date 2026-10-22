#!/bin/bash
# 在没有 PTY（xcodebuild test 起不了测试宿主）的环境里验证核心逻辑。
# 编译 Domain 层为 macOS 命令行程序，跑与 HanziKidTests 一致的断言。
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .build/mcache

xcrun swiftc \
  -swift-version 5 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -target arm64-apple-macos14.0 \
  -Xfrontend -disable-sandbox \
  -module-cache-path .build/mcache \
  HanziKid/Domain/Models.swift \
  HanziKid/Domain/HanziText.swift \
  HanziKid/Services/CardImporter.swift \
  HanziKid/Services/StrokeLibrary.swift \
  HanziKid/Domain/Scheduler.swift \
  HanziKid/Domain/StudySession.swift \
  Tools/logic_checks/main.swift \
  -o .build/logic_checks

./.build/logic_checks
