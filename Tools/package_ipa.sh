#!/bin/bash
# 打包成「无签名」IPA（自签 / Sideloadly / AltStore / ESign 用）
#
# 说明：无签名 IPA 不能直接装到 iPad，需要先用你自己的 Apple ID 重签。
# 当前沙箱禁止嵌套 sandbox-exec，所以必须带 -disable-sandbox（宏插件子进程要用）。
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="HanziKid-unsigned"
DIST="dist"
APP=".build/Build/Products/Release-iphoneos/HanziKid.app"

echo "== 1/3 编译（Release / iphoneos / arm64，关闭签名）"
xcodebuild build \
  -project HanziKid.xcodeproj \
  -scheme HanziKid \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

test -d "$APP" || { echo "❌ 没找到 $APP"; exit 1; }

echo "== 2/3 打包 Payload"
rm -rf .build/ipa
mkdir -p .build/ipa/Payload "$DIST"
cp -R "$APP" .build/ipa/Payload/
( cd .build/ipa && zip -qry "../../$DIST/$NAME.ipa" Payload )

echo "== 3/3 校验"
unzip -l "$DIST/$NAME.ipa" | tail -3
file "$APP/HanziKid" | sed 's/^/  /'
codesign -dv "$APP" 2>&1 | head -1 | sed 's/^/  /' || true
ls -lh "$DIST/$NAME.ipa"
shasum -a 256 "$DIST/$NAME.ipa"
