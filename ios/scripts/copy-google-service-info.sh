#!/bin/bash
# Copies the correct GoogleService-Info.plist based on the active build configuration.
# Add this as a "Run Script" build phase in Xcode BEFORE "Compile Sources".

set -euo pipefail

PLIST_DIR="${PROJECT_DIR}/config"
DESTINATION="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"

if [[ "${CONFIGURATION}" == *"local"* ]]; then
    FLAVOR="local"
elif [[ "${CONFIGURATION}" == *"staging"* ]]; then
    FLAVOR="staging"
elif [[ "${CONFIGURATION}" == *"production"* ]]; then
    FLAVOR="production"
else
    echo "warning: Unknown configuration '${CONFIGURATION}', defaulting to local"
    FLAVOR="local"
fi

SOURCE="${PLIST_DIR}/${FLAVOR}/GoogleService-Info.plist"

if [[ ! -f "${SOURCE}" ]]; then
    echo "error: GoogleService-Info.plist not found at ${SOURCE}"
    exit 1
fi

echo "Copying GoogleService-Info.plist for ${FLAVOR}"
cp "${SOURCE}" "${DESTINATION}"
