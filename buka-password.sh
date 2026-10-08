#!/usr/bin/env bash
# =============================================================================
# buka-password.sh : membuka login PASSWORD SEMENTARA di SSH (port 2222)
# Tujuan: supaya PuTTY bisa login dengan user biasa untuk mengambil file .ppk.
#
# Pemakaian (sebagai root):
#   bash buka-password.sh
#
# SETELAH SELESAI mengambil key, kunci lagi sesuai soal (key only):
#   bash setup.sh
# =============================================================================
set -u

CONF="/etc/ssh/sshd_config.d/00-kebijakan.conf"

[ "$(id -u)" -eq 0 ] || { echo "[GAGAL] Jalankan sebagai root. Ketik: su -"; exit 1; }
[ -f "$CONF" ] || { echo "[GAGAL] $CONF tidak ditemukan. Jalankan dulu: bash setup.sh"; exit 1; }

echo "=== Membuka login password sementara ==="
cp -n "$CONF" /root/00-kebijakan.conf.bak

sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' "$CONF"
sed -i 's/^AllowUsers.*/AllowUsers admin1 admin3 user/' "$CONF"
sed -i '/^AuthenticationMethods/d' "$CONF"

if ! sshd -t; then
  echo "[GAGAL] Konfigurasi salah, mengembalikan file asli..."
  cp /root/00-kebijakan.conf.bak "$CONF"
  exit 1
fi

systemctl restart ssh
sleep 2

echo
echo "--- Isi konfigurasi sekarang ---"
cat "$CONF"
echo
ss -tlnp | grep ssh

cat << 'EOF'

=== SELESAI ===
Sekarang PuTTY bisa login pakai password:
  Host : 192.168.4.177 (IP bridged)    Port : 2222    User : user  (lalu: su -)

Ambil key:
  cat /root/ssh-keys/admin1.ppk
  cat /root/ssh-keys/admin3.ppk
Blok teks di PuTTY, paste ke Notepad, simpan admin1.ppk / admin3.ppk (tipe All files).

JANGAN LUPA kunci lagi setelah selesai:
  bash setup.sh
EOF
