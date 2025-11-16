#!/bin/bash
#
# Kernel build script for OnePlus Nord N30 (larry) with KernelSU support
# FIXED: Uses proper toolchain for OnePlus kernel sources
# Added: Profile-Guided Optimization (PGO) support for both GCC and Clang
#

# Exit on any error
set -e

# -----------------
# ARGUMENT PARSING
# -----------------

CLEAN_BUILD=false
DEFCONFIG="vendor/larry-stratosphere_defconfig"
TOOLCHAIN_TYPE="system"  # Options: aosp, gcc, system
PGO_PHASE="none"  # Options: none, instrument, optimize
PGO_COMPILER="detect"  # Options: detect, gcc, clang

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
            echo "PGO Workflows:"
            echo ""
            echo "=== GCC PGO (uses GCOV) ==="
            echo "  1. ./build_pgo.sh --pgo-instrument --toolchain=gcc"
            echo "  2. Flash kernel, run benchmarks for 30+ minutes"
            echo "  3. adb shell 'mount -t debugfs none /sys/kernel/debug'"
            echo "  4. adb shell 'cp -r /sys/kernel/debug/gcov /data/local/tmp/gcov_data'"
            echo "  5. adb pull /data/local/tmp/gcov_data ~/kernel_gcov_profiles/run1/"
            echo "  6. cd ~/kernel_gcov_profiles/run1/gcov/home/.../out/"
            echo "  7. cp -r --parents \$(find . -name '*.gcda') ~/android/.../out/"
            echo "  8. ./build_pgo.sh --pgo-optimize --toolchain=gcc"
            echo ""
            echo "=== Clang PGO (uses LLVM profiling) ==="
            echo "  1. ./build_pgo.sh --pgo-instrument --toolchain=system (or aosp)"
            echo "  2. Flash kernel, run benchmarks for 30+ minutes"
            echo "  3. adb shell 'mount -t debugfs none /sys/kernel/debug'"
            echo "  4. adb shell 'cp -r /sys/kernel/debug/pgo /data/local/tmp/pgo_data'"
            echo "  5. adb pull /data/local/tmp/pgo_data ~/kernel_pgo_profiles/run1/"
            echo "  6. ./build_pgo.sh --pgo-optimize --toolchain=system"
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
CONFIG="${PWD}/../"
OUTPUT_DIR="${CONFIG}/out"

# Define kernel source tree path (absolute path to common/)
KERNEL_SRC="${PWD}"

# PGO data directories
PGO_GCOV_DIR="${OUTPUT_DIR}"  # For GCC .gcda files
PGO_CLANG_DIR="${KERNEL_SRC}/../kernel_pgo_profiles/run1/pgo"  # For Clang .profraw

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

# Detect PGO compiler type if auto
if [ "$PGO_COMPILER" = "detect" ]; then
    if [ "$TOOLCHAIN_TYPE" = "gcc" ]; then
        PGO_COMPILER="gcc"
    else
        PGO_COMPILER="clang"
    fi
fi

# -----------------
# PGO CONFIGURATION
# -----------------
setup_pgo() {
    if [ "$PGO_PHASE" = "instrument" ]; then
        echo "==> Configuring PGO instrumentation build (${PGO_COMPILER})..."

        if [ "$PGO_COMPILER" = "gcc" ]; then
            echo "==> Using GCC GCOV profiling..."
            # Enable GCOV profiling via kernel config
            scripts/config --file "${OUTPUT_DIR}/.config" \
                --enable GCOV_KERNEL \
                --enable GCOV_PROFILE_ALL \
                --disable COMPILE_TEST

            # Regenerate config to apply changes
            make O=$OUTPUT_DIR ARCH=arm64 olddefconfig

        elif [ "$PGO_COMPILER" = "clang" ]; then
            echo "==> Using Clang PGO profiling..."
            # Enable Clang's kernel PGO support
            scripts/config --file "${OUTPUT_DIR}/.config" \
                --enable PGO_CLANG \
                --disable COMPILE_TEST

            # Regenerate config
            make O=$OUTPUT_DIR ARCH=arm64 olddefconfig
        fi

    elif [ "$PGO_PHASE" = "optimize" ]; then
        echo "==> Configuring PGO optimized build (${PGO_COMPILER})..."

        if [ "$PGO_COMPILER" = "gcc" ]; then
            echo "==> Using GCC profile data..."
            # Check for .gcda files
            GCDA_COUNT=$(find "${PGO_GCOV_DIR}" -name "*.gcda" 2>/dev/null | wc -l)
            if [ "$GCDA_COUNT" -eq 0 ]; then
                echo "ERROR: No .gcda files found in ${PGO_GCOV_DIR}"
                echo "Please copy profile data first!"
                exit 1
            fi
            echo "✓ Found ${GCDA_COUNT} .gcda profile files"
            # GCC auto-detects .gcda files, no explicit flags needed

        elif [ "$PGO_COMPILER" = "clang" ]; then
            echo "==> Using Clang profile data..."

            # Look for .profraw files to merge
            if [ -d "$PGO_CLANG_DIR" ]; then
                PROFRAW_COUNT=$(find "${PGO_CLANG_DIR}" -name "*.profraw" 2>/dev/null | wc -l)
                if [ "$PROFRAW_COUNT" -gt 0 ]; then
                    echo "✓ Found ${PROFRAW_COUNT} .profraw files"

                    # Find llvm-profdata
                    LLVM_PROFDATA=$(command -v llvm-profdata 2>/dev/null || echo "")
                    if [ -z "$LLVM_PROFDATA" ]; then
                        echo "ERROR: llvm-profdata not found!"
                        echo "Install with: sudo pacman -S llvm"
                        exit 1
                    fi

                    # Merge profile data
                    echo "==> Merging profile data..."
                    PROFDATA_FILE="${KERNEL_SRC}/vmlinux.profdata"
                    $LLVM_PROFDATA merge -output="${PROFDATA_FILE}" \
                        $(find "${PGO_CLANG_DIR}" -name "*.profraw")

                    # Use merged profile
                    export KCFLAGS="${KCFLAGS} -fprofile-use=${PROFDATA_FILE}"
                    export KCPPFLAGS="${KCPPFLAGS} -fprofile-use=${PROFDATA_FILE}"
                    echo "✓ Using merged profile: ${PROFDATA_FILE}"
                else
                    echo "ERROR: No .profraw files found in ${PGO_CLANG_DIR}"
                    exit 1
                fi
            else
                echo "ERROR: PGO data directory not found: ${PGO_CLANG_DIR}"
                echo "Please collect profile data first!"
                exit 1
            fi
        fi
    fi
}

