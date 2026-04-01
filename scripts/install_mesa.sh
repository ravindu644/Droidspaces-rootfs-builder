#!/usr/bin/env bash
set -e

# Re-exec as root
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# --- Config ---
# Use these for local files (absolute paths recommended)
MESA_LOCAL=""
PATCH_LOCAL=""

# Use these for URLs (takes priority)
MESA_URL="https://github.com/ravindu644/Droidspaces-rootfs-builder/raw/refs/heads/main/mesa/mesa-25.0.7.tar.xz"
PATCH_URL="https://github.com/ravindu644/Droidspaces-rootfs-builder/raw/refs/heads/main/mesa/Mesa-25.0.x-patches-wayland-dri3.zip"
# --------------

if ! command -v apt &>/dev/null; then
    echo "Error: apt not found."
    exit 1
fi

WORK_DIR=$(mktemp -d)
BEFORE_PKGS=$(mktemp)
trap cleanup EXIT

cleanup() {
    echo "Starting deep cleanup..."
    cd /

    AFTER_PKGS=$(mktemp)

    # Both files must be sorted for comm to work correctly
    dpkg --get-selections | awk '$2=="install"{print $1}' | sort > "$AFTER_PKGS"

    # comm -13: suppress lines only in file1 and lines in both → leaves lines only in file2 (newly installed)
    TO_REMOVE=$(comm -13 "$BEFORE_PKGS" "$AFTER_PKGS")

    if [ -n "$TO_REMOVE" ]; then
        echo "Removing build-dependencies..."
        # Word-split is intentional here: each package is a separate argument
        # shellcheck disable=SC2086
        apt-get purge -y $TO_REMOVE
        apt-get autoremove -y --purge
    else
        echo "No new packages to remove."
    fi

    # Revert sources
    if [ -f /etc/apt/sources.list.bak ]; then
        mv /etc/apt/sources.list.bak /etc/apt/sources.list
    fi
    if [ -f /etc/apt/sources.list.d/debian.sources.bak ]; then
        mv /etc/apt/sources.list.d/debian.sources.bak /etc/apt/sources.list.d/debian.sources
    fi
    if [ -f /etc/apt/sources.list.d/ubuntu.sources.bak ]; then
        mv /etc/apt/sources.list.d/ubuntu.sources.bak /etc/apt/sources.list.d/ubuntu.sources
    fi

    # Clean up any manual tagging in sources.list if it exists
    if [ -f /etc/apt/sources.list ]; then
        sed -i '/#MESA_TEMP_SRC/d' /etc/apt/sources.list
    fi

    rm -rf "$WORK_DIR"
    rm -f "$BEFORE_PKGS" "$AFTER_PKGS"
    apt-get update -qq
    echo "Cleanup complete."
}

# Record exact package state before doing anything — must be sorted for comm
# We install glxgears/glxinfo and basic mesa runtime BEFORE the snapshot
# so they are considered part of the "base system" and NOT purged in cleanup.
echo "Installing mesa-utils and runtime dependencies..."
apt-get update -qq
apt-get install -y --no-install-recommends mesa-utils libgl1 libegl1 libgles2 libgbm1 libglx-mesa0 libgl1-mesa-dri

dpkg --get-selections | awk '$2=="install"{print $1}' | sort > "$BEFORE_PKGS"

echo "Configuring sources..."
# Handle traditional sources.list
if [ -f /etc/apt/sources.list ]; then
    cp /etc/apt/sources.list /etc/apt/sources.list.bak
    if ! grep -q "^deb-src " /etc/apt/sources.list; then
        grep "^deb " /etc/apt/sources.list | sed 's/^deb /deb-src /; s/$/ #MESA_TEMP_SRC/' >> /etc/apt/sources.list
        NEED_UPDATE=1
    fi
fi

# Handle DEB822 debian.sources (Debian 13+)
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
    cp /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/debian.sources.bak
    if ! grep -q "deb-src" /etc/apt/sources.list.d/debian.sources; then
        sed -i '/Types: deb/s/$/ deb-src/' /etc/apt/sources.list.d/debian.sources
        NEED_UPDATE=1
    fi
fi

# Handle DEB822 ubuntu.sources (Ubuntu 24.04+)
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
    if ! grep -q "deb-src" /etc/apt/sources.list.d/ubuntu.sources; then
        # Ubuntu often has multiple stanzas, we want to add deb-src to the 'deb' types
        sed -i '/Types: deb/s/$/ deb-src/' /etc/apt/sources.list.d/ubuntu.sources
        NEED_UPDATE=1
    fi
fi

if [ "$NEED_UPDATE" = "1" ]; then
    apt-get update -qq
fi

echo "Installing required build tools..."
apt-get install -y glslang-tools libxfixes-dev unzip curl wget build-essential meson ninja-build patch git
apt-get build-dep mesa -y

# Get Mesa
if [ -n "$MESA_URL" ]; then
    wget -qO "$WORK_DIR/mesa.tar.xz" "$MESA_URL"
else
    cp "$MESA_LOCAL" "$WORK_DIR/mesa.tar.xz"
fi

# Get Patches
if [ -n "$PATCH_URL" ]; then
    wget -qO "$WORK_DIR/patches.zip" "$PATCH_URL"
else
    cp "$PATCH_LOCAL" "$WORK_DIR/patches.zip"
fi

echo "Extracting Mesa..."
tar -xf "$WORK_DIR/mesa.tar.xz" -C "$WORK_DIR"
MESA_SRC=$(find "$WORK_DIR" -maxdepth 1 -type d -name "mesa-*")

echo "Applying patches..."
unzip -q "$WORK_DIR/patches.zip" -d "$MESA_SRC"
cd "$MESA_SRC"
for p in *.patch; do
    [ -e "$p" ] || continue
    patch -p1 < "$p"
done

echo "Building Mesa (this will take a few minutes)..."
rm -rf subprojects
meson build \
    -D platforms=x11,wayland \
    -D gallium-drivers=swrast,virgl,zink,freedreno \
    -D vulkan-drivers=freedreno \
    -D egl=enabled \
    -D gles2=enabled \
    -D glvnd=true \
    -D glx=dri \
    -D libunwind=disabled \
    -D osmesa=true \
    -D shared-glapi=enabled \
    -D microsoft-clc=disabled \
    -D valgrind=disabled \
    -D gles1=disabled \
    -D freedreno-kmds=kgsl \
    -D buildtype=release \
    -D gbm=enabled \
    --prefix /usr

ninja -C build -j$(nproc) install

echo "Configuring environment variables..."
if ! grep -q 'TU_DEBUG' /etc/environment; then
    echo 'TU_DEBUG=noconform,sysmem' >> /etc/environment
fi

# Reinstall our custom mesa on top (distro packages may have overwritten some files)
echo "Reinstalling custom Mesa over distro packages..."
ninja -C build -j$(nproc) install

# Hold all mesa-related packages so apt can never overwrite our custom build
echo "Holding mesa packages to protect custom Turnip driver..."
MESA_HOLD_PKGS=(
    libgl1-mesa-dri
    libglx-mesa0
    libgles2-mesa
    libgles1-mesa
    libegl-mesa0
    libgbm1
    mesa-libgallium
    mesa-vulkan-drivers
    mesa-utils
    mesa-vdpau-drivers
    mesa-va-drivers
    libgl1
    libegl1
    libgles2
)

for pkg in "${MESA_HOLD_PKGS[@]}"; do
    # Only hold if the package is actually installed (skip if not present)
    if dpkg -l "$pkg" &>/dev/null 2>&1; then
        apt-mark hold "$pkg"
        echo "  held: $pkg"
    fi
done

echo ""
echo "Mesa installed and protected successfully."
echo "The following are now held and cannot be updated/overwritten by apt:"
apt-mark showhold
echo ""
echo "To verify Turnip is active, run: glxinfo | grep 'OpenGL renderer'"
# The trap 'cleanup' now runs automatically
