#!/bin/sh

ARCHIVE_DIR="archives"
export WORKDIR="$(pwd)"

UBOOT_REPO="https://github.com/radxa/u-boot"
UBOOT_VERSION="next-dev-v2024.10"
KERNEL_VERSION="linux-6.12.5"

KERNEL_ARCHIVE="${KERNEL_VERSION}.tar.xz"

KERNEL_SITE="https://cdn.kernel.org/pub/linux/kernel/v6.x/${KERNEL_ARCHIVE}"
JOBS="4"

if [ ! -f "${ARCHIVE_DIR}/${KERNEL_ARCHIVE}" ]; then
    wget -O "${ARCHIVE_DIR}/${KERNEL_ARCHIVE}" "${KERNEL_SITE}"
fi

if [ ! -d "u-boot" ]; then
    git clone "${UBOOT_REPO}" -b "${UBOOT_VERSION}" u-boot

    cd "${WORKDIR}/u-boot"
    for i in "${WORKDIR}/patches/u-boot/"*; do patch -p1 < "${i}"; done 
    cd "${WORKDIR}"
fi


echo "Building u-boot..."
cd u-boot

make rk3576_defconfig
sed -i "s#CONFIG_MKIMAGE_DTC_PATH=.*#CONFIG_MKIMAGE_DTC_PATH=\"${WORKDIR}/u-boot/scripts/dtc/dtc\"#g" .config
sed -i "s#CONFIG_RADXA_IMG=.*#CONFIG_RADXA_IMG=n#g" .config
make BL31="${WORKDIR}/rkbin/bin/rk35/rk3576_bl31_v1.12.elf" spl/u-boot-spl.bin u-boot.dtb u-boot.itb -j${JOBS}
tools/mkimage -n rk3576 -T rksd -d "${WORKDIR}/rkbin/bin/rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin":spl/u-boot-spl.bin idbloader.img
cd ..

if [ ! -d "kernel" ]; then
    tar -xJf "${ARCHIVE_DIR}/${KERNEL_ARCHIVE}"
    mv "${KERNEL_VERSION}" kernel

    cd "${WORKDIR}/kernel"
    for i in "${WORKDIR}/patches/kernel/"*; do patch -Np1 < "${i}"; done
    cp -rf "${WORKDIR}/patches/kernel-overlay/." ./

    cd "${WORKDIR}"
fi

echo "Building kernel..."

cd "${WORKDIR}/kernel"
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
mkdir -p build deploy/modules
make O=build photonicat2_defconfig
make O=build Image -j${JOBS}
make O=build modules -j${JOBS}
make O=build rockchip/rk3576-photonicat2.dtb
cp -v build/arch/arm64/boot/Image deploy/
cp -v build/arch/arm64/boot/dts/rockchip/rk3576-photonicat2.dtb deploy/
make O=build modules_install INSTALL_MOD_PATH="${WORKDIR}/kernel/deploy/modules" INSTALL_MOD_STRIP=1
tar --owner=0 --group=0 --xform s:'^./':: -czf deploy/kmods.tar.gz -C "${WORKDIR}/kernel/deploy/modules" .
cd "${WORKDIR}"

mkdir -p deploy
mkimage -A arm -O linux -T script -C none -a 0 -e 0 -d scripts/photonicat2.bootscript deploy/boot.scr

#dd if="u-boot/deploy/idbloader.img" of="${IMG_FILE}" seek=64 conv=notrunc
#dd if="u-boot/deploy/u-boot.itb" of="${IMG_FILE}" seek=16384 conv=notrunc
