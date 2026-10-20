#!/bin/bash
# 10-19 06:00：dc 閘 01:46 已過期、Jev 閘仍封鎖，oc-free-check 只讀 dc 那份 → 併發打全池 9 次 403，
# 推「免費模型掛了（上游回錯）」。要求：
#   1) 只有 Jev 那份閘封鎖也要整輪跳過
#   2) 閘外先打 1 隻當探針，回 abusive traffic 就 trip 共用閘、停手；不併發打全池、不報「掛了」、不寫 TSV
set -u
T=$(mktemp -d); trap 'kill $SP 2>/dev/null; rm -rf "$T"' EXIT
BIN="$(cd "$(dirname "$0")/.." && pwd)/bin"
printf '#!/bin/sh\necho "$1" >> %s/pushed\n' "$T" > "$T/hpush"; chmod +x "$T/hpush"
export PATH="$T:$PATH" DC_ZEN_GATE="$T/gate" JEV_ZEN_STATUS_FILE="$T/jev.json"
echo '{"opencode-go":{"models":{"a-free":{"cost":{"input":0,"output":0}},"b-free":{"cost":{"input":0,"output":0}},"c-free":{"cost":{"input":0,"output":0}}}}}' > "$T/models.json"
export MODELS_JSON="$T/models.json"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2' want '$3'"; fail=1; fi; }

# 1) 只有 Jev 閘（blocked，毫秒）
printf '{"ok":false,"blocked":true,"cooldown_until":%s}' "$(( ($(date +%s) + 3600) * 1000 ))" > "$T/jev.json"
"$BIN/oc-free-check" -p opencode-go --x-handle '' --server http://127.0.0.1:9 > "$T/out1" 2>&1
chk "Jev 閘封鎖時整輪跳過" "$(grep -c '本輪不探測' "$T/out1")" 1

# 2) 閘外：假 opencode server，每個 prompt 都回 IP 判濫用
echo '{"ok":true}' > "$T/jev.json"; rm -f "$T/pushed"
cat > "$T/srv.py" <<'PY'
import http.server, json, sys
n = 0
ERR = "OpenCode's free models aren't available from your current network because we've detected abusive traffic from this IP address."
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, obj):
        b = json.dumps(obj).encode(); self.send_response(200)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        global n
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if self.path == "/session": return self.send({"id": "s1"})
        if self.path.endswith("/prompt_async"):
            n += 1; open(sys.argv[1], "w").write(str(n))
        self.send(None)
    def do_DELETE(self): self.send(None)
    def do_GET(self):
        if self.path == "/session/status": return self.send({})
        if self.path.endswith("/message"):
            return self.send([{"info": {"role": "assistant", "error": {"data": {"message": ERR}}}, "parts": []}])
        self.send(None)
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True); s.serve_forever()
PY
python3 -I "$T/srv.py" "$T/prompts" > "$T/port" & SP=$!
for _ in $(seq 50); do [ -s "$T/port" ] && break; sleep 0.1; done
"$BIN/oc-free-check" -p opencode-go -j 4 -t 10 --x-handle '' --tsv "$T/probe.tsv" \
  --server "http://127.0.0.1:$(cat "$T/port")" > "$T/out2" 2>&1
chk "判濫用只打 1 隻探針" "$(cat "$T/prompts" 2>/dev/null)" 1
chk "trip 共用閘（dc 份）" "$([ "$(cat "$T/gate" 2>/dev/null || echo 0)" -gt "$(date +%s)" ] && echo y)" y
chk "trip 共用閘（Jev 份）" "$(jq -r .blocked "$T/jev.json" 2>/dev/null)" true
chk "不報「免費模型掛了」" "$(grep -c '掛了' "$T/pushed" 2>/dev/null)" 0
chk "推一則 IP 濫用" "$(grep -c 'IP 濫用' "$T/pushed" 2>/dev/null)" 1
chk "不寫 TSV（dcq rank 沿用上一批）" "$([ -e "$T/probe.tsv" ] && echo wrote || echo none)" none
exit "$fail"
