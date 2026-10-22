#!/bin/bash
# 升版本号 + build 号，并在 CHANGELOG.md 顶部插入一条待填写的新记录
#
# 用法：
#   ./Tools/bump_version.sh minor    # 0.4.0 → 0.5.0，build +1（加功能用这个）
#   ./Tools/bump_version.sh patch    # 0.4.0 → 0.4.1，build +1（修 bug 用这个）
#   ./Tools/bump_version.sh major    # 0.4.0 → 1.0.0，build +1
#   ./Tools/bump_version.sh build    # 版本不变，只 build +1（内部测试包）
set -euo pipefail

cd "$(dirname "$0")/.."
LEVEL="${1:-minor}"

python3 - "$LEVEL" <<'PY'
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

level = sys.argv[1]
if level not in ("major", "minor", "patch", "build"):
    sys.exit("用法：bump_version.sh [major|minor|patch|build]")

project = Path("HanziKid.xcodeproj/project.pbxproj")
text = project.read_text(encoding="utf-8")
version = re.search(r"MARKETING_VERSION = ([\d.]+);", text).group(1)
build = int(re.search(r"CURRENT_PROJECT_VERSION = (\d+);", text).group(1))

major, minor, patch = (list(map(int, version.split("."))) + [0, 0])[:3]
if level == "major":
    major, minor, patch = major + 1, 0, 0
elif level == "minor":
    minor, patch = minor + 1, 0
elif level == "patch":
    patch += 1
build += 1

new_version = f"{major}.{minor}.{patch}"
text = re.sub(r"MARKETING_VERSION = [\d.]+;", f"MARKETING_VERSION = {new_version};", text)
text = re.sub(r"CURRENT_PROJECT_VERSION = \d+;", f"CURRENT_PROJECT_VERSION = {build};", text)
project.write_text(text, encoding="utf-8")

changelog = Path("CHANGELOG.md")
today = datetime.now().strftime("%Y-%m-%d")
entry = f"## [{new_version}] - {today}  (build {build})\n\n- TODO：写这次改了什么（用户能感知的变化）\n\n"
if changelog.exists():
    content = changelog.read_text(encoding="utf-8")
    marker = "\n## ["
    index = content.find(marker)
    if index == -1:
        content = content.rstrip() + "\n\n" + entry
    else:
        content = content[:index] + "\n" + entry + content[index + 1:]
    changelog.write_text(content, encoding="utf-8")
else:
    changelog.write_text(f"# 更新日志\n\n{entry}", encoding="utf-8")

print(f"{new_version} (build {build})")
PY

echo "已更新 CHANGELOG.md，把 TODO 那条改成实际改动后打包：./Tools/package_ipa.sh"
echo "（打包成功会自动 commit + push 到 GitHub、打 vX.Y.Z tag、并把 IPA 传到 Releases）"
