#!/bin/bash
# 把当前版本同步到 GitHub（默认仓库 ashoru/HanziKid）
#
# 做的事（幂等，重复跑不会出错）：
#   1. 有改动就提交（提交说明默认带版本号）
#   2. 推送 main 分支
#   3. 打版本 tag v主.次.修（已存在就跳过）
#   4. 建/更新 GitHub Release，说明取自 CHANGELOG.md 对应版本段落
#   5. 把 dist/ 里本版本的 unsigned IPA 传上去（Assets 里可下载）
#
# 用法：
#   ./Tools/sync_github.sh                      # 全套同步
#   ./Tools/sync_github.sh -m "fix: 修 xxx"      # 自定义提交说明
#   ./Tools/sync_github.sh --no-ipa             # 只同步源码 + tag，不传 IPA
#   ./Tools/sync_github.sh --retag              # tag 已存在时强制挪到当前提交
#   ./Tools/sync_github.sh --dry-run            # 只看要做什么，不真的提交推送
#
# Token 来源（按顺序）：环境变量 GH_TOKEN / GITHUB_TOKEN，否则读 macOS 钥匙串
# （github.com 那条 Personal Access Token）。token 不会写进任何文件。
# 新 token 申请地址：https://github.com/settings/tokens  （scopes 勾 repo + workflow）
set -euo pipefail

cd "$(dirname "$0")/.."

WITH_IPA=1
DRY_RUN=0
RETAG=0
COMMIT_MSG=""

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--message) COMMIT_MSG="${2:?需要提交说明}"; shift 2 ;;
    --no-ipa)     WITH_IPA=0; shift ;;
    --retag)      RETAG=1; shift ;;   # tag 已存在时强制挪到当前提交（发版后又补了提交用这个）
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$1（-h 看用法）" >&2; exit 2 ;;
  esac
done

PROJ="HanziKid.xcodeproj/project.pbxproj"
VERSION=$(grep -m1 'MARKETING_VERSION = ' "${PROJ}" | tr -dc '0-9.')
BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION = ' "${PROJ}" | tr -dc '0-9.')
[ -n "${VERSION}" ] && [ -n "${BUILD}" ] || { echo "❌ 读不到版本号，检查 ${PROJ}"; exit 1; }
TAG="v${VERSION}"

REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
[ -n "${REMOTE_URL}" ] || { echo "❌ 没有 origin，先跑：git remote add origin https://github.com/<owner>/<repo>.git"; exit 1; }
SLUG=$(printf '%s' "${REMOTE_URL}" | sed -E 's#^git@github.com:##; s#^ssh://git@github.com/##; s#^https://([^@]*@)?github.com/##; s#/$##; s#\.git$##')

echo "== 同步 ${SLUG}  版本 ${VERSION} (build ${BUILD})  分支 $(git rev-parse --abbrev-ref HEAD)"

# ---------- token ----------
# 来源优先顺序：GH_TOKEN / GITHUB_TOKEN 环境变量 → git 的 osxkeychain 助手
# （读的就是钥匙串里 github.com 那条 Personal Access Token，git 已授权，不弹窗不卡住）
# → 直接问 security（首次可能要你在弹窗点「允许」，最多等 10 秒）。
# token 只存在内存里，不写进任何文件。
_TOKEN=""
gh_token() {
  if [ -n "${_TOKEN}" ]; then printf '%s' "${_TOKEN}"; return 0; fi
  if [ -n "${GH_TOKEN:-}" ]; then _TOKEN="${GH_TOKEN}"; printf '%s' "${_TOKEN}"; return 0; fi
  if [ -n "${GITHUB_TOKEN:-}" ]; then _TOKEN="${GITHUB_TOKEN}"; printf '%s' "${_TOKEN}"; return 0; fi
  local t=""
  t=$({ printf 'protocol=https\nhost=github.com\n\n' | git credential-osxkeychain get 2>/dev/null || true; } \
      | awk -F= '/^password=/{sub(/^password=/,""); print; exit}')
  if [ -z "$t" ]; then
    mkdir -p .tmp
    ( security find-internet-password -s github.com -w > .tmp/.tok 2>/dev/null & p=$!; sleep 10; kill $p 2>/dev/null ) || true
    t=$(tail -1 .tmp/.tok 2>/dev/null || true)
    rm -f .tmp/.tok
  fi
  [ -n "$t" ] || { echo "❌ 没拿到 GitHub token：可用 GH_TOKEN 环境变量传入（申请：https://github.com/settings/tokens）" >&2; return 1; }
  _TOKEN="$t"
  printf '%s' "${_TOKEN}"
}

RETRY_SSL=3
push_retry() {
  local i
  for i in $(seq 1 ${RETRY_SSL}); do
    if git push "$@"; then return 0; fi
    [ "$i" -lt ${RETRY_SSL} ] && { echo "   推送失败（第 $i 次），3 秒后重试…" >&2; sleep 3; }
  done
  echo "❌ 推送失败，检查网络/权限" >&2
  return 1
}

api() { # api METHOD PATH [json] → 输出 body，非 2xx 返回非 0（网络抖动/5xx 自动重试）
  local method="$1" path="$2" data="${3:-}" out code attempt
  local args=(-sS --max-time 60 -X "${method}" -H "Authorization: token $(gh_token)" -H "Accept: application/vnd.github+json")
  [ -n "${data}" ] && args+=(-H "Content-Type: application/json" -d "${data}")
  for attempt in 1 2 3; do
    out=$(curl "${args[@]}" -w $'\n%{http_code}' "https://api.github.com${path}" || true)
    code=$(printf '%s' "${out}" | tail -1)
    case "${code}" in
      2*) printf '%s' "${out}" | sed '$d'; return 0 ;;
      000|"") [ "${attempt}" -lt 3 ] && { echo "   网络抖动，重试（${attempt}/3）…" >&2; sleep 3; continue; } ;;
      5*|429)  [ "${attempt}" -lt 3 ] && { echo "   HTTP ${code}，重试（${attempt}/3）…" >&2; sleep 3; continue; } ;;
    esac
    break
  done
  printf '%s' "${out}" | sed '$d'
  echo "   HTTP ${code}" >&2
  return 1
}

# ---------- 1. 提交 ----------
if [ -n "$(git status --porcelain)" ]; then
  echo "== 1/4 提交改动"
  git status --short | sed 's/^/   /'
  [ -n "${COMMIT_MSG}" ] || COMMIT_MSG="${VERSION} (build ${BUILD}): 同步更新"
  if [ "${DRY_RUN}" = "1" ]; then
    echo "   [dry-run] 会提交：${COMMIT_MSG}"
  else
    git add -A
    git commit -q -m "${COMMIT_MSG}"
    echo "   ✅ $(git log -1 --oneline)"
  fi
else
  echo "== 1/4 没有未提交的改动"
fi

# ---------- 2. 推送 main ----------
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "== 2/4 推送 ${BRANCH}"
if [ "${DRY_RUN}" = "1" ]; then
  echo "   [dry-run] git push origin ${BRANCH}"
else
  push_retry origin "${BRANCH}:${BRANCH}"
  git branch --set-upstream-to="origin/${BRANCH}" "${BRANCH}" >/dev/null 2>&1 || true
  echo "   ✅ 已推送 $(git rev-parse --short HEAD)"
fi

# ---------- 3. tag ----------
echo "== 3/4 版本 tag ${TAG}"
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  TAG_SHA=$(git rev-list -n1 "${TAG}")
  if [ "$TAG_SHA" != "$(git rev-parse HEAD)" ] && [ "$RETAG" = "1" ]; then
    echo "   已存在但指向 ${TAG_SHA}，--retag：挪到 $(git rev-parse --short HEAD)"
    if [ "$DRY_RUN" = "1" ]; then
      echo "   [dry-run] git tag -f -a ${TAG} && git push -f origin ${TAG}"
    else
      git tag -f -a "${TAG}" -m "${TAG} (build ${BUILD})" >/dev/null
      push_retry -f origin "${TAG}"
      echo "   ✅ tag 已更新"
    fi
  elif [ "$TAG_SHA" != "$(git rev-parse HEAD)" ]; then
    echo "   已存在，跳过（指向 ${TAG_SHA:0:7}，要挪到最新提交加 --retag）"
  else
    echo "   已存在，跳过"
  fi
elif [ "${DRY_RUN}" = "1" ]; then
  echo "   [dry-run] git tag -a ${TAG} -m \"${TAG} (build ${BUILD})\""
else
  git tag -a "${TAG}" -m "${TAG} (build ${BUILD})"
  push_retry origin "${TAG}"
  echo "   ✅ 已打 tag 并推送"
fi

# ---------- 4. Release + IPA ----------
echo "== 4/4 Release ${TAG}"
CHANGELOG_BODY=$(python3 - "${VERSION}" <<'PY'
import json, re, sys
from pathlib import Path
ver = sys.argv[1]
text = Path("CHANGELOG.md").read_text(encoding="utf-8") if Path("CHANGELOG.md").exists() else ""
blocks = re.split(r"(?m)^## \[", text)
body = ""
for b in blocks[1:]:
    if b.startswith(ver + "]"):
        body = "## [" + b
        break
if not body:
    body = f"## [{ver}]\n\n详见 CHANGELOG.md"
body = body.strip()
body += "\n\n---\n\n**安装包**：`HanziKid-{v}-unsigned.ipa`（需自签后安装）\n".format(v=ver)
print(json.dumps(body))
PY
)

RELEASE_JSON=$(api GET "/repos/${SLUG}/releases/tags/${TAG}" 2>/dev/null || true)
RELEASE_ID=$(printf '%s' "${RELEASE_JSON}" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("id",""))
except Exception: print("")' 2>/dev/null || true)

