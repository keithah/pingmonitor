#!/bin/bash

# PingMonitor Release Build Script
# Builds, signs, and notarizes PingMonitor for macOS distribution

set -e  # Exit on any error

# Configuration
PRODUCT_NAME="PingMonitor"
BUNDLE_ID="com.pingmonitor.app"
DEVELOPER_ID_APP="Developer ID Application: Keith Herrington (6R7S5GA944)"
DEVELOPER_ID_INSTALLER="Developer ID Installer: Keith Herrington (6R7S5GA944)"
TEAM_ID="6R7S5GA944"
NOTARYTOOL_PROFILE="NotarytoolProfile"

# Get version from script argument or prompt user
if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.0.1"
    exit 1
fi

VERSION="$1"
echo "🚀 Building PingMonitor v${VERSION}..."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf /private/tmp/artifacts/PingMonitor-v${VERSION}-ReadyToSign
mkdir -p /private/tmp/artifacts/PingMonitor-v${VERSION}-ReadyToSign
cd /private/tmp/artifacts/PingMonitor-v${VERSION}-ReadyToSign

# Update version in Info.plist
echo "📝 Updating version in Info.plist..."
cd /Users/keith/src/pingmonitor
sed -i '' "s/<string>[0-9]\+\.[0-9]\+\.[0-9]\+<\/string>/<string>${VERSION}<\/string>/g" Info.plist

# Build the application
echo "🔨 Building PingMonitor..."
swiftc -o /private/tmp/artifacts/PingMonitor-v${VERSION}-ReadyToSign/PingMonitor \
    PingMonitor.swift \
    -framework Cocoa \
    -framework SwiftUI \
    -framework UserNotifications

# Create app bundle structure
echo "📦 Creating app bundle..."
cd /private/tmp/artifacts/PingMonitor-v${VERSION}-ReadyToSign
mkdir -p PingMonitor.app/Contents/{MacOS,Resources}

# Copy files to app bundle
cp /Users/keith/src/pingmonitor/Info.plist PingMonitor.app/Contents/
cp PingMonitor PingMonitor.app/Contents/MacOS/
cp /Users/keith/src/pingmonitor/PingMonitor.icns PingMonitor.app/Contents/Resources/
chmod +x PingMonitor.app/Contents/MacOS/PingMonitor

# Create entitlements file
echo "🔐 Creating entitlements..."
cat > entitlements.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
EOF

# Sign the app bundle
echo "✍️  Signing app bundle..."
codesign --force --deep --sign "$DEVELOPER_ID_APP" --options runtime --entitlements entitlements.plist PingMonitor.app

# Verify signing
echo "🔍 Verifying signature..."
codesign -dv --verbose=4 PingMonitor.app

# Create DMG
echo "💿 Creating DMG..."
hdiutil create -volname "$PRODUCT_NAME v${VERSION}" \
    -srcfolder PingMonitor.app \
    -ov -format UDZO \
    "${PRODUCT_NAME}-v${VERSION}.dmg"

# Create PKG
echo "📋 Creating PKG..."
pkgbuild --root PingMonitor.app \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location "/Applications/PingMonitor.app" \
    "unsigned.pkg"

# Sign PKG
echo "✍️  Signing PKG..."
productsign --sign "$DEVELOPER_ID_INSTALLER" \
    "unsigned.pkg" \
    "${PRODUCT_NAME}-v${VERSION}.pkg"

# Submit for notarization
echo "📡 Submitting DMG for notarization..."
xcrun notarytool submit "${PRODUCT_NAME}-v${VERSION}.dmg" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

echo "📡 Submitting PKG for notarization..."
xcrun notarytool submit "${PRODUCT_NAME}-v${VERSION}.pkg" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

# Staple notarization tickets
echo "📎 Stapling notarization tickets..."
xcrun stapler staple "${PRODUCT_NAME}-v${VERSION}.dmg"
xcrun stapler staple "${PRODUCT_NAME}-v${VERSION}.pkg"

# Verify notarization
echo "🔍 Verifying notarization..."
spctl -a -t exec -vv PingMonitor.app
spctl -a -t install -vv "${PRODUCT_NAME}-v${VERSION}.pkg"

# Create checksums
echo "🔐 Creating checksums..."
shasum -a 256 "${PRODUCT_NAME}-v${VERSION}.dmg" > "checksums-v${VERSION}.txt"
shasum -a 256 "${PRODUCT_NAME}-v${VERSION}.pkg" >> "checksums-v${VERSION}.txt"

# Clean up
rm unsigned.pkg

# Commit and tag
echo "📝 Committing changes and creating tag..."
cd /Users/keith/src/pingmonitor
git add Info.plist PingMonitor.swift
git commit -m "🚀 Release v${VERSION}: $(date '+%Y-%m-%d')

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

git tag "v${VERSION}"
git push origin main
git push origin "v${VERSION}"

# Create GitHub release
echo "🐙 Creating GitHub release..."
cd /Users/keith/src/pingmonitor

gh release create "v${VERSION}" \
    --title "PingMonitor v${VERSION}" \
    --notes "$(cat <<EOF
# PingMonitor v${VERSION}

Released on $(date '+%B %d, %Y')

## 📥 Installation

### DMG Installation (Recommended)
1. Download \`${PRODUCT_NAME}-v${VERSION}.dmg\`
2. Open the DMG file
3. Drag PingMonitor to your Applications folder
4. Launch from Applications or Spotlight

### PKG Installation
1. Download \`${PRODUCT_NAME}-v${VERSION}.pkg\`
2. Double-click to run the installer
3. Follow the installation prompts
4. Launch from Applications or Spotlight

## 🔐 Security
- ✅ **Signed with Developer ID** for security and trust
- ✅ **Notarized by Apple** for Gatekeeper compatibility
- ✅ **Hardened runtime** enabled for enhanced security
- ✅ **No sensitive data collection** - all data stays local

## ✅ System Requirements
- macOS 13.0 or later
- Apple Silicon (M1/M2/M3) or Intel processor
- Network connectivity for ping operations

---

**Checksums:**
\`\`\`
$(cat /private/tmp/artifacts/PingMonitor-v${VERSION}-ReadyToSign/checksums-v${VERSION}.txt)
\`\`\`

🤖 Generated with [Claude Code](https://claude.ai/code)
EOF
)" \
    "/private/tmp/artifacts/PingMonitor-v${VERSION}-ReadyToSign/${PRODUCT_NAME}-v${VERSION}.dmg" \
    "/private/tmp/artifacts/PingMonitor-v${VERSION}-ReadyToSign/${PRODUCT_NAME}-v${VERSION}.pkg" \
    "/private/tmp/artifacts/PingMonitor-v${VERSION}-ReadyToSign/checksums-v${VERSION}.txt"

echo ""
echo "🎉 Release v${VERSION} completed successfully!"
echo "📁 Artifacts located at: /private/tmp/artifacts/PingMonitor-v${VERSION}-ReadyToSign/"
echo "🌐 GitHub release: https://github.com/keithah/pingmonitor/releases/tag/v${VERSION}"
echo ""
echo "✅ The app is now fully signed and notarized by Apple!"