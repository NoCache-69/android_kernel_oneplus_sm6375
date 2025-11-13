#!/bin/bash
#
# Kernel build script for OnePlus Nord N30 (larry) with KernelSU support
# FIXED: Uses proper toolchain for OnePlus kernel sources
#

# Exit on any error
set -e

# -----------------
# ARGUMENT PARSING
# -----------------

CLEAN_BUILD=false
DEFCONFIG="vendor/larry-stratosphere_defconfig"
TOOLCHAIN_TYPE="system"  # Options: aosp, gcc, system

# Parse arguments
for arg in "$@"; do
    case $arg in
        --clean)
            CLEAN_BUILD=true
            echo "==> Clean build enabled"
            ;;
        --stratosphere)
            DEFCONFIG="vendor/larry-stratosphere_defconfig"
            echo "==> Using Stratosphere config"
            ;;
        --exosphere)
            DEFCONFIG="vendor/larry-exosphere_defconfig"
            echo "==> Using Exosphere config"
            ;;
        --toolchain=*)
            TOOLCHAIN_TYPE="${arg#*=}"
            echo "==> Using toolchain: $TOOLCHAIN_TYPE"
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --clean         Perform a clean build (mrproper)"
            echo "  --stratosphere  Use larry-stratosphere_defconfig"
            echo "  --exosphere     Use larry-exosphere_defconfig"
            echo "  --toolchain=TYPE Use specific toolchain (aosp, gcc, system)"
            echo "  --help, -h      Show this help message"
            echo ""
            echo "Default: Incremental build with larry-stratosphere_defconfig"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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
CONFIG="${PWD}/../../"
OUTPUT_DIR="${CONFIG}/out"

# Define kernel source tree path (absolute path to common/)
KERNEL_SRC="${PWD}"

# -----------------
# TOOLCHAIN SETUP
# -----------------
setup_toolchain() {
    case $TOOLCHAIN_TYPE in
        "aosp")
            echo "==> Using AOSP Clang with standalone GCC"
            if [ ! -d "../toolchains/aosp" ]; then
                echo "==> Downloading AOSP toolchain..."
                mkdir -p ../toolchains
                cd ../toolchains

                # Download AOSP Clang
                wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r487747c.tar.gz
                mkdir aosp && tar -xzf clang-r487747c.tar.gz -C aosp

                # Download AOSP GCC
                wget -q https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-13.0.0_r0.2.tar.gz
                mkdir aosp-gcc && tar -xzf android-13.0.0_r0.2.tar.gz -C aosp-gcc

                rm clang-r487747c.tar.gz android-13.0.0_r0.2.tar.gz
                cd "$KERNEL_SRC"
            fi

            export PATH="${PWD}/../toolchains/aosp/bin:${PWD}/../toolchains/aosp-gcc/bin:${PATH}"
            export CROSS_COMPILE="${PWD}/../toolchains/aosp-gcc/bin/aarch64-linux-android-"
            export CROSS_COMPILE_ARM32="${PWD}/../toolchains/aosp-gcc/bin/arm-linux-androideabi-"
            ;;

        "gcc")
            echo "==> Using pure GCC toolchain"
            # Install if missing
            if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
                echo "ERROR: aarch64 cross-compiler not found!"
                echo "Install with: sudo pacman -S aarch64-linux-gnu-gcc"
                exit 1
            fi
            # Disable Clang for GCC build
            export LLVM=0
            ;;

        "system")
            echo "==> Using standard Linux cross-compiler"
            # Install if missing
            if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
                echo "Installing aarch64 cross-compiler..."
                sudo pacman -S aarch64-linux-gnu-gcc aarch64-linux-gnu-binutils
            fi
            export CROSS_COMPILE="aarch64-linux-gnu-"
            export CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
            ;;

        *)
            echo "ERROR: Unknown toolchain type: $TOOLCHAIN_TYPE"
            echo "Available: aosp, gcc, system"
            exit 1
            ;;
    esac
}

# Setup the selected toolchain
setup_toolchain

