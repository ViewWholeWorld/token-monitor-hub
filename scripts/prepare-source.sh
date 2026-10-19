#!/usr/bin/env bash
set -euo pipefail
REF="${REQUESTED_REF:-$(tr -d '\r\n' < upstream-ref.txt)}"
if [[ "$REF" == latest ]]; then
  REF=$(gh api repos/Javis603/token-monitor/releases/latest --jq '.tag_name')
fi
if [[ ! "$REF" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]{0,199}$ ]]; then
  echo '上游版本标识无效' >&2
  exit 1
fi
test ! -e upstream
git init upstream
git -C upstream remote add origin https://github.com/Javis603/token-monitor.git
git -C upstream fetch --depth=1 origin "$REF"
git -C upstream checkout --detach FETCH_HEAD
REVISION=$(git -C upstream rev-parse HEAD)
test -f upstream/src/hub/server.js
test -f upstream/src/shared/hubBuildRegistry.json
printf 'revision=%s\nref=%s\n' "$REVISION" "$REF" >> "$GITHUB_OUTPUT"
printf '构建上游 %s，提交 %s\n' "$REF" "$REVISION"
