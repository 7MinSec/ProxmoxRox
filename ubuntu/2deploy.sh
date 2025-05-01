#!/bin/bash

# Function to check and fix template disk configuration
check_and_fix_template() {
    local template_id=$1
    echo "Checking template disk configuration..."
    
    # Check if there's an unused disk
    if qm config $template_id | grep -q "unused"; then
        echo "Found unused disk in template, attempting to fix..."
        # Get the unused disk name
        unused_disk=$(qm config $template_id | grep "unused" | awk '{print $3}')
        if [ ! -z "$unused_disk" ]; then
            echo "Moving unused disk to scsi0..."
            qm set $template_id --scsi0 "$unused_disk"
            
            # Add a small delay to let the change take effect
            sleep 5
            
            # Verify the fix
            if qm config $template_id | grep -q "scsi0"; then
                echo "Successfully fixed template disk configuration."
            else
                echo "ERROR: Failed to fix template disk configuration."
                echo "Please fix the template manually:"
                echo "qm set $template_id --scsi0 $unused_disk"
                exit 1
            fi
        fi
    else
        # Check if scsi0 exists
        if ! qm config $template_id | grep -q "scsi0"; then
            echo "ERROR: Template has no scsi0 disk configured."
            echo "Please check template configuration and fix manually."
            exit 1
        else
            echo "Template disk configuration appears correct."
        fi
    fi
}

# Find available templates
echo "Finding available templates..."
templates=$(qm list | grep -i template)
if [ -z "$templates" ]; then
    echo "No templates found. Please run 2build.sh first."
    exit 1
fi

echo "Available templates:"
echo "$templates"

# Get template ID
default_template_id=$(echo "$templates" | awk 'NR==1 {print $1}')
read -p "Enter template ID [${default_template_id}]: " template_id
template_id=${template_id:-$default_template_id}

# Check and fix template disk configuration
check_and_fix_template $template_id

# Get VM name
read -p "Enter VM name: " vm_name
if [ -z "$vm_name" ]; then
    echo "VM name is required"
    exit 1
fi

# Get next available VM ID
next_id=$(qm list | awk '{print $1}' | grep -v VMID | sort -n | tail -n1)
next_id=$((next_id + 1))

# Get memory size
read -p "Enter memory size in MB [8192]: " memory
memory=${memory:-8192}

# Get disk size
read -p "Enter disk size in GB [75]: " disk_size
disk_size=${disk_size:-75}

# Get network settings
echo -e "\nCurrent VM network configurations (showing up to 2 VMs):"
count=0
declare -A bridge_counts
for vmid in $(qm list | grep -v VMID | awk '{print $1}'); do
    name=$(qm config $vmid | grep "name:" | awk '{print $2}')
    net=$(qm config $vmid | grep "net0:" | sed 's/net0: //')
    if [ ! -z "$net" ]; then
        bridge=$(echo $net | grep -o "bridge=[^,]*" | cut -d= -f2)
        echo "VM $vmid ($name) -> Bridge: $bridge"
        bridge_counts[$bridge]=$((${bridge_counts[$bridge]:-0} + 1))
        count=$((count + 1))
        if [ $count -eq 2 ]; then
            break
        fi
    fi
done

# Find most common bridge
most_common_bridge="vmbr0"  # Default fallback
max_count=0
for bridge in "${!bridge_counts[@]}"; do
    if [ ${bridge_counts[$bridge]} -gt $max_count ]; then
        most_common_bridge=$bridge
        max_count=${bridge_counts[$bridge]}
    fi
done

echo -e "\n"
read -p "Enter bridge [$most_common_bridge]: " bridge
bridge=${bridge:-$most_common_bridge}

read -p "Enter VLAN ID (leave empty for none): " vlan_id

# Get MAC address (optional)
read -p "Enter MAC address (or press Enter to let Proxmox generate one): " mac_address

# Get storage target
echo -e "\nCurrent VM storage configurations (showing up to 2 VMs):"
count=0
declare -A storage_counts
for vmid in $(qm list | grep -v VMID | awk '{print $1}'); do
    name=$(qm config $vmid | grep "name:" | awk '{print $2}')
    storage=$(qm config $vmid | grep "scsi0:" | awk -F ':' '{print $2}' | awk -F ',' '{print $1}')
    if [ ! -z "$storage" ]; then
        echo "VM $vmid ($name) -> Storage: $storage"
        storage_counts[$storage]=$((${storage_counts[$storage]:-0} + 1))
        count=$((count + 1))
        if [ $count -eq 2 ]; then
            break
        fi
    fi
