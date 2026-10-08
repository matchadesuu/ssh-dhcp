#!/usr/bin/env bash
# =============================================================================
# Setup Debian 13 (Trixie) : DHCP Server + SSH Server (key only)
# Ulangan Praktik Administrasi Sistem Jaringan - SMK Negeri 1 Kedungwuni
#
# Pemakaian (sebagai root):
#   bash setup.sh                 (default absen 33 -> IP 172.60.30.133)
#   bash setup.sh <NO_ABSEN>      (absen lain, contoh: bash setup.sh 12)
#   bash setup.sh show-keys       tampilkan ulang private key (.ppk)
#
# Hasil:
#   IP server LAN  : 172.60.30.(100 + absen)/24
#   DHCP range     : 172.60.30.150 - 172.60.30.200
#   SSH            : port 2222, root ditolak, hanya admin1 & admin3, key only
#
# Opsi lewat environment variable (semua opsional):
#   WAN_IF=enp0s3  LAN_IF=enp0s8  USE_MIRROR=0  ADMIN_PASS=Admin123
# =============================================================================
set -u
export DEBIAN_FRONTEND=noninteractive

SSH_PORT=2222
NET="172.60.30"
KEYDIR="/root/ssh-keys"
BACKUP="/root/backup-setup"
ADMIN_PASS="${ADMIN_PASS:-Admin123}"
USE_MIRROR="${USE_MIRROR:-1}"

say()  { echo; echo "=== $* ==="; }
warn() { echo "[PERINGATAN] $*"; }
die()  { echo "[GAGAL] $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Jalankan sebagai root. Ketik: su -"

# ------------------------------------------------------------------ show-keys
show_keys() {
  for u in admin1 admin3; do
    echo
    if [ -f "$KEYDIR/$u.ppk" ]; then
      echo "######## $u.ppk  (blok semua, paste ke Notepad, simpan sebagai $u.ppk) ########"
      cat "$KEYDIR/$u.ppk"
    elif [ -f "$KEYDIR/$u.key" ]; then
      echo "######## $u.key (format OpenSSH; buka di PuTTYgen > Conversions > Import key) ########"
      cat "$KEYDIR/$u.key"
    else
      warn "Key $u belum ada. Jalankan: bash setup.sh <NO_ABSEN>"
    fi
  done
}

if [ "${1:-}" = "show-keys" ]; then show_keys; exit 0; fi

# --------------------------------------------------------------- validasi input
ABSEN="${1:-33}"   # default absen 33; bisa diganti: bash setup.sh <NO_ABSEN>
case "$ABSEN" in ''|*[!0-9]*) die "Pakai: bash setup.sh <NO_ABSEN>   contoh: bash setup.sh 33";; esac
ABSEN=$((10#$ABSEN))
[ "$ABSEN" -ge 1 ] && [ "$ABSEN" -le 154 ] || die "No absen harus 1-154"

LAST=$((100 + ABSEN))
IP="$NET.$LAST"

# Range DHCP default 150-200. Kalau IP server jatuh di range itu, geser ke 201-250.
RANGE_START=150; RANGE_END=200
if [ "$LAST" -ge 150 ] && [ "$LAST" -le 200 ]; then RANGE_START=201; RANGE_END=250; fi

# ------------------------------------------------------------ deteksi interface
ALL_IF=$(ls /sys/class/net | grep -v '^lo$' | sort)
WAN="${WAN_IF:-$(ip route show default 2>/dev/null | awk '{print $5; exit}')}"
[ -n "$WAN" ] || WAN=$(echo "$ALL_IF" | head -n1)
LAN="${LAN_IF:-$(echo "$ALL_IF" | grep -vx "$WAN" | head -n1)}"
[ -n "$LAN" ] || die "Interface kedua (Host-Only) tidak ditemukan. Cek Adapter 2 di VirtualBox, lalu 'ip a'."
[ "$WAN" != "$LAN" ] || die "WAN dan LAN sama ($WAN). Cek 'ip a'."

say "RINGKASAN"
echo "No absen        : $ABSEN"
echo "IP server LAN   : $IP/24  (interface $LAN)"
echo "Interface WAN   : $WAN (internet)"
echo "DHCP range      : $NET.$RANGE_START - $NET.$RANGE_END"
echo "SSH port        : $SSH_PORT"

mkdir -p "$BACKUP" "$KEYDIR"; chmod 700 "$KEYDIR"

# ------------------------------------------------------------------ 1. repository
say "1. REPOSITORY"
if [ "$USE_MIRROR" = "1" ]; then
  [ -f /etc/apt/sources.list ] && cp -n /etc/apt/sources.list "$BACKUP/sources.list.bak"
  if [ -f /etc/apt/sources.list.d/debian.sources ]; then
    cp -n /etc/apt/sources.list.d/debian.sources "$BACKUP/debian.sources.bak"
    rm -f /etc/apt/sources.list.d/debian.sources
  fi
  cat > /etc/apt/sources.list << 'EOF'
deb https://cermin.rumahweb.id/debian/ trixie main contrib non-free
deb https://cermin.rumahweb.id/debian/ trixie-updates main contrib non-free
deb https://cermin.rumahweb.id/debian-security trixie-security main
EOF
  cat /etc/apt/sources.list
fi
if ! apt-get update; then
  warn "apt update gagal, mengembalikan repository bawaan..."
  [ -f "$BACKUP/sources.list.bak" ] && cp "$BACKUP/sources.list.bak" /etc/apt/sources.list
  [ -f "$BACKUP/debian.sources.bak" ] && cp "$BACKUP/debian.sources.bak" /etc/apt/sources.list.d/debian.sources
  apt-get update || die "apt update tetap gagal. Cek internet: ping -c 3 8.8.8.8 dan ping -c 3 google.com"
fi

# ------------------------------------------------------------------ 2. network
say "2. IP STATIC $LAN"
mkdir -p /etc/network/interfaces.d
touch /etc/network/interfaces

# hapus konfigurasi lama interface LAN dari file utama (sisa percobaan sebelumnya)
awk -v i="$LAN" '
  /^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]]+/ { skip = ($2 == i) }
  /^[[:space:]]*(source|source-directory|mapping)/ { skip = 0 }
  !skip { print }
' /etc/network/interfaces > /etc/network/interfaces.new && mv /etc/network/interfaces.new /etc/network/interfaces

# pastikan interfaces.d dibaca
grep -qE '^[[:space:]]*source(-directory)?[[:space:]]+/etc/network/interfaces.d' /etc/network/interfaces \
  || echo "source /etc/network/interfaces.d/*" >> /etc/network/interfaces

cat > /etc/network/interfaces.d/lan << EOF
auto $LAN
iface $LAN inet static
    address $IP
    netmask 255.255.255.0
EOF

# pastikan WAN dikonfigurasi DHCP (hanya ditambah kalau belum ada)
if ! grep -rqsE "^[[:space:]]*iface[[:space:]]+$WAN[[:space:]]" /etc/network/interfaces /etc/network/interfaces.d/; then
  printf 'auto %s\niface %s inet dhcp\n' "$WAN" "$WAN" > /etc/network/interfaces.d/wan
fi

# terapkan langsung tanpa ifup/ifdown (supaya tidak menggantung / memutus PuTTY)
ip link set "$LAN" up
ip addr flush dev "$LAN"
ip addr add "$IP/24" dev "$LAN"
ip a show "$LAN"

echo "--- tes internet ---"
ping -c 2 -W 3 8.8.8.8   || warn "Server belum bisa ping 8.8.8.8 (cek Adapter 1 Bridged)"
ping -c 2 -W 3 google.com || warn "DNS / google.com belum bisa"

# ------------------------------------------------------------------ 3. paket + DHCP
say "3. INSTALASI PAKET"
# cegah service auto-start saat instalasi (belum dikonfigurasi, jadi pasti gagal)
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d
apt-get install -y isc-dhcp-server openssh-server
RC=$?
rm -f /usr/sbin/policy-rc.d
[ $RC -eq 0 ] || die "Instalasi paket gagal (cek internet / repository)."
apt-get install -y putty-tools || warn "putty-tools tidak terpasang; key tetap tersedia format OpenSSH"

say "3b. KONFIGURASI DHCP SERVER"
cat > /etc/default/isc-dhcp-server << EOF
INTERFACESv4="$LAN"
INTERFACESv6=""
EOF

cat > /etc/dhcp/dhcpd.conf << EOF
default-lease-time 600;
max-lease-time 7200;
authoritative;

subnet $NET.0 netmask 255.255.255.0 {
    range $NET.$RANGE_START $NET.$RANGE_END;
    option routers $IP;
    option subnet-mask 255.255.255.0;
    option broadcast-address $NET.255;
    option domain-name-servers 8.8.8.8, 1.1.1.1;
}
EOF
cat /etc/dhcp/dhcpd.conf
mkdir -p /var/lib/dhcp; touch /var/lib/dhcp/dhcpd.leases
dhcpd -t -cf /etc/dhcp/dhcpd.conf || die "Sintaks dhcpd.conf salah"
systemctl enable isc-dhcp-server 2>/dev/null
systemctl restart isc-dhcp-server
sleep 3
if systemctl is-active --quiet isc-dhcp-server; then
  echo "DHCP server: active (running)"
else
  warn "DHCP gagal start. Penyebab:"
  journalctl -u isc-dhcp-server --no-pager -n 25 | grep -iE "no subnet|not configured|error|interface|exiting|permission"
fi

# ------------------------------------------------------------------ 4. user
say "4. USER admin1, admin2, admin3"
for u in admin1 admin2 admin3; do
  id "$u" >/dev/null 2>&1 || useradd -m -s /bin/bash "$u"
  echo "$u:$ADMIN_PASS" | chpasswd
  echo "user $u siap"
done

# ------------------------------------------------------------------ 5. SSH key
say "5. SSH KEY admin1 & admin3"
for u in admin1 admin3; do
  h="/home/$u"
  install -d -m 700 -o "$u" -g "$u" "$h/.ssh"
  [ -f "$h/.ssh/id_ed25519" ] || ssh-keygen -q -t ed25519 -N "" -C "$u@$(hostname)" -f "$h/.ssh/id_ed25519"
  cp "$h/.ssh/id_ed25519.pub" "$h/.ssh/authorized_keys"
  chown -R "$u:$u" "$h/.ssh"
  chmod 700 "$h/.ssh"; chmod 600 "$h/.ssh/authorized_keys" "$h/.ssh/id_ed25519"; chmod 644 "$h/.ssh/id_ed25519.pub"

  cp "$h/.ssh/id_ed25519" "$KEYDIR/$u.key"; chmod 600 "$KEYDIR/$u.key"
  if command -v puttygen >/dev/null 2>&1; then
    puttygen "$KEYDIR/$u.key" -O private -o "$KEYDIR/$u.ppk" 2>/dev/null && chmod 600 "$KEYDIR/$u.ppk"
  fi
  echo "key $u dibuat -> $KEYDIR/$u.ppk"
done

# ------------------------------------------------------------------ 6. SSH config
say "6. KONFIGURASI SSH"
rm -f /etc/ssh/sshd_config.d/kebijakan.conf /etc/ssh/sshd_config.d/99-kebijakan.conf
cat > /etc/ssh/sshd_config.d/00-kebijakan.conf << EOF
Port $SSH_PORT
PermitRootLogin no
AllowUsers admin1 admin3
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
AuthenticationMethods publickey
EOF
cat /etc/ssh/sshd_config.d/00-kebijakan.conf

# di Debian 13, ssh.socket dapat memaksa port 22; matikan
systemctl disable --now ssh.socket 2>/dev/null
systemctl enable ssh 2>/dev/null

if ! sshd -t; then
  rm -f /etc/ssh/sshd_config.d/00-kebijakan.conf
  die "Konfigurasi SSH salah, file kebijakan dihapus agar tidak terkunci."
fi
systemctl restart ssh
sleep 2
ss -tlnp | grep ":$SSH_PORT"

# ------------------------------------------------------------------ 7. pengujian otomatis
say "7. PENGUJIAN OTOMATIS"
PASS=0; FAIL=0
check() { # check "label" perintah...
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "[OK]     $label"; PASS=$((PASS+1)); else echo "[GAGAL]  $label"; FAIL=$((FAIL+1)); fi
}
SSHO="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o ConnectTimeout=5"
K1="$KEYDIR/admin1.key"; K3="$KEYDIR/admin3.key"

check "IP $IP terpasang di $LAN"            sh -c "ip -4 addr show $LAN | grep -q $IP/24"
check "DHCP server active"                  systemctl is-active --quiet isc-dhcp-server
check "SSH listen di port $SSH_PORT"        sh -c "ss -tln | grep -q ':$SSH_PORT '"
check "SSH TIDAK listen di port 22"         sh -c "! ss -tln | grep -q ':22 '"
check "Login admin1 pakai key"              ssh $SSHO -i "$K1" -p $SSH_PORT admin1@127.0.0.1 true
check "Login admin3 pakai key"              ssh $SSHO -i "$K3" -p $SSH_PORT admin3@127.0.0.1 true
check "admin2 ditolak"                      sh -c "! ssh $SSHO -i $K1 -p $SSH_PORT admin2@127.0.0.1 true"
check "root ditolak"                        sh -c "! ssh $SSHO -i $K1 -p $SSH_PORT root@127.0.0.1 true"
check "Login password ditolak"              sh -c "! ssh $SSHO -o PubkeyAuthentication=no -o PreferredAuthentications=password -p $SSH_PORT admin1@127.0.0.1 true"
check "Port 22 ditolak"                     sh -c "! ssh $SSHO -i $K1 -p 22 admin1@127.0.0.1 true"
check "Internet (ping 8.8.8.8)"             ping -c 1 -W 3 8.8.8.8
check "DNS (ping google.com)"               ping -c 1 -W 3 google.com

echo
echo "HASIL: $PASS lolos, $FAIL gagal"

# ------------------------------------------------------------------ 8. selesai
say "SELESAI"
cat << EOF
IP server LAN : $IP/24
SSH           : port $SSH_PORT (admin1 / admin3, key only)
DHCP range    : $NET.$RANGE_START - $NET.$RANGE_END
File key      : $KEYDIR/ (admin1.ppk, admin3.ppk)

LANGKAH BERIKUTNYA:
 1. Salin isi private key di bawah ke Notepad Windows, simpan sebagai admin1.ppk dan admin3.ppk
    (tipe: All files). Jangan tutup sesi PuTTY ini dulu.
 2. PuTTY baru: Host $IP (atau IP bridged), Port $SSH_PORT
    Connection > Data > Auto-login username: admin1
    Connection > SSH > Auth > Credentials > Private key file: admin1.ppk
 3. Tampilkan lagi key kapan saja (lewat console VirtualBox): bash setup.sh show-keys
EOF
show_keys
