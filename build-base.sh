#!/bin/sh


echo "Building u-boot..."
cd u-boot
export WORKDIR="$(pwd)"
#for i in "../patches/u-boot/"*; do patch -Np1 < "${i}"; done

make rk3576_defconfig
sed -i "s#CONFIG_MKIMAGE_DTC_PATH=.*#CONFIG_MKIMAGE_DTC_PATH=\"${WORKDIR}/scripts/dtc/dtc\"#g" .config
sed -i "s#CONFIG_RADXA_IMG=.*#CONFIG_RADXA_IMG=n#g" .config
make BL31="${WORKDIR}/../rkbin/bin/rk35/rk3576_bl31_v1.12.elf" spl/u-boot-spl.bin u-boot.dtb u-boot.itb -j8
tools/mkimage -n rk3576 -T rksd -d "${WORKDIR}/../rkbin/bin/rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin":spl/u-boot-spl.bin idbloader.img
cd ..

#dd if="u-boot/deploy/idbloader.img" of="${IMG_FILE}" seek=64 conv=notrunc
#dd if="u-boot/deploy/u-boot.itb" of="${IMG_FILE}" seek=16384 conv=notrunc