# -----------------
# BUILD PROCESS
# -----------------
echo "==============================================="
echo "  Kernel Build Script - Dual PGO Support"
echo "==============================================="
echo "Device: OnePlus Nord N30 (larry)"
echo "Platform: Holi (SM6375) - GKI 1.0"
echo "Defconfig: $DEFCONFIG"
echo "Clean Build: $CLEAN_BUILD"
echo "Toolchain: $TOOLCHAIN_TYPE"
echo "PGO Phase: $PGO_PHASE"
echo "PGO Compiler: $PGO_COMPILER"
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

# Setup PGO flags if needed
setup_pgo

# Common make arguments
MAKE_ARGS=(
    -j$(nproc)
    O=$OUTPUT_DIR
    ARCH=arm64
)

# Add Clang-specific args if using Clang
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

# Add cross-compilation
MAKE_ARGS+=(
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
)

# Start the compilation process
echo "==> Starting kernel compilation..."
echo "Make args: ${MAKE_ARGS[@]}"

# Set optimization flags (base O3 + LTO, PGO flags added by setup_pgo)
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

make "${MAKE_ARGS[@]}"

# Strip modules in-place (skip for instrumented builds to preserve profiling info)
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
echo "PGO Phase: $PGO_PHASE ($PGO_COMPILER)"
echo "Kernel Image: ${OUTPUT_DIR}/arch/arm64/boot/Image"
echo ""

if [ "$PGO_PHASE" = "instrument" ]; then
    echo "Next steps for PGO:"
    echo "1. Flash this instrumented kernel"
    echo "2. Run benchmarks for 30+ minutes"
    echo ""
    if [ "$PGO_COMPILER" = "gcc" ]; then
        echo "3. Collect GCC profile data:"
        echo "   adb shell 'mount -t debugfs none /sys/kernel/debug'"
        echo "   adb shell 'cp -r /sys/kernel/debug/gcov /data/local/tmp/gcov_data'"
        echo "   adb pull /data/local/tmp/gcov_data ~/kernel_gcov_profiles/run1/"
        echo "   cd ~/kernel_gcov_profiles/run1/gcov/home/.../out/"
        echo "   cp -r --parents \$(find . -name '*.gcda') ${OUTPUT_DIR}/"
    else
        echo "3. Collect Clang profile data:"
        echo "   adb shell 'mount -t debugfs none /sys/kernel/debug'"
        echo "   adb shell 'cp -r /sys/kernel/debug/pgo /data/local/tmp/pgo_data'"
        echo "   adb pull /data/local/tmp/pgo_data ${PGO_CLANG_DIR}/../"
    fi
    echo ""
    echo "4. Build optimized kernel: ./build_pgo.sh --pgo-optimize --toolchain=${TOOLCHAIN_TYPE}"

elif [ "$PGO_PHASE" = "optimize" ]; then
    echo "PGO-optimized kernel built successfully!"
    echo "This kernel is optimized based on your usage patterns."
else
    echo "Next steps:"
    echo "1. Run package_kernel.sh to create AnyKernel3 flashable zip"
    echo "2. Flash via recovery"
    echo ""
    echo "For PGO optimization:"
    echo "  ./build_pgo.sh --pgo-instrument [--toolchain=gcc or system]"
fi
echo "==============================================="
