#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Self-contained WAGO firmware setup
# Place this script inside the base dataset directory:
#   e.g., /home/nathan/Documents/DRIFT-Dataset/datasets/wago_data/
#
# It will:
#   1) download both .img files into ./downloads/
#   2) extract them via binwalk -Me into ./extracted/
#   3) copy their ext-root contents into ./03.10.10 and ./03.10.08
#   4) remove original dropbear binaries and insert replacements from ./dropbear_samples/
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOWNLOADS="$BASE_DIR/downloads"
EXTRACTED="$BASE_DIR/extracted"
SAMPLES="$BASE_DIR/dropbear_samples"
DRY_RUN="${1:-false}"

mkdir -p "$DOWNLOADS" "$EXTRACTED"

# ---- URLs ----
declare -A FW_URLS=(
  ["03.10.10"]="https://github.com/WAGO/pfc-firmware/releases/download/v03.10.10-22/WAGO_FW0750-8x1x_V031010_IX22_SP1_r71749.img"
  ["03.10.08"]="https://github.com/WAGO/pfc-firmware/releases/download/v03.10.08-22/WAGO_FW0750-8x1x_V031008_IX22_r68457.img"
)

# ---- Dependencies ----
for c in wget binwalk sha256sum strings find cp chmod; do
  command -v "$c" >/dev/null 2>&1 || { echo "Missing command: $c"; exit 1; }
done

# ---- Helper Functions ----
copy_tree() {
  mkdir -p "$2"
  rsync -a --delete "$1"/ "$2"/ 2>/dev/null || cp -a "$1"/. "$2"/
}

find_ext_root() {
  find "$1" -type d -regex '.*\(ext-root\|rootfs\|squashfs-root\)$' -print -quit
}

find_dropbear_candidates() {
  find "$1" -type f \( -iname 'dropbear' -o -iname 'dropbear*' -o -iname '*dropbear*' \) -print
  find "$1" -type f -perm /111 -exec grep -Il "dropbear" {} + 2>/dev/null || true
}

remove_dropbear_and_insert() {
  local src="$1" dst="$2" variant="$3"
  echo "==> Creating $dst from $src ($variant)"

  if [[ "$DRY_RUN" != true ]]; then
    rm -rf "$dst"
    copy_tree "$src" "$dst"
  else
    echo "(dry-run) Would copy $src -> $dst"
  fi

  # Find candidate dropbear files in DEST tree
  mapfile -t candidates_abs < <(find_dropbear_candidates "$dst" | sort -u)
  if [[ ${#candidates_abs[@]} -eq 0 ]]; then
    echo "No dropbear candidates found in $dst"
  else
    printf '   candidates:\n'; printf '     %s\n' "${candidates_abs[@]}"
  fi

  # Build hash map (paths relative to $dst)
  local hashfile="$dst/.hashes"
  if [[ "$DRY_RUN" != true ]]; then
    ( cd "$dst" && find . -type f -print0 | xargs -0 sha256sum ) > "$hashfile"
  else
    echo "(dry-run) Would compute hash map for $dst -> $hashfile"
  fi

  # Remove matching files by hash
  declare -A seen_sha=()
  for cand_abs in "${candidates_abs[@]}"; do
    [[ -f "$cand_abs" ]] || continue
    local sha; sha=$(sha256sum "$cand_abs" | awk '{print $1}')
    [[ -n "${seen_sha[$sha]:-}" ]] && continue
    seen_sha["$sha"]=1

    echo "   Removing all files matching hash: $sha"
    if [[ "$DRY_RUN" != true ]]; then
      awk -v S="$sha" '{print $2}' "$hashfile" \
        | sed 's#^\./##' \
        | while read -r rel; do rm -f "$dst/$rel" 2>/dev/null || true; done
    else
      awk -v S="$sha" '$1==S {print $2}' "$hashfile"
    fi
  done

  # Insert single replacement at top level
  local rep="$SAMPLES/dropbear-clean"
  local rep_name="dropbear-clean"
  [[ "$variant" == "backdoor" ]] && { rep="$SAMPLES/dropbear-backdoor"; rep_name="dropbear-backdoor"; }

  local target="$dst/$rep_name"
  echo "==> Inserting replacement at: $target"
  if [[ "$DRY_RUN" != true ]]; then
    mkdir -p "$dst"
    cp -a "$rep" "$target"
    chmod +x "$target" || true
  else
    echo "(dry-run) Would copy $rep -> $target"
  fi

  echo "✅ Placed $rep_name at top level of $dst"
}



# ============================================================
# Main
# ============================================================

for ver in 03.10.10 03.10.08; do
  url="${FW_URLS[$ver]}"
  img="$DOWNLOADS/$(basename "$url")"

  echo "==> [$ver] Downloading"
  [[ "$DRY_RUN" == true ]] || wget -c -O "$img" "$url"

  echo "==> [$ver] Extracting with binwalk"
  [[ "$DRY_RUN" == true ]] || (cd "$EXTRACTED" && binwalk -Me -q "$img")

  extracted_dir="$EXTRACTED/_$(basename "$img").extracted"
  root=$(find_ext_root "$extracted_dir")
  [[ -z "$root" ]] && { echo "No ext-root found for $ver"; exit 1; }

  [[ "$DRY_RUN" == true ]] || copy_tree "$root" "$BASE_DIR/$ver"
done

# --- Build final variants ---
remove_dropbear_and_insert "$BASE_DIR/03.10.10" "$BASE_DIR/03.10.10-backdoor" "backdoor"
remove_dropbear_and_insert "$BASE_DIR/03.10.10" "$BASE_DIR/03.10.10-clean" "clean"
remove_dropbear_and_insert "$BASE_DIR/03.10.08" "$BASE_DIR/03.10.08-clean" "clean"

# ============================================================
# Final packaging and cleanup
# ============================================================

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
echo "✅ Cleanup complete. Final dataset structure:"
tree -L 2 "$FINAL_DIR" 2>/dev/null || ls -R "$FINAL_DIR"


echo "✅ Done. Generated datasets in:"
echo "  $BASE_DIR/03.10.10-backdoor"
echo "  $BASE_DIR/03.10.10-clean"
echo "  $BASE_DIR/03.10.08-clean"
