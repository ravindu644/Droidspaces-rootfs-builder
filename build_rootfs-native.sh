#!/bin/bash
# Refactored Droidspaces RootFS Build Engine (Single Template Mode)
# This script is designed to be called by a parent loop or CI matrix.

# Configuration
: "${VERSION:=dev}"
DATE=$(date +%Y%m%d)

# Parse arguments
while getopts "i:v:" opt; do
  case $opt in
    i) DOCKERFILE="$OPTARG" ;;
    v) VERSION="$OPTARG" ;;
    *) echo "Usage: $0 -i <template.Dockerfile> [-v <version>]" ; exit 1 ;;
  esac
done

if [ -z "$DOCKERFILE" ]; then
    echo "Error: Template file (-i) is required."
    exit 1
fi

if [ ! -f "$DOCKERFILE" ]; then
    echo "Error: Template file '$DOCKERFILE' not found."
    exit 1
fi

# Extract prefix (e.g., Ubuntu-24.04 from Ubuntu-24.04.Dockerfile)
PREFIX=$(echo "$DOCKERFILE" | sed 's/\.Dockerfile//')

echo "========================================================="
echo " Starting Build: $PREFIX"
echo " Using Template: $DOCKERFILE"
echo " Build Version : $VERSION"
echo "========================================================="

# 1. Environment Initialization (Native)
echo "Ensuring native build environment..."
# In native mode, no QEMU or binfmt initialization is required.

# 2. Builder Setup
if ! docker buildx inspect droidspaces-builder >/dev/null 2>&1; then
    echo "Creating new buildx builder: droidspaces-builder"
    docker buildx create --name droidspaces-builder --driver docker-container --use
else
    echo "Using existing buildx builder: droidspaces-builder"
    docker buildx use droidspaces-builder
fi

# Bootstrap to ensure it's ready
docker buildx inspect --bootstrap || echo "Warning: Bootstrap failed, attempting to continue..."

set -e

# 3. Core Build Process
TEMP_TAR="custom-${PREFIX}-rootfs.tar"
FINAL_NAME="${PREFIX}-Droidspaces-rootfs-${DATE}-${VERSION}.tar.gz"

echo "Running Docker Build (Native)..."
docker buildx build \
  --target export \
  --output type=tar,dest="$TEMP_TAR" \
  -f "$DOCKERFILE" \
  .

# 4. Packaging
echo "Compressing build output..."
gzip -9 -f "$TEMP_TAR"

echo "Finalizing: $FINAL_NAME"
mv "${TEMP_TAR}.gz" "$FINAL_NAME"

echo "========================================================="
echo " Successfully completed: $FINAL_NAME"
echo "========================================================="
