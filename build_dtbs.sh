#!/bin/bash
#
# DTBO Build Script for OnePlus Nord N30 (larry)
# For devices with DTBO partition only (base DTB appended to kernel)
#

set -e

# Configuration
OUTPUT_DIR="${PWD}/../out"
KERNEL_IMAGE="${OUTPUT_DIR}/arch/arm64/boot/Image"
DTB_DIR="${OUTPUT_DIR}/arch/arm64/boot/dts/vendor"
TOOLS_DIR="${PWD}/../tools"

# Output files
KERNEL_DTB="${OUTPUT_DIR}/Image-dtb"
DTBO_IMG="${OUTPUT_DIR}/dtbo.img"

echo "==============================================="
echo "  DTBO Build Script for Larry (Holi)"
echo "  Mode: DTB appended to kernel + DTBO partition"
echo "==============================================="

# -----------------
# SETUP MKDTIMG TOOL
# -----------------
setup_mkdtimg() {
    mkdir -p "${TOOLS_DIR}"

    # Try system mkdtimg first
    if command -v mkdtimg &> /dev/null; then
        MKDTIMG_CMD="mkdtimg"
        echo "✓ Using system mkdtimg"
        return 0
    fi

    # Check for our Python version
    if [ -f "${TOOLS_DIR}/mkdtimg.py" ]; then
        chmod +x "${TOOLS_DIR}/mkdtimg.py"
        MKDTIMG_CMD="${TOOLS_DIR}/mkdtimg.py"
        echo "✓ Using Python mkdtimg"
        return 0
    fi

    # Try to build from source
    if [ -f "${TOOLS_DIR}/mkdtimg" ]; then
        MKDTIMG_CMD="${TOOLS_DIR}/mkdtimg"
        echo "✓ Using built mkdtimg"
        return 0
    fi

    echo "ERROR: mkdtimg not found!"
    echo ""
    echo "Options:"
    echo "1. Use Python version (recommended for Arch):"
    echo "   Save mkdtimg.py to ${TOOLS_DIR}/ and re-run"
    echo ""
    echo "2. Build from source:"
    echo "   Run: ./build_mkdtimg.sh"
    echo ""
    echo "3. Install from AUR:"
    echo "   yay -S android-tools"
    exit 1
}

# -----------------
# APPEND DTB TO KERNEL
# -----------------
append_dtb_to_kernel() {
    echo ""
    echo "==> Appending DTB to kernel Image..."

    # Find larry DTB first (your specific device)
    DTB_FILE=$(find "${DTB_DIR}/larry" -name "blair-larry.dtb" 2>/dev/null | head -1)

    if [ -z "$DTB_FILE" ]; then
        # Fallback: try qcom directory
        DTB_FILE=$(find "${DTB_DIR}/qcom" -name "blair.dtb" 2>/dev/null | head -1)
    fi

    if [ -z "$DTB_FILE" ]; then
        # Last resort: find any blair DTB
        DTB_FILE=$(find "${DTB_DIR}" -name "blair*.dtb" ! -name "*-overlay.dtb" 2>/dev/null | head -1)
    fi

    if [ -z "$DTB_FILE" ]; then
        echo "ERROR: No base DTB files found in ${DTB_DIR}"
        echo "Available DTBs:"
        find "${DTB_DIR}" -name "*.dtb" | sed 's/^/  /'
        exit 1
    fi

    echo "Using base DTB: $(basename $DTB_FILE)"
    echo "Full path: $DTB_FILE"

    # Append DTB to kernel
    cat "${KERNEL_IMAGE}" "$DTB_FILE" > "${KERNEL_DTB}"

    KERNEL_SIZE=$(stat -c%s "${KERNEL_IMAGE}" 2>/dev/null)
    DTB_SIZE=$(stat -c%s "$DTB_FILE" 2>/dev/null)
    TOTAL_SIZE=$(stat -c%s "${KERNEL_DTB}" 2>/dev/null)

    KERNEL_MB=$(echo "scale=2; $KERNEL_SIZE/1024/1024" | bc)
    DTB_KB=$(echo "scale=2; $DTB_SIZE/1024" | bc)
    TOTAL_MB=$(echo "scale=2; $TOTAL_SIZE/1024/1024" | bc)

    echo "✓ Kernel+DTB image created:"
    echo "  - Kernel: ${KERNEL_MB} MB"
    echo "  - DTB:    ${DTB_KB} KB"
    echo "  - Total:  ${TOTAL_MB} MB"
    echo "  - Output: ${KERNEL_DTB}"
}

# -----------------
# BUILD DTBO IMAGE
# -----------------
build_dtbo_image() {
    echo ""
    echo "==> Building DTBO image..."

    # Find all overlay DTBs (search all vendor subdirs)
    DTBO_FILES=$(find "${DTB_DIR}" -name "*-overlay.dtb" 2>/dev/null | sort)

    if [ -z "$DTBO_FILES" ]; then
        echo "INFO: No DTBO overlay files found"
        echo "This is normal if your device doesn't use device tree overlays"
        echo "Skipping DTBO image creation..."
        return 0
    fi

    DTBO_COUNT=$(echo "$DTBO_FILES" | wc -l)
    echo "Found ${DTBO_COUNT} DTBO overlay files:"
    echo "$DTBO_FILES" | sed 's/^/  /'

    # Use mkdtimg to create proper DTBO image
    $MKDTIMG_CMD create "${DTBO_IMG}" \
        --page_size=4096 \
        $DTBO_FILES

    if [ -f "${DTBO_IMG}" ]; then
        DTBO_SIZE=$(stat -c%s "${DTBO_IMG}" 2>/dev/null)
        DTBO_SIZE_KB=$(echo "scale=2; $DTBO_SIZE/1024" | bc)

        echo "✓ DTBO image created: ${DTBO_IMG} (${DTBO_SIZE_KB} KB)"
    else
        echo "ERROR: Failed to create DTBO image"
        exit 1
    fi
}

# -----------------
# MAIN EXECUTION
# -----------------

# Verify output directory exists
if [ ! -d "${OUTPUT_DIR}" ]; then
    echo "ERROR: Output directory not found: ${OUTPUT_DIR}"
    echo "Please build the kernel first!"
    exit 1
fi

# Verify kernel image exists
if [ ! -f "${KERNEL_IMAGE}" ]; then
    echo "ERROR: Kernel Image not found: ${KERNEL_IMAGE}"
    echo "Please build the kernel first!"
    exit 1
fi

# Setup tools
setup_mkdtimg

# Append DTB to kernel
append_dtb_to_kernel

# Build DTBO
build_dtbo_image

echo ""
echo "==============================================="
echo "        DTBO Build Complete!"
echo "==============================================="
echo "Kernel+DTB: ${KERNEL_DTB}"
[ -f "${DTBO_IMG}" ] && echo "DTBO:       ${DTBO_IMG}"
echo ""
echo "Next step: Update package_kernel.sh to use Image-dtb"
echo "==============================================="
