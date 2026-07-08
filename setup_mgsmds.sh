#!/bin/bash
# setup_mgsmds.sh — ตั้งค่า MGS/MDS node ของ Lustre lab (labfs)
# รันบน mgsmds ด้วยสิทธิ์ root: sudo bash setup_mgsmds.sh
#
# ทำ: /etc/hosts, ปิด firewalld/SELinux, format (ครั้งแรกเท่านั้น) + mount MDT,
#     เขียน /etc/fstab ด้วย UUID เสมอ (ห้าม hardcode /dev/sdX — ดู Improve.md ข้อ 1)

set -e

# ========================= CONFIG — แก้ตรงนี้ก่อนรัน =========================
FSNAME="labfs"
MDT_MOUNT="/mnt/mdt"
MDT_LABEL="${FSNAME}-MDT0000"

HOSTNAME_MGSMDS="mgsmds"; IP_MGSMDS="192.168.100.10"
HOSTNAME_OSS="oss";       IP_OSS="192.168.100.11"
HOSTNAME_CLIENT="client"; IP_CLIENT="192.168.100.12"
# =============================================================================

if [ "$(id -u)" -ne 0 ]; then
  echo "ต้องรันด้วย root/sudo" >&2
  exit 1
fi

echo "=== [1/6] ตั้งค่า /etc/hostname และ /etc/hosts ==="
hostnamectl set-hostname "$HOSTNAME_MGSMDS"
for line in \
  "$IP_MGSMDS $HOSTNAME_MGSMDS" \
  "$IP_OSS $HOSTNAME_OSS" \
  "$IP_CLIENT $HOSTNAME_CLIENT"
do
  grep -qF "$line" /etc/hosts || echo "$line" >> /etc/hosts
done
cat /etc/hosts

echo "=== [2/6] ปิด firewalld + SELinux ==="
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true
setenforce 0 2>/dev/null || true
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config 2>/dev/null || true

echo "=== [3/6] เลือก disk สำหรับ MDT ==="
lsblk
read -rp "พิมพ์ชื่อ device สำหรับ MDT (เช่น sdb, ไม่ต้องใส่ /dev/): " MDT_DEV_NAME
MDT_DEV="/dev/${MDT_DEV_NAME}"

if [ ! -b "$MDT_DEV" ]; then
  echo "ไม่พบ device $MDT_DEV" >&2
  exit 1
fi

echo "=== [4/6] format เป็น MGS/MDT (ข้ามถ้า format แล้ว) ==="
EXISTING_LABEL="$(blkid -s LABEL -o value "$MDT_DEV" 2>/dev/null || true)"
if [ "$EXISTING_LABEL" = "$MDT_LABEL" ]; then
  echo "-> $MDT_DEV format เป็น $MDT_LABEL อยู่แล้ว ข้ามขั้นตอน mkfs"
else
  echo "!! กำลังจะ format $MDT_DEV เป็น MGS/MDT — ข้อมูลทั้งหมดบน disk นี้จะหายถาวร !!"
  lsblk "$MDT_DEV"
  read -rp "พิมพ์ 'yes' เพื่อยืนยัน format $MDT_DEV: " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "ยกเลิก ไม่ format"
    exit 1
  fi
  mkfs.lustre --fsname="$FSNAME" --mgs --mdt --index=0 "$MDT_DEV"
fi

echo "=== [5/6] mount + เขียน fstab ด้วย UUID ==="
mkdir -p "$MDT_MOUNT"
mountpoint -q "$MDT_MOUNT" || mount -t lustre "$MDT_DEV" "$MDT_MOUNT"

MDT_UUID="$(blkid -s UUID -o value "$MDT_DEV")"
if [ -z "$MDT_UUID" ]; then
  echo "หา UUID ของ $MDT_DEV ไม่เจอ — เช็ค blkid ด้วยมือ" >&2
  exit 1
fi

FSTAB_LINE="UUID=${MDT_UUID}   ${MDT_MOUNT}    lustre   _netdev,defaults   0 0"
if grep -qF "$MDT_MOUNT" /etc/fstab; then
  echo "-> มี entry ของ $MDT_MOUNT ใน fstab แล้ว ไม่แก้ทับ (เช็คด้วยมือถ้า UUID เปลี่ยน)"
else
  echo "$FSTAB_LINE" >> /etc/fstab
  echo "-> เพิ่มบรรทัดนี้ใน /etc/fstab:"
  echo "   $FSTAB_LINE"
fi
systemctl daemon-reload

echo "=== [6/6] เสร็จ — สถานะปัจจุบัน ==="
df -h "$MDT_MOUNT" || true
lctl dl || true

echo ""
echo "เสร็จ setup_mgsmds.sh — ต่อไปรัน setup_oss.sh บนเครื่อง oss"
