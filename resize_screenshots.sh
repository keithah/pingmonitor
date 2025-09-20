#!/bin/bash

# App Store screenshot dimensions
sizes=(
    "1280x800"
    "1440x900"
    "2560x1600"
    "2880x1800"
)

images=("mainscreen.png" "settings.png" "compact.png")

for image in "${images[@]}"; do
    if [[ ! -f "$image" ]]; then
        echo "Warning: $image not found"
        continue
    fi

    base_name="${image%.*}"

    # Get original dimensions
    original_size=$(sips -g pixelWidth -g pixelHeight "$image" | grep -E "pixelWidth|pixelHeight" | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')
    echo "Processing $image (original: $original_size)"

    for size in "${sizes[@]}"; do
        output_name="${base_name}_${size}.png"
        echo "  Creating $output_name"

        # Extract width and height
        width=${size%x*}
        height=${size#*x}

        # Use sips to resize and pad to fit exactly in the target dimensions
        # This maintains aspect ratio and adds padding as needed
        sips -z "$height" "$width" --padToHeightWidth "$height" "$width" --padColor FFFFFF "$image" --out "$output_name" > /dev/null 2>&1

        if [[ $? -eq 0 ]]; then
            echo "    ✓ Created $output_name"
        else
            echo "    ✗ Failed to create $output_name"
        fi
    done
    echo
done

echo "Screenshot resizing complete!"
echo "Generated files:"
ls -la *_[0-9]*x[0-9]*.png 2>/dev/null || echo "No resized files found"