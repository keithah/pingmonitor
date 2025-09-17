#!/usr/bin/env python3

import os
from PIL import Image, ImageDraw, ImageFont
import sys

def create_app_store_screenshot(original_path, output_dir, size, bg_color=(245, 245, 247)):
    """
    Create App Store screenshot by centering the original on a background
    """
    target_width, target_height = size

    # Open original image
    original = Image.open(original_path)
    orig_width, orig_height = original.size

    # Calculate scaling to fit nicely (leave some padding)
    padding = 100
    max_width = target_width - (padding * 2)
    max_height = target_height - (padding * 2)

    # Calculate scale factor (maintain aspect ratio)
    width_scale = max_width / orig_width
    height_scale = max_height / orig_height
    scale = min(width_scale, height_scale, 2.0)  # Don't scale up more than 2x

    # Calculate new size
    new_width = int(orig_width * scale)
    new_height = int(orig_height * scale)

    # Resize original
    resized = original.resize((new_width, new_height), Image.Resampling.LANCZOS)

    # Create background
    background = Image.new('RGB', (target_width, target_height), bg_color)

    # Calculate position to center the image
    x = (target_width - new_width) // 2
    y = (target_height - new_height) // 2

    # Paste resized image onto background
    if resized.mode == 'RGBA':
        background.paste(resized, (x, y), resized)
    else:
        background.paste(resized, (x, y))

    # Create output filename
    base_name = os.path.splitext(os.path.basename(original_path))[0]
    output_name = f"{base_name}_{target_width}x{target_height}.png"
    output_path = os.path.join(output_dir, output_name)

    # Save
    background.save(output_path, 'PNG', quality=95)
    print(f"✅ Created: {output_name}")

    return output_path

def main():
    # App Store required dimensions
    app_store_sizes = [
        (1280, 800),   # 16:10 ratio
        (1440, 900),   # 16:10 ratio
        (2560, 1600),  # 16:10 ratio
        (2880, 1800),  # 16:10 ratio
    ]

    # Input screenshots
    screenshots = [
        'mainscreen.png',
        'settings.png',
        'compact.png'
    ]

    # Create output directory
    output_dir = 'AppStore_Screenshots'
    os.makedirs(output_dir, exist_ok=True)

    print("🖼️  Converting screenshots for App Store...")
    print(f"📁 Output directory: {output_dir}")
    print()

    # Convert each screenshot to each required size
    for screenshot in screenshots:
        if os.path.exists(screenshot):
            print(f"📸 Processing: {screenshot}")
            for size in app_store_sizes:
                create_app_store_screenshot(screenshot, output_dir, size)
            print()
        else:
            print(f"⚠️  Warning: {screenshot} not found")

    print("🎉 Screenshot conversion complete!")
    print(f"📂 All screenshots saved to: {output_dir}/")
    print()
    print("📋 Upload these files to App Store Connect:")
    for screenshot in screenshots:
        base_name = os.path.splitext(screenshot)[0]
        for size in app_store_sizes:
            filename = f"{base_name}_{size[0]}x{size[1]}.png"
            print(f"   • {filename}")

if __name__ == "__main__":
    main()