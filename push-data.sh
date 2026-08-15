#!/bin/bash
# 把現場分析結果推上線，讓學員用手機也看得到。
# 用法：./push-data.sh <你的 json 檔>
# 例：  ./push-data.sh /tmp/live.json
#
# 投影不需要跑這支。投影是把 JSON 貼進網頁按套用，立刻就有，零等待。
# 這支只在「要讓學員自己開手機看」的時候跑。

set -euo pipefail
REPO="Jiang-Yude/rotary-matching-0815"
FILE="${1:?用法: ./push-data.sh <json 檔路徑>}"

[ -f "$FILE" ] || { echo "❌ 找不到檔案：$FILE"; exit 1; }

PAYLOAD=$(mktemp)
trap 'rm -f "$PAYLOAD"' EXIT

# 驗 JSON、取遠端 sha、組 payload 一次做完
python3 - "$FILE" "$PAYLOAD" "$REPO" <<'PY'
import base64, json, subprocess, sys
src, out, repo = sys.argv[1], sys.argv[2], sys.argv[3]

d = json.load(open(src))                     # 不合法會直接丟例外，不會推上去
if not (d.get('algorithms') or d.get('pairs')):
    raise SystemExit('❌ JSON 裡沒有 algorithms 也沒有 pairs，沒有推上去')
n = len(d.get('algorithms') or [1])
pairs = sum(len(a.get('pairs') or []) for a in (d.get('algorithms') or [])) or len(d.get('pairs') or [])
print(f'✅ JSON 合法：{n} 套算法、{pairs} 組配對')

r = subprocess.run(['gh','api',f'repos/{repo}/contents/data.json','--jq','.sha'],
                   capture_output=True, text=True)
sha = r.stdout.strip() if r.returncode == 0 else ''

body = {'message': '現場結果更新',
        'content': base64.b64encode(open(src,'rb').read()).decode(),
        'branch': 'main'}
if sha:
    body['sha'] = sha
json.dump(body, open(out,'w'))
PY

echo "⬆️  推送中"
COMMIT=$(gh api -X PUT "repos/$REPO/contents/data.json" --input "$PAYLOAD" --jq '.commit.sha[0:7]')
echo "✅ 已推送 commit $COMMIT"

echo "⏳ 等 GitHub Pages 生效"
# 用完整 JSON 解析判斷，不要用 head -c 截斷後 grep：
# JSON 格式化後 algorithms 在很後面，截斷比對會永遠失敗、誤報沒生效（2026-08-15 實測踩到）
for i in $(seq 1 24); do
  if curl -s "https://jiang-yude.github.io/rotary-matching-0815/data.json?t=$RANDOM$RANDOM" \
     | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if (d.get('algorithms') or d.get('pairs')) else 1)" 2>/dev/null; then
    echo "✅ 線上已生效（約 $((i*5)) 秒）"
    echo "👉 https://jiang-yude.github.io/rotary-matching-0815/"
    exit 0
  fi
  sleep 5
done
echo "⚠️ 120 秒內還沒生效。投影畫面不受影響（那份是本機貼的，照投）。"
echo "   學員端再等一下重新整理即可。"
