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
if ! command -v brew &>/dev/null; then
  warn "Homebrew not found – installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for Apple Silicon
  eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
  eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
fi
ok "Homebrew ready"

# ── 2. Node.js ────────────────────────────────
log "Checking Node.js..."
REQUIRED_NODE="22"
if ! command -v node &>/dev/null || [[ "$(node -e 'process.stdout.write(process.versions.node.split(".")[0])')" -lt "$REQUIRED_NODE" ]]; then
  warn "Node.js $REQUIRED_NODE+ not found – installing via nvm or brew..."
  if command -v nvm &>/dev/null || [ -s "$HOME/.nvm/nvm.sh" ]; then
    # shellcheck disable=SC1090
    source "$HOME/.nvm/nvm.sh" 2>/dev/null || true
    nvm install 22 && nvm use 22
  else
    brew install node@22
    export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
    export PATH="/usr/local/opt/node@22/bin:$PATH"
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
if ! command -v cargo &>/dev/null; then
  warn "Rust not found – installing via rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  source "$HOME/.cargo/env"
fi
source "$HOME/.cargo/env" 2>/dev/null || true
ok "Rust $(rustc --version)"

# ── 5. Python 3 ───────────────────────────────
# cx_Freeze 7.x requires Python 3.10+ — skip macOS system Python 3.9
log "Checking Python..."
PYTHON=""
for cmd in python3.13 python3.12 python3.11 python3.10; do
  if command -v "$cmd" &>/dev/null; then
    PYTHON="$cmd"
    break
  fi
done
# Also check generic python3 if it's 3.10+
if [[ -z "$PYTHON" ]] && command -v python3 &>/dev/null; then
  if python3 -c "import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)" 2>/dev/null; then
    PYTHON="python3"
  fi
fi
if [[ -z "$PYTHON" ]]; then
  warn "Python 3.10+ not found – installing via brew..."
  brew install python@3.11
  export PATH="/opt/homebrew/opt/python@3.11/bin:$PATH"
  export PATH="/usr/local/opt/python@3.11/bin:$PATH"
  PYTHON="python3.11"
fi
ok "Python $($PYTHON --version)"

# ── 6. Python dependencies ────────────────────
log "Installing Python dependencies..."
$PYTHON -m pip install --upgrade pip --quiet
if ! $PYTHON -c "import libtorrent" 2>/dev/null; then
  warn "libtorrent not found for Python – trying brew..."
  brew install libtorrent-rasterbar 2>/dev/null || true
  # Try to install python-libtorrent binding via pip
  $PYTHON -m pip install libtorrent --quiet 2>/dev/null || {
    warn "pip install libtorrent failed – trying brew python binding..."
    # Homebrew may ship the binding at a different site-packages path
    BREW_LIBTORRENT=$(brew --prefix libtorrent-rasterbar 2>/dev/null || true)
    if [[ -n "$BREW_LIBTORRENT" ]]; then
      export DYLD_FALLBACK_LIBRARY_PATH="$BREW_LIBTORRENT/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"
    fi
    $PYTHON -c "import libtorrent" 2>/dev/null || \
      warn "Could not install libtorrent – the Python RPC (torrent) feature may not work"
  }
fi
$PYTHON -m pip install -r requirements.txt --quiet
ok "Python dependencies ready"

# ── 7. Node modules ───────────────────────────
log "Installing Node dependencies..."
yarn --frozen-lockfile
ok "Node modules ready"

# ── 8. Build Python RPC (cx_Freeze) ──────────
log "Building Python RPC..."
$PYTHON python_rpc/setup.py build
ok "Python RPC built"

# ── 9. Build native Rust addon ────────────────
log "Building native Rust addon..."
yarn build:native
ok "Native addon built"

# ── 10. Build Electron app ────────────────────
log "Building Electron app (Vite + TypeScript)..."
electron-vite build 2>/dev/null || npx electron-vite build
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
