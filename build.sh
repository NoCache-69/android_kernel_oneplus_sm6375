#!/bin/bash
#
# Kernel build script for OnePlus Nord N30 (larry) with KernelSU support
#

# Exit on any error
set -e

# -----------------
# BUILD CONFIGURATION
# -----------------

# Set your build user and host for the kernel version string
export KBUILD_BUILD_USER="Strato"
export KBUILD_BUILD_HOST="BuildPC"

# Set the architecture and sub-architecture
export ARCH=arm64
export SUBARCH=arm64

# Define the output directory
OUTPUT_DIR="out"

# Device defconfig (holi platform for larry)
DEFCONFIG="larry-strato_defconfig"

# Use system toolchain (set to "true") or custom toolchain (set to "false")
USE_SYSTEM_TOOLCHAIN=false

# Define the path to your custom toolchain directory (only if USE_SYSTEM_TOOLCHAIN=false)
TOOLCHAIN_DIR="../clang-toolchain/prebuilts/clang/host/linux-x86/clang-r547379"

# Set LLVM variable to 1 to enable Clang, change to 0 for GCC.
export LLVM=1

# -----------------
# KERNELSU NEXT SETUP (for GKI 1.0 devices)
# -----------------

#Check if KernelSU Next is already integrated
if [ ! -d "KernelSU-Next" ]; then
    echo "==> KernelSU Next not found. Installing KernelSU Next..."
    curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s next
    echo "==> KernelSU Next installed successfully!"
else
    echo "==> KernelSU Next already installed, skipping..."
fi

# -----------------
# TOOLCHAIN SETUP
# -----------------

if [ "$USE_SYSTEM_TOOLCHAIN" = true ]; then
    echo "==> Using system toolchain (Arch Linux packages)"

    # Verify clang is available
    if ! command -v clang &> /dev/null; then
        echo "ERROR: clang not found! Install with: sudo pacman -S clang lld llvm"
        exit 1
    fi

    # Verify cross-compile tools are available
    if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
        echo "ERROR: aarch64 cross-compiler not found!"
        echo "Install with: sudo pacman -S aarch64-linux-gnu-gcc"
        exit 1
    fi
else
    echo "==> Using custom toolchain from $TOOLCHAIN_DIR"
    # Add the custom toolchain's binaries to the PATH
    export PATH="${PWD}/${TOOLCHAIN_DIR}/bin:$PATH"
fi

# Set cross-compile variables
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-

# -----------------
# BUILD PROCESS
# -----------------
echo "==============================================="
echo "  Kernel Build Script - KernelSU Next Enabled "
echo "==============================================="
echo "Device: OnePlus Nord N30 (larry)"
echo "Platform: Holi (SM6375) - GKI 1.0"
echo "Defconfig: $DEFCONFIG"
echo "==============================================="

# Clean the source tree (optional, use 'make mrproper' for a deeper clean)
echo "==> Cleaning source tree..."
make O=$OUTPUT_DIR mrproper

# Set the kernel configuration file
echo "==> Applying '$DEFCONFIG'..."
make O=$OUTPUT_DIR ARCH=arm64 $DEFCONFIG

# Regenerate config
make O=$OUTPUT_DIR ARCH=arm64 olddefconfig

# Use a menu to edit config
make O=$OUTPUT_DIR ARCH=arm64 nconfig

# Optional: compiler flags for perf parity
export KCFLAGS="-O3 -pipe -fomit-frame-pointer -fno-stack-protector -fno-var-tracking -flto=thin -Wno-error=unused-label"

# Start the compilation process
echo "==> Starting kernel compilation..."
make -j13 O=$OUTPUT_DIR ARCH=arm64 \
    CC=clang \
    LD=ld.lld \
    AR=llvm-ar \
    NM=llvm-nm \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    STRIP=llvm-strip \
    READELF=llvm-readelf \
    OBJSIZE=llvm-size \
    LLVM=1 \
    LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-

# -----------------
# COMPLETION
# -----------------

echo "==============================================="
echo "        Build finished successfully!           "
echo "==============================================="
echo "Kernel Image: ${PWD}/${OUTPUT_DIR}/arch/arm64/boot/Image"
echo ""
echo "Next steps:"
echo "1. Create AnyKernel3 flashable zip"
echo "2. Flash via recovery"
echo "3. Install KernelSU Next Manager APK"
echo "==============================================="
