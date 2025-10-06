# Dataset of Embedded Systems with Multiple Firmware Version

This is a dataset of products with at least 10 provided firmware versions. This dataset was created by filtering through an original dataset (https://github.com/WUSTL-CSPL/Firmware-Dataset) and identifying products with at least 10 versions of firmware.


## Dependancies

- Python 3
- Required Python Packages:
  - requests (for downloading firmware files)
  - pandas (for reading and processing the CSV file)
- Other Dependencies:
  - binwalk (for unpacking firmware files)

## Installation

Clone the Repository:

    git clone https://github.com/Program-Understanding/Firmware-Dataset.git

Install Python Dependencies: Install the required Python packages using pip.


    pip install pandas

Install binwalk: Install binwalk for unpacking firmware files:

    sudo apt-get install binwalk  # For Ubuntu/Debian

## Download Firmware Samples

The script takes two command-line arguments:

- firmware_data_path: Path to the CSV file containing the firmware URLs.
- save_path: Directory where the downloaded firmware files will be saved.

Example Command

    python3 firmware_downloader.py /path/to/firmware_download_list.csv /path/to/save_directory

## CSV File Format

The input CSV file should contain a column named url, with each row containing a firmware download URL. Ensure the column header is named exactly url for the script to function correctly.

Example:

    vendor,product,version,date,url
    VendorA,Product1,1.0,2022-01-01,http://example.com/firmware1.bin
    VendorB,Product2,2.1,2022-01-02,http://example.com/firmware2.bin
