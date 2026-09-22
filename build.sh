#!/bin/bash

# Compiling Setting
export DEVICE=beyondxks
export MODE=y
export ANDROID_BUILD_TOP=$(pwd)
export AIK_DIR=${ANDROID_BUILD_TOP}/prebuilts/AIK
export OUT_DIR=${ANDROID_BUILD_TOP}/out

# Import KernelSU-Next driver
if [ "${MODE}" == 'ksun' ]; then
    curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/legacy/kernel/setup.sh" | bash -s legacy
fi

# Define specific variables
case ${DEVICE} in
beyondxks)
    BOARD=SRPRK21D006KU
    SOC=exynos9820
    TZDEV=new
;;
*)
    exit
esac
echo -n "${BOARD}" > "${AIK_DIR}/split_img/boot.img-board"

# Add Specific Device DEFCONFIG
echo -e "\nCONFIG_MODEL_${DEVICE^^}=y" >> "${ANDROID_BUILD_TOP}/arch/arm64/configs/${SOC}.config"

# Setting tzdev drvier
# All Galaxy S10 Series and Korean Note 10 Series use new tzdev drvier, but Global Note 10 Series uses old tzdev drvier
# So, we need this file setting codes (Scamsung issue)
rm -rf ${ANDROID_BUILD_TOP}/drivers/misc/tzdev
cp -ar ${ANDROID_BUILD_TOP}/prebuilts/tzdev/tzdev_${TZDEV} ${ANDROID_BUILD_TOP}/drivers/misc/tzdev

# OEM Setting
export ARCH=arm64
export PLATFORM_VERSION=12
export ANDROID_MAJOR_VERSION=s

# Setting toolchain
TOOLCHAIN_URL="https://github.com/GoRhanHee/exynos9820_toolchain/releases/download/toolchain/toolchain.tar.xz"
TOOLCHAIN_FILE=$(basename "$TOOLCHAIN_URL")
if [ ! -f "$TOOLCHAIN_FILE" ]; then
    wget -q -O "$TOOLCHAIN_FILE" "$TOOLCHAIN_URL"
fi
tar -xf "$TOOLCHAIN_FILE" && rm "$TOOLCHAIN_FILE"

# Cooking Kernel Source
MAKE_ARGS="
ARCH=arm64 \
CROSS_COMPILE=${ANDROID_BUILD_TOP}/toolchain/gcc-cfp/gcc-cfp-jopp-only/aarch64-linux-android-4.9/bin/aarch64-linux-android- \
-j4 \
O=out
"

DEFCONFIG="exynos9820-${DEVICE}_defconfig ${SOC}.config"

if [ "${MODE}" == "ksun" ]; then
    CONFIGS="${DEFCONFIG} kernelsu.config"
else
    CONFIGS="${DEFCONFIG}"    
fi

make ${MAKE_ARGS} ${CONFIGS} > /dev/null || exit 1
make ${MAKE_ARGS} > /dev/null || exit 1

# Cooking Ramdisk
cp ${ANDROID_BUILD_TOP}/prebuilts/ramdisk_prop/${DEVICE}.prop ${AIK_DIR}/ramdisk/system/etc/ramdisk/build.prop
cd ${AIK_DIR}/ramdisk
find . | cpio -o -H newc | gzip > ../split_img/boot.img-ramdisk.cpio.gz

cd ${ANDROID_BUILD_TOP}

# Cooking boot.img
cp ${OUT_DIR}/arch/arm64/boot/Image ${AIK_DIR}/split_img/boot.img-kernel
cd ${AIK_DIR} && ./repackimg.sh
cd ${ANDROID_BUILD_TOP}
mv ${AIK_DIR}/image-new.img ${ANDROID_BUILD_TOP}/prebuilts/boot.img

# Cooking dt.img
./prebuilts/mkdtimg cfg_create prebuilts/dt.img prebuilts/dtconfigs/${SOC}.cfg -d ${OUT_DIR}/arch/arm64/boot/dts/exynos

# Cooking dtbo.img
./prebuilts/mkdtimg cfg_create prebuilts/dtbo.img prebuilts/dtconfigs/${DEVICE}.cfg -d ${OUT_DIR}/arch/arm64/boot/dts/samsung

# Copying patched vbmeta.img
cp ${ANDROID_BUILD_TOP}/prebuilts/vbmeta/${DEVICE}.img ${ANDROID_BUILD_TOP}/prebuilts/vbmeta.img

# Cooking flashable tar file
cd ${ANDROID_BUILD_TOP}/prebuilts
zip -r Kernel_for_${DEVICE}_${MODE}.zip META-INF boot.img dt.img dtbo.img
