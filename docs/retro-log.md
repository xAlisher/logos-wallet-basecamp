# Retro Log — logos-wallet-basecamp

## 2026-04-29 — v0.1.0 epic retro

### Wins

- Two-column wallet UI delivered end-to-end: account list with PUBLIC/PRIVATE sections, large balance display, send form, faucet, per-account tx history — all from a single QML file + C++ plugin.
- C++ `getTransactions` + `saveTx` pattern works cleanly: QSettings, 50-entry cap, both sender and receiver get records on every transfer.
- `lgx-portable` build + install loop confirmed stable: `nix build` → `lgpm install` → `rm qmlcache` → relaunch is the reliable cycle.
- GitHub release published with both LGX artifacts attached.

### Fails / Pitfalls caught

- **Duplicate `readonly property accentOrange`** caused silent module load failure. A bulk rename (`accentBlue → accentOrange`) wrote the property name twice. Zero feedback from the UI — module just never appeared. Fix: `qmllint` catches this immediately.

- **`model.from` is broken in QML delegate scope.** `from` collides with JS/QML internal naming in model context. All direction checks (`isSent`) always returned false. Fix: rename keys to `sender`/`receiver` in both C++ and QML.

- **QML ListModel `required property` with non-uniform rows.** Faucet entries were missing the `sender` field. QML sets roles from the first item appended — if that item is missing a key, the role never exists and the delegate renders nothing for *all* rows. Fix: always append `sender: ""` for faucet entries.

- **Polling timer was resetting selected account.** `onCountChanged` on `accountModel` fired during each `.append()` call (one per account returned) and selected the first account each time. Fix: `onCountChanged` only acts when `selectedFromId.length === 0`; balance refresh in `refreshAccounts()` scans the fully-built model inline.

- **`lgpm` variant mismatch.** Core module built as `linux-amd64` (via `lgx-portable`) must be installed with the *old* lgpm binary; UI plugin (`linux-amd64-dev`) uses the *new* lgpm binary. Both binaries are in `/nix/store/` — see README for hashes.

### Skills extracted

Platform-wide (→ basecamp-skills):
- `qml-duplicate-property-fatal` [build/critical]
- `qml-listmodel-uniform-roles` [integration/high]
- `qml-delegate-from-reserved` [integration/high]
- `qml-listview-section-grouping` [integration/low]

Module-specific (→ docs/skills/):
- `wallet-cli-setup-from-zero`
