#!/usr/bin/env bash

# Load this file before running orbitx:
#   source ./orbitx.config.sh
#   sudo -E ./orbitx -m server

export ORBITX_DATABASE_URL="${ORBITX_DATABASE_URL:-https://orbitx-os-default-rtdb.asia-southeast1.firebasedatabase.app}"
export ORBITX_UUID="${ORBITX_UUID:-test123}"
export ORBITX_DEVICE_NAME="${ORBITX_DEVICE_NAME:-orbitx-ubuntu}"
export ORBITX_INTERFACE="${ORBITX_INTERFACE:-wg0}"
export ORBITX_DATA_DIR="${ORBITX_DATA_DIR:-$HOME/.orbitx}"