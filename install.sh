#!/bin/bash
# arch_install.sh
# Full automated installation script for Arch Linux, similar to archinstall.
#
# Steps performed:
# 1. Partitioning the selected disk (EFI, root, home)
# 2. Formatting and mounting partitions
# 3. Installing the base system and packages: nano, grub, efibootmgr, NetworkManager, hyprland, sudo
# 4. Generating fstab and basic system configuration (timezone, locale, hostname, GRUB, NetworkManager)
# 5. Creating a new user (with login, password, and optional sudo privileges)
#
# Usage:
#   sudo ./arch_install.sh /dev/sdX  or  sudo ./arch_install.sh /dev/nvme0n1
#
# WARNING: ALL DATA ON THE SELECTED DISK WILL BE DESTROYED!

set -e

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run the script as root (e.g. using sudo)."
    exit 1
fi

# Check command line parameter
if [ -z "$1" ]; then
    echo "Usage: $0 <disk>"
    exit 1
fi

DISK="$1"

echo "WARNING: All data on the device $DISK will be destroyed!"
read -rp "Are you sure you want to continue? [y/N] " answer
if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Operation cancelled."
    exit 1
fi

# Check if the device exists
if [ ! -b "$DISK" ]; then
    echo "Device $DISK not found!"
    exit 1
fi

echo "Starting partitioning of disk $DISK..."

# Create a new GPT partition table
parted -s "$DISK" mklabel gpt

echo "Creating EFI partition (1MiB - 513MiB)..."
parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$DISK" set 1 boot on

echo "Creating root partition (513MiB - 40GiB)..."
parted -s "$DISK" mkpart primary ext4 513MiB 40GiB

echo "Creating /home partition (40GiB - 100%)..."
parted -s "$DISK" mkpart primary ext4 40GiB 100%

# Define partition names (for NVMe disks, append "p")
if [[ "$DISK" == *nvme* ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
    HOME_PART="${DISK}p3"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
    HOME_PART="${DISK}3"
fi

echo "Formatting partitions..."
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 "$ROOT_PART"
mkfs.ext4 "$HOME_PART"

echo "Mounting partitions..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot
mkdir -p /mnt/home
mount "$HOME_PART" /mnt/home

echo "Installing base system and packages..."
pacstrap /mnt base linux linux-firmware base-devel nano grub efibootmgr networkmanager swww firefox sddm hyprland sudo

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "Entering chroot for basic system configuration..."
arch-chroot /mnt /bin/bash <<'CHROOT_EOF'
set -e

echo "Setting timezone..."
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

echo "Configuring locale..."
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "Setting hostname..."
echo "arch" > /etc/hostname
cat <<EOT > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   arch.localdomain arch
EOT

echo "Installing and configuring GRUB (UEFI)..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "Enabling NetworkManager..."
systemctl enable NetworkManager

CHROOT_EOF

# Prompt for new user information
read -rp "Enter the new username: " NEWUSER
read -rsp "Enter password for user $NEWUSER: " NEWPASS
echo
read -rp "Should the user $NEWUSER have sudo privileges? [y/N]: " SUPERMODE

echo "Creating user $NEWUSER..."

# Create the user in the chroot environment
arch-chroot /mnt /bin/bash <<EOF
set -e
useradd -m $NEWUSER
echo "$NEWUSER:$NEWPASS" | chpasswd
if [[ "$SUPERMODE" == "y" || "$SUPERMODE" == "Y" ]]; then
    usermod -aG wheel $NEWUSER
    # Add sudo privileges for wheel group if not already set
    if ! grep -q "^%wheel" /etc/sudoers; then
        echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
    fi
fi
EOF

echo "Installation complete!"
echo "After reboot, your system should boot up. Don't forget to remove the installation media."
