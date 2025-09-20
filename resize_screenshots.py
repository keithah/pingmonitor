#!/usr/bin/env python3

import sys
from PIL import Image, ImageOps
import os

def resize_for_app_store(input_path, output_path, target_size):
    """
    Resize image to App Store requirements without stretching.
    Adds padding to maintain aspect ratio.
    """
    try:
        # Open the original image
        img = Image.open(input_path)
        print(f"Original size: {img.size}")

        # Calculate scaling to fit within target size while maintaining aspect ratio
        img_ratio = img.width / img.height
        target_ratio = target_size[0] / target_size[1]

        if img_ratio > target_ratio:
            # Image is wider - scale based on width
            new_width = target_size[0]
            new_height = int(target_size[0] / img_ratio)
        else:
            # Image is taller - scale based on height
            new_height = target_size[1]
            new_width = int(target_size[1] * img_ratio)

        # Resize image maintaining aspect ratio
        img_resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)

        # Create new image with target size and white background
        new_img = Image.new('RGB', target_size, (255, 255, 255))

        # Calculate position to center the resized image
        x = (target_size[0] - new_width) // 2
        y = (target_size[1] - new_height) // 2

        # Paste the resized image onto the white background
        if img_resized.mode == 'RGBA':
            new_img.paste(img_resized, (x, y), img_resized)
        else:
            new_img.paste(img_resized, (x, y))

        # Save the result
        new_img.save(output_path, 'PNG', quality=95)
        print(f"Saved {output_path} at {target_size}")

    except Exception as e:
        print(f"Error processing {input_path}: {e}")

def main():
    # App Store screenshot requirements
    sizes = [
        (1280, 800),
        (1440, 900),
        (2560, 1600),
        (2880, 1800)
    ]

    images = ['mainscreen.png', 'settings.png', 'compact.png']

    for image in images:
        if not os.path.exists(image):
            print(f"Warning: {image} not found")
            continue

        base_name = os.path.splitext(image)[0]

        for width, height in sizes:
            output_name = f"{base_name}_{width}x{height}.png"
            print(f"\nProcessing {image} -> {output_name}")
            resize_for_app_store(image, output_name, (width, height))

if __name__ == "__main__":
    main()