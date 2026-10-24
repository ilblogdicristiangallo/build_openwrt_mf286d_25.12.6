#!/bin/bash
set -Eeuo pipefail
trap 'echo "[X] Errore alla riga $LINENO. Uscita."; exit 1' ERR

# 🔧 CONFIGURAZIONE
VERSION="25.12.6"
TARGET="ipq40xx"
SUBTARGET="generic"
PROFILE="zte_mf286d"

BASE_URL="https://downloads.openwrt.org"
ARCHIVE_NAME="openwrt-imagebuilder-${VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64.tar.zst"
ARCHIVE_URL="${BASE_URL}/releases/${VERSION}/targets/${TARGET}/${SUBTARGET}/${ARCHIVE_NAME}"

# 📦 Pacchetti base
PACKAGES="luci luci-proto-qmi luci-proto-modemmanager luci-proto-wireguard \
wireguard-tools kmod-usb-serial-option kmod-usb-serial kmod-usb-serial-wwan \
usb-modeswitch kmod-mii kmod-usb-net kmod-usb-wdm kmod-usb-net-qmi-wwan \
uqmi kmod-usb-net-cdc-mbim modemmanager umbim luci-proto-mbim \
wget-ssl ca-bundle adb"

# 📦 Verifica tool richiesti
for t in wget tar make unzstd sha256sum; do
  command -v "$t" >/dev/null || {
    echo "[!] Tool mancante: $t. Installa con: sudo apt install $t"
    exit 1
  }
done

echo "==> OpenWrt ${VERSION} | Target: ${TARGET}/${SUBTARGET} | Profilo: ${PROFILE}"

# 🌐 Test rete + fix DNS
echo "==> Test connettività..."
if ! ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
  echo "[X] Nessuna connessione Internet."
  exit 1
fi

if ! getent hosts downloads.openwrt.org >/dev/null; then
  echo "[!] DNS non funzionante, imposto DNS pubblico..."
  echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null
fi

echo "==> Scarico ImageBuilder da: $ARCHIVE_URL"

# 📥 Download con retry + fallback
if [[ ! -f "$ARCHIVE_NAME" || ! -s "$ARCHIVE_NAME" ]]; then
  wget --tries=3 --timeout=15 --show-progress "$ARCHIVE_URL" -O "$ARCHIVE_NAME" || {
    echo "[!] Mirror principale fallito, provo fallback..."
    FALLBACK_URL="https://mirror1.openwrt.org/releases/${VERSION}/targets/${TARGET}/${SUBTARGET}/${ARCHIVE_NAME}"
    wget --tries=3 --timeout=15 --show-progress "$FALLBACK_URL" -O "$ARCHIVE_NAME" || {
      echo "[X] Download fallito anche dal mirror."
      exit 1
    }
  }
fi

# 📦 Estrazione
tar --use-compress-program=unzstd -xf "$ARCHIVE_NAME"

# 📁 Cartella
FOLDER_NAME=$(find . -maxdepth 1 -type d -name "openwrt-imagebuilder-${VERSION}-*${TARGET}*${SUBTARGET}*" | head -n1)
[[ -d "$FOLDER_NAME" ]] || {
  echo "[X] Cartella ImageBuilder non trovata."
  exit 1
}
echo "[✓] Cartella trovata: $FOLDER_NAME"

# Fix warning TMPDIR
mkdir -p "$FOLDER_NAME/tmp"

# 🔍 KMOD HASH corretto
KMOD_HASH=$(
  wget -qO- "${BASE_URL}/releases/${VERSION}/targets/${TARGET}/${SUBTARGET}/kmods/" \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-1-[a-f0-9]{32}/' \
  | head -n1 \
  | tr -d '/'
)

[[ -n "$KMOD_HASH" ]] || {
  echo "[X] Impossibile recuperare hash kmods."
  exit 1
}
echo "[✓] Kernel hash: $KMOD_HASH"

# 📄 repositories.conf per ImageBuilder
cat > "$FOLDER_NAME/repositories.conf" <<EOF
src/gz openwrt_core ${BASE_URL}/releases/${VERSION}/targets/${TARGET}/${SUBTARGET}/packages
src/gz openwrt_base ${BASE_URL}/releases/${VERSION}/packages/arm_cortex-a7_neon-vfpv4/base
src/gz openwrt_kmods ${BASE_URL}/releases/${VERSION}/targets/${TARGET}/${SUBTARGET}/kmods/${KMOD_HASH}
src/gz openwrt_luci ${BASE_URL}/releases/${VERSION}/packages/arm_cortex-a7_neon-vfpv4/luci
src/gz openwrt_packages ${BASE_URL}/releases/${VERSION}/packages/arm_cortex-a7_neon-vfpv4/packages
src/gz openwrt_routing ${BASE_URL}/releases/${VERSION}/packages/arm_cortex-a7_neon-vfpv4/routing
src/gz openwrt_telephony ${BASE_URL}/releases/${VERSION}/packages/arm_cortex-a7_neon-vfpv4/telephony
src imagebuilder file:packages
option check_signature
EOF

# === CONFIGURAZIONE APK (OpenWrt 25.12.2) ===

mkdir -p "$FOLDER_NAME/files/etc/apk/repositories.d"
mkdir -p "$FOLDER_NAME/files/etc/apk/keys"

# Pulizia vecchi file feed personalizzati
rm -f "$FOLDER_NAME/files/etc/apk/repositories.d/iceg.list"
rm -f "$FOLDER_NAME/files/etc/apk/repositories.d/cristian.list"
rm -f "$FOLDER_NAME/files/etc/apk/repositories.d/customfeeds.list"

# Repository esterni in un solo file
cat > "$FOLDER_NAME/files/etc/apk/repositories.d/customfeeds.list" <<'EOF'
https://github.com/4IceG/Modem-extras-apk/raw/refs/heads/main/myapk/packages.adb
https://github.com/ilblogdicristiangallo/ilblogdicristiangallo_repo_openwrt_APK/raw/refs/heads/main/packages.adb
EOF
echo "[✓] Repository esterni scritti in customfeeds.list"

# Chiave IceG (sempre scaricata online)
echo "==> Scarico chiave IceG..."
wget -q "https://github.com/4IceG/Modem-extras-apk/raw/refs/heads/main/myapk/IceG-apkpub.pem" \
  -O "$FOLDER_NAME/files/etc/apk/keys/IceG-apkpub.pem" || {
    echo "[X] Errore: impossibile scaricare la chiave IceG."
    exit 1
}
echo "[✓] Chiave APK IceG scaricata e installata"

# Chiave ilblogdicristiangallo
wget -q "https://github.com/ilblogdicristiangallo/ilblogdicristiangallo_repo_openwrt_APK/raw/refs/heads/main/ilblogdicristiangallo.apkpub.pem" \
  -O "$FOLDER_NAME/files/etc/apk/keys/ilblogdicristiangallo.apkpub.pem"
echo "[✓] Chiave APK ilblogdicristiangallo copiata"

# 📦 APK locali
mkdir -p "$FOLDER_NAME/packages"
cp _local_packages_apk/*.apk "$FOLDER_NAME/packages/" 2>/dev/null || true
echo "[✓] APK locali copiati in packages/ (se presenti)"

# 🔁 Script di init per applicare automaticamente le chiavi APK al primo boot
mkdir -p "$FOLDER_NAME/files/etc/init.d"
mkdir -p "$FOLDER_NAME/files/etc/rc.d"

cat > "$FOLDER_NAME/files/etc/init.d/apk-keys-setup" <<'EOF'
#!/bin/sh /etc/rc.common
START=10
USE_PROCD=1

start_service() {
    echo "[apk-keys-setup] Installazione chiavi APK personalizzate..."

    if ! command -v apk >/dev/null 2>&1; then
        echo "[apk-keys-setup] apk non trovato, esco."
        return 0
    fi

    for KEY in /etc/apk/keys/*.pem; do
        [ -f "$KEY" ] || continue
        echo "[apk-keys-setup] Aggiungo chiave: $KEY"
        apk add-key "$KEY" 2>/dev/null || true
    done

    echo "[apk-keys-setup] Chiavi APK elaborate."

    rm -f /etc/rc.d/S10apk-keys-setup 2>/dev/null || true
}
EOF

chmod +x "$FOLDER_NAME/files/etc/init.d/apk-keys-setup"
ln -sf "../init.d/apk-keys-setup" "$FOLDER_NAME/files/etc/rc.d/S10apk-keys-setup"
echo "[✓] Script di init apk-keys-setup creato e abilitato"

# 📦 Pacchetti custom dentro il firmware
PACKAGES="$PACKAGES \
luci-app-modemband \
luci-app-sms-tool-js \
luci-app-3ginfo-lite"

# 🌐 CONFIGURAZIONI
mkdir -p "$FOLDER_NAME/files/etc/config"

cat > "$FOLDER_NAME/files/etc/config/network" << 'EOF'
config interface 'loopback'
    option device 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

config globals 'globals'
    option ula_prefix 'fd00:abcd::/48'

config device
    option name 'br-lan'
    option type 'bridge'
    list ports 'lan2'
    list ports 'lan3'
    list ports 'lan4'

config interface 'lan'
    option device 'br-lan'
    option proto 'static'
    option ipaddr '192.168.1.1'
    option netmask '255.255.255.0'

config interface 'wan'
    option device '/dev/cdc-wdm0'
    option proto 'qmi'
    option apn 'internet.it'
    option auth 'none'
    option pdptype 'ipv4'
    option auto '1'

config interface 'wan6'
    option device 'wan'
    option proto 'dhcpv6'
EOF

cat > "$FOLDER_NAME/files/etc/config/firewall" << 'EOF'
config defaults
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'REJECT'
    option syn_flood '1'

config zone
    option name 'lan'
    option network 'lan'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'ACCEPT'

config zone
    option name 'wan'
    option network 'wan wan6'
    option input 'REJECT'
    option output 'ACCEPT'
    option forward 'REJECT'
    option masq '1'
    option mtu_fix '1'

config forwarding
    option src 'lan'
    option dest 'wan'
EOF

cat > "$FOLDER_NAME/files/etc/config/wireless" << 'EOF'
config wifi-device 'radio0'
        option type 'mac80211'
        option path 'platform/soc/a000000.wifi'
        option band '2g'
        option htmode 'HT20'
        option channel '8'
        option country 'IT'
        option disabled '0'
        option cell_density '0'

config wifi-iface 'default_radio0'
        option device 'radio0'
        option network 'lan'
        option mode 'ap'
        option ssid 'OpenWrt'

config wifi-device 'radio1'
        option type 'mac80211'
        option path 'platform/soc/a800000.wifi'
        option band '5g'
        option htmode 'VHT80'
        option channel 'auto'
        option disabled '0'
        option cell_density '0'

config wifi-iface 'default_radio1'
        option device 'radio1'
        option network 'lan'
        option mode 'ap'
        option ssid 'OpenWRT-5Ghz'
EOF

# ➕ AGGIUNTA CONFIG 3GINFO
cat > "$FOLDER_NAME/files/etc/config/3ginfo" << 'EOF'
config 3ginfo
        option website 'https://lteitaly.it/internal/map.php#bts='
        option network 'wan'
        option device '/dev/ttyUSB1'
EOF

# ➕ AGGIUNTA CONFIG MODEMBAND
cat > "$FOLDER_NAME/files/etc/config/modemband" << 'EOF'
config modemband
        option iface 'wan'
        option wanrestart '0'
        option modemrestart '0'
        option notify '0'
        option set_bands '1,3,7,8,20,28,38'
        option set_port '/dev/ttyUSB1'
EOF

# ➕ AGGIUNTA CONFIG SMSTOOLS
cat > "$FOLDER_NAME/files/etc/config/sms_tool_js" << 'EOF'
config sms_tool_js
        option storage 'SM'
        option mergesms '0'
        option pnumber '48'
        option prefix '1'
        option lednotify '0'
        option ussd '0'
        option pdu '0'
        option sendingroup '0'
        option information '1'
        option readport '/dev/ttyUSB1'
        option sendport '/dev/ttyUSB1'
        option forward_sms_enabled '0'
        option emailprovider 'custom'
        option forward_sms_mail_security 'tls'
        option ussdport '/dev/ttyUSB1'
        option coding 'auto'
        option atport '/dev/ttyUSB1'
        option ontopsms '0'
        option checktime '10'
        option prestart '6'
        option ledtype 'D'
EOF

# 🏗️ BUILD
cd "$FOLDER_NAME"
make image PROFILE="$PROFILE" FILES=files/ PACKAGES="$PACKAGES"

OUT_DIR="bin/targets/${TARGET}/${SUBTARGET}"
SYSUPGRADE=$(find "$OUT_DIR" -name '*sysupgrade*.bin' | head -n1)
[[ -f "$SYSUPGRADE" ]] || {
  echo "[X] sysupgrade.bin non trovato."
  exit 1
}

REAL_USER=${SUDO_USER:-$USER}
DEST="/home/$REAL_USER/Desktop/sysupgrade-${PROFILE}-$(date +%Y%m%d-%H%M).bin"

cp "$SYSUPGRADE" "$DEST"
echo "[✓] Firmware pronto: $DEST"

