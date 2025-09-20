#!/bin/sh

# Xcode Cloud CI Script - Pre Xcodebuild
echo "🏗️  Xcode Cloud: Pre-build setup"

# Display build configuration
echo "📋 Build Configuration:"
echo "  Product: PingScope"
echo "  Bundle ID: com.hadm.pingmonitor"
echo "  Scheme: $CI_XCODEBUILD_SCHEME"
echo "  Configuration: $CI_XCODEBUILD_CONFIGURATION"
echo "  Action: $CI_XCODEBUILD_ACTION"

# Ensure entitlements are correct
echo "🔒 Verifying entitlements files..."
if [ -f "entitlements-appstore.plist" ]; then
    echo "✅ Found App Store entitlements"
else
    echo "❌ Missing App Store entitlements"
    exit 1
fi

echo "✅ Pre-build setup complete"