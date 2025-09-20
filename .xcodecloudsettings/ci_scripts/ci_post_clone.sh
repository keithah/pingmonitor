#!/bin/sh

# Xcode Cloud CI Script - Post Clone
echo "🔧 Xcode Cloud: Post clone setup"

# Set executable permissions on build scripts
chmod +x build-appstore.sh

# Log environment info
echo "📋 Build Environment:"
echo "  Xcode Version: $(xcodebuild -version | head -1)"
echo "  macOS Version: $(sw_vers -productVersion)"
echo "  Git Commit: $CI_COMMIT"
echo "  Git Branch: $CI_BRANCH"

# Update version if CI_TAG is set (for releases)
if [ -n "$CI_TAG" ]; then
    echo "🏷️  Setting version to tag: $CI_TAG"
    VERSION=$(echo $CI_TAG | sed 's/^v//')

    # Update all Info.plist files
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" PingMonitor/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" PingMonitor/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" PingMonitorSources/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" PingMonitorSources/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" PingMonitorWidget/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" PingMonitorWidget/Info.plist

    echo "✅ Updated version to $VERSION"
fi

echo "✅ Post clone setup complete"