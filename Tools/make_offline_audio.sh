#!/bin/bash
# 把预生成音频放进 App 资源目录，做成「完全离线发音」版本（安装包 +83MB）
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d Tools/audio/chars ]; then
  echo "❌ 还没有音频，先跑：python3 Tools/fetch_audio.py"
  exit 1
fi

mkdir -p HanziKid/Resources/audio
rm -rf HanziKid/Resources/audio/chars HanziKid/Resources/audio/words
cp -R Tools/audio/chars Tools/audio/words HanziKid/Resources/audio/
echo "✅ 已拷入 $(find HanziKid/Resources/audio -name '*.mp3' | wc -l | tr -d ' ') 个音频文件，现在打包就是离线版"
echo "   想回到在线版：rm -rf HanziKid/Resources/audio"
