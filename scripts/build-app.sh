#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
PRODUCT_NAME="SimpleCmux"
PRODUCT_ID="com.example.SimpleCmux"
BUILD_CONFIGURATION="${SIMPLECMUX_BUILD_CONFIGURATION:-release}"
DESTINATION="${1:-${HOME}/Desktop/${PRODUCT_NAME}.app}"

if [[ "${DESTINATION##*.}" != "app" ]]; then
	print -u2 "error: destination must be an .app bundle: ${DESTINATION}"
	exit 1
fi

print "Building ${PRODUCT_NAME} (${BUILD_CONFIGURATION})..."
cd "${PROJECT_ROOT}"
"${PROJECT_ROOT}/scripts/ensure-ghosttykit.sh"
swift build -c "${BUILD_CONFIGURATION}" --product simple
BIN_PATH="$(swift build -c "${BUILD_CONFIGURATION}" --product simple --show-bin-path)"

if [[ ! -x "${BIN_PATH}/simple" ]]; then
	print -u2 "error: Swift build did not produce ${BIN_PATH}/simple"
	exit 1
fi

SIGNING_IDENTITY="${SIMPLECMUX_SIGNING_IDENTITY:-}"
if [[ -z "${SIGNING_IDENTITY}" ]]; then
	SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
		| sed -n 's/^[[:space:]]*[0-9][^\"]*\"\(.*\)\"$/\1/p' \
		| sed -n '/^Apple Development:/p; /^Developer ID Application:/p' \
		| head -n 1)"
fi

if [[ -z "${SIGNING_IDENTITY}" ]]; then
	print -u2 "error: no valid Apple signing identity was found"
	print -u2 "Set SIMPLECMUX_SIGNING_IDENTITY or install an Apple Development certificate."
	exit 1
fi

STAGING_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/simplecmux-app.XXXXXX")"
trap 'rm -rf "${STAGING_DIRECTORY}"' EXIT
STAGED_APP="${STAGING_DIRECTORY}/${PRODUCT_NAME}.app"

mkdir -p "${STAGED_APP}/Contents/MacOS" "${STAGED_APP}/Contents/Resources"
cp "${PROJECT_ROOT}/Resources/Info.plist" "${STAGED_APP}/Contents/Info.plist"
cp "${BIN_PATH}/simple" "${STAGED_APP}/Contents/MacOS/${PRODUCT_NAME}"
chmod 755 "${STAGED_APP}/Contents/MacOS/${PRODUCT_NAME}"

# Swift Package Manager does not compile an xcassets catalog for an executable
# target, so compile the existing catalog while assembling the app bundle.
xcrun actool \
	--compile "${STAGED_APP}/Contents/Resources" \
	--platform macosx \
	--minimum-deployment-target 14.0 \
	--app-icon AppIcon \
	--output-partial-info-plist "${STAGING_DIRECTORY}/assetcatalog-info.plist" \
	"${PROJECT_ROOT}/Assets.xcassets" >/dev/null

# Keep the designated requirement stable across release builds. TCC uses this
# requirement to recognize a new signed build as the same application.
DESIGNATED_REQUIREMENT="designated => anchor apple generic and identifier \"${PRODUCT_ID}\""
codesign \
	--force \
	--sign "${SIGNING_IDENTITY}" \
	-r="${DESIGNATED_REQUIREMENT}" \
	--timestamp=none \
	"${STAGED_APP}"

mkdir -p "${DESTINATION:h}"
ditto --rsrc --extattr --acl "${STAGED_APP}" "${DESTINATION}"

codesign --verify --deep --strict "${DESTINATION}"
print "Installed signed app at ${DESTINATION}"
print "Signing identity: ${SIGNING_IDENTITY}"
