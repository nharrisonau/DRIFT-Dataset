#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Flags / CLI
# ============================================================
DRY_RUN=false
USE_STRIPPED=true  # default to stripped firmware-like binaries

print_usage() {
  cat <<'EOF'
Usage: build_wago.sh [--stripped|--symbols] [--dry-run]

  --stripped   Use dropbear from dropbear_samples/stripped/*.stripped (default)
  --symbols    Use dropbear from dropbear_samples/symbols/* (non-stripped)
  --dry-run    Print actions without modifying files

Examples:
  build_wago.sh
  build_wago.sh --symbols
  build_wago.sh --dry-run --symbols
EOF
}

# Simple arg parser
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stripped) USE_STRIPPED=true; shift;;
    --symbols)  USE_STRIPPED=false; shift;;
    --dry-run)  DRY_RUN=true; shift;;
    -h|--help)  print_usage; exit 0;;
    *)
      echo "Unknown option: $1"
      print_usage
      exit 1
      ;;
  esac
done

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOWNLOADS="$BASE_DIR/downloads"
EXTRACTED="$BASE_DIR/extracted"
SAMPLES="$BASE_DIR/dropbear_samples"

mkdir -p "$DOWNLOADS" "$EXTRACTED"

echo ">> mode: $([[ "$USE_STRIPPED" == true ]] && echo 'stripped' || echo 'symbols')   dry-run: $DRY_RUN"

# ---- URLs ----
declare -A FW_URLS=(
  ["03.10.10"]="https://github.com/WAGO/pfc-firmware/releases/download/v03.10.10-22/WAGO_FW0750-8x1x_V031010_IX22_SP1_r71749.img"
  ["03.10.08"]="https://github.com/WAGO/pfc-firmware/releases/download/v03.10.08-22/WAGO_FW0750-8x1x_V031008_IX22_r68457.img"
)

# ---- Replacement mapping (dest dir -> sample filename, base names only) ----
# We’ll resolve to stripped/symbols path later based on USE_STRIPPED.
declare -A REP_BASENAME=(
  ["03.10.08-clean"]="dropbear83-clean"
  ["03.10.10-clean"]="dropbear86-clean"
  ["03.10.10-backdoor"]="dropbear86-backdoor"
)

# ---- Resolve a safe binwalk (prefer system over venv) ----
BINWALK_BIN=""
if [[ -x /usr/bin/binwalk ]]; then
  BINWALK_BIN="/usr/bin/binwalk"
else
  BINWALK_BIN="$(command -v binwalk || true)"
fi
if [[ -z "${BINWALK_BIN}" ]]; then
  echo "Missing command: binwalk"; exit 1
fi
if [[ "${BINWALK_BIN}" == *"/venv/"* ]]; then
  echo "Warning: Using venv binwalk at ${BINWALK_BIN}. If this fails, install system binwalk and rerun."
fi

# ---- Dependencies ----
for c in wget sha256sum strings find cp chmod; do
  command -v "$c" >/dev/null 2>&1 || { echo "Missing command: $c"; exit 1; }
done
command -v unsquashfs >/dev/null 2>&1 || { echo "Missing command: unsquashfs (install squashfs-tools)"; exit 1; }

copy_tree() {
  mkdir -p "$2"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$1"/ "$2"/
  else
    cp -a "$1"/. "$2"/
  fi
}

# --- improved root finder (broader) ---
find_ext_root() {
  find "$1" -type d \
    \( -iname 'ext-root' -o -iname 'rootfs' -o -iname 'squashfs-root' \
       -o -iname '*rootfs*' -o -iname '*-root' -o -iname 'fs' \) \
    -print -quit
}

# --- canonical dropbear path ---
find_dropbear_candidates() {
  local root="$1"
  local path="$root/usr/sbin/dropbear"
  if [[ -f "$path" ]]; then
    printf '%s\n' "$path"
    return 0
  else
    return 1
  fi
}

# Resolve sample path from REP_BASENAME and the stripped/symbols flag
resolve_sample_path() {
  local map_key="$1"     # e.g., 03.10.10-backdoor
  local base="${REP_BASENAME[$map_key]:-}"
  if [[ -z "$base" ]]; then
    echo "ERROR: No replacement base name for key '$map_key'" >&2
    return 1
  fi
  if [[ "$USE_STRIPPED" == true ]]; then
    echo "$SAMPLES/stripped/${base}.stripped"
  else
    echo "$SAMPLES/symbols/${base}"
  fi
}

# --- remove by the single dropbear hash & insert mapped replacement at usr/sbin/dropbear ---
remove_dropbear_and_insert() {
  local src="$1"     # source rootfs copied tree
  local dst="$2"     # destination variant dir to create
  local map_key="$3" # key into REP_BASENAME, e.g., 03.10.10-backdoor

  echo "==> Creating $dst from $src ($map_key)"
  if [[ "$DRY_RUN" != true ]]; then
    rm -rf "$dst"
    copy_tree "$src" "$dst"
  else
    echo "(dry-run) Would copy $src -> $dst"
  fi

  # Locate canonical dropbear
  local cand
  if ! cand="$(find_dropbear_candidates "$dst")"; then
    echo "No 'usr/sbin/dropbear' found in $dst"
  else
    echo "   Found dropbear: $cand"

    # compute sha of the exact file
    local sha
    sha=$(sha256sum "$cand" | awk '{print $1}')
    echo "   SHA256($cand) = $sha"

    # build hash map once
    local hashfile="$dst/.hashes"
    if [[ "$DRY_RUN" != true ]]; then
      ( cd "$dst" && find . -type f -print0 | xargs -0 sha256sum ) > "$hashfile"
    else
      echo "(dry-run) Would compute hash map for $dst -> $hashfile"
    fi

    # Remove all files matching that sha
    echo "   Removing all files matching hash: $sha"
    if [[ "$DRY_RUN" != true ]]; then
      awk -v S="$sha" '$1==S {print $2}' "$hashfile" \
        | sed 's#^\./##' \
        | while read -r rel; do
            [[ -n "$rel" && -f "$dst/$rel" ]] && rm -f "$dst/$rel" 2>/dev/null || true
          done
    else
      awk -v S="$sha" '$1==S {print $2}' "$hashfile"
    fi
  fi

  # Insert mapped replacement at usr/sbin/dropbear
  local rep
  if ! rep="$(resolve_sample_path "$map_key")"; then
    exit 1
  fi
  local target="$dst/usr/sbin/dropbear"

  if [[ ! -f "$rep" ]]; then
    echo "ERROR: Replacement binary not found: $rep"
    exit 1
  fi

  echo "==> Inserting replacement ($( [[ "$USE_STRIPPED" == true ]] && echo stripped || echo symbols )):"
  echo "    $rep -> $target"
  if [[ "$DRY_RUN" != true ]]; then
    mkdir -p "$(dirname "$target")"
    cp -a "$rep" "$target"
    chmod +x "$target" || true
  else
    echo "(dry-run) Would copy $rep -> $target"
  fi

  echo "✅ Placed $(basename "$rep") at $target"
}

# ============================================================
# Main
# ============================================================
for ver in 03.10.10 03.10.08; do
  url="${FW_URLS[$ver]}"
  img="$DOWNLOADS/$(basename "$url")"

  echo "==> [$ver] Downloading"
  [[ "$DRY_RUN" == true ]] || wget -c -O "$img" "$url"

  echo "==> [$ver] Extracting with binwalk ($BINWALK_BIN)"
  if [[ "$DRY_RUN" != true ]]; then
    (cd "$EXTRACTED" && "$BINWALK_BIN" -Me "$img")
  fi

  extracted_dir="$EXTRACTED/_$(basename "$img").extracted"
  root=$(find_ext_root "$extracted_dir")
  [[ -z "$root" ]] && { echo "No ext-root found for $ver"; exit 1; }

  [[ "$DRY_RUN" == true ]] || copy_tree "$root" "$BASE_DIR/$ver"
done

# Build final variants per mapping table
remove_dropbear_and_insert "$BASE_DIR/03.10.10" "$BASE_DIR/03.10.10-backdoor" "03.10.10-backdoor"
remove_dropbear_and_insert "$BASE_DIR/03.10.10" "$BASE_DIR/03.10.10-clean"    "03.10.10-clean"
remove_dropbear_and_insert "$BASE_DIR/03.10.08" "$BASE_DIR/03.10.08-clean"    "03.10.08-clean"

FINAL_DIR="$BASE_DIR/experiment_samples"
mkdir -p "$FINAL_DIR"

echo
echo "==> Moving final sample directories into $FINAL_DIR"
for dir in "$BASE_DIR"/03.10.10-backdoor "$BASE_DIR"/03.10.10-clean "$BASE_DIR"/03.10.08-clean; do
  if [[ -d "$dir" ]]; then
    echo "   Moving $(basename "$dir")"
    mv "$dir" "$FINAL_DIR/"
  fi
done

echo "==> Removing intermediate folders (03.10.10, 03.10.08, downloads, extracted)"
rm -rf "$BASE_DIR"/03.10.10 "$BASE_DIR"/03.10.08 "$BASE_DIR"/downloads "$BASE_DIR"/extracted

echo
echo "✅ Cleanup complete"
echo "✅ Done. Generated datasets in:"
echo "  $FINAL_DIR/03.10.10-backdoor"
echo "  $FINAL_DIR/03.10.10-clean"
echo "  $FINAL_DIR/03.10.08-clean"
