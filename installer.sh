#!/bin/bash

# Install dialog if it's not already installed
if ! command -v dialog &> /dev/null; then
    echo "dialog is not installed. Installing dialog..."
    apt-get update && apt-get install -y dialog
fi

# Display a notice to the user using dialog
dialog --backtitle "Important Notice" --msgbox "\nThis script assumes you are using bridges, as they are supported in every scenario, but you may also opt for hardware passthrough.\n\nYou will also need at least 2 network interfaces to run Tomato64 as a router." 15 78 --title "Please Read" --ok-button "Understand"

# Clear the screen after dialog
clear

# Get the next available VM ID and touch the VM's configuration file
ID=$(pvesh get /cluster/nextid)
touch "/etc/pve/qemu-server/${ID}.conf"

# Fetch the latest release data from GitHub
latest_release_data=$(curl -s "https://api.github.com/repos/tomato64/tomato64/releases/latest")

# Extract the download URL for the .img.zip asset
download_url=$(echo "$latest_release_data" | grep "browser_download_url.*img.zip" | cut -d '"' -f 4)

# Use basename to extract the filename from the URL
filename=$(basename "$download_url")

# Download the file with a sanitized name
wget "$download_url" -O "$filename"

# Unzip the file
unzip "$filename"

# Extract the .img file name from the zip archive
IMAGE_NAME=$(unzip -l "$filename" | grep '.img' | tr -s ' ' | cut -d ' ' -f 5)

# Prompt for storage name
STORAGE=$(whiptail --inputbox 'Enter the storage name where the image should be imported:' 8 78 --title 'Tomato64 Installation' 3>&1 1>&2 2>&3)

# Determine filesystem type and set disk parameter
if (whiptail --title "Filesystem Type" --yesno "Are you using BTRFS, ZFS, or Directory storage? Select YES. If using LVM-Thin Provisioning, select NO." 10 78); then
    qm_disk_param="$STORAGE:$ID/vm-$ID-disk-0.raw"
else
    qm_disk_param="$STORAGE:vm-$ID-disk-0"
fi

# Import the disk image to the VM
qm importdisk "$ID" "$IMAGE_NAME" "$STORAGE"

# Set VM settings
qm set "$ID" --cores 2
qm set "$ID" --memory 2048
qm set "$ID" --bios ovmf
qm set "$ID" --scsihw virtio-scsi-pci
qm set "$ID" --scsi0 "$qm_disk_param"
qm set "$ID" --boot c=scsi0
qm set "$ID" --name 'Tomato64'
qm set "$ID" --description 'Tomato64 VM'
qm set "$ID" --efidisk0 "$STORAGE:4,format=qcow2"

# Check for the presence of vmbr1 and vmbr2 and add network devices
if grep -q "iface vmbr1" /etc/network/interfaces && grep -q "iface vmbr2" /etc/network/interfaces; then
    qm set "$ID" --net0 "virtio,bridge=vmbr1"
    qm set "$ID" --net1 "virtio,bridge=vmbr2"
else
    echo "vmbr1 or vmbr2 not found. Using vmbr0 as default."
    qm set "$ID" --net0 "virtio,bridge=vmbr0"
fi

# Clean up downloaded and extracted files
rm -f "$filename" "$IMAGE_NAME"

# Notify the user that the VM has been created
echo "VM $ID Created."

# Start the VM
qm start "$ID"
