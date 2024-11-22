#!/usr/bin/env pipx run python
import os
import subprocess
import sys
import json
import time
import threading
import shutil
import psutil
import tqdm

CONFIG_FILE = os.path.expanduser("~/.ubuntu_flash_config.json")

def load_config():
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    return {}

def save_config(config):
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f)

def show_progress(filename, total_size):
    start_size = os.path.getsize(filename) if os.path.exists(filename) else 0
    last_size = start_size
    unchanged_count = 0
    with tqdm.tqdm(total=total_size, unit='B', unit_scale=True, desc="Converting") as pbar:
        while True:
            time.sleep(1)
            if os.path.exists(filename):
                current_size = os.path.getsize(filename)
                progress = current_size - start_size
                pbar.update(current_size - last_size)
                if current_size == last_size:
                    unchanged_count += 1
                    if unchanged_count >= 30:
                        print("\nWarning: Progress has stalled for 30 seconds. Attempting to resume...")
                        return False
                else:
                    unchanged_count = 0
                last_size = current_size
                if progress >= total_size:
                    print("\nConversion completed successfully.")
                    return True
            else:
                break
    return False

def get_iso_size(iso_path):
    return os.path.getsize(iso_path)

def convert_iso_to_img(iso_path, img_path):
    base_img_path = os.path.splitext(img_path)[0]

    for ext in ['.img', '.dmg']:
        file_path = base_img_path + ext
        if os.path.exists(file_path):
            os.remove(file_path)

    print("Starting ISO to IMG conversion...")
    cmd = f"hdiutil convert '{iso_path}' -format UDRW -o '{base_img_path}'"

    iso_size = get_iso_size(iso_path)

    max_retries = 3
    for attempt in range(max_retries):
        process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        progress_thread = threading.Thread(target=show_progress, args=(base_img_path + ".dmg", iso_size))
        progress_thread.start()

        try:
            stdout, stderr = process.communicate(timeout=600)  # 10 minutes timeout
            if process.returncode == 0:
                print("\nConversion completed successfully.")
                break
            else:
                print(f"\nError during conversion (Attempt {attempt+1}/{max_retries}): {stderr.decode()}")
                if attempt < max_retries - 1:
                    print("Retrying conversion...")
                else:
                    print("Max retries reached. Conversion failed.")
                    return False
        except subprocess.TimeoutExpired:
            process.kill()
            print(f"\nConversion timed out (Attempt {attempt+1}/{max_retries})")
            if attempt < max_retries - 1:
                print("Retrying conversion...")
            else:
                print("Max retries reached. Conversion failed.")
                return False
        finally:
            progress_thread.join()

    dmg_path = base_img_path + ".dmg"
    if os.path.exists(dmg_path):
        os.rename(dmg_path, img_path)

    return os.path.exists(img_path)

def list_disk_devices():
    cmd = "diskutil list"
    output = subprocess.check_output(cmd, shell=True).decode('utf-8')
    return output

def prepare_thumb_drive(disk):
    print(f"Preparing thumb drive {disk}...")
    try:
        subprocess.run(f"diskutil unmountDisk {disk}", shell=True, check=True)
        subprocess.run(f"diskutil eraseDisk FAT32 UBUNTU {disk}", shell=True, check=True)
        subprocess.run(f"diskutil unmountDisk {disk}", shell=True, check=True)
        print("Thumb drive prepared successfully.")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error preparing thumb drive: {e}")
        return False

def write_img_to_disk(img_path, disk):
    print("Starting to write IMG to disk...")
    img_size = os.path.getsize(img_path)
    block_size = 1024 * 1024  # 1 MB

    # Ensure the disk is unmounted before writing
    try:
        print(f"Unmounting {disk}...")
        subprocess.run(['sudo', 'diskutil', 'unmountDisk', disk], check=True)
        time.sleep(5)  # Wait for 5 seconds to ensure the disk is fully unmounted
    except subprocess.CalledProcessError as e:
        print(f"Error unmounting disk: {e}")
        return False

    with open(img_path, 'rb') as img_file, tqdm.tqdm(total=img_size, unit='B', unit_scale=True, desc="Writing") as pbar:
        while True:
            chunk = img_file.read(block_size)
            if not chunk:
                break
            try:
                subprocess.run(['sudo', 'dd', f'of={disk}', 'bs=1m', 'count=1'], input=chunk, check=True)
                pbar.update(len(chunk))
            except subprocess.CalledProcessError as e:
                print(f"\nError writing to disk: {e}")
                return False

    print("\nVerifying write operation...")
    try:
        subprocess.run(['sudo', 'diskutil', 'eject', disk], check=True)
        print("Write operation completed and verified.")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error ejecting disk: {e}")
        return False

def main():
    config = load_config()
    downloads_dir = os.path.expanduser("~/Downloads")
    iso_files = [f for f in os.listdir(downloads_dir) if f.endswith(".iso") and "ubuntu" in f.lower()]

    if not iso_files:
        print("No Ubuntu ISO found in Downloads folder.")
        sys.exit(1)

    iso_path = os.path.join(downloads_dir, iso_files[0])
    img_path = os.path.splitext(iso_path)[0] + ".img"

    try:
        print(f"Using ISO: {iso_path}")
        if not convert_iso_to_img(iso_path, img_path):
            print("Failed to convert ISO to IMG. Exiting.")
            sys.exit(1)

        print("\nAvailable disk devices:")
        print(list_disk_devices())

        if 'last_disk' in config:
            print(f"Last used disk: {config['last_disk']}")
            use_last = input("Use this disk? (y/n): ").lower() == 'y'
            if use_last:
                disk = config['last_disk']
            else:
                disk = input("Enter the disk identifier for your USB drive (e.g., /dev/disk2): ")
        else:
            disk = input("Enter the disk identifier for your USB drive (e.g., /dev/disk2): ")

        config['last_disk'] = disk
        save_config(config)

        confirm = input(f"Are you sure you want to flash Ubuntu to {disk}? This will erase all data on the device. (y/n): ")
        if confirm.lower() != 'y':
            print("Operation cancelled by user.")
            sys.exit(0)

        if not prepare_thumb_drive(disk):
            print("Failed to prepare thumb drive. Exiting.")
            sys.exit(1)

        if not write_img_to_disk(img_path, disk):
            print("Failed to write IMG to disk. Exiting.")
            sys.exit(1)

        print("Ubuntu has been successfully flashed to the USB drive.")
    except subprocess.CalledProcessError as e:
        print(f"An error occurred: {e}")
        print("Please check the disk identifier and ensure you have the necessary permissions.")
    except FileNotFoundError:
        print(f"Error: The IMG file was not found at {img_path}")
        print("Please ensure the ISO to IMG conversion was successful.")
    except KeyboardInterrupt:
        print("\nOperation cancelled by user.")
    finally:
        if os.path.exists(img_path):
            try:
                os.remove(img_path)
                print(f"Temporary IMG file removed: {img_path}")
            except PermissionError:
                print(f"Could not remove temporary IMG file: {img_path}")
                print("You may want to remove it manually to save disk space.")

if __name__ == "__main__":
    main()
