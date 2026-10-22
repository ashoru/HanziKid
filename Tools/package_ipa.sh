#!/bin/bash
# 打包成「无签名」IPA（自签 / Sideloadly / AltStore / ESign 用）
#
# 说明：无签名 IPA 不能直接装到 iPad，需要先用你自己的 Apple ID 重签。
# 当前沙箱禁止嵌套 sandbox-exec，所以必须带 -disable-sandbox（宏插件子进程要用）。
set -euo pipefail

cd "$(dirname "$0")/.."

DIST="dist"
APP=".build/Build/Products/Release-iphoneos/HanziKid.app"

echo "== 1/4 编译（Release / iphoneos / arm64，关闭签名）"
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

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Info.plist")
NAME="HanziKid-${VERSION}(${BUILD})-unsigned"
echo "   版本 $VERSION (build $BUILD)"

echo "== 2/4 打包 Payload"
rm -rf .build/ipa
mkdir -p .build/ipa/Payload "$DIST"
cp -R "$APP" .build/ipa/Payload/
( cd .build/ipa && zip -qry "../../$DIST/$NAME.ipa" Payload )

echo "== 3/4 校验（版本 ${VERSION}，build ${BUILD}）"
unzip -l "$DIST/$NAME.ipa" | tail -3
file "$APP/HanziKid" | sed 's/^/  /'
codesign -dv "$APP" 2>&1 | head -1 | sed 's/^/  /' || true
ls -lh "$DIST/$NAME.ipa"
echo "   安装包：$DIST/$NAME.ipa"
echo "   记得在 CHANGELOG.md 里补上 $VERSION 的改动"
shasum -a 256 "$DIST/$NAME.ipa"

# == 4/4 同步到 GitHub（源码 + tag + Release 里的 IPA）
# 不想自动同步：SYNC_GITHUB=0 ./Tools/package_ipa.sh
if [ "${SYNC_GITHUB:-1}" = "0" ]; then
  echo "== 4/4（SYNC_GITHUB=0，跳过 GitHub 同步）"
else
  echo "== 4/4 同步到 GitHub"
  ./Tools/sync_github.sh -m "release: $NAME" \
    || echo "⚠️ GitHub 同步失败（安装包本身已打好）：网络恢复后重跑 ./Tools/sync_github.sh 即可补齐"
fi
