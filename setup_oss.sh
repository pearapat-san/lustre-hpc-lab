#!/bin/bash
# setup_oss.sh — ตั้งค่า OSS node ของ Lustre lab (labfs)
# รันบน oss ด้วยสิทธิ์ root: sudo bash setup_oss.sh
# ต้องรัน setup_mgsmds.sh บน mgsmds ให้เสร็จก่อน (ต้อง ping ผ่านแล้ว)
#
# ทำ: /etc/hosts, ปิด firewalld/SELinux, format (ครั้งแรกเท่านั้น) + mount OST,
#     เขียน /etc/fstab ด้วย UUID เสมอ (ห้าม hardcode /dev/sdX — ดู Improve.md ข้อ 1)

set -e

# ========================= CONFIG — แก้ตรงนี้ก่อนรัน =========================
FSNAME="labfs"
OST_INDEX=0                       # OST ตัวแรก = 0, ตัวที่สอง = 1 (ดู Improve.md ข้อ 4)
OST_MOUNT="/mnt/ost"
OST_LABEL="$(printf '%s-OST%04x' "$FSNAME" "$OST_INDEX")"
MGS_NIDS="mgsmds@tcp0"

HOSTNAME_MGSMDS="mgsmds"; IP_MGSMDS="192.168.100.10"
HOSTNAME_OSS="oss";       IP_OSS="192.168.100.11"
HOSTNAME_CLIENT="client"; IP_CLIENT="192.168.100.12"
# =============================================================================

if [ "$(id -u)" -ne 0 ]; then
  echo "ต้องรันด้วย root/sudo" >&2
  exit 1
fi

echo "=== [1/7] ตั้งค่า /etc/hostname และ /etc/hosts ==="
hostnamectl set-hostname "$HOSTNAME_OSS"
for line in \
  "$IP_MGSMDS $HOSTNAME_MGSMDS" \
  "$IP_OSS $HOSTNAME_OSS" \
  "$IP_CLIENT $HOSTNAME_CLIENT"
do
  grep -qF "$line" /etc/hosts || echo "$line" >> /etc/hosts
done
cat /etc/hosts

echo "=== [2/7] ปิด firewalld + SELinux ==="
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true
setenforce 0 2>/dev/null || true
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config 2>/dev/null || true

echo "=== [3/7] เช็คว่าคุยกับ mgsmds ผ่าน LNet ได้ไหม ==="
if lctl ping "$MGS_NIDS" >/dev/null 2>&1; then
  echo "-> ping $MGS_NIDS สำเร็จ"
else
  echo "!! ping $MGS_NIDS ไม่ผ่าน — เช็ค network/firewalld/lnet บน mgsmds ก่อน แล้วค่อยรันสคริปต์นี้ใหม่" >&2
  exit 1
fi

echo "=== [4/7] เลือก disk สำหรับ OST index $OST_INDEX ==="
lsblk
read -rp "พิมพ์ชื่อ device สำหรับ OST (เช่น sdb, ไม่ต้องใส่ /dev/): " OST_DEV_NAME
OST_DEV="/dev/${OST_DEV_NAME}"

if [ ! -b "$OST_DEV" ]; then
  echo "ไม่พบ device $OST_DEV" >&2
  exit 1
fi

echo "=== [5/7] format เป็น OST (ข้ามถ้า format แล้ว) ==="
EXISTING_LABEL="$(blkid -s LABEL -o value "$OST_DEV" 2>/dev/null || true)"
if [ "$EXISTING_LABEL" = "$OST_LABEL" ]; then
  echo "-> $OST_DEV format เป็น $OST_LABEL อยู่แล้ว ข้ามขั้นตอน mkfs"
else
  echo "!! กำลังจะ format $OST_DEV เป็น OST index=$OST_INDEX — ข้อมูลทั้งหมดบน disk นี้จะหายถาวร !!"
  lsblk "$OST_DEV"
  read -rp "พิมพ์ 'yes' เพื่อยืนยัน format $OST_DEV: " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "ยกเลิก ไม่ format"
    exit 1
  fi
  mkfs.lustre --fsname="$FSNAME" --ost --index="$OST_INDEX" --mgsnode="$MGS_NIDS" "$OST_DEV"
fi

echo "=== [6/7] mount + เขียน fstab ด้วย UUID ==="
mkdir -p "$OST_MOUNT"
mountpoint -q "$OST_MOUNT" || mount -t lustre "$OST_DEV" "$OST_MOUNT"

OST_UUID="$(blkid -s UUID -o value "$OST_DEV")"
if [ -z "$OST_UUID" ]; then
  echo "หา UUID ของ $OST_DEV ไม่เจอ — เช็ค blkid ด้วยมือ" >&2
  exit 1
fi

FSTAB_LINE="UUID=${OST_UUID}   ${OST_MOUNT}    lustre   _netdev,defaults   0 0"
if grep -qF "$OST_MOUNT" /etc/fstab; then
  echo "-> มี entry ของ $OST_MOUNT ใน fstab แล้ว ไม่แก้ทับ (เช็คด้วยมือถ้า UUID เปลี่ยน)"
else
  echo "$FSTAB_LINE" >> /etc/fstab
  echo "-> เพิ่มบรรทัดนี้ใน /etc/fstab:"
  echo "   $FSTAB_LINE"
fi
systemctl daemon-reload

echo "=== [7/7] เสร็จ — สถานะปัจจุบัน ==="
df -h "$OST_MOUNT" || true
lctl dl || true

echo ""
echo "เสร็จ setup_oss.sh — ต่อไปรัน setup_client.sh บนเครื่อง client"
