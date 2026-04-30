#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
#  Hydra Launcher – macOS Build Script
#  Builds the app and produces a .dmg installer
# ─────────────────────────────────────────────

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${BOLD}▶ $*${NC}"; }
ok()   { echo -e "${GREEN}✔ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
die()  { echo -e "${RED}✖ $*${NC}"; exit 1; }

# Must run on macOS
[[ "$(uname)" == "Darwin" ]] || die "This script must be run on macOS."

cd "$(dirname "$0")"

# ── 1. Homebrew ───────────────────────────────
log "Checking Homebrew..."
# Ensure brew is on PATH (Apple Silicon: /opt/homebrew, Intel: /usr/local)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v brew &>/dev/null; then
  warn "Homebrew not found – installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
fi
ok "Homebrew $(brew --version | head -1)"

# ── 2. Node.js ────────────────────────────────
log "Checking Node.js..."
REQUIRED_NODE="22"
# Ensure brew-installed node@22 is on PATH
export PATH="/opt/homebrew/opt/node@22/bin:/usr/local/opt/node@22/bin:$PATH"
if ! command -v node &>/dev/null || [[ "$(node -e 'process.stdout.write(process.versions.node.split(".")[0])')" -lt "$REQUIRED_NODE" ]]; then
  warn "Node.js $REQUIRED_NODE+ not found – installing via nvm or brew..."
  if [ -s "$HOME/.nvm/nvm.sh" ]; then
    # shellcheck disable=SC1090
    source "$HOME/.nvm/nvm.sh" 2>/dev/null || true
    nvm install 22 && nvm use 22
  else
    brew install node@22
    export PATH="/opt/homebrew/opt/node@22/bin:/usr/local/opt/node@22/bin:$PATH"
  fi
fi
ok "Node $(node --version)"

# ── 3. Yarn ───────────────────────────────────
log "Checking Yarn..."
if ! command -v yarn &>/dev/null; then
  warn "Yarn not found – installing..."
  npm install -g yarn
fi
ok "Yarn $(yarn --version)"

# ── 4. Rust / Cargo ───────────────────────────
log "Checking Rust..."
export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v cargo &>/dev/null; then
  warn "Rust not found – installing via rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  source "$HOME/.cargo/env"
fi
source "$HOME/.cargo/env" 2>/dev/null || true
ok "Rust $(rustc --version)"

# ── 5. Python 3.10+ via virtualenv ───────────
# cx_Freeze 7.x requires Python 3.10+.
# Homebrew Python 3.13/3.14 is "externally managed" so we use a venv.
log "Checking Python..."

# Find a suitable Python 3.10+ binary
PYTHON_BIN=""
for cmd in python3.13 python3.12 python3.11 python3.10 \
           /opt/homebrew/opt/python@3.13/bin/python3 \
           /opt/homebrew/opt/python@3.12/bin/python3 \
           /opt/homebrew/opt/python@3.11/bin/python3 \
           /opt/homebrew/opt/python@3.10/bin/python3; do
  if command -v "$cmd" &>/dev/null && "$cmd" -c "import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)" 2>/dev/null; then
    PYTHON_BIN="$cmd"
    break
  fi
done
# Fallback: check generic python3 for 3.10+
if [[ -z "$PYTHON_BIN" ]] && command -v python3 &>/dev/null; then
  if python3 -c "import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)" 2>/dev/null; then
    PYTHON_BIN="python3"
  fi
fi
if [[ -z "$PYTHON_BIN" ]]; then
  warn "Python 3.10+ not found – installing python@3.11 via brew..."
  brew install python@3.11
  PYTHON_BIN="/opt/homebrew/opt/python@3.11/bin/python3"
fi
ok "Found $($PYTHON_BIN --version)"

# Create (or reuse) a virtualenv so pip works on Homebrew Python.
# --system-site-packages lets it see the brew-installed libtorrent binding.
VENV_DIR="$(pwd)/.build-venv"
if [[ ! -f "$VENV_DIR/bin/python" ]]; then
  log "Creating Python virtualenv at $VENV_DIR..."
  "$PYTHON_BIN" -m venv --system-site-packages "$VENV_DIR"
fi
PYTHON="$VENV_DIR/bin/python"
PIP="$VENV_DIR/bin/pip"
ok "Virtualenv ready ($($PYTHON --version))"

# ── 6. Python dependencies ────────────────────
log "Installing Python dependencies..."
"$PIP" install --upgrade pip --quiet

# libtorrent: install brew C library first, then Python binding
if ! "$PYTHON" -c "import libtorrent" 2>/dev/null; then
  warn "libtorrent not found – installing via brew + pip..."
  brew install libtorrent-rasterbar 2>/dev/null || true
  "$PIP" install libtorrent --quiet 2>/dev/null || \
    warn "pip install libtorrent failed – torrent downloads may not work"
fi

"$PIP" install -r requirements.txt --quiet
ok "Python dependencies ready"

# ── 7. Node modules ───────────────────────────
log "Installing Node dependencies..."
yarn --frozen-lockfile
ok "Node modules ready"

# ── 8. Build Python RPC (cx_Freeze) ──────────
log "Building Python RPC..."
"$PYTHON" python_rpc/setup.py build
ok "Python RPC built"

# ── 9. Build native Rust addon ────────────────
log "Building native Rust addon..."
yarn build:native
ok "Native addon built"

# ── 10. Build Electron app ────────────────────
log "Building Electron app (Vite + TypeScript)..."
npx electron-vite build
ok "Electron app built"

# ── 11. Package into DMG ─────────────────────
log "Packaging into DMG (this may take a minute)..."
npx electron-builder --mac dmg 2>&1 | grep -v "^\s*$"
ok "Packaging complete"

# ── 12. Done ─────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  Build complete!${NC}"
echo ""

DMG=$(find dist -maxdepth 1 -name "*.dmg" 2>/dev/null | head -n1)
if [[ -n "$DMG" ]]; then
  echo -e "  DMG → ${BOLD}$DMG${NC}"
  echo ""
  echo -e "  First time opening (unsigned build):"
  echo -e "  Run:  ${BOLD}xattr -cr /Applications/Hydra.app${NC}"
  echo -e "  Or:   Right-click the .dmg → Open"
  echo ""
  open "$(dirname "$DMG")" 2>/dev/null || true
else
  warn "DMG not found in dist/ – check output above for errors"
fi

echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