if [ "${DRY_RUN}" = "1" ]; then
  if [ -n "${RELEASE_ID}" ]; then echo "   [dry-run] 会更新 Release ${TAG}"; else echo "   [dry-run] 会创建 Release ${TAG}"; fi
  [ "${WITH_IPA}" = "1" ] && echo "   [dry-run] 会检查并上传 dist/ 里的 IPA"
  echo "✅ dry-run 结束"
  exit 0
fi

PAYLOAD=$(python3 - "${TAG}" "${BUILD}" "${CHANGELOG_BODY}" <<'PY'
import json, sys
tag, build, body = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
print(json.dumps({
    "tag_name": tag,
    "name": f"{tag} (build {build})",
    "body": body,
    "draft": False,
    "prerelease": False,
}))
PY
)

if [ -n "${RELEASE_ID}" ]; then
  api PATCH "/repos/${SLUG}/releases/${RELEASE_ID}" "${PAYLOAD}" >/dev/null
  echo "   ✅ 已更新 Release：https://github.com/${SLUG}/releases/tag/${TAG}"
else
  RELEASE_JSON=$(api POST "/repos/${SLUG}/releases" "${PAYLOAD}")
  RELEASE_ID=$(printf '%s' "${RELEASE_JSON}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  echo "   ✅ 已创建 Release：https://github.com/${SLUG}/releases/tag/${TAG}"
fi

if [ "${WITH_IPA}" = "0" ]; then
  echo "   （--no-ipa：跳过 IPA 上传）"
  echo "✅ 同步完成"
  exit 0
fi

IPA=$(ls -t "dist/HanziKid-${VERSION}(${BUILD})-unsigned.ipa" dist/HanziKid-"${VERSION}"*unsigned*.ipa 2>/dev/null | head -1 || true)
if [ -z "${IPA}" ]; then
  echo "   ⚠️ dist/ 里没有 ${VERSION} 的 IPA，先跑 ./Tools/package_ipa.sh；本次只同步了源码"
  echo "✅ 同步完成（无安装包）"
  exit 0
fi

ASSET_NAME=$(basename "${IPA}")
# GitHub 会把 asset 名里的括号等字符换成点，所以上传名单独规整成
# HanziKid-0.5.0(5)-unsigned.ipa → HanziKid-0.5.0-build5-unsigned.ipa
ASSET_UPLOAD_NAME=$(python3 -c 'import re,sys
n = sys.argv[1]
n = re.sub(r"\((\d+)\)", r"-build\1", n)
n = re.sub(r"[^A-Za-z0-9._-]+", "-", n)
print(re.sub(r"-{2,}", "-", n))' "${ASSET_NAME}")
UPLOAD_URL=$(printf '%s' "${RELEASE_JSON}" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("upload_url","").split("{")[0])
except Exception: print("")' 2>/dev/null || true)
[ -n "${UPLOAD_URL}" ] || UPLOAD_URL="https://uploads.github.com/repos/${SLUG}/releases/${RELEASE_ID}/assets"

# 同名 asset 先删掉，避免 422 already_exists
OLD_ASSET_ID=$(api GET "/repos/${SLUG}/releases/${RELEASE_ID}/assets?per_page=100" | python3 -c '
import json,sys
name=sys.argv[1]
try:
    for a in json.load(sys.stdin):
        if a.get("name")==name:
            print(a["id"]); break
except Exception: pass' "${ASSET_UPLOAD_NAME}" 2>/dev/null || true)
if [ -n "${OLD_ASSET_ID}" ]; then
  api DELETE "/repos/${SLUG}/releases/assets/${OLD_ASSET_ID}" >/dev/null || true
  echo "   已删除同名旧 asset ${ASSET_UPLOAD_NAME}"
fi

echo "   上传 ${ASSET_NAME}（$(du -h "${IPA}" | cut -f1)）→ asset 名 ${ASSET_UPLOAD_NAME}"
QNAME=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "${ASSET_UPLOAD_NAME}")
UP_OK=0
for attempt in 1 2 3; do
  RESP=$(curl -sS --max-time 1800 -X POST \
    -H "Authorization: token $(gh_token)" \
    -H "Content-Type: application/octet-stream" \
    -H "Accept: application/vnd.github+json" \
    --data-binary "@${IPA}" \
    "${UPLOAD_URL}?name=${QNAME}" || true)
  if printf '%s' "${RESP}" | grep -q browser_download_url; then
    printf '%s' "${RESP}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("   ✅ 已上传：", d["browser_download_url"])'
    UP_OK=1
    break
  fi
  echo "   上传失败（第 ${attempt} 次）：$(printf '%s' "${RESP}" | head -c 200)" >&2
  sleep 3
done

if [ "${UP_OK}" != "1" ]; then
  echo "⚠️ IPA 没传上去（源码和 tag 已同步）：网络恢复后重跑 ./Tools/sync_github.sh 即可补传"
  exit 1
fi

echo "✅ 同步完成：https://github.com/${SLUG}/releases/tag/${TAG}"
