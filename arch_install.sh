#!/bin/bash
# arch_install.sh
# Полный автоматизированный скрипт для установки Arch Linux, похожий на archinstall.
#
# Выполняемые действия:
# 1. Разметка выбранного диска (EFI, root, home)
# 2. Форматирование и монтирование разделов
# 3. Установка базовой системы и дополнительных пакетов: nano, grub, NetworkManager, hyprland
# 4. Генерация fstab и базовая настройка системы (timezone, locale, hostname, GRUB, NetworkManager)
#
# Использование:
#   sudo ./arch_install.sh /dev/sdX или /dev/nvme0n1
#
# ВНИМАНИЕ: ВСЕ ДАННЫЕ НА ВЫБРАННОМ ДИСКЕ БУДУТ УДАЛЕНЫ!

set -e

# Проверка прав суперпользователя
if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите скрипт от имени root (например, через sudo)."
    exit 1
fi

# Проверка параметров
if [ -z "$1" ]; then
    echo "Использование: $0 <диск>"
    exit 1
fi

DISK="$1"

echo "ВНИМАНИЕ: все данные на устройстве $DISK будут уничтожены!"
read -rp "Вы уверены, что хотите продолжить? [y/N] " answer
if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Операция прервана."
    exit 1
fi

# Проверка существования устройства
if [ ! -b "$DISK" ]; then
    echo "Устройство $DISK не найдено!"
    exit 1
fi

echo "Начинаем разметку диска $DISK..."

# Создаем новую GPT-разметку
parted -s "$DISK" mklabel gpt

echo "Создаем EFI-раздел (1MiB - 513MiB)..."
parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$DISK" set 1 boot on

echo "Создаем корневой раздел (513MiB - 40GiB)..."
parted -s "$DISK" mkpart primary ext4 513MiB 40GiB

echo "Создаем раздел для /home (40GiB - 100%)..."
parted -s "$DISK" mkpart primary ext4 40GiB 100%

# Определяем имена разделов (для NVMe-дисков добавляется "p")
if [[ "$DISK" == *nvme* ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
    HOME_PART="${DISK}p3"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
    HOME_PART="${DISK}3"
fi

echo "Форматирование разделов..."
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 "$ROOT_PART"
mkfs.ext4 "$HOME_PART"

echo "Монтирование разделов..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot
mkdir -p /mnt/home
mount "$HOME_PART" /mnt/home

echo "Установка базовой системы и пакетов..."
pacstrap /mnt base linux linux-firmware base-devel nano grub networkmanager hyprland

echo "Генерация fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "Настройка системы в chroot..."
arch-chroot /mnt /bin/bash <<'EOF'
set -e

echo "Настройка часового пояса..."
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

echo "Настройка локали..."
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "Настройка имени хоста..."
echo "arch" > /etc/hostname
cat <<EOT > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   arch.localdomain arch
EOT

echo "Установка и настройка загрузчика GRUB (UEFI)..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "Включение NetworkManager..."
systemctl enable NetworkManager

EOF

echo "Установка завершена! После перезагрузки ваша система должна загрузиться."
echo "Не забудьте извлечь установочный носитель перед перезагрузкой."
