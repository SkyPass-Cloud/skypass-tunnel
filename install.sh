#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────────────────
#  SkyPass Tunnel — installer / updater
#
#  نصب:      curl -fsSL https://raw.githubusercontent.com/SkyPass-Cloud/skypass-tunnel/main/install.sh | sudo bash
#  آپدیت:    sudo skypass-tun-update
#
#  این اسکریپت آخرین باینری منتشرشده را از GitHub Releases (مخزن عمومی) دانلود و
#  در /usr/local/bin نصب می‌کند، وابستگی‌های شبکه را تنظیم می‌کند و یک دستور
#  ساده‌ی آپدیت می‌سازد.
# ────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="SkyPass-Cloud/skypass-tunnel"
BRANCH="main"                      # برنچی که install.sh عمومی روی آن است (برای آپدیت)
BIN_DIR="/usr/local/bin"
BIN_PATH="${BIN_DIR}/skypass-tun"
UPDATE_WRAPPER="${BIN_DIR}/skypass-tun-update"
ASSET_PREFIX="skypass-tun-linux"   # asset نهایی: skypass-tun-linux-amd64 / -arm64

# ── رنگ‌ها ──
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

# ── ریشه بودن ──
[ "$(id -u)" -eq 0 ] || die "این اسکریپت باید با root اجرا شود (از sudo استفاده کن)."

# ── تشخیص معماری ──
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "معماری پشتیبانی‌نشده: $(uname -m) (فقط amd64 و arm64)" ;;
  esac
}

# ── نیازمندی‌های پایه ──
ensure_deps() {
  local need=()
  command -v curl >/dev/null 2>&1 || need+=(curl)
  if [ "${#need[@]}" -gt 0 ]; then
    say "نصب ابزارهای لازم: ${need[*]}"
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -qq && apt-get install -y -qq "${need[@]}"
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y -q "${need[@]}"
    elif command -v yum >/dev/null 2>&1; then
      yum install -y -q "${need[@]}"
    else
      die "مدیر بسته ناشناخته. لطفاً دستی نصب کن: ${need[*]}"
    fi
  fi
}

# ── دانلود آخرین باینری از Releases ──
download_binary() {
  local arch asset url tmp
  arch="$(detect_arch)"
  asset="${ASSET_PREFIX}-${arch}"
  url="https://github.com/${REPO}/releases/latest/download/${asset}"
  tmp="$(mktemp)"

  say "دانلود ${asset} ..."
  if ! curl -fSL --retry 3 -o "$tmp" "$url"; then
    rm -f "$tmp"
    die "دانلود ناموفق بود. آیا نسخه‌ای برای ${arch} منتشر شده؟ ($url)"
  fi

  install -m 0755 "$tmp" "$BIN_PATH"
  rm -f "$tmp"
  ok "باینری در ${BIN_PATH} نصب شد."
}

# ── بهینه‌سازی شبکه (BBR + بافرها) — فقط در install ──
tune_network() {
  local sysctl_file="/etc/sysctl.d/99-skypass-tun.conf"
  say "اعمال بهینه‌سازی شبکه (BBR)..."
  cat > "$sysctl_file" <<'EOF'
# SkyPass Tunnel network tuning
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
EOF
  sysctl -p "$sysctl_file" >/dev/null 2>&1 || warn "اعمال sysctl کامل نشد (بی‌اهمیت)."
  ok "بهینه‌سازی شبکه اعمال شد."
}

# ── ساخت دستور ساده‌ی آپدیت ──
install_update_wrapper() {
  cat > "$UPDATE_WRAPPER" <<EOF
#!/usr/bin/env bash
# به‌روزرسانی SkyPass Tunnel به آخرین نسخه.
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
    ok "نصب کامل شد!"
    echo ""
    echo -e "  برای شروع اجرا کن:  ${C_G}skypass-tun${C_0}"
    echo -e "  برای آپدیت بعدی:    ${C_G}sudo skypass-tun-update${C_0}"
    echo ""
    ;;
  update)
    banner
    ensure_deps
    download_binary
    # اگر تونلی ذخیره شده، روی باینری جدید دوباره بالا بیاور.
    if "$BIN_PATH" restart-all >/dev/null 2>&1; then
      ok "تونل‌های ذخیره‌شده روی نسخه‌ی جدید ری‌استارت شدند."
    fi
    ok "به‌روزرسانی کامل شد."
    ;;
  *)
    die "زیردستور ناشناخته: ${SUBCMD} (فقط install یا update)"
    ;;
esac
