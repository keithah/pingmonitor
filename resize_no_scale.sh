#!/bin/bash

# Target App Store screenshot size: 1440x900
TARGET_WIDTH=1440
TARGET_HEIGHT=900

images=("mainscreen.png" "settings.png" "compact.png")

echo "Creating screenshots at original resolution with padding to ${TARGET_WIDTH}x${TARGET_HEIGHT}..."

for image in "${images[@]}"; do
    if [[ ! -f "$image" ]]; then
        echo "Warning: $image not found"
        continue
    fi

    base_name="${image%.*}"
    output_name="${base_name}_final.png"

    echo "Processing $image -> $output_name"

    # Get original dimensions
    original_info=$(sips -g pixelWidth -g pixelHeight "$image")
    original_width=$(echo "$original_info" | grep "pixelWidth" | awk '{print $2}')
    original_height=$(echo "$original_info" | grep "pixelHeight" | awk '{print $2}')

    echo "  Keeping original size: ${original_width}x${original_height}"

    # Check if image fits within target dimensions
    if [[ $original_width -gt $TARGET_WIDTH ]] || [[ $original_height -gt $TARGET_HEIGHT ]]; then
        echo "  Warning: Image is larger than target canvas!"
    fi

    # Create canvas with white background and place original image in center
    sips -c "$TARGET_HEIGHT" "$TARGET_WIDTH" --padColor FFFFFF "$image" --out "$output_name" > /dev/null 2>&1

    if [[ -f "$output_name" ]]; then
        echo "  ✓ Created $output_name"
        # Verify the output dimensions
        actual_size=$(sips -g pixelWidth -g pixelHeight "$output_name" | grep -E "pixelWidth|pixelHeight" | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')
        echo "    Canvas size: $actual_size"
    else
        echo "  ✗ Failed to create $output_name"
    fi
done

echo -e "\nCompleted! Original resolution screenshots with padding:"
ls -la *_final.png 2>/dev/null