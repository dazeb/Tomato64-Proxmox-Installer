#!/bin/bash

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Function to print success message
print_success() {
    echo -e "${GREEN}$1${NC}"
}

# Function to print error message
print_error() {
    echo -e "${RED}$1${NC}"
}

# Install unzip if it's not already installed
apt-get update && apt-get install -y unzip whiptail

# Display a notice to the user using whiptail
whiptail --title "Important Notice" --msgbox "This script assumes you are using bridges, as they are supported in every scenario, but you may also opt for hardware passthrough.\n\nYou will also need at least 2 network interfaces to run Tomato64 as a router." 15 78

# Clear the screen after whiptail
clear

# Get the next available VM ID
ID=$(pvesh get /cluster/nextid)

# Check if the VM already exists
if qm status "$ID" &>/dev/null; then
    print_error "VM with ID $ID already exists. Please choose a different ID or remove the existing VM."
    exit 1
fi

# Create a new VM with the specified parameters and set VirtIO SCSI Single as the SCSI controller
qm create "$ID" --name 'Tomato64' --memory 2048 --cores 2 --net0 "virtio,bridge=vmbr0" --bios ovmf --ostype l26 --scsihw virtio-scsi-single

# Fetch the latest release data from GitHub
latest_release_data=$(curl -s "https://api.github.com/repos/tomato64/tomato64/releases/latest")

# Extract the download URL for the .img.zip asset
download_url=$(echo "$latest_release_data" | grep "browser_download_url.*img.zip" | cut -d '"' -f 4)

# Download the zip file with the original name
original_zip_filename=$(basename "$download_url")
wget "$download_url" -O "$original_zip_filename"

# Unzip the file to extract the .img file
unzip -o "$original_zip_filename"

# Find the extracted .img file (assuming there's only one .img file in the zip)
extracted_img_filename=$(ls | grep '\.img$')

# Rename the extracted .img file to tomato64.img
mv "$extracted_img_filename" tomato64.img

# Define IMAGE_NAME as the renamed .img file
IMAGE_NAME="tomato64.img"

# Prompt for storage name
STORAGE=$(whiptail --inputbox "Enter the storage name where the image should be imported (e.g., local, local-lvm, local-zfs):" 8 78 --title "Tomato64 Installation" 3>&1 1>&2 2>&3)

# Import the disk image to the VM and capture the volume ID
DISK_VOLUME_ID=$(qm importdisk "$ID" "$IMAGE_NAME" "$STORAGE" --format raw)

# Check if the import was successful and we have a volume ID
if [ -z "$DISK_VOLUME_ID" ]; then
    print_error "Failed to import disk image or capture volume ID."
    exit 1
fi

# The volume ID should be in the format 'storage:vmid/volume'
# For example, 'local-lvm:vm-100-disk-0'
# If the storage is 'nvme-zfs', it might look like 'nvme-zfs:vm-100-disk-0'
# Make sure the volume ID is correct and does not contain extra spaces or the word 'importing disk'
echo "Imported disk as ${STORAGE}:${DISK_VOLUME_ID}"

# Attach the imported disk to the VM
if qm set "$ID" --scsi0 "${STORAGE}:${DISK_VOLUME_ID}"; then
    print_success "Disk attached successfully."
else
    print_error "Failed to attach disk."
    exit 1
fi

# Create an EFI disk for the VM using the special syntax
qm set "$ID" --efidisk0 "${STORAGE}:0"

# Set boot order to the SCSI disk
qm set "$ID" --boot c --bootdisk scsi0

# Clean up downloaded and extracted files
rm -f "$original_zip_filename" "$IMAGE_NAME"

# Notify the user that the VM has been created
print_success "VM $ID Created. Now add the second network card and bridge."
