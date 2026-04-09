cat automation-cloud-image.sh 
#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Proxmox Ubuntu 24.04 Cloud-Init Template Creator
# Author: polson_r
# ------------------------------------------------------------------------------

# -----------------------------
# Default values
# -----------------------------
VMID=9999
VM_NAME="ubuntu-24.04"
MEMORY_MB=1024
CORES=1
BRIDGE="vmbr0"
NET_MODEL="virtio"
STORAGE="lvm-03"
CLOUD_DIR="/var/lib/vz/template/iso"

UBUNTU_IMG_URL="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
UBUNTU_IMG_FILE="ubuntu-24.04-server-cloudimg-amd64.img"

CI_USER="root"
IPCONFIG0="ip=dhcp"
DISK_RESIZE="8G"

# Authentication
SSH_PUBLIC_KEY=""
CI_PASSWORD=""

# -----------------------------
# Helper: ask question with default
# -----------------------------
ask() {
    local prompt="$1"
    local default="$2"
    local value
    read -p "$prompt [$default]: " value
    echo "${value:-$default}"
}

# -----------------------------
# Helper: secure input (no echo)
# -----------------------------
ask_secure() {
    local prompt="$1"
    local value
    read -s -p "$prompt: " value
    echo ""
    printf '%s' "$value"
}

# -----------------------------
# Interactive configuration
# -----------------------------
interactive_config() {
    echo ""
    echo "Configure VM parameters (press ENTER to use default value)"
    echo ""

    VMID=$(ask "VM ID" "$VMID")
    VM_NAME=$(ask "VM Name" "$VM_NAME")
    MEMORY_MB=$(ask "RAM (MB)" "$MEMORY_MB")
    CORES=$(ask "CPU Cores" "$CORES")
    BRIDGE=$(ask "Network Bridge" "$BRIDGE")
    STORAGE=$(ask "Storage" "$STORAGE")
    CI_USER=$(ask "Cloud-init User" "$CI_USER")
    IPCONFIG0=$(ask "IP Config" "$IPCONFIG0")
    DISK_RESIZE=$(ask "Disk Resize" "$DISK_RESIZE")
    
    # Authentication
    echo ""
    echo "--- Authentication Configuration ---"
    echo "Recommended: Use SSH keys for production"
    echo ""
    
    read -p "SSH Public Key (path or full key): " ssh_input
    if [[ -n "$ssh_input" ]]; then
        if [[ -f "$ssh_input" ]]; then
            SSH_PUBLIC_KEY=$(cat "$ssh_input")
        elif [[ -f "$HOME/.ssh/$ssh_input" ]]; then
            SSH_PUBLIC_KEY=$(cat "$HOME/.ssh/$ssh_input")
        else
            SSH_PUBLIC_KEY="$ssh_input"
        fi
    fi
    
    echo ""
    read -p "Set Cloud-Init password? (y/n) [n]: " set_password
    if [[ "$set_password" == "y" || "$set_password" == "Y" ]]; then
        CI_PASSWORD=$(ask_secure "Enter password")
        echo ""
        local confirm_password
        confirm_password=$(ask_secure "Confirm password")
        echo ""
        
        if [[ "$CI_PASSWORD" != "$confirm_password" ]]; then
            echo "ERROR: Passwords do not match!"
            exit 1
        fi
        
        if [[ ${#CI_PASSWORD} -lt 8 ]]; then
            echo "WARNING: Password is less than 8 characters!"
            read -p "Continue anyway? (y/n) [n]: " continue_weak
            if [[ "$continue_weak" != "y" && "$continue_weak" != "Y" ]]; then
                exit 1
            fi
        fi
    fi
    
    # Validation
    if [[ -z "$SSH_PUBLIC_KEY" && -z "$CI_PASSWORD" ]]; then
        echo ""
        echo "WARNING: No authentication configured!"
        read -p "Continue without auth? (NOT RECOMMENDED) (y/n) [n]: " continue_no_auth
        if [[ "$continue_no_auth" != "y" && "$continue_no_auth" != "Y" ]]; then
            exit 1
        fi
    fi
}

# -----------------------------
# Menu
# -----------------------------
menu() {
    echo ""
    echo "Proxmox Ubuntu 24.04 Cloud-Init Template Script"
    echo "-----------------------------------------------"
    echo ""
    echo "1) Install with default settings"
    echo "2) Customize parameters"
    echo "3) Exit"
    echo ""

    read -p "Select option: " choice

    case $choice in
        1)
            echo "Running with default settings..."
            ;;
        2)
            interactive_config
            ;;
        *)
            echo "Exit."
            exit 0
            ;;
    esac
}

# -----------------------------
# Parameter handling
# -----------------------------
if [[ $# -eq 0 ]]; then
    menu
fi

if [[ "${1:-}" == "--default" ]]; then
    echo "Running with default configuration..."
fi

# -----------------------------
# Preflight checks
# -----------------------------
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root."
    exit 1
fi

command -v qm >/dev/null || { echo "qm command not found"; exit 1; }
command -v wget >/dev/null || { echo "wget not found"; exit 1; }

UBUNTU_IMG_PATH="$CLOUD_DIR/$UBUNTU_IMG_FILE"
mkdir -p "$CLOUD_DIR"

# -----------------------------
# Download cloud image
# -----------------------------
if [[ ! -f "$UBUNTU_IMG_PATH" ]]; then
    echo "Downloading Ubuntu Cloud Image..."
    wget -q --show-progress -O "$UBUNTU_IMG_PATH" "$UBUNTU_IMG_URL"
else
    echo "Cloud image already exists."
fi

# -----------------------------
# Create VM
# -----------------------------
echo "Creating VM $VMID..."

if qm list 2>/dev/null | grep -q "^[[:space:]]*$VMID[[:space:]]"; then
    echo "ERROR: VM $VMID already exists!"
    exit 1
fi

qm create "$VMID" \
  --name "$VM_NAME" \
  --memory "$MEMORY_MB" \
  --cores "$CORES" \
  --net0 "${NET_MODEL},bridge=${BRIDGE}" \
  --bios seabios \
  --onboot 0

# -----------------------------
# Import disk
# -----------------------------
echo "Importing disk..."

qm importdisk "$VMID" "$UBUNTU_IMG_PATH" "$STORAGE"

IMPORTED_VOL="${STORAGE}:vm-${VMID}-disk-0"

# -----------------------------
# Configure disk
# -----------------------------
qm set "$VMID" \
  --scsihw virtio-scsi-single \
  --scsi0 "${IMPORTED_VOL},discard=on,ssd=1,iothread=1"

# -----------------------------
# Add cloud-init drive
# -----------------------------
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"


# -----------------------------
# OS Type configuration
# -----------------------------
qm set "$VMID" --ostype l26

# Boot configuration
# -----------------------------
qm set "$VMID" --boot c --bootdisk scsi0

# Enable QEMU agent
qm set "$VMID" --agent enabled=1

# -----------------------------
# Resize disk
# -----------------------------
qm resize "$VMID" scsi0 "$DISK_RESIZE"

# -----------------------------
# Cloud-init defaults
# -----------------------------
qm set "$VMID" --ciuser "$CI_USER"
qm set "$VMID" --ipconfig0 "$IPCONFIG0"

# SSH Key
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    echo "Configuring SSH public key..."
    qm set "$VMID" --sshkeys "$SSH_PUBLIC_KEY"
fi

# Password
if [[ -n "$CI_PASSWORD" ]]; then
    echo "Configuring Cloud-Init password..."
    qm set "$VMID" --cipassword "$CI_PASSWORD"
fi

# DNS
qm set "$VMID" --nameserver "8.8.8.8 8.8.4.4" 2>/dev/null || true

# -----------------------------
# Convert to template
# -----------------------------
echo "Converting VM to template..."

qm stop "$VMID" 2>/dev/null || true
sleep 2

qm template "$VMID"

echo ""
echo "=========================================="
echo "Template successfully created!"
echo "=========================================="
echo "VMID: $VMID"
echo "Name: $VM_NAME"
echo "User: $CI_USER"
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
    echo "SSH Key: configured"
else
    echo "SSH Key: NOT configured"
fi
if [[ -n "$CI_PASSWORD" ]]; then
    echo "Password: configured"
else
    echo "Password: NOT configured"
fi
echo "=========================================="
