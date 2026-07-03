#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────────────────
#  SkyPass Tunnel — installer / updater
#
#  install:  curl -fsSL https://raw.githubusercontent.com/SkyPass-Cloud/skypass-tunnel/main/install.sh | sudo bash
#  update:   sudo skypass-tun-update
#
#  This script downloads the latest released binary from GitHub Releases (public
#  repo), installs it into /usr/local/bin, tunes the network, and creates a
#  simple update command.
# ────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="SkyPass-Cloud/skypass-tunnel"
BRANCH="main"                      # branch the public install.sh lives on (for updates)
BIN_DIR="/usr/local/bin"
BIN_PATH="${BIN_DIR}/skypass-tun"
UPDATE_WRAPPER="${BIN_DIR}/skypass-tun-update"
ASSET_PREFIX="skypass-tun-linux"   # final asset: skypass-tun-linux-amd64 / -arm64

# ── colors ──
if [ -t 1 ]; then
  C_G="\033[32m"; C_Y="\033[33m"; C_R="\033[31m"; C_B="\033[36m"; C_0="\033[0m"
else
  C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""
fi
say()  { echo -e "${C_B}▸${C_0} $*"; }
ok()   { echo -e "${C_G}✔${C_0} $*"; }
warn() { echo -e "${C_Y}!${C_0} $*"; }
die()  { echo -e "${C_R}✗${C_0} $*" >&2; exit 1; }

SUBCMD="${1:-install}"

# ── must be root ──
[ "$(id -u)" -eq 0 ] || die "This script must be run as root (use sudo)."

# ── detect architecture ──
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "Unsupported architecture: $(uname -m) (only amd64 and arm64)" ;;
  esac
}

# ── base dependencies ──
ensure_deps() {
  local need=()
  command -v curl >/dev/null 2>&1 || need+=(curl)
  if [ "${#need[@]}" -gt 0 ]; then
    say "Installing required tools: ${need[*]}"
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -qq && apt-get install -y -qq "${need[@]}"
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y -q "${need[@]}"
    elif command -v yum >/dev/null 2>&1; then
      yum install -y -q "${need[@]}"
    else
      die "Unknown package manager. Please install manually: ${need[*]}"
    fi
  fi
}

# ── download the latest binary from Releases ──
download_binary() {
  local arch asset url tmp
  arch="$(detect_arch)"
  asset="${ASSET_PREFIX}-${arch}"
  url="https://github.com/${REPO}/releases/latest/download/${asset}"
  tmp="$(mktemp)"

  say "Downloading ${asset} ..."
  if ! curl -fSL --retry 3 -o "$tmp" "$url"; then
    rm -f "$tmp"
    die "Download failed. Is there a release published for ${arch}? ($url)"
  fi

  install -m 0755 "$tmp" "$BIN_PATH"
  rm -f "$tmp"
  ok "Binary installed at ${BIN_PATH}."
}

# ── network tuning (BBR + buffers) — install only ──
tune_network() {
  local sysctl_file="/etc/sysctl.d/99-skypass-tun.conf"
  say "Applying network tuning (BBR)..."
  cat > "$sysctl_file" <<'EOF'
# SkyPass Tunnel network tuning
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
EOF
  sysctl -p "$sysctl_file" >/dev/null 2>&1 || warn "sysctl not fully applied (harmless)."
  ok "Network tuning applied."
}

# ── create the simple update command ──
install_update_wrapper() {
  cat > "$UPDATE_WRAPPER" <<EOF
#!/usr/bin/env bash
# Update SkyPass Tunnel to the latest version.
curl -fsSL https://raw.githubusercontent.com/${REPO}/${BRANCH}/install.sh | sudo bash -s -- update
EOF
  chmod 0755 "$UPDATE_WRAPPER"
}

banner() {
  echo ""
  echo -e "${C_B}  ☁️  SkyPass Tunnel${C_0}"
  echo -e "  ──────────────────────────────"
  echo ""
}

case "$SUBCMD" in
  install)
    banner
    ensure_deps
    download_binary
    tune_network
    install_update_wrapper
    echo ""
    ok "Installation complete!"
    echo ""
    echo -e "  To get started, run:  ${C_G}skypass-tun${C_0}"
    echo -e "  To update later:      ${C_G}sudo skypass-tun-update${C_0}"
    echo ""
    ;;
  update)
    banner
    ensure_deps
    download_binary
    # If any tunnels are saved, bring them back up on the new binary.
    if "$BIN_PATH" restart-all >/dev/null 2>&1; then
      ok "Saved tunnels restarted on the new version."
    fi
    ok "Update complete."
    ;;
  *)
    die "Unknown subcommand: ${SUBCMD} (only install or update)"
    ;;
esac
