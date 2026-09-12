#!/usr/bin/env bash

# Load this file before running orbitx:
#   source ./orbitx.config.sh
#   sudo -E ./orbitx -m server

export ORBITX_DATABASE_URL="${ORBITX_DATABASE_URL:-https://orbitx-os-default-rtdb.asia-southeast1.firebasedatabase.app}"
export ORBITX_UUID="${ORBITX_UUID:-af9aa286-d101-47b8-b799-2fa16d660e83}"
export ORBITX_DEVICE_NAME="${ORBITX_DEVICE_NAME:-orbitx-ubuntu}"
export ORBITX_PRESHARED_SECRET="${ORBITX_PRESHARED_SECRET:-orbitx_p2p_default_secret}"
export ORBITX_INTERFACE="${ORBITX_INTERFACE:-wg0}"
export ORBITX_DATA_DIR="${ORBITX_DATA_DIR:-$HOME/.orbitx}"