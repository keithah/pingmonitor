#!/bin/sh

# Xcode Cloud CI Script - Post Xcodebuild
echo "📦 Xcode Cloud: Post-build processing"

# Check if archive was created successfully
if [ "$CI_XCODEBUILD_ACTION" = "archive" ]; then
    echo "🗃️  Archive build completed"

    # Log archive path if available
    if [ -n "$CI_ARCHIVE_PATH" ]; then
        echo "📁 Archive path: $CI_ARCHIVE_PATH"

        # List archive contents
        echo "📋 Archive contents:"
        ls -la "$CI_ARCHIVE_PATH"
    fi

    echo "✅ Ready for App Store distribution"
fi

echo "✅ Post-build processing complete"