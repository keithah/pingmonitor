#!/bin/bash

# Target App Store screenshot size: 1440x900
TARGET_WIDTH=1440
TARGET_HEIGHT=900

images=("mainscreen.png" "settings.png" "compact.png")

echo "Creating properly sized screenshots (${TARGET_WIDTH}x${TARGET_HEIGHT}) without stretching..."

for image in "${images[@]}"; do
    if [[ ! -f "$image" ]]; then
        echo "Warning: $image not found"
        continue
    fi

    base_name="${image%.*}"
    temp_resized="${base_name}_temp.png"
    output_name="${base_name}_proper.png"

    echo "Processing $image -> $output_name"

    # Get original dimensions
    original_info=$(sips -g pixelWidth -g pixelHeight "$image")
    original_width=$(echo "$original_info" | grep "pixelWidth" | awk '{print $2}')
    original_height=$(echo "$original_info" | grep "pixelHeight" | awk '{print $2}')

    echo "  Original: ${original_width}x${original_height}"

    # Calculate scale factor to fit within target while maintaining aspect ratio
    scale_x=$(echo "scale=4; $TARGET_WIDTH / $original_width" | bc)
    scale_y=$(echo "scale=4; $TARGET_HEIGHT / $original_height" | bc)

    # Use the smaller scale factor to ensure it fits
    if (( $(echo "$scale_x < $scale_y" | bc -l) )); then
        scale=$scale_x
    else
        scale=$scale_y
    fi

    # Calculate new dimensions
    new_width=$(echo "scale=0; $original_width * $scale / 1" | bc)
    new_height=$(echo "scale=0; $original_height * $scale / 1" | bc)

    echo "  Scaled: ${new_width}x${new_height}"

    # First, resize maintaining aspect ratio
    sips -z "$new_height" "$new_width" "$image" --out "$temp_resized" > /dev/null 2>&1

    # Then create a canvas with white background and center the image
    # Calculate padding
    pad_x=$(echo "($TARGET_WIDTH - $new_width) / 2" | bc)
    pad_y=$(echo "($TARGET_HEIGHT - $new_height) / 2" | bc)

    # Create white canvas and composite the resized image
    sips -c "$TARGET_HEIGHT" "$TARGET_WIDTH" --padColor FFFFFF "$temp_resized" --out "$output_name" > /dev/null 2>&1

    # Clean up temp file
    rm -f "$temp_resized"

    if [[ -f "$output_name" ]]; then
        echo "  ✓ Created $output_name"
        # Verify the output dimensions
        actual_size=$(sips -g pixelWidth -g pixelHeight "$output_name" | grep -E "pixelWidth|pixelHeight" | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')
        echo "    Final size: $actual_size"
    else
        echo "  ✗ Failed to create $output_name"
    fi
done

echo -e "\nCompleted! Properly sized screenshots:"
ls -la *_proper.png 2>/dev/null