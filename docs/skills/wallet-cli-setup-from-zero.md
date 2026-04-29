---
id: wallet-cli-setup-from-zero
title: Set up wallet-lez CLI and create working Logos testnet accounts from zero
phase: setup
type: pattern
severity: high
severity_reason: Without a working wallet CLI wrapper the module renders "wallet CLI not found" and all operations fail.
modules: ["logos-wallet-basecamp"]
source: extracted-local
last_used: "2026-04-29"
created: "2026-04-29"
status: active
---

## Problem

The `logos-wallet-basecamp` module wraps a CLI binary (`wallet-lez`) via a shell
script. A fresh machine has neither the binary nor the wrapper, and the module UI
shows "wallet CLI not found" until both are in place and at least one account exists.

## Recipe

### 1 — Download wallet-lez

```bash
# Check GitHub releases for the latest wallet-lez binary:
# https://github.com/logos-co/nomos-node/releases
# Download the binary for your platform, e.g.:
curl -L -o ~/.local/bin/wallet-lez \
  "https://github.com/logos-co/nomos-node/releases/latest/download/wallet-lez-linux-amd64"
chmod +x ~/.local/bin/wallet-lez
```

### 2 — Write the wrapper script

The module calls `wallet` (not `wallet-lez` directly) so that output can be
normalised to JSON. Create `~/.local/bin/wallet`:

```bash
cat > ~/.local/bin/wallet << 'EOF'
#!/usr/bin/env bash
# Logos wallet wrapper — normalises wallet-lez output to JSON
set -euo pipefail

WALLET_LEZ="${WALLET_LEZ:-$HOME/.local/bin/wallet-lez}"

# Pass all args through; capture stdout+stderr merged
output=$("$WALLET_LEZ" "$@" 2>&1) || {
  code=$?
  # Try to forward JSON errors from wallet-lez as-is
  if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    echo "$output"
  else
    python3 -c "import sys,json; print(json.dumps({'error': sys.argv[1]}))" "$output"
  fi
  exit $code
}

# If output is already JSON, pass through; otherwise wrap in {ok, output}
if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  echo "$output"
else
  python3 -c "import sys,json; print(json.dumps({'ok': True, 'output': sys.argv[1]}))" "$output"
fi
EOF
chmod +x ~/.local/bin/wallet
```

Verify:
```bash
wallet account ls -l
# → {"ok":true,"output":""} or a JSON array of accounts
```

### 3 — Create a public account

```bash
wallet account new public
# → {"id":"Public/abc123...","type":"Public","balance":0}
```

Note the `id` value (e.g. `Public/abc123...`).

### 4 — Initialise for transfers

Before sending or receiving, initialise the account on the auth-transfer contract:

```bash
wallet auth-transfer init --account-id Public/abc123...
# → {"ok":true,"txHash":"0x..."}
```

This submits an on-chain transaction. Wait ~10s for confirmation before proceeding.

### 5 — Claim testnet faucet (150 TOK)

```bash
wallet pinata claim --to Public/abc123...
# → {"ok":true,"claimed":150,"txHash":"0x..."}
```

### 6 — Verify balance

```bash
wallet account get --account-id Public/abc123...
# → {"id":"Public/abc123...","type":"Public","balance":150}
```

### 7 — Configure path in the module UI

Open the wallet module in Basecamp → click the ⚙ gear icon → enter the path to
your `wallet` wrapper (default: `~/.local/bin/wallet`). The CLI pill turns green
when found.

---

## Supported CLI commands

| Command | Description |
|---------|-------------|
| `wallet account ls -l` | List all accounts |
| `wallet account get --account-id <id>` | Get account details + balance |
| `wallet account new public` | Create a new public account |
| `wallet auth-transfer init --account-id <id>` | Initialise account for transfers |
| `wallet auth-transfer send --from <id> --to <id> --amount <n>` | Send tokens |
| `wallet pinata claim --to <id>` | Claim 150 TOK from faucet |

## Notes

- `wallet-lez` communicates with the Logos testnet; ensure network connectivity.
- The `auth-transfer init` step is required exactly once per account before any sends.
- The module stores up to 50 tx history entries per account in QSettings locally.
- Private accounts follow the same flow but use `Private/<id>` as the account ID.