# Set cross-compile variables
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export SRCTREE="${KERNEL_SRC}"

# Enable Clang for non-GCC builds
if [ "$TOOLCHAIN_TYPE" != "gcc" ]; then
    export LLVM=1
    export LLVM_IAS=1
fi

# -----------------
# BUILD PROCESS
# -----------------
echo "==============================================="
echo "  Kernel Build Script - Fixed Toolchain"
echo "==============================================="
echo "Device: OnePlus Nord N30 (larry)"
echo "Platform: Holi (SM6375) - GKI 1.0"
echo "Defconfig: $DEFCONFIG"
echo "Clean Build: $CLEAN_BUILD"
echo "Toolchain: $TOOLCHAIN_TYPE"
echo "==============================================="

# Clean the source tree if requested
if [ "$CLEAN_BUILD" = true ]; then
    echo "==> Cleaning source tree (mrproper)..."
    make O=$OUTPUT_DIR mrproper
else
    echo "==> Skipping clean (incremental build)..."
fi

# Set the kernel configuration file
echo "==> Setting up config: $DEFCONFIG"
make O=$OUTPUT_DIR ARCH=arm64 ${DEFCONFIG}

# Regenerate config
make O=$OUTPUT_DIR ARCH=arm64 olddefconfig

export KCFLAGS="-O3 -flto=thin"

# Common make arguments
MAKE_ARGS=(
    -j$(nproc)
    O=$OUTPUT_DIR
    ARCH=arm64
)

# Add Clang-specific args if using Clang
if [ "$TOOLCHAIN_TYPE" != "gcc" ]; then
    MAKE_ARGS+=(
        -j$(nproc)
        CC=clang
        LD=ld.lld
        AR=llvm-ar
        NM=llvm-nm
        OBJCOPY=llvm-objcopy
        OBJDUMP=llvm-objdump
        STRIP=llvm-strip
        LLVM=1
        LLVM_IAS=1
    )
fi

# Add cross-compilation
MAKE_ARGS+=(
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
)

# Start the compilation process
echo "==> Starting kernel compilation..."
echo "Make args: ${MAKE_ARGS[@]}"
make "${MAKE_ARGS[@]}"

# Strip modules in-place
echo "==> Stripping modules..."
if [ "$TOOLCHAIN_TYPE" != "gcc" ]; then
    find "${OUTPUT_DIR}" -name "*.ko" -exec llvm-strip --strip-debug {} \;
else
    find "${OUTPUT_DIR}" -name "*.ko" -exec aarch64-linux-gnu-strip --strip-debug {} \;
fi

# -----------------
# BUILD VERIFICATION
# -----------------

echo ""
echo "==> Build verification..."
if [ -f "${OUTPUT_DIR}/arch/arm64/boot/Image" ]; then
    KERNEL_SIZE=$(stat -c%s "${OUTPUT_DIR}/arch/arm64/boot/Image")
    echo "✓ Kernel Image: $(echo "scale=2; $KERNEL_SIZE/1024/1024" | bc) MB"
else
    echo "✗ Kernel Image not found!"
    exit 1
fi

# Check for DTB files
DTB_COUNT=$(find "${OUTPUT_DIR}/arch/arm64/boot/dts" -name "*.dtb" 2>/dev/null | wc -l)
echo "✓ DTB files: $DTB_COUNT"

MODULE_COUNT=$(find "${OUTPUT_DIR}" -name "*.ko" | wc -l)
echo "✓ Kernel modules: $MODULE_COUNT"

# -----------------
# COMPLETION
# -----------------

echo ""
echo "==============================================="
echo "        Build finished successfully!           "
echo "==============================================="
echo "Toolchain: $TOOLCHAIN_TYPE"
echo "Kernel Image: ${OUTPUT_DIR}/arch/arm64/boot/Image"
echo ""
echo "Next steps:"
echo "1. Run package_kernel.sh to create AnyKernel3 flashable zip"
echo "2. Flash via recovery"
echo "==============================================="
