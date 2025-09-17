#!/bin/bash

# Create output directory
mkdir -p AppStore_Screenshots

# App Store required dimensions
sizes=("1280x800" "1440x900" "2560x1600" "2880x1800")

# Input screenshots
screenshots=("mainscreen.png" "settings.png" "compact.png")

echo "🖼️  Converting screenshots for App Store..."
echo "📁 Output directory: AppStore_Screenshots/"
echo

# Function to resize and center image
resize_screenshot() {
    local input="$1"
    local size="$2"
    local width=$(echo $size | cut -d'x' -f1)
    local height=$(echo $size | cut -d'x' -f2)
    local base=$(basename "$input" .png)
    local output="AppStore_Screenshots/${base}_${size}.png"

    # Create a canvas with the target size and light gray background
    # Then resize the original to fit with padding and center it
    sips -z $height $width --padToHeightWidth $height $width \
         --padColor F5F5F7 \
         "$input" --out "$output" >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "✅ Created: ${base}_${size}.png"
    else
        echo "❌ Failed: ${base}_${size}.png"
    fi
}

# Process each screenshot
for screenshot in "${screenshots[@]}"; do
    if [ -f "$screenshot" ]; then
        echo "📸 Processing: $screenshot"
        for size in "${sizes[@]}"; do
            resize_screenshot "$screenshot" "$size"
        done
        echo
    else
        echo "⚠️  Warning: $screenshot not found"
    fi
done

echo "🎉 Screenshot conversion complete!"
echo "📂 All screenshots saved to: AppStore_Screenshots/"
echo
echo "📋 Upload these files to App Store Connect:"
for screenshot in "${screenshots[@]}"; do
    base=$(basename "$screenshot" .png)
    for size in "${sizes[@]}"; do
        echo "   • ${base}_${size}.png"
    done
done