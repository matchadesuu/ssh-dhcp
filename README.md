# Debian 13: DHCP Server + SSH Server (Key Only)

Script otomatis untuk ulangan praktik Administrasi Sistem Jaringan (SMK Negeri 1 Kedungwuni).

| Item | Nilai |
|---|---|
| IP server LAN | `172.60.30.(100 + no absen)/24` |
| DHCP range | `172.60.30.150 - 172.60.30.200` (otomatis geser ke `.201-.250` jika IP server bentrok) |
| SSH | port `2222`, root ditolak, hanya `admin1` & `admin3`, hanya SSH key |
| Interface | WAN (Bridged) dan LAN (Host-Only) dideteksi otomatis |

## 1. Persiapan VirtualBox
1. VM Debian 13 dengan 2 adapter: **Adapter 1 = Bridged**, **Adapter 2 = Host-Only**. Centang *Cable Connected* di keduanya.
2. Matikan DHCP bawaan VirtualBox: *File > Tools > Network Manager > Host-only Networks > tab DHCP Server > hapus centang Enable*.
3. (Jika laptop host jadi client/PuTTY) set IP adapter Host-Only di Windows ke `172.60.30.254/24`.

## 2. Jalankan
Login (console VirtualBox atau PuTTY ke IP bridged, port 22), lalu:

```bash
su -
apt-get update && apt-get install -y git
git clone https://github.com/matchadesuu/ssh-dhcp
cd REPO
bash setup.sh          # default absen 33 (IP 172.60.30.133); absen lain: bash setup.sh 12
```

Script aman dijalankan ulang. Di akhir ada tes otomatis dan private key (`.ppk`) ditampilkan.

## 3. Login PuTTY dengan key
1. Salin key yang ditampilkan ke Notepad, simpan `admin1.ppk` dan `admin3.ppk` (tipe *All files*).
2. PuTTY: Host `172.60.30.1xx`, Port `2222`; *Connection > Data* auto-login `admin1`; *Connection > SSH > Auth > Credentials* pilih `admin1.ppk`.

Tampilkan ulang key kapan saja: `bash setup.sh show-keys`

## Opsi (environment variable)
```bash
WAN_IF=enp0s3 LAN_IF=enp0s8 bash setup.sh 33   # paksa nama interface
USE_MIRROR=0 bash setup.sh 33                  # jangan ganti repository
ADMIN_PASS=Rahasia123 bash setup.sh 33         # password console user admin
```

## Troubleshooting
| Masalah | Solusi |
|---|---|
| PuTTY *Connection timed out* ke `172.60.30.x` | Set IP Host-Only Windows `172.60.30.254/24`, atau pakai IP bridged |
| *No supported authentication methods* | Normal: hanya key yang diterima. Pilih `.ppk` dan user `admin1`/`admin3` |
| DHCP gagal start | `ip a show <LAN>` harus punya IP; cek *Cable Connected* Adapter 2 |
| Lupa private key | Dari console VirtualBox: `bash setup.sh show-keys` |
