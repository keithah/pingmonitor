#!/bin/bash

# Target App Store screenshot size: 1440x900
TARGET_WIDTH=1440
TARGET_HEIGHT=900

images=("mainscreen.png" "settings.png" "compact.png")

echo "Resizing screenshots to ${TARGET_WIDTH}x${TARGET_HEIGHT} with padding..."

for image in "${images[@]}"; do
    if [[ ! -f "$image" ]]; then
        echo "Warning: $image not found"
        continue
    fi

    base_name="${image%.*}"
    output_name="${base_name}_appstore.png"

    echo "Processing $image -> $output_name"

    # Use sips to resize maintaining aspect ratio and pad with white background
    sips -z "$TARGET_HEIGHT" "$TARGET_WIDTH" \
         --padToHeightWidth "$TARGET_HEIGHT" "$TARGET_WIDTH" \
         --padColor FFFFFF \
         "$image" --out "$output_name" > /dev/null 2>&1

    if [[ $? -eq 0 ]]; then
        echo "  ✓ Created $output_name"
        # Verify the output dimensions
        actual_size=$(sips -g pixelWidth -g pixelHeight "$output_name" | grep -E "pixelWidth|pixelHeight" | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')
        echo "    Size: $actual_size"
    else
        echo "  ✗ Failed to create $output_name"
    fi
done

echo -e "\nCompleted! App Store ready screenshots:"
ls -la *_appstore.png 2>/dev/null