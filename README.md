# logos-wallet-basecamp

Native token wallet module for [Logos Basecamp](https://github.com/logos-co). Manages public and private accounts, faucet claims, and authenticated transfers on the Logos testnet.

## Structure

```
logos-wallet-basecamp/
├── src/plugin/
│   ├── WalletPlugin.cpp   # C++ Qt plugin — CLI wrapper + local tx history
│   └── WalletPlugin.h
├── plugins/wallet_ui/
│   ├── qml/Main.qml       # QML UI — two-column wallet interface
│   ├── icons/wallet.png
│   └── flake.nix          # builds logos-wallet_ui-module.lgx
├── flake.nix              # builds logos-logos_wallet-module-lib.lgx
└── metadata.json
```

## Features

- List public and private accounts, grouped by type
- Display balance for the selected account
- Send transfers between accounts (authenticated)
- Claim testnet faucet tokens (150 TOK per claim)
- Per-account transaction history, stored locally
- Settings panel to configure the wallet CLI path

## Requirements

- [Logos Basecamp](https://github.com/logos-co/logos-basecamp) AppImage
- `wallet-lez` binary — the underlying Logos wallet CLI
- `wallet` wrapper script at `~/.local/bin/wallet` (see below)
- Nix (for building)

## Build

**C++ core module:**

```bash
nix build .#packages.x86_64-linux.lgx-portable
```

**QML UI plugin:**

```bash
cd plugins/wallet_ui
nix build .#packages.x86_64-linux.lgx
```

## Install

```bash
LGPM_OLD=/nix/store/3b8c9lhp5jdb89k2rb42i17z1780jbv6-logos-package-manager-cli-1.0.0/bin/lgpm
LGPM=/nix/store/l2kcbdg9hn7lb053lx111smrvi88jl38-logos-package-manager-cli-1.0.0/bin/lgpm
MDIR=~/.local/share/Logos/LogosBasecamp/modules
PDIR=~/.local/share/Logos/LogosBasecamp/plugins

# Core module
rm -rf $MDIR/logos_wallet
$LGPM_OLD --modules-dir $MDIR --ui-plugins-dir $PDIR --allow-unsigned install \
  --file result/logos-logos_wallet-module-lib.lgx

# UI plugin
rm -rf $PDIR/wallet_ui
$LGPM --modules-dir $MDIR --ui-plugins-dir $PDIR --allow-unsigned install \
  --file plugins/wallet_ui/result/logos-wallet_ui-module.lgx

# Clear QML cache and relaunch
rm -rf ~/.cache/Logos/LogosBasecamp/qmlcache/
~/logos-basecamp-current.AppImage &
```

## Wallet CLI wrapper

The module calls a `wallet` script at `~/.local/bin/wallet` that wraps `wallet-lez` and normalises output to JSON. The path is configurable in the UI settings panel.

Supported commands the wrapper must handle:

| Command | Description |
|---------|-------------|
| `account ls -l` | List all accounts with balances |
| `account get --account-id <id>` | Get account details |
| `account new public` | Create a new public account |
| `auth-transfer init --account-id <id>` | Initialise account for transfers |
| `auth-transfer send --from <id> --to <id> --amount <n>` | Send tokens |
| `pinata claim --to <id>` | Claim faucet tokens |

## C++ API

Methods exposed to QML via `logos.callModule("logos_wallet", ...)`:

| Method | Returns |
|--------|---------|
| `getStatus()` | `{ cliFound, cliPath }` |
| `getConfig()` | `{ cliPath, cliPathEff }` |
| `setCliPath(path)` | `{ ok }` |
| `listAccounts()` | `[{ id, type, balance }]` |
| `getBalance(accountId)` | `{ id, type, balance }` |
| `createAccount()` | `{ id, type, balance }` |
| `initAccount(accountId)` | `{ ok, txHash }` |
| `claimFaucet(accountId)` | `{ ok, claimed, txHash }` |
| `sendTransfer(from, to, amount)` | `{ ok, txId }` |
| `getTransactions(accountId)` | `[{ type, sender, receiver, amount, txId, ts }]` |

Transaction history is stored locally in QSettings (up to 50 entries per account). Both sender and receiver accounts are updated on each transfer.
