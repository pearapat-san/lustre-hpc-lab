#!/bin/bash
# setup_client.sh — ตั้งค่า client node ของ Lustre lab (labfs)
# รันบน client ด้วยสิทธิ์ root: sudo bash setup_client.sh
# ต้องรัน setup_mgsmds.sh และ setup_oss.sh ให้เสร็จก่อน
#
# ทำ: /etc/hosts, ปิด firewalld/SELinux, mount labfs, เขียน /etc/fstab
# (client mount ผ่าน network path ไม่ใช่ device ตรงๆ เลยไม่มีปัญหา UUID/device สลับ)

set -e

# ========================= CONFIG — แก้ตรงนี้ก่อนรัน =========================
FSNAME="labfs"
LABFS_MOUNT="/mnt/labfs"
MGS_NIDS="mgsmds@tcp0"

HOSTNAME_MGSMDS="mgsmds"; IP_MGSMDS="192.168.100.10"
HOSTNAME_OSS="oss";       IP_OSS="192.168.100.11"
HOSTNAME_CLIENT="client"; IP_CLIENT="192.168.100.12"
# =============================================================================

if [ "$(id -u)" -ne 0 ]; then
  echo "ต้องรันด้วย root/sudo" >&2
  exit 1
fi

echo "=== [1/6] ตั้งค่า /etc/hostname และ /etc/hosts ==="
hostnamectl set-hostname "$HOSTNAME_CLIENT"
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

echo "=== [3/6] เช็คว่าคุยกับ mgsmds และ oss ผ่าน LNet ได้ไหม ==="
FAIL=0
for nid in "mgsmds@tcp0" "oss@tcp0"; do
  if lctl ping "$nid" >/dev/null 2>&1; then
    echo "-> ping $nid สำเร็จ"
  else
    echo "!! ping $nid ไม่ผ่าน" >&2
    FAIL=1
  fi
done
if [ "$FAIL" -eq 1 ]; then
  echo "แก้ network/firewalld ให้ผ่านก่อน แล้วรันสคริปต์นี้ใหม่" >&2
  exit 1
fi

echo "=== [4/6] mount labfs ==="
mkdir -p "$LABFS_MOUNT"
mountpoint -q "$LABFS_MOUNT" || mount -t lustre "${MGS_NIDS}:/${FSNAME}" "$LABFS_MOUNT"

echo "=== [5/6] เขียน /etc/fstab ==="
FSTAB_LINE="${MGS_NIDS}:/${FSNAME}   ${LABFS_MOUNT}   lustre   _netdev,defaults   0 0"
if grep -qF "$LABFS_MOUNT" /etc/fstab; then
  echo "-> มี entry ของ $LABFS_MOUNT ใน fstab แล้ว ไม่แก้ทับ"
else
  echo "$FSTAB_LINE" >> /etc/fstab
  echo "-> เพิ่มบรรทัดนี้ใน /etc/fstab:"
  echo "   $FSTAB_LINE"
fi
systemctl daemon-reload

echo "=== [6/6] เสร็จ — ทดสอบเขียน/อ่านไฟล์ ==="
df -h "$LABFS_MOUNT" || true
lfs df -h || true
TESTFILE="${LABFS_MOUNT}/setup_test.txt"
echo "setup_client.sh ok $(date)" > "$TESTFILE" && cat "$TESTFILE" && rm -f "$TESTFILE"

echo ""
echo "เสร็จ setup_client.sh — labfs mount แล้วที่ $LABFS_MOUNT"
