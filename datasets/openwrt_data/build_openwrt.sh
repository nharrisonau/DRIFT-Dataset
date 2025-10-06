#!/bin/bash
set -e

# Directories (assumes the script is run from the openwrt directory)
OPENWRT_DIR="$(pwd)"
REPO_DIR="$OPENWRT_DIR/openwrt_repo"
BUILDS_DIR="$OPENWRT_DIR/builds"
TAGS_FILE="$OPENWRT_DIR/tags.txt"

# Ensure the tags file exists
if [ ! -f "$TAGS_FILE" ]; then
  echo "Tags file $TAGS_FILE not found!"
  exit 1
fi

# Ensure the builds directory exists
mkdir -p "$BUILDS_DIR"

# Iterate over each tag in the tags file
while IFS= read -r tag || [ -n "$tag" ]; do
# Clone the repository if it doesn't exist
if [ ! -d "$REPO_DIR" ]; then
echo "Cloning OpenWrt repository..."
git clone https://github.com/openwrt/openwrt.git "$REPO_DIR"
fi

  # Skip empty lines or lines starting with '#'
  if [[ -z "$tag" || "$tag" =~ ^# ]]; then
    continue
  fi

  dest_dir="$BUILDS_DIR/openwrt-$tag"
  if [ -d "$dest_dir" ]; then
    echo "Build directory for version $tag already exists at $dest_dir. Skipping build."
    continue
  fi

  echo "-----------------------------------------"
  echo "Building OpenWrt version: $tag"

  # Change into the repository directory
  pushd "$REPO_DIR" > /dev/null

  # Fetch tags and checkout the specific tag
  git fetch --tags
  git checkout "$tag"

  # Clean previous build artifacts to avoid configuration mismatches
  make distclean

  # Update and install feeds (if applicable)
  echo "Updating and installing feeds for $tag..."
  ./scripts/feeds update -a
  ./scripts/feeds install -a

  # Generate the full non-interactive configuration
  make defconfig

  # Start the build using all available CPU cores
  echo "Starting build for $tag..."
  make -j"$(nproc)"

  popd > /dev/null

  # Copy the build output (assumed to be in the 'bin' directory) to the builds folder
  mkdir -p "$dest_dir"
  cp -r "$REPO_DIR/bin" "$dest_dir/"

  echo "Build for version $tag completed and copied to $dest_dir"
done < "$TAGS_FILE"

echo "All builds are complete."
