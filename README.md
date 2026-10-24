# build_openwrt_mf286d_25.12.6
This script downloads and extracts the OpenWrt ImageBuilder, configures repositories, adds custom packages and web files, sets network/firewall/Wi‑Fi defaults, builds a firmware image for the ZTE MF286D, and copies the final sysupgrade file to the desktop.

# OpenWrt ImageBuilder Automation Script
Automated firmware build for ZTE MF286D (OpenWrt 24.10.2)

# 📌 Overview
This script automates the entire process of building a customized OpenWrt firmware image for the ZTE MF286D router.
It downloads the correct ImageBuilder, configures repositories, integrates custom .ipk packages, applies network/firewall/Wi‑Fi defaults, embeds static web files, and finally compiles and exports a ready‑to‑flash sysupgrade.bin.

# 🚀 Features
Automatic download and extraction of the correct OpenWrt ImageBuilder

Auto‑detection of the kernel kmods hash

Repository configuration override (repositories.conf)

Integration of local custom packages (luci-app-modemband, sms-tool-js, 3ginfo-lite, etc.)

Deployment of custom APN web UI files

Preconfigured:

Network (LAN, WAN QMI, WAN6)

Firewall zones and forwarding

Wi‑Fi (2.4 GHz + 5 GHz, WPA3‑SAE mixed)

Automatic build of the firmware image

Automatic copy of the final sysupgrade.bin to the Desktop

# 📦 Requirements
The following tools must be installed on the system:

wget

tar

make

unzstd

sha256sum

# The script checks for missing tools and stops if any are not installed.

# 📁 Directory Structure

_local_packages/
    *.ipk
    apn-web-files/
        apn.html
        control
        reboot_router
        restart_wan
        set_apn
        set_apn_modemmanager
        system_action
        
# Configuration Variables
The script defines the following key variables:


Variable	Description
VERSION	OpenWrt release version
TARGET / SUBTARGET	Architecture (ipq40xx/generic)
PROFILE	Device profile (zte_mf286d)
PACKAGES	List of packages to include in the firmware

# What the Script Does Step‑by‑Step

1. Environment validation
Ensures required tools are installed.

2. Download ImageBuilder
Fetches the correct archive if not already present.

3. Extract ImageBuilder
Unpacks the .tar.zst archive and detects the extracted folder.

4. Retrieve kernel kmods hash
Automatically scrapes the correct hash for the release.

5. Rewrite repositories.conf
Overrides default feeds with architecture‑correct ones.

6. Validate and import local packages
Ensures required .ipk files exist and copies them into ImageBuilder.

7. Install custom APN web interface
Copies HTML and CGI scripts into files/www/.

8. Apply default configuration files
Adds:

/etc/config/network

/etc/config/firewall

/etc/config/wireless

9. Build the firmware image
Runs ImageBuilder with the selected profile and packages.

10. Export final sysupgrade image
Copies the generated sysupgrade.bin to the user’s Desktop with timestamp.

# 📤 Output
The final firmware is saved as:

<pre>~/Desktop/sysupgrade-zte_mf286d-YYYYMMDD-HHMM.bin
</pre>

# Notes
This script is intended for advanced users familiar with OpenWrt and ImageBuilder.

Flashing custom firmware may void warranties or brick devices if misused.

Ensure the ZTE MF286D is compatible with the selected OpenWrt version.

# License
You may include your preferred license here (MIT, GPLv3, etc.).