done

# Find most common storage
most_common_storage="local-lvm"  # Default fallback
max_count=0
for storage in "${!storage_counts[@]}"; do
    if [ ${storage_counts[$storage]} -gt $max_count ]; then
        most_common_storage=$storage
        max_count=${storage_counts[$storage]}
    fi
done

echo -e "\n"
read -p "Enter storage target [$most_common_storage]: " storage_target
storage_target=${storage_target:-$most_common_storage}

# Copy xfer directory to snippets if it exists
if [ -d "xfer" ]; then
    echo "Copying xfer directory to snippets..."
    cp -r xfer /var/lib/vz/snippets/
fi

# Create the VM-specific user-data file
echo "Creating cloud-init configuration..."

# Create initial VM-specific config
cat > "/var/lib/vz/snippets/user-data-${next_id}.yaml" << EOL
#cloud-config
hostname: ${vm_name}
manage_etc_hosts: true

# BEGIN: Cloud-init password reset prevention block (Added 2024-03-21)
# This block prevents cloud-init from resetting the password on subsequent boots
# If you experience issues with this block, you can safely remove everything
# between these BEGIN and END comments
disable_root: false
ssh_pwauth: true
manage_etc_hosts: true
preserve_hostname: false
manage_resolv_conf: true
resolv_conf:
  nameservers: ['8.8.8.8', '8.8.4.4']
  domain: localdomain
  search_domains: ['localdomain']

# Only run once
runcmd:
  - cloud-init clean
  - cloud-init clean -l
  - systemctl disable cloud-init
  - systemctl disable cloud-init-local
  - systemctl disable cloud-config
  - systemctl disable cloud-final
# END: Cloud-init password reset prevention block (Added 2024-03-21)

users:
  - name: sevminsec
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    home: /home/sevminsec
    shell: /bin/bash
    lock_passwd: false

chpasswd:
  list: |
    admin:ChangeMe123!
  expire: False
EOL

# Append the rest of the configuration from base template, excluding duplicate sections
cat /var/lib/vz/snippets/user-data.yaml | \
    sed 's/#cloud-config!//' | \
    grep -v '^#cloud-config' | \
    grep -v '^hostname:' | \
    grep -v '^manage_etc_hosts:' | \
    grep -v '^users:' -A 5 | \
    grep -v '^chpasswd:' -A 2 >> "/var/lib/vz/snippets/user-data-${next_id}.yaml"

# Verify the file was created
if [ ! -f "/var/lib/vz/snippets/user-data-${next_id}.yaml" ]; then
    echo "ERROR: Failed to create VM-specific user-data file"
    exit 1
fi

echo "Cloud-init configuration created successfully"

echo -e "\n=== Starting VM Creation ==="

echo "Creating VM from template..."
qm clone $template_id $next_id --name "$vm_name" --full --format qcow2

# Fix disk configuration immediately after cloning
echo "Configuring disk..."

# First, check if there's an unused disk and move it to scsi0 if needed
if qm config $next_id | grep -q "unused0"; then
    echo "Found unused disk, fixing attachment..."
    unused_disk=$(qm config $next_id | grep "unused0" | awk '{print $2}')
    qm set $next_id --scsi0 "$unused_disk"
    qm set $next_id --delete unused0
fi

# Verify scsi0 is properly configured
if ! qm config $next_id | grep -q "scsi0"; then
    echo "ERROR: Failed to configure disk properly"
    exit 1
fi

# Set proper boot configuration
echo "Setting boot configuration..."
qm set $next_id --boot order=scsi0
qm set $next_id --bootdisk scsi0

# Resize the disk
echo "Resizing disk to ${disk_size}G for VM ID $next_id"
qm resize $next_id scsi0 ${disk_size}G

echo "Configuring VM..."
# Set memory for the VM
echo "Setting memory to ${memory}MB for VM ID $next_id"
qm set $next_id --memory $memory

# Set number of CPU cores for the VM
echo "Setting number of cores to 2 for VM ID $next_id"
qm set $next_id --cores 2

# Configure network interface
echo "Configuring network interface with virtio on bridge $bridge and VLAN ID $vlan_id for VM ID $next_id"
qm set $next_id --net0 "virtio,bridge=$bridge${vlan_id:+,tag=$vlan_id}${mac_address:+,macaddr=$mac_address}"

# Set cloud-init configuration
echo "Setting cloud-init configuration for VM ID $next_id"
qm set $next_id --cicustom "user=local:snippets/user-data-${next_id}.yaml"

# Set the machine type to pc-i440fx-9.0
echo "Setting machine type to pc-i440fx-9.0 for VM ID $next_id"
qm set $next_id --machine pc-i440fx-9.0

# Always set the SCSI hardware type to virtio-scsi-single
echo "Setting SCSI hardware type to virtio-scsi-single for VM ID $next_id"
qm set $next_id --scsihw virtio-scsi-single

# Set BIOS to Default SEABIOS
echo "Setting BIOS to Default SEABIOS for VM ID $next_id"
qm set $next_id --bios seabios

# Set the disk size in Proxmox
echo "Setting disk size..."
max_attempts=5
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "Attempting to resize disk for VM ID $next_id (Attempt $attempt of $max_attempts)"
    qm resize $next_id scsi0 ${disk_size}G
    if [ $? -eq 0 ]; then
        echo "Disk size set successfully."
        echo "Disk size set to ${disk_size}G for VM ID $next_id"
        break
    else
        echo "Attempt $attempt failed. Retrying in 10 seconds..."
        sleep 10
        attempt=$((attempt + 1))
    fi
done

if [ $attempt -gt $max_attempts ]; then
    echo "Failed to set disk size in Proxmox after $max_attempts attempts. Please check the logs."
    exit 1
fi

# After creating the VM but before starting it
echo "Enabling QEMU Guest Agent..."
qm set $next_id --agent enabled=1

# Start the VM
qm start $next_id

# Send completion email
echo "Sending notification email..."
email_content="Subject: VM $vm_name (ID: $next_id) - Build Started

Your VM build has started.
VM Name: $vm_name
VM ID: $next_id

IMPORTANT: Initial setup will take 30-45 minutes to complete
- The system is installing many packages and tools
- High CPU usage (80%+) is normal during this process
- The login credentials will NOT work until cloud-init finishes
- You will receive another email when setup is complete

Default credentials (after setup completes):
Username: sevminsec
Password: ChangeMe123!

To check progress:
1. Watch CPU usage in Proxmox (high usage means still working)
2. Try to SSH: ssh sevminsec@<vm-ip>
   (SSH will work once setup is complete)"

echo "$email_content" | curl --url 'smtps://smtp.gmail.com:465' --ssl-reqd \
  --mail-from 'your-email@example.com' \
  --mail-rcpt 'recipient@example.com' \
  --user 'your-email@example.com:your-app-password' \
  --upload-file -

echo -e "\n=== IMPORTANT INFORMATION ==="
echo "VM $vm_name (ID: $next_id) has been created and started."
echo "Initial setup will take 30-45 minutes to complete:"
echo "1. Cloud-init is installing packages and configuring the system"
echo "2. High CPU usage (80%+) is normal during this process"
echo "3. Login credentials will NOT work until cloud-init finishes"
echo "4. You will receive an email when setup is complete"
echo ""
echo "Default credentials (after setup completes):"
echo "Username: sevminsec"
echo "Password: ChangeMe123!"
echo ""
echo "To monitor progress:"
echo "1. Watch CPU usage in Proxmox (high usage means still working)"
echo "2. Watch VM console: Select VM in Proxmox -> Console"
echo "3. Try: qm guest cmd $next_id network-get-interfaces"
echo "   When this command works, setup is nearly complete"
echo "4. Try to SSH: ssh sevminsec@<vm-ip>"
echo "   SSH will work once setup is complete"
echo "============================="

echo -e "\nTROUBLESHOOTING TEMPLATE ISSUES:"
echo "If you encounter issues with the template not having a proper disk attached,"
echo "you may need to run these commands on the template (replace 777 with your template ID):"
echo ""
echo "1. Check template configuration:"
echo "   qm config 777 | cat"
echo ""
echo "2. If you see 'unused0' instead of 'scsi0', fix it with:"
echo "   qm set 777 --scsi0 local-lvm:vm-777-disk-1"
echo ""
echo "3. Then run 2deploy.sh again to create your VM"
echo "=============================="