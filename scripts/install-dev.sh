#!/usr/bin/env bash
# Install logos-wallet-basecamp to LogosBasecamp for dev testing.
# Usage: ./scripts/install-dev.sh [--qml-only]

set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
NIX=/nix/var/nix/profiles/default/bin/nix
MDIR="$HOME/.local/share/Logos/LogosBasecamp/modules/logos_wallet"
PDIR="$HOME/.local/share/Logos/LogosBasecamp/plugins/wallet_ui"

QML_ONLY=0
for arg in "$@"; do [[ "$arg" == "--qml-only" ]] && QML_ONLY=1; done

# ── Core C++ module ──────────────────────────────────────────────────────────
if [[ $QML_ONLY -eq 0 ]]; then
    echo "Building core module…"
    cd "$REPO"
    $NIX build .#packages.x86_64-linux.lgx

    echo "Installing logos_wallet…"
    rm -rf "$MDIR"
    mkdir -p "$MDIR"

    # Extract .so from lgx
    python3 - << 'PYEOF'
import tarfile, os
lgx = os.path.expanduser('~') + '/.local/share/Logos/LogosBasecamp/modules/logos_wallet/.tmp_extract'
import sys, pathlib
repo = pathlib.Path(os.environ.get('REPO', '.'))
lgx_path = str(repo / 'result' / 'logos-logos_wallet-module-lib.lgx')
out_dir = os.path.expanduser('~/.local/share/Logos/LogosBasecamp/modules/logos_wallet')
with tarfile.open(lgx_path) as t:
    for m in t.getmembers():
        if m.name.endswith('.so'):
            f = t.extractfile(m)
            out = os.path.join(out_dir, 'logos_wallet_plugin.so')
            with open(out, 'wb') as o:
                o.write(f.read())
            print(f'  Extracted {m.name} → {out}')
PYEOF

    # Patch RUNPATH
    if command -v patchelf &>/dev/null; then
        NIX_PATHS=$(ldd "$MDIR/logos_wallet_plugin.so" 2>/dev/null | grep nix | awk '{print $3}' | \
                    xargs -I{} dirname {} | sort -u | tr '\n' ':' | sed 's/:$//')
        QT_LIB="$HOME/Qt/6.9.3/gcc_64/lib"
        patchelf --set-rpath "\$ORIGIN:${NIX_PATHS}:${QT_LIB}:/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu" \
            "$MDIR/logos_wallet_plugin.so"
        echo "  RUNPATH patched"
    fi

    echo "linux-amd64" > "$MDIR/variant"

    cat > "$MDIR/manifest.json" << 'MANIFEST'
{
  "author": "Logos Wallet",
  "category": "blockchain",
  "dependencies": [],
  "description": "Native token wallet — accounts, faucet, keycard-gated transfers",
  "icon": "",
  "main": {
    "linux-amd64":       "logos_wallet_plugin.so",
    "linux-amd64-dev":   "logos_wallet_plugin.so",
    "linux-x86_64-dev":  "logos_wallet_plugin.so",
    "darwin-arm64":      "logos_wallet_plugin.dylib"
  },
  "manifestVersion": "0.2.0",
  "name": "logos_wallet",
  "type": "core",
  "version": "0.1.0"
}
MANIFEST
    echo "  Core module installed → $MDIR"
fi

# ── QML UI plugin ─────────────────────────────────────────────────────────────
echo "Building wallet_ui…"
cd "$REPO/plugins/wallet_ui"
$NIX build .#packages.x86_64-linux.lgx 2>/dev/null || $NIX build

rm -rf "$PDIR"
mkdir -p "$PDIR/qml" "$PDIR/icons"
cp result/lib/qml/Main.qml "$PDIR/qml/"
cp result/lib/icons/wallet.png "$PDIR/icons/" 2>/dev/null || true
cp result/lib/metadata.json "$PDIR/"

cat > "$PDIR/manifest.json" << 'MANIFEST'
{
  "author": "Logos Wallet",
  "category": "blockchain",
  "dependencies": ["logos_wallet"],
  "description": "Native token wallet UI",
  "icon": "icons/wallet.png",
  "main": {},
  "manifestVersion": "0.2.0",
  "name": "wallet_ui",
  "type": "ui_qml",
  "version": "0.1.0",
  "view": "qml/Main.qml"
}
MANIFEST

echo "linux-amd64" > "$PDIR/variant"
rm -rf ~/.cache/Logos/LogosBasecamp/qmlcache/
echo "  UI plugin installed → $PDIR"

echo ""
echo "Done. Relaunch Basecamp:"
echo "  kill -9 \$(pgrep -f logos_host) 2>/dev/null; kill -9 \$(pgrep -f 'LogosBasecamp\\.elf') 2>/dev/null"
echo "  ~/logos-basecamp-current.AppImage &"
