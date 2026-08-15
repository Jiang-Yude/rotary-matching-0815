#!/bin/bash
# 把現場分析結果推上線，讓學員用手機也看得到。
# 用法：./push-data.sh <你的 json 檔>
# 例：  ./push-data.sh /tmp/live.json
#
# 投影不需要跑這支。投影是把 JSON 貼進網頁按套用，立刻就有，零等待。
# 這支只在「要讓學員自己開手機看」的時候跑。

set -e
REPO="Jiang-Yude/rotary-matching-0815"
FILE="${1:?用法: ./push-data.sh <json 檔路徑>}"

[ -f "$FILE" ] || { echo "❌ 找不到檔案：$FILE"; exit 1; }

# 先驗 JSON 合不合法，不合法就別推上去
python3 -c "
import json,sys
d=json.load(open('$FILE'))
assert d.get('algorithms') or d.get('pairs'), 'JSON 裡沒有 algorithms 也沒有 pairs'
n=len(d.get('algorithms') or [1])
print(f'✅ JSON 合法，{n} 套算法')
" || { echo "❌ JSON 有問題，沒有推上去"; exit 1; }

# 取遠端現有 sha（第一次推沒有，忽略錯誤）
SHA=$(gh api "repos/$REPO/contents/data.json" --jq .sha 2>/dev/null || echo "")

TMP=$(mktemp)
if [ -n "$SHA" ]; then
  printf '{"message":"現場結果更新","content":"%s","sha":"%s","branch":"main"}' \
    "$(base64 < "$FILE" | tr -d '\n')" "$SHA" > "$TMP"
else
  printf '{"message":"現場結果上線","content":"%s","branch":"main"}' \
    "$(base64 < "$FILE" | tr -d '\n')" > "$TMP"
fi

gh api -X PUT "repos/$REPO/contents/data.json" --input "$TMP" --jq '.commit.sha[0:7]' \
  | xargs -I{} echo "✅ 已推送 commit {}"
rm -f "$TMP"

echo "⏳ 等 GitHub Pages 生效（通常 30 到 60 秒）"
for i in $(seq 1 12); do
  if curl -s "https://jiang-yude.github.io/rotary-matching-0815/data.json?t=$RANDOM" \
     | head -c 200 | grep -q '"algorithms"\|"pairs"'; then
    echo "✅ 線上已生效（第 $i 次檢查，約 $((i*5)) 秒）"
    echo "👉 https://jiang-yude.github.io/rotary-matching-0815/"
    exit 0
  fi
  sleep 5
done
echo "⚠️ 60 秒內還沒生效，投影用的畫面不受影響（那份是本機貼的）。"
echo "   再等一下重新整理就好，或直接用投影畫面。"
