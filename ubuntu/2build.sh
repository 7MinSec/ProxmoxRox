#!/bin/bash

# Function to find the next available VM ID
find_next_vmid() {
    local vmid=777
    while qm status $vmid &>/dev/null; do
        ((vmid++))
    done
    echo $vmid
}

echo "Starting Ubuntu Cloud-Init Template creation script"

# Get VM ID
read -p "Enter VM ID (default: auto-assign 777 or higher): " VMID
VMID=${VMID:-$(find_next_vmid)}
echo "Using VM ID: $VMID"

# Get storage target
echo "Available storage targets:"
pvesm status | awk 'NR>1 {print $1}'  # Display available storage options
read -p "Enter storage target (default: local-lvm): " STORAGE
STORAGE=${STORAGE:-local-lvm}

# Debugging line to check storage value
echo "Using storage target: $STORAGE"

# Verify storage exists
if ! pvesm status | grep -q "^$STORAGE"; then
    echo "Error: Storage '$STORAGE' not found"
    pvesm status | awk 'NR>1 {print $1}'
    exit 1
fi

# Download the latest Ubuntu cloud image
UBUNTU_VERSION="24.04"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_PATH="/tmp/ubuntu-${UBUNTU_VERSION}-cloudimg.img"

echo "Downloading Ubuntu ${UBUNTU_VERSION} cloud image..."
wget -O "$IMAGE_PATH" "$IMAGE_URL"

# Create VM
echo "Creating VM..."
qm create $VMID \
    --name "ubuntu-${UBUNTU_VERSION}-template" \
    --memory 2048 \
    --cores 2 \
    --net0 virtio,bridge=vmbr0 \
    --bios ovmf \
    --machine q35 \
    --ostype l26 \
    --agent enabled=1 \
    --cpu host \
    --efidisk0 ${STORAGE}:1,pre-enrolled-keys=1

# Import disk
echo "Importing disk..."
qm importdisk $VMID "$IMAGE_PATH" $STORAGE

# Wait for disk to be available
echo "Waiting for disk to be available..."
sleep 10

# Configure disks and boot
echo "Configuring disks and boot settings..."

# Find the correct disk name
DISK_NAME="vm-${VMID}-disk-1"

# Attach the disk correctly
qm set $VMID --scsi0 ${STORAGE}:${VMID}/${DISK_NAME},ssd=1,iothread=1

# Verify disk attachment
if qm config $VMID | grep -q "unused0"; then
    echo "Fixing disk attachment..."
    unused_disk=$(qm config $VMID | grep "unused0" | awk '{print $2}')
    qm set $VMID --scsi0 "$unused_disk"
    qm set $VMID --delete unused0
fi

# Set boot order
qm set $VMID --boot order=scsi0
qm set $VMID --bootdisk scsi0
qm set $VMID --ide2 ${STORAGE}:cloudinit
qm set $VMID --serial0 socket

# Set cloud-init defaults
echo "Setting cloud-init defaults..."
qm set $VMID --ciuser sevminsec
qm set $VMID --ipconfig0 ip=dhcp

# Convert to template
echo "Converting to template..."
qm template $VMID

# Cleanup
rm -f "$IMAGE_PATH"

# Verify configuration
echo "Verifying template configuration..."
qm config $VMID

# Check for unused disks
if qm config $VMID | grep -q "unused"; then
    echo "Warning: Found unused disks in configuration. Template may not be configured correctly."
    echo "Please verify the configuration above carefully."
fi

echo "Template creation complete! Template ID: $VMID"
echo "Use '2deploy.sh' to create VMs from this template."