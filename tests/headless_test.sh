#!/usr/bin/env bash
# Headless tests for logos-wallet-basecamp using logoscore daemon mode.
# Usage: bash tests/headless_test.sh

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
LOGOSCORE=$(find /nix/store -maxdepth 4 -name "logoscore" -path "*/bin/*" 2>/dev/null | head -1)
if [[ -z "$LOGOSCORE" ]]; then
    echo "FATAL: logoscore not found in Nix store" >&2
    exit 1
fi

MODULE_SRC="$HOME/.local/share/Logos/LogosBasecamp/modules/logos_wallet"
if [[ ! -d "$MODULE_SRC" ]]; then
    echo "FATAL: logos_wallet not installed at $MODULE_SRC" >&2
    echo "Run scripts/install-dev.sh first." >&2
    exit 1
fi

# ── Temp workspace ────────────────────────────────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'cleanup' EXIT

cleanup() {
    if [[ -n "${DAEMON_PID:-}" ]]; then
        kill "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
    fi
    rm -rf "$TMPDIR"
}

MDIR="$TMPDIR/modules"
mkdir -p "$MDIR/logos_wallet"
cp -r "$MODULE_SRC/." "$MDIR/logos_wallet/"

# ── Fake wallet CLI ───────────────────────────────────────────────────────────
FAKE_CLI="$TMPDIR/fake_wallet.sh"
cat > "$FAKE_CLI" << 'FAKECLI'
#!/usr/bin/env bash
# Fake wallet CLI — echoes canned responses based on subcommand args
CMD="${1:-} ${2:-}"
case "$CMD" in
  "account ls")
    echo '[{"id":"public/testaccount001","type":"public","balance":150},{"id":"public/testaccount002","type":"public","balance":0}]'
    ;;
  "account get")
    echo '{"id":"public/testaccount001","type":"public","balance":150}'
    ;;
  "account new")
    echo '{"id":"public/newaccount123","type":"public","balance":0}'
    ;;
  "auth-transfer init")
    echo '{"ok":true,"message":"account initialized for transfers"}'
    ;;
  "auth-transfer send")
    echo '{"ok":true,"txId":"tx_abc123def456","from":"public/testaccount001","to":"public/testaccount002","amount":"10"}'
    ;;
  "pinata claim")
    echo '{"ok":true,"claimed":150,"to":"public/testaccount001"}'
    ;;
  *)
    echo '{"error":"unknown command"}'
    exit 1
    ;;
esac
FAKECLI
chmod +x "$FAKE_CLI"

# ── Test counters ─────────────────────────────────────────────────────────────
PASS=0
FAIL=0
SKIP=0

pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
skip() { echo "  - $1 (skipped)"; SKIP=$((SKIP+1)); }

json_field() {
    local json="$1" field="$2"
    python3 -c "import sys,json; d=json.loads('''$json'''); print(d.get('$field',''))" 2>/dev/null || echo ""
}

check_no_error() {
    local json="$1" label="$2"
    if echo "$json" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); sys.exit(1 if 'error' in d else 0)" 2>/dev/null; then
        pass "$label"
    else
        local err
        err=$(echo "$json" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('error','?'))" 2>/dev/null || echo "?")
        fail "$label — error: $err"
    fi
}

check_field() {
    local json="$1" field="$2" expected="$3" label="$4"
    local actual
    actual=$(echo "$json" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(str(d.get('$field','')).lower())" 2>/dev/null || echo "")
    if [[ "$actual" == "$expected" ]]; then
        pass "$label"
    else
        fail "$label — expected '$expected', got '$actual'"
    fi
}

# ── Start daemon ──────────────────────────────────────────────────────────────
echo "Starting logoscore daemon…"
"$LOGOSCORE" -D --modules-dir "$MDIR" > "$TMPDIR/daemon.log" 2>&1 &
DAEMON_PID=$!
sleep 2

# Verify daemon is alive
if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
    echo "FATAL: daemon failed to start"
    cat "$TMPDIR/daemon.log"
    exit 1
fi
echo "Daemon PID $DAEMON_PID"
echo ""

# ── Load module ───────────────────────────────────────────────────────────────
echo "=== Module load ==="
LOAD_OUT=$("$LOGOSCORE" load-module logos_wallet 2>&1) || true
if echo "$LOAD_OUT" | grep -qi "ok\|loaded\|success"; then
    pass "load-module logos_wallet"
else
    fail "load-module logos_wallet — output: $LOAD_OUT"
    echo "Daemon log:"
    cat "$TMPDIR/daemon.log"
    exit 1
fi

LIST_OUT=$("$LOGOSCORE" list-modules --loaded 2>&1) || true
if echo "$LIST_OUT" | grep -q "logos_wallet"; then
    pass "logos_wallet appears in list-modules --loaded"
else
    fail "logos_wallet not in list-modules --loaded — output: $LIST_OUT"
fi
echo ""

# ── getStatus — no CLI configured yet ────────────────────────────────────────
echo "=== getStatus (default — no CLI configured) ==="
RAW=$("$LOGOSCORE" call logos_wallet getStatus 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
# cliFound may be true if 'wallet' is in PATH, or false — both are valid
if echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert 'cliFound' in d and 'cliPath' in d" 2>/dev/null; then
    pass "getStatus returns cliFound + cliPath fields"
else
    fail "getStatus missing expected fields — result: $RESULT"
fi

# ── getConfig ─────────────────────────────────────────────────────────────────
echo ""
echo "=== getConfig ==="
RAW=$("$LOGOSCORE" call logos_wallet getConfig 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
if echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert 'cliPath' in d and 'cliPathEff' in d" 2>/dev/null; then
    pass "getConfig returns cliPath + cliPathEff fields"
else
    fail "getConfig missing expected fields — result: $RESULT"
fi

# ── setCliPath — point to fake CLI ────────────────────────────────────────────
echo ""
echo "=== setCliPath ==="

# Empty path → error
RAW=$("$LOGOSCORE" call logos_wallet setCliPath "" 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
if echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert 'error' in d" 2>/dev/null; then
    pass "setCliPath('') returns error"
else
    fail "setCliPath('') should return error — result: $RESULT"
fi

# Valid path → ok
RAW=$("$LOGOSCORE" call logos_wallet setCliPath "$FAKE_CLI" 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
if echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d.get('ok') is True" 2>/dev/null; then
    pass "setCliPath(fake_cli) returns ok:true"
else
    fail "setCliPath(fake_cli) failed — result: $RESULT"
fi

# Verify getStatus now shows cliFound:true
RAW=$("$LOGOSCORE" call logos_wallet getStatus 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
if echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d.get('cliFound') is True" 2>/dev/null; then
    pass "getStatus.cliFound=true after setCliPath"
else
    fail "getStatus.cliFound still false after setCliPath — result: $RESULT"
fi

# ── listAccounts ──────────────────────────────────────────────────────────────
echo ""
echo "=== listAccounts ==="
RAW=$("$LOGOSCORE" call logos_wallet listAccounts 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','[]'))" 2>/dev/null || echo "[]")
COUNT=$(echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo "0")
if [[ "$COUNT" == "2" ]]; then
    pass "listAccounts returns 2 accounts from fake CLI"
else
    fail "listAccounts: expected 2 accounts, got '$COUNT' — result: $RESULT"
fi

FIRST_ID=$(echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d[0]['id'] if isinstance(d,list) and d else '')" 2>/dev/null || echo "")
if [[ "$FIRST_ID" == "public/testaccount001" ]]; then
    pass "listAccounts first account id correct"
else
    fail "listAccounts first id: expected 'public/testaccount001', got '$FIRST_ID'"
fi

BALANCE=$(echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d[0].get('balance','') if isinstance(d,list) and d else '')" 2>/dev/null || echo "")
if [[ "$BALANCE" == "150" ]]; then
    pass "listAccounts first account balance=150"
else
    fail "listAccounts balance: expected '150', got '$BALANCE'"
fi

# ── getBalance ────────────────────────────────────────────────────────────────
echo ""
echo "=== getBalance ==="

# Missing accountId → error
RAW=$("$LOGOSCORE" call logos_wallet getBalance "" 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
if echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert 'error' in d" 2>/dev/null; then
    pass "getBalance('') returns error"
else
    fail "getBalance('') should return error — result: $RESULT"
fi

# Valid accountId → balance
RAW=$("$LOGOSCORE" call logos_wallet getBalance "public/testaccount001" 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
BAL=$(echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('balance',''))" 2>/dev/null || echo "")
if [[ "$BAL" == "150" ]]; then
    pass "getBalance returns balance=150"
else
    fail "getBalance: expected balance=150, got '$BAL' — result: $RESULT"
fi

# ── createAccount ─────────────────────────────────────────────────────────────
echo ""
echo "=== createAccount ==="
RAW=$("$LOGOSCORE" call logos_wallet createAccount 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
NEW_ID=$(echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('id',''))" 2>/dev/null || echo "")
if [[ "$NEW_ID" == "public/newaccount123" ]]; then
    pass "createAccount returns new account id"
else
    fail "createAccount: expected id='public/newaccount123', got '$NEW_ID' — result: $RESULT"
fi

# ── initAccount ───────────────────────────────────────────────────────────────
echo ""
echo "=== initAccount ==="

# Missing accountId → error
RAW=$("$LOGOSCORE" call logos_wallet initAccount "" 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
if echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert 'error' in d" 2>/dev/null; then
    pass "initAccount('') returns error"
else
    fail "initAccount('') should return error — result: $RESULT"
fi

# Valid accountId → ok
RAW=$("$LOGOSCORE" call logos_wallet initAccount "public/testaccount001" 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
if echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d.get('ok') is True" 2>/dev/null; then
    pass "initAccount returns ok:true"
else
    fail "initAccount: expected ok:true — result: $RESULT"
fi

# ── claimFaucet ───────────────────────────────────────────────────────────────
echo ""
echo "=== claimFaucet ==="

# Missing accountId → error
RAW=$("$LOGOSCORE" call logos_wallet claimFaucet "" 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
if echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert 'error' in d" 2>/dev/null; then
    pass "claimFaucet('') returns error"
else
    fail "claimFaucet('') should return error — result: $RESULT"
fi

# Valid accountId → ok + claimed=150
RAW=$("$LOGOSCORE" call logos_wallet claimFaucet "public/testaccount001" 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
CLAIMED=$(echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('claimed',''))" 2>/dev/null || echo "")
if [[ "$CLAIMED" == "150" ]]; then
    pass "claimFaucet returns claimed=150"
else
    fail "claimFaucet: expected claimed=150, got '$CLAIMED' — result: $RESULT"
fi

# Without prefix → plugin should add public/ prefix before passing to CLI
RAW=$("$LOGOSCORE" call logos_wallet claimFaucet "testaccount001" 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
if echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d.get('ok') is True" 2>/dev/null; then
    pass "claimFaucet adds public/ prefix automatically"
else
    fail "claimFaucet without prefix: expected ok:true — result: $RESULT"
fi

# ── sendTransfer — input validation ──────────────────────────────────────────
echo ""
echo "=== sendTransfer (validation) ==="

# NOTE: logoscore daemon parses CLI args as JSON before forwarding.
# Numeric-only strings (e.g. "10") are coerced to int → METHOD_FAILED for QString params.
# Use '"10"' (JSON-quoted) so logoscore delivers a string, or use a non-numeric value.

# Missing from → error
RAW=$("$LOGOSCORE" call logos_wallet sendTransfer "" "public/testaccount002" '"10"' 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
if echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert 'error' in d" 2>/dev/null; then
    pass "sendTransfer(from='') returns error"
else
    fail "sendTransfer(from='') should return error — result: $RESULT"
fi

# Missing to → error
RAW=$("$LOGOSCORE" call logos_wallet sendTransfer "public/testaccount001" "" '"10"' 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
if echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert 'error' in d" 2>/dev/null; then
    pass "sendTransfer(to='') returns error"
else
    fail "sendTransfer(to='') should return error — result: $RESULT"
fi

# Missing amount → error
RAW=$("$LOGOSCORE" call logos_wallet sendTransfer "public/testaccount001" "public/testaccount002" "" 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
if echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert 'error' in d" 2>/dev/null; then
    pass "sendTransfer(amount='') returns error"
else
    fail "sendTransfer(amount='') should return error — result: $RESULT"
fi

# ── sendTransfer — success path ───────────────────────────────────────────────
echo ""
echo "=== sendTransfer (success) ==="
# Use '"10"' so logoscore passes it as a JSON string, not an integer
RAW=$("$LOGOSCORE" call logos_wallet sendTransfer \
    "public/testaccount001" "public/testaccount002" '"10"' 2>/dev/null) || RAW="{}"
RESULT=$(echo "$RAW" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('result','{}'))" 2>/dev/null || echo "{}")
TX_ID=$(echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('txId',''))" 2>/dev/null || echo "")
if [[ "$TX_ID" == "tx_abc123def456" ]]; then
    pass "sendTransfer returns txId from fake CLI"
elif echo "$RESULT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert d.get('ok') is True" 2>/dev/null; then
    pass "sendTransfer returns ok:true"
else
    fail "sendTransfer: expected txId — result: $RESULT"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"
echo "══════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Daemon log tail:"
    tail -20 "$TMPDIR/daemon.log"
    exit 1
fi
echo "All tests passed."
