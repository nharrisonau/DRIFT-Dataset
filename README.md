# Dataset of Embedded Systems with Multiple Firmware Versions

This repository contains datasets of embedded and industrial systems with multiple firmware versions.  
Each dataset includes automated scripts for downloading, unpacking, and preparing firmware samples for analysis and comparison.

---

## Datasets Overview

### 1. OpenWRT Dataset (`openwrt_data/`)

This dataset includes multiple versions of OpenWRT firmware, providing a consistent and open-source platform for analyzing software evolution, function-level changes, and update behavior.

**Contents**
- **build_openwrt.sh** – Automates downloading and unpacking of OpenWRT firmware images.  
- **tags.txt** – Lists component identifiers used for function-level semantic retrieval and evaluation.

---

### 2. WAGO PLC Dataset (`wago_data/`)

This dataset provides real-world firmware samples from WAGO PFC200 programmable logic controllers (PLCs).  
The setup script automates downloading, extraction, and controlled modification of firmware to generate labeled clean and backdoor variants for experimentation.

**Contents**
- **setup_wago_data.sh** – End-to-end automation script that  
  1. Downloads firmware versions 03.10.10 and 03.10.08 from WAGO’s public GitHub releases.  
  2. Extracts filesystem contents using binwalk.  
  3. Removes the original Dropbear SSH binaries.  
  4. Inserts controlled replacements:  
     - dropbear-backdoor → backdoor variant  
     - dropbear-clean → clean variant  
  5. Produces three labeled datasets:  
     - 03.10.10-backdoor  
     - 03.10.10-clean  
     - 03.10.08-clean  
  6. Moves final datasets into the **experiment_samples** directory.

- **dropbear_samples/** – Contains reference binaries for controlled insertion:  
  - dropbear-backdoor  
  - dropbear-clean  

- **experiment_samples/** – Directory where final processed datasets are stored after setup.

**Purpose**  
This dataset enables comparative firmware analysis, differential triage, and semantic diffing experiments (e.g., using DRIFT) to measure how controlled modifications affect function-level representations.

---

## Dependencies

**Required Tools**
- Python 3  
- binwalk (for unpacking firmware)  
- rsync (optional, improves copy performance)
- lzop

**Required Python Packages**
- pandas  
- requests  

**Install Binwalk**
- Ubuntu/Debian: `sudo apt-get install lzop binwalk`

---

## Usage

**OpenWRT Dataset**
1. Navigate to `datasets/openwrt_data/`
2. Run the script `build_openwrt.sh` to automatically download and unpack firmware versions.

**WAGO Dataset**
1. Navigate to `datasets/wago_data/`
2. Run the script `setup_wago_data.sh` to download, extract, and generate the labeled variants.

After completion, the **experiment_samples** directory will contain:

- 03.10.10-backdoor  
- 03.10.10-clean  
- 03.10.08-clean  

Each folder contains the unpacked firmware root filesystem with a single top-level  
**dropbear-clean** or **dropbear-backdoor** binary for controlled evaluation.

---

## Source Attribution

- **OpenWRT Firmware:** https://downloads.openwrt.org/  
- **WAGO PLC Firmware:** https://github.com/WAGO/pfc-firmware  
- **Original Multi-Firmware Dataset:** https://github.com/WUSTL-CSPL/Firmware-Dataset  

---

---

## Citation

If you use these datasets in your research, please cite: