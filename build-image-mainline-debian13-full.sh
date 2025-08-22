#!/bin/sh

export WORKDIR="$(pwd)"
export PATH="${PATH}:/sbin:/usr/sbin"
DATE_TS="$(date +%Y%m%d)"

IMG_FILE="deploy/rk3576-photonicat2-mainline-debian13-full-${DATE_TS}.img"
ROOTFS_FILE="rootfs/rootfs-debian-full.tar.gz"
ROOTFS_BUILD_SCRIPT="mk-rootfs-debian.sh"
PARTITION_SCRIPT="scripts/photonicat2-disk-parts-full.sfdisk"
BOOTFS_IMG_FILE="rootfs/rk3576-photonicat2-mainline-debian13-full-bootfs.img"
ROOTFS_IMG_FILE="rootfs/rk3576-photonicat2-mainline-debian13-full-rootfs.img"

IMG_SIZE="13312"
BOOTFS_SIZE="256"
ROOTFS_SIZE="12288"

if [ $(id -u) != "0" ]; then
    echo "Need root privilege to create rootfs!"
    exit 1
fi

if [ ! -f "u-boot/idbloader.img" ]; then
    echo "Missing idbloader.img, build u-boot first!"
    exit 2
fi

if [ ! -f "u-boot/u-boot.itb" ]; then
    echo "Missing u-boot.itb, build u-boot first!"
    exit 2
fi

if [ ! -f "kernel/deploy/Image" ]; then
    echo "Missing kernel image, build kernel first!"
    exit 3
fi

if [ ! -f "kernel/deploy/rk3576-photonicat2.dtb" ]; then
    echo "Missing kernel device tree, build kernel first!"
    exit 3
fi

if [ ! -f "kernel/deploy/kmods.tar.gz" ]; then
    echo "Missing kernel modules, build kernel first!"
    exit 3
fi

if [ ! -f "deploy/boot.scr" ]; then
    echo "Missing boot.scr, build boot script first!"
    exit 4
fi

if [ ! -f "${ROOTFS_FILE}" ]; then
    cd "${WORKDIR}/rootfs"
    "./${ROOTFS_BUILD_SCRIPT}"
    cd "${WORKDIR}"
fi

echo "Creating disk image..."
dd if=/dev/zero of="${IMG_FILE}" bs=1M count="${IMG_SIZE}"
sfdisk -X gpt "${IMG_FILE}" < "${PARTITION_SCRIPT}"

echo "Setup bootloader..."
dd if="u-boot/idbloader.img" of="${IMG_FILE}" seek=64 conv=notrunc
dd if="u-boot/u-boot.itb" of="${IMG_FILE}" seek=16384 conv=notrunc

TMP_MOUNT_DIR="$(mktemp -d)"

echo "Creating bootfs..."
dd if=/dev/zero of="${BOOTFS_IMG_FILE}" bs=1M count="${BOOTFS_SIZE}"
mkfs.ext4 -L boot -F "${BOOTFS_IMG_FILE}"

echo "Creating rootfs..."
dd if=/dev/zero of="${ROOTFS_IMG_FILE}" bs=1M count="${ROOTFS_SIZE}"
mkfs.ext4 -L rootfs -F "${ROOTFS_IMG_FILE}"

mkdir -p "${TMP_MOUNT_DIR}/rootfs"
mount "${ROOTFS_IMG_FILE}" "${TMP_MOUNT_DIR}/rootfs"
mkdir -p "${TMP_MOUNT_DIR}/rootfs/boot"
mount "${BOOTFS_IMG_FILE}" "${TMP_MOUNT_DIR}/rootfs/boot"
tar -xpf "${ROOTFS_FILE}" --xattrs --xattrs-include='*' -C "${TMP_MOUNT_DIR}/rootfs"
mkdir -p "${TMP_MOUNT_DIR}/rootfs/repo"
cp "${WORKDIR}/kernel/deploy/linux-"*.deb "${TMP_MOUNT_DIR}/rootfs/repo/"
cp "${WORKDIR}/external/drivers/aic8800/"*.deb "${TMP_MOUNT_DIR}/rootfs/repo/"
cp "${WORKDIR}/deploy/boot.scr" "${TMP_MOUNT_DIR}/rootfs/boot/"

KERNEL_DEB_FULL_PATH="$(ls ${TMP_MOUNT_DIR}/rootfs/repo/linux-image-*_arm64.deb | grep -v dbg | head -n 1)"
KERNEL_DEB="$(basename ${KERNEL_DEB_FULL_PATH})"

mount --bind /dev "${TMP_MOUNT_DIR}/rootfs/dev"
mount --bind /proc "${TMP_MOUNT_DIR}/rootfs/proc"

cat << EOF | chroot "${TMP_MOUNT_DIR}/rootfs"

dpkg -i /repo/linux-headers-*_arm64.deb
dpkg -i "/repo/${KERNEL_DEB}"
dpkg -i /repo/aic8800-*.deb
EOF

sleep 15
sync

umount -f "${TMP_MOUNT_DIR}/rootfs/dev"
umount -f "${TMP_MOUNT_DIR}/rootfs/proc"

umount -f "${TMP_MOUNT_DIR}/rootfs/boot"
umount -f "${TMP_MOUNT_DIR}/rootfs"
rmdir "${TMP_MOUNT_DIR}/rootfs"
gzip -f "${ROOTFS_IMG_FILE}"
gzip -f "${BOOTFS_IMG_FILE}"

rmdir "${TMP_MOUNT_DIR}"

echo "Making system image..."
zcat "${BOOTFS_IMG_FILE}.gz" | dd of="${IMG_FILE}" bs=1M seek=32 conv=notrunc
zcat "${ROOTFS_IMG_FILE}.gz" | dd of="${IMG_FILE}" bs=1M seek="$(expr 32 + ${BOOTFS_SIZE})" conv=notrunc
gzip -f "${IMG_FILE}"
echo "Create system image completed."
