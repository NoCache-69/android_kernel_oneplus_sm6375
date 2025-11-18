#!/bin/bash
#
# Kernel build script for OnePlus Nord N30 (larry) with KernelSU support
# FIXED: Uses proper toolchain for OnePlus kernel sources
# Added: Profile-Guided Optimization (PGO) support for both GCC and Clang
# Added: DTB/DTBO building support
#

# Exit on any error
set -e

# -----------------
# ARGUMENT PARSING
# -----------------

CLEAN_BUILD=false
DEFCONFIG="vendor/larry-exosphere_defconfig"
TOOLCHAIN_TYPE="system"  # Options: aosp, gcc, system
PGO_PHASE="none"  # Options: none, instrument, optimize
PGO_COMPILER="none"  # Options: detect, gcc, clang

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
        --pgo-instrument)
            PGO_PHASE="instrument"
            echo "==> PGO: Building instrumented kernel for profiling"
            ;;
        --pgo-optimize)
            PGO_PHASE="optimize"
            echo "==> PGO: Building optimized kernel using profile data"
            ;;
        --pgo-compiler=*)
            PGO_COMPILER="${arg#*=}"
            echo "==> PGO compiler type: $PGO_COMPILER"
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --clean           Perform a clean build (mrproper)"
            echo "  --stratosphere    Use larry-stratosphere_defconfig"
            echo "  --exosphere       Use larry-exosphere_defconfig"
            echo "  --toolchain=TYPE  Use specific toolchain (aosp, gcc, system)"
            echo "  --pgo-instrument  Build with profiling instrumentation (Phase 1)"
            echo "  --pgo-optimize    Build with PGO optimization (Phase 2)"
            echo "  --pgo-compiler=TYPE  Force PGO method (gcc, clang, detect)"
            echo "  --help, -h        Show this help message"
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
export KBUILD_BUILD_USER="Strato"
export KBUILD_BUILD_HOST="BuildPC"
export ARCH=arm64
export SUBARCH=arm64

CONFIG="${PWD}/.."
OUTPUT_DIR="${CONFIG}/out"
KERNEL_SRC="${PWD}"

PGO_GCOV_DIR="${OUTPUT_DIR}"
PGO_CLANG_DIR="${KERNEL_SRC}/../kernel_pgo_profiles/run1/pgo"

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

                wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r487747c.tar.gz
                mkdir aosp && tar -xzf clang-r487747c.tar.gz -C aosp

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
            if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
                echo "ERROR: aarch64 cross-compiler not found!"
                echo "Install with: sudo pacman -S aarch64-linux-gnu-gcc"
                exit 1
            fi
            export LLVM=0
            ;;

        "system")
            echo "==> Using standard Linux cross-compiler"
            if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
                echo "Installing aarch64 cross-compiler..."
                sudo pacman -S aarch64-linux-gnu-gcc aarch64-linux-gnu-binutils
            fi
            export CROSS_COMPILE="aarch64-linux-gnu-"
            export CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
            ;;

        *)
            echo "ERROR: Unknown toolchain type: $TOOLCHAIN_TYPE"
            exit 1
            ;;
    esac
}

setup_toolchain

export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export SRCTREE="${KERNEL_SRC}"

if [ "$TOOLCHAIN_TYPE" != "gcc" ]; then
    export LLVM=1
    export LLVM_IAS=1
fi

if [ "$PGO_COMPILER" = "detect" ]; then
    if [ "$TOOLCHAIN_TYPE" = "gcc" ]; then
        PGO_COMPILER="gcc"
    else
        PGO_COMPILER="clang"
    fi
elif [ "$PGO_COMPILER" = "none" ]; then
        PGO_COMPILER="none"
fi

# -----------------
# PGO CONFIGURATION
# -----------------
setup_pgo() {
    if [ "$PGO_PHASE" = "instrument" ]; then
        echo "==> Configuring PGO instrumentation build (${PGO_COMPILER})..."

        if [ "$PGO_COMPILER" = "gcc" ]; then
            echo "==> Using GCC GCOV profiling..."
            scripts/config --file "${OUTPUT_DIR}/.config" \
                --enable GCOV_KERNEL \
                --enable GCOV_PROFILE_ALL \
                --disable COMPILE_TEST

            make O=$OUTPUT_DIR ARCH=arm64 olddefconfig

        elif [ "$PGO_COMPILER" = "clang" ]; then
            echo "==> Using Clang PGO profiling..."
            scripts/config --file "${OUTPUT_DIR}/.config" \
                --enable PGO_CLANG \
                --disable COMPILE_TEST

            make O=$OUTPUT_DIR ARCH=arm64 olddefconfig
        fi

    elif [ "$PGO_PHASE" = "optimize" ]; then
        echo "==> Configuring PGO optimized build (${PGO_COMPILER})..."

        if [ "$PGO_COMPILER" = "gcc" ]; then
            echo "==> Using GCC profile data..."
            GCDA_COUNT=$(find "${PGO_GCOV_DIR}" -name "*.gcda" 2>/dev/null | wc -l)
            if [ "$GCDA_COUNT" -eq 0 ]; then
                echo "ERROR: No .gcda files found in ${PGO_GCOV_DIR}"
                exit 1
            fi
            echo "✓ Found ${GCDA_COUNT} .gcda profile files"

        elif [ "$PGO_COMPILER" = "clang" ]; then
            echo "==> Using Clang profile data..."

            if [ -d "$PGO_CLANG_DIR" ]; then
                PROFRAW_COUNT=$(find "${PGO_CLANG_DIR}" -name "*.profraw" 2>/dev/null | wc -l)
                if [ "$PROFRAW_COUNT" -gt 0 ]; then
                    echo "✓ Found ${PROFRAW_COUNT} .profraw files"

                    LLVM_PROFDATA=$(command -v llvm-profdata 2>/dev/null || echo "")
                    if [ -z "$LLVM_PROFDATA" ]; then
                        echo "ERROR: llvm-profdata not found!"
                        exit 1
                    fi

                    echo "==> Merging profile data..."
                    PROFDATA_FILE="${KERNEL_SRC}/vmlinux.profdata"
                    $LLVM_PROFDATA merge -output="${PROFDATA_FILE}" \
                        $(find "${PGO_CLANG_DIR}" -name "*.profraw")

                    export KCFLAGS="${KCFLAGS} -fprofile-use=${PROFDATA_FILE}"
                    export KCPPFLAGS="${KCPPFLAGS} -fprofile-use=${PROFDATA_FILE}"
                    echo "✓ Using merged profile: ${PROFDATA_FILE}"
                else
                    echo "ERROR: No .profraw files found"
                    exit 1
                fi
            else
                echo "ERROR: PGO data directory not found"
                exit 1
            fi
        fi
    fi
}

# -----------------
# BUILD PROCESS
# -----------------
echo "==============================================="
echo "  Kernel Build Script - DTB/DTBO Support"
echo "==============================================="
echo "Device: OnePlus Nord N30 (larry)"
echo "Platform: Holi (SM6375) - GKI 1.0"
echo "Defconfig: $DEFCONFIG"
echo "Clean Build: $CLEAN_BUILD"
echo "Toolchain: $TOOLCHAIN_TYPE"
echo "PGO Phase: $PGO_PHASE"
echo "PGO Compiler: $PGO_COMPILER"
echo "==============================================="

if [ "$CLEAN_BUILD" = true ]; then
    echo "==> Cleaning source tree (mrproper)..."
    make O=$OUTPUT_DIR mrproper
else
    echo "==> Skipping clean (incremental build)..."
fi

echo "==> Setting up config: $DEFCONFIG"
make O=$OUTPUT_DIR ARCH=arm64 ${DEFCONFIG}
make O=$OUTPUT_DIR ARCH=arm64 olddefconfig
make O=$OUTPUT_DIR ARCH=arm64 nconfig

setup_pgo

MAKE_ARGS=(
    -j$(nproc)
    O=$OUTPUT_DIR
    ARCH=arm64
)

if [ "$TOOLCHAIN_TYPE" != "gcc" ]; then
    MAKE_ARGS+=(
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

MAKE_ARGS+=(
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
)

echo "==> Starting kernel compilation..."

if [ "$PGO_PHASE" != "instrument" ]; then
    if [ "$TOOLCHAIN_TYPE" != "gcc" ]; then
        export KCFLAGS="-O3 -flto=thin -march=armv8.2-a+crypto+dotprod"
    else
        export KCFLAGS="-O3 -flto -march=armv8.2-a+crypto+dotprod"
    fi
else
    export KCFLAGS="-O3"
fi

echo "KCFLAGS: ${KCFLAGS}"

# Build kernel and DTBs
make "${MAKE_ARGS[@]}"

# Build DTBs explicitly
echo "==> Building device tree blobs..."
make "${MAKE_ARGS[@]}" dtbs

if [ "$PGO_PHASE" != "instrument" ]; then
    echo "==> Stripping modules..."
    if [ "$TOOLCHAIN_TYPE" != "gcc" ]; then
        find "${OUTPUT_DIR}" -name "*.ko" -exec llvm-strip --strip-debug {} \;
    else
        find "${OUTPUT_DIR}" -name "*.ko" -exec aarch64-linux-gnu-strip --strip-debug {} \;
    fi
else
    echo "==> Skipping module stripping (instrumented build)"
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

DTB_COUNT=$(find "${OUTPUT_DIR}/arch/arm64/boot/dts" -name "*.dtb" 2>/dev/null | wc -l)
echo "✓ DTB files: $DTB_COUNT"

MODULE_COUNT=$(find "${OUTPUT_DIR}" -name "*.ko" | wc -l)
echo "✓ Kernel modules: $MODULE_COUNT"

# -----------------
# BUILD DTB/DTBO IMAGES
# -----------------
echo ""
echo "==> Creating DTB/DTBO images..."

# Run the DTB build script
if [ -f "../build_dtbs.sh" ]; then
    bash ../build_dtbs.sh
else
    echo "WARNING: build_dtbs.sh not found, skipping DTB/DTBO image creation"
    echo "Run build_dtbs.sh manually after build completes"
fi

# -----------------
# COMPLETION
# -----------------

echo ""
echo "==============================================="
echo "        Build finished successfully!           "
echo "==============================================="
echo "Toolchain: $TOOLCHAIN_TYPE"
echo "PGO Phase: $PGO_PHASE ($PGO_COMPILER)"
echo "Kernel Image: ${OUTPUT_DIR}/arch/arm64/boot/Image"
if [ -f "${OUTPUT_DIR}/dtb.img" ]; then
    echo "DTB Image:    ${OUTPUT_DIR}/dtb.img"
fi
if [ -f "${OUTPUT_DIR}/dtbo.img" ]; then
    echo "DTBO Image:   ${OUTPUT_DIR}/dtbo.img"
fi
echo ""
echo "Next steps:"
echo "1. Run package_kernel.sh to create AnyKernel3 flashable zip"
echo "2. Flash via recovery"
echo "==============================================="