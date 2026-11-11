#!/bin/sh
# Victoria Housekeeping - minimal Alpine *edge* live ISO with an interactive
# installer, themed around Corin Wickes (Zenless Zone Zero).
#
#   sh build.sh      -> ./out/alpine-corin-edge-x86_64.iso
#   (also works unchanged as: bash build.sh  /  zsh build.sh)
#
# Needs Docker + network access on the build machine.
set -eu

ALPINE_VER="${ALPINE_VER:-edge}"
case "$ALPINE_VER" in
	edge) BRANCH=master ;;
	*)    BRANCH="${ALPINE_VER}-stable" ;;
esac

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/work"
OV="$WORK/overlay"
SKEL="$OV/usr/local/share/corin/skel"
rm -rf "$OV"
mkdir -p "$HERE/out" "$OV/root" "$OV/usr/local/bin" \
	"$SKEL/.config/berry" "$SKEL/.config/sxhkd" "$SKEL/.config/conky" \
	"$SKEL/.config/polybar" "$SKEL/.config/rofi" "$SKEL/.config/kitty" \
	"$OV/usr/local/share/corin/sddm-theme" "$SKEL/.local/share/applications"
chmod 777 "$HERE/out"

# ---------------------------------------------------------------- wallpaper
# Drop your own image at wallpaper/custom.png (or .jpg) next to this script to
# use it. Otherwise an original generated wallpaper in the theme colors is used.
mkdir -p "$HERE/wallpaper"
rm -f "$WORK"/wallpaper-custom.*
WP_CUSTOM=""
for f in "$HERE/wallpaper/custom.png" "$HERE/wallpaper/custom.jpg" "$HERE/wallpaper/custom.jpeg"; do
	if [ -f "$f" ]; then WP_CUSTOM="$f"; break; fi
done
if [ -n "$WP_CUSTOM" ]; then
	WP_EXT="${WP_CUSTOM##*.}"
	cp "$WP_CUSTOM" "$WORK/wallpaper-custom.$WP_EXT"
	WALL_CMD="cp /work/wallpaper-custom.$WP_EXT /home/build/wallpaper.$WP_EXT"
else
	WALL_CMD="rsvg-convert -w 2560 -h 1440 /work/wallpaper.svg -o /home/build/wallpaper.png"
fi

cat > "$WORK/wallpaper.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080">
  <defs>
    <radialGradient id="glow" cx="75%" cy="40%" r="75%">
      <stop offset="0" stop-color="#3a0a18"/>
      <stop offset="1" stop-color="#0b0b10"/>
    </radialGradient>
    <pattern id="teeth" width="48" height="36" patternUnits="userSpaceOnUse">
      <path d="M0 36 L24 0 L48 36 Z" fill="#e3103c"/>
    </pattern>
    <pattern id="ruffle" width="40" height="20" patternUnits="userSpaceOnUse">
      <circle cx="20" cy="0" r="20" fill="#e8e8f0"/>
    </pattern>
  </defs>

  <rect width="1920" height="1080" fill="url(#glow)"/>

  <g transform="rotate(-18 960 540)">
    <rect x="-400" y="260" width="2800" height="90" fill="#e3103c" opacity="0.14"/>
    <rect x="-400" y="420" width="2800" height="40" fill="#ff5c8a" opacity="0.10"/>
    <rect x="-400" y="720" width="2800" height="120" fill="#e3103c" opacity="0.12"/>
  </g>

  <rect width="1920" height="20" fill="#e8e8f0"/>
  <rect y="20" width="1920" height="20" fill="url(#ruffle)"/>
  <rect y="1044" width="1920" height="36" fill="url(#teeth)"/>
  <rect y="1038" width="1920" height="6" fill="#e8e8f0"/>

  <g fill="none">
    <circle cx="1500" cy="620" r="300" stroke="#e3103c" stroke-width="6" opacity="0.8"/>
    <circle cx="1500" cy="620" r="262" stroke="#ff5c8a" stroke-width="2" opacity="0.7"/>
  </g>
  <polygon points="1350,460 1430,460 1500,680 1570,460 1650,460 1530,790 1470,790"
           fill="#ff5c8a" stroke="#e3103c" stroke-width="8" stroke-linejoin="round"/>

  <g font-family="DejaVu Sans, sans-serif" font-weight="bold">
    <text x="140" y="520" font-size="150" letter-spacing="8" fill="#e8e8f0">VICTORIA</text>
    <text x="146" y="610" font-size="70" letter-spacing="6" fill="#e3103c">HOUSEKEEPING CO.</text>
  </g>
  <text x="150" y="676" font-family="DejaVu Sans, sans-serif" font-size="30" fill="#8c8c99">Stains don't stand a chance.</text>
</svg>
EOF

# =====================================================================
# mkimage profile
# =====================================================================
cat > "$WORK/mkimg.corin.sh" <<'EOF'
profile_corin() {
	profile_base
	title="CorinOS"
	desc="Victoria Housekeeping Co. live installer"
	profile_abbrev="corin"
	image_ext="iso"
	arch="x86_64"
	output_format="iso"
	hostname="victoria"
	kernel_flavors="stable"
	kernel_cmdline="console=tty0 quiet loglevel=3 modloop_verify=no"
	# NOTE: mkimage's update-kernel already bundles the firmware that the kernel's
	# drivers ask for into the modloop (and adds wireless-regdb). Do not also
	# install linux-firmware into the live RAM filesystem: it is ~750 MB.
	apks="$apks alpine-base busybox-suid nano vim htop \
		e2fsprogs dosfstools sfdisk cfdisk lsblk util-linux-misc \
		syslinux grub grub-efi efibootmgr pciutils usbutils \
		wpa_supplicant iw wireless-regdb"
	# Per-vendor network firmware (list built from the live repo at build time).
	# These sit in the ISO's package repo; corin-fw-load installs only what is needed.
	apks="$apks $(cat /home/build/fwpkgs 2>/dev/null)"
	local _k
	for _k in $kernel_flavors; do
		apks="$apks linux-$_k"
	done
	apkovl="genapkovl-corin.sh"
}
EOF
# =====================================================================
# apkovl generator
# =====================================================================
cat > "$WORK/genapkovl-corin.sh" <<'EOF'
#!/bin/sh -e
HOSTNAME="$1"
[ -n "$HOSTNAME" ] || exit 1

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

rc_add() {
	mkdir -p "$tmp/etc/runlevels/$2"
	ln -sf "/etc/init.d/$1" "$tmp/etc/runlevels/$2/$1"
}

cp -a /work/overlay/. "$tmp"/

mkdir -p "$tmp/etc/apk"
cat > "$tmp/etc/apk/world" <<WORLD
alpine-base
busybox-suid
nano
htop
wpa_supplicant
iw
wireless-regdb
pciutils
usbutils
e2fsprogs
dosfstools
sfdisk
cfdisk
lsblk
util-linux-misc
efibootmgr
syslinux
grub
grub-efi
WORLD

mkdir -p "$tmp/usr/local/share/corin/skel/.local/share/corin"
cp /home/build/wallpaper.* "$tmp/usr/local/share/corin/skel/.local/share/corin/" 2>/dev/null || true
mkdir -p "$tmp/etc"
echo "$HOSTNAME" > "$tmp/etc/hostname"
chown -R root:root "$tmp" 2>/dev/null || true

for s in devfs dmesg mdev hwdrivers modloop; do rc_add $s sysinit; done
for s in hwclock modules sysctl hostname bootmisc syslog; do rc_add $s boot; done
for s in mount-ro killprocs savecache; do rc_add $s shutdown; done

# Late reload of wireless modules so they pick up firmware from the overlay
mkdir -p "$tmp/etc/local.d"
cat > "$tmp/etc/local.d/wifi-reload.start" <<'WIFIEOF'
#!/bin/sh
# Unblock radios
rfkill unblock all 2>/dev/null || true

# If no wireless interface exists yet, force-load the common drivers
if ! ip link show | grep -q -E 'wlan|wlp'; then
	for mod in iwlwifi ath9k ath10k_pci ath11k_pci rtw88_pci rtw89pci \
	           mt76 mt76x2e mt76x2u mt7603e mt7615e brcmfmac; do
		modprobe -r "$mod" 2>/dev/null || true
		modprobe "$mod" 2>/dev/null || true
	done
	sleep 1
fi

WIFIEOF
chmod 755 "$tmp/etc/local.d/wifi-reload.start"
cat > "$tmp/etc/local.d/10-corin-fw.start" <<'FWEOF'
#!/bin/sh
# Remember the ISO's own package repo, then fetch any missing firmware from it.
cp /etc/apk/repositories /etc/apk/repositories.iso 2>/dev/null
corin-fw-load > /tmp/fw-load.log 2>&1
exit 0
FWEOF
chmod 755 "$tmp/etc/local.d/10-corin-fw.start"
rc_add local default

tar -c -C "$tmp" . | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
EOF
chmod +x "$WORK/genapkovl-corin.sh"
# =====================================================================
# Live-system files
# =====================================================================
mkdir -p "$OV/etc"
: > "$OV/etc/motd"

cat > "$OV/etc/inittab" <<'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
tty1::respawn:/bin/login -f root
tty2::respawn:/sbin/getty 38400 tty2
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF

cat > "$OV/root/.profile" <<'EOF'
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$CORIN_SHOWN" ]; then
	export CORIN_SHOWN=1
	corin-greeter
fi
PS1='\[\e[1;31m\]corin\[\e[0m\]@\[\e[1;37m\]\h\[\e[0m\]:\w \[\e[1;35m\]\$\[\e[0m\] '
alias ls='ls --color=auto'
EOF

# ---------------------------------------------------------------- greeter
cat > "$OV/usr/local/bin/corin-greeter" <<'EOF'
#!/bin/sh
# Console palette: black / crimson / white / pink. Edit hex values to retheme.
pal() { printf '\033]P%s%s' "$1" "$2"; }
pal 0 0b0b10; pal 1 e3103c; pal 2 8c8c99; pal 3 ff9db8
pal 4 5a5a6e; pal 5 ff5c8a; pal 6 c9c9d6; pal 7 e8e8f0
pal 8 2a2a35; pal 9 ff2d55; pal A b0b0bd; pal B ffc2d4
pal C 7a7a90; pal D ff85a8; pal E e0e0ea; pal F ffffff
printf '\033[0;37;40m\033[2J\033[H'

R='\033[1;31m'; W='\033[1;37m'; P='\033[1;35m'; G='\033[0;90m'; N='\033[0m'

printf "$R"
cat <<'ART'

   ___ ___  ___ ___ _  _    ___  ___ 
  / __/ _ \| _ \_ _| \| |  / _ \/ __|
 | (_| (_) |   /| || .` | | (_) \__ \
  \___\___/|_|_\___|_|\_|  \___/|___/
                                     
ART
printf "$W   V I C T O R I A   H O U S E K E E P I N G   C O .$N\n"
printf "$G   ------------------------------------------------$N\n\n"
printf "  ${P}Maid on duty:${N} Corin Wickes\n"
printf "  ${P}Job         :${N} Moving you into a spotless new system\n\n"
printf "  ${G}Ctrl+C at any prompt drops to a shell. Re-run with: corin-install${N}\n\n"
sleep 2

corin-install
printf "\n${G}Installer exited. Run corin-install to retry, or poweroff.${N}\n\n"
EOF

# ---------------------------------------------------------------- installer
cat > "$OV/usr/local/bin/corin-install" <<'EOF'
#!/bin/sh
# Victoria Housekeeping installer: disk, user, password, browser -> desktop.
set -u

R='\033[1;31m'; W='\033[1;37m'; P='\033[1;35m'; G='\033[0;90m'; N='\033[0m'
say()  { printf "${P}::${N} %s\n" "$*"; }
warn() { printf "${R}!!${N} %s\n" "$*"; }
die()  { warn "$*"; exit 1; }
ask()  { printf "${R}>${N} %s" "$1"; read -r REPLY || exit 1; }

trap 'stty echo 2>/dev/null' EXIT INT
[ "$(id -u)" = 0 ] || die "Run as root."

SKEL=/usr/local/share/corin/skel
HOST=victoria

# ------------------------------------------------------------ network
# ------------------------------------------------------------ hardware / drivers
KV=$(uname -r)
have_nic() {
	for d in /sys/class/net/*; do
		[ "$(basename "$d")" != "lo" ] && return 0
	done
	return 1
}

# Make sure the kernel modules (modloop) are mounted and drivers are loaded.
ensure_hw() {
	if [ ! -d "/lib/modules/$KV" ]; then
		warn "Kernel modules are missing (modloop not mounted). Trying to mount it..."
		rc-service modloop start >/dev/null 2>&1
	fi
	if [ ! -d "/lib/modules/$KV" ]; then
		ML=$(find /media -maxdepth 3 -name 'modloop-*' 2>/dev/null | head -1)
		if [ -n "$ML" ]; then
			mkdir -p /.modloop /lib/modules
			mountpoint -q /.modloop || mount -o loop,ro "$ML" /.modloop
			mount --bind /.modloop/modules /lib/modules 2>/dev/null
			if [ -d /.modloop/modules/firmware ]; then
				mkdir -p /lib/firmware
				mount --bind /.modloop/modules/firmware /lib/firmware 2>/dev/null
			fi
		fi
	fi
	if [ -d "/lib/modules/$KV" ]; then
		find /sys/devices -name modalias -type f -exec cat {} + 2>/dev/null \
			| xargs modprobe -b -a 2>/dev/null
		sleep 3
		corin-fw-load >/dev/null 2>&1
	fi
}

net_support_info() {
	{
		echo "kernel: $KV"
		echo "--- /lib/modules:";        ls /lib/modules 2>&1
		echo "--- modloop files on media:"; find /media -maxdepth 3 -name 'modloop-*' 2>&1
		echo "--- mounts (media/modloop):"; mount | grep -i -E 'media|modloop'
		echo "--- modules loaded: $(lsmod 2>/dev/null | wc -l)"
		echo "--- PCI network:";          lspci -nnk 2>/dev/null | grep -A3 -i -E 'network|ethernet|wireless'
		echo "--- USB:";                  lsusb 2>/dev/null
		echo "--- dmesg (tail):";         dmesg | tail -25
	} > /tmp/netdiag.txt 2>&1
	cat /tmp/netdiag.txt
}

SHOWN=0
while ! have_nic; do
	ensure_hw
	have_nic && break
	warn "No network interfaces found."
	if [ "$SHOWN" = 0 ]; then net_support_info; SHOWN=1; say "(saved to /tmp/netdiag.txt)"; fi
	ask "Plug in Ethernet or a USB-tethered phone, then press Enter to rescan (q = quit): "
	[ "$REPLY" = "q" ] && exit 1
done

# Alpine's own network setup (setup-interfaces) handles Ethernet and Wi-Fi.
online() { timeout 8 ping -c1 -W3 dl-cdn.alpinelinux.org >/dev/null 2>&1; }

if ! online; then
	say "No network yet. Launching Alpine's network setup..."
	rfkill unblock all 2>/dev/null || true
	setup-interfaces -r
	n=0
	while ! online && [ "$n" -lt 3 ]; do n=$((n + 1)); sleep 2; done
	online || die "Still offline. Run setup-interfaces, then re-run corin-install."
fi

cat > /etc/apk/repositories <<REPOS
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
https://dl-cdn.alpinelinux.org/alpine/edge/testing
REPOS
ntpd -q -n -p pool.ntp.org >/dev/null 2>&1 || true
apk update >/dev/null || die "apk update failed."

# ------------------------------------------------------------ disk
LIVEDEV=$(grep ' /media/' /proc/mounts | awk '{print $1}' | sed 's/p\?[0-9]*$//' | head -1)
DISKS=$(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}' \
	| grep -v -e '^/dev/loop' -e '^/dev/ram' -e '^/dev/zram' -e '^/dev/fd' \
	| { [ -n "$LIVEDEV" ] && grep -vx "$LIVEDEV" || cat; })
[ -n "$DISKS" ] || die "No installable disks found."

echo
say "Available drives:"
i=0
for d in $DISKS; do
	i=$((i + 1))
	printf "   ${W}%d)${N} %s\n" "$i" "$(lsblk -dpno NAME,SIZE,MODEL "$d")"
done
echo
while :; do
	ask "Install to which drive? [1-$i]: "
	case "$REPLY" in ''|*[!0-9]*) continue ;; esac
	[ "$REPLY" -ge 1 ] && [ "$REPLY" -le "$i" ] && break
done
DISK=$(echo "$DISKS" | sed -n "${REPLY}p")

# ------------------------------------------------------------ swap size
# Swap = 2x installed RAM; none when the machine has more than 64 GB.
RAM_KB=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
RAM_GB=$(( (RAM_KB + 1048575) / 1048576 ))
if [ "$RAM_GB" -gt 64 ]; then
	SWAP_MB=0
else
	SWAP_MB=$((RAM_GB * 2 * 1024))
fi
DISK_MB=$(( $(lsblk -bdno SIZE "$DISK" | head -1) / 1048576 ))
SWAP_NOTE=""
if [ "$SWAP_MB" -gt 0 ] && [ $((SWAP_MB + 8192)) -gt "$DISK_MB" ]; then
	SWAP_MB=$((DISK_MB - 8192))
	[ "$SWAP_MB" -lt 0 ] && SWAP_MB=0
	SWAP_NOTE=" (reduced: the drive is too small for 2x RAM)"
fi

# ------------------------------------------------------------ partitioning mode
ROOTPART=""; ESP_CHOSEN=""; SWAPPART=""
echo
say "Partitioning:"
printf "   ${W}1)${N} Automatic  (erase the whole drive; swap = 2x RAM, none above 64 GB)\n"
printf "   ${W}2)${N} Manual     (cfdisk, then choose the root / EFI / swap partitions)\n"
while :; do
	ask "Choice [1-2]: "
	case "$REPLY" in 1) PART_MODE=auto ;; 2) PART_MODE=manual ;; *) continue ;; esac
	break
done

list_parts() {
	PARTS=$(lsblk -lnpo NAME,TYPE "$DISK" | awk '$2=="part"{print $1}')
	[ -n "$PARTS" ] || return 1
	i=0
	for p in $PARTS; do
		i=$((i + 1))
		printf "   ${W}%d)${N} %s\n" "$i" "$(lsblk -dpno NAME,SIZE,FSTYPE,PARTTYPENAME "$p" | tr -s ' ')"
	done
}
pick_part() {   # $1 = prompt, $2 = "optional" to allow Enter for none
	PICK=""
	while :; do
		ask "$1"
		if [ -z "$REPLY" ] && [ "${2:-}" = "optional" ]; then return 0; fi
		case "$REPLY" in ''|*[!0-9]*) continue ;; esac
		PICK=$(echo "$PARTS" | sed -n "${REPLY}p")
		[ -n "$PICK" ] && return 0
	done
}

if [ "$PART_MODE" = manual ]; then
	SWAP_MB=0
	command -v cfdisk >/dev/null 2>&1 || die "cfdisk is missing from this image."
	echo
	say "cfdisk will open on $DISK. Create:"
	printf "   - a root partition (type: Linux filesystem)\n"
	if [ -d /sys/firmware/efi ]; then
		printf "   - an EFI System partition, about 512 MB (type: EFI System)\n"
	else
		printf "   - BIOS boot: use an MBR (dos) label and mark the root partition bootable\n"
	fi
	printf "   - optionally a swap partition (type: Linux swap)\n"
	printf "   Choose Write, then Quit.\n"
	ask "Press Enter to start cfdisk: "
	cfdisk "$DISK"
	blockdev --rereadpt "$DISK" 2>/dev/null
	mdev -s 2>/dev/null
	sleep 1
	echo
	say "Partitions on $DISK:"
	list_parts || die "No partitions found on $DISK."
	echo
	pick_part "Root partition [number]: ";                  ROOTPART=$PICK
	if [ -d /sys/firmware/efi ]; then
		pick_part "EFI System partition [number]: ";        ESP_CHOSEN=$PICK
	fi
	pick_part "Swap partition [number, Enter = none]: " optional; SWAPPART=$PICK
	[ "$ROOTPART" != "$ESP_CHOSEN" ] && [ "$ROOTPART" != "$SWAPPART" ] \
		|| die "The root partition cannot also be the EFI or swap partition."
	[ -z "$SWAPPART" ] || [ "$SWAPPART" != "$ESP_CHOSEN" ] \
		|| die "The swap partition cannot also be the EFI partition."
fi

# ------------------------------------------------------------ user
echo
while :; do
	ask "Username: "
	USERNAME=$REPLY
	echo "$USERNAME" | grep -Eq '^[a-z_][a-z0-9_-]{0,31}$' \
		&& [ "$USERNAME" != root ] && break
	warn "Use lowercase letters, digits, - or _ (not 'root')."
done

while :; do
	printf "${R}>${N} Password (also used for root): "; stty -echo; read -r PW1; stty echo; echo
	printf "${R}>${N} Confirm password: ";              stty -echo; read -r PW2; stty echo; echo
	[ -n "$PW1" ] && [ "$PW1" = "$PW2" ] && break
	warn "Passwords empty or not matching, try again."
done

# ------------------------------------------------------------ browser
echo
say "Web browser:"
printf "   ${W}1)${N} Chromium\n   ${W}2)${N} Firefox\n   ${W}3)${N} None\n"
while :; do
	ask "Choice [1-3]: "
	case "$REPLY" in 1|2|3) break ;; esac
done
case "$REPLY" in
	1) BROWSER_PKG=chromium; BROWSER_CMD=chromium ;;
	2) BROWSER_PKG=firefox;  BROWSER_CMD=firefox ;;
	3) BROWSER_PKG="";       BROWSER_CMD="kitty --hold sh -c 'echo No browser installed: doas apk add firefox'" ;;
esac

# ------------------------------------------------------------ shell
echo
say "Login shell:"
printf "   ${W}1)${N} bash\n   ${W}2)${N} zsh\n   ${W}3)${N} ash (Alpine default)\n"
while :; do
	ask "Choice [1-3, Enter = bash]: "
	case "$REPLY" in
		''|1) USER_SHELL=/bin/bash ;;
		2)    USER_SHELL=/bin/zsh ;;
		3)    USER_SHELL=/bin/ash ;;
		*)    continue ;;
	esac
	break
done

# ------------------------------------------------------------ secure boot
SB=0
SB_ENROLLED=0
if [ -d /sys/firmware/efi ]; then
	echo
	say "Secure Boot:"
	printf "   Builds a signed unified kernel image using your own keys (sbctl).\n"
	printf "   To enroll them, the firmware must be in ${W}Setup Mode${N}\n"
	printf "   (clear/erase the Secure Boot keys in firmware setup first).\n"
	ask "Configure Secure Boot? [Y/n]: "
	case "$REPLY" in n|N) ;; *) SB=1 ;; esac
else
	warn "Booted in legacy BIOS mode: Secure Boot needs UEFI, skipping."
fi

# ------------------------------------------------------------ confirm
echo
say "Summary"
if [ "$PART_MODE" = auto ]; then
	printf "   Drive    : %s  (ALL DATA WILL BE ERASED)\n" "$DISK"
	if [ "$SWAP_MB" -gt 0 ]; then
		printf "   Swap     : %s MB (2x %s GB RAM)%s\n" "$SWAP_MB" "$RAM_GB" "$SWAP_NOTE"
	else
		printf "   Swap     : none (%s GB RAM)\n" "$RAM_GB"
	fi
else
	printf "   Drive    : %s (manual partitions)\n" "$DISK"
	printf "   Root     : %s (will be formatted ext4)\n" "$ROOTPART"
	[ -n "$ESP_CHOSEN" ] && printf "   EFI      : %s\n" "$ESP_CHOSEN"
	[ -n "$SWAPPART" ]   && printf "   Swap     : %s (will be formatted)\n" "$SWAPPART"
fi
printf "   User     : %s (shell: %s)\n   Browser  : %s\n" "$USERNAME" "$USER_SHELL" "${BROWSER_PKG:-none}"
printf "   SecureBoot: %s\n\n" "$([ "$SB" = 1 ] && echo yes || echo no)"
if [ "$PART_MODE" = auto ]; then
	ask "Type the drive name ($DISK) to confirm: "
	[ "$REPLY" = "$DISK" ] || die "Confirmation did not match. Nothing was changed."
else
	ask "Type 'yes' to format the selected partitions and install: "
	[ "$REPLY" = "yes" ] || die "Confirmation did not match. Nothing was changed."
fi

# ------------------------------------------------------------ base install
say "Partitioning and installing base system (this takes a while)..."
echo "$HOST" > /etc/hostname
export ERASE_DISKS="$DISK"
if [ "$PART_MODE" = auto ]; then
	setup-disk -m sys -k stable -s "$SWAP_MB" "$DISK" || die "setup-disk failed."
	ROOTPART=$(lsblk -lnpo NAME,FSTYPE "$DISK" | awk '$2=="ext4"{print $1; exit}')
	[ -n "$ROOTPART" ] || die "Could not find the new root partition."
	mountpoint -q /mnt || mount "$ROOTPART" /mnt || die "Could not mount $ROOTPART."
else
	MKFS_OPT=""
	[ -d /sys/firmware/efi ] || MKFS_OPT="-O ^64bit"
	say "Formatting $ROOTPART..."
	mkfs.ext4 -F -q $MKFS_OPT "$ROOTPART" || die "mkfs.ext4 failed."
	mount "$ROOTPART" /mnt || die "Could not mount $ROOTPART."
	if [ -n "$ESP_CHOSEN" ]; then
		# Only format the EFI partition if it has no filesystem yet (keeps other OSes bootable).
		[ -n "$(blkid -s TYPE -o value "$ESP_CHOSEN")" ] || mkfs.vfat -F32 "$ESP_CHOSEN" >/dev/null
		mkdir -p /mnt/boot/efi
		mount "$ESP_CHOSEN" /mnt/boot/efi || die "Could not mount the EFI partition."
	fi
	if [ -n "$SWAPPART" ]; then
		mkswap "$SWAPPART" >/dev/null && swapon "$SWAPPART"
	fi
	setup-disk -m sys -k stable /mnt || die "setup-disk failed."
	if [ -n "$SWAPPART" ]; then
		echo "UUID=$(blkid -s UUID -o value "$SWAPPART") none swap sw 0 0" >> /mnt/etc/fstab
	fi
fi

mount --bind /dev /mnt/dev
mount -t proc proc /mnt/proc
mount -t sysfs sys /mnt/sys
cp /etc/resolv.conf /mnt/etc/resolv.conf
cp /etc/apk/repositories /mnt/etc/apk/repositories
C="chroot /mnt"

# ------------------------------------------------------------ packages
say "Installing desktop packages..."
$C apk update >/dev/null
$C apk add xorg-server xf86-input-libinput xf86-video-vesa mesa-dri-gallium \
	eudev xinit xsetroot feh kitty xclip xdotool dbus doas bash zsh \
	networkmanager networkmanager-tui networkmanager-wifi wpa_supplicant iw \
	sddm elogind polkit-elogind i3lock fzf \
	sxhkd conky rofi polybar font-dejavu font-noto-emoji \
	|| die "Core desktop packages failed to install."
$C apk add berry || die "Could not install berry (berrywm)."
$C apk add rofi-emoji || warn "rofi-emoji unavailable; emoji picker will not work."
[ -n "$BROWSER_PKG" ] && { $C apk add "$BROWSER_PKG" || warn "Browser install failed."; }

say "Installing firmware and CPU microcode..."
$C apk add linux-firmware wireless-regdb || warn "linux-firmware failed; some GPU/Wi-Fi hardware may not work."
if grep -q GenuineIntel /proc/cpuinfo; then UCODE=intel-ucode
elif grep -q AuthenticAMD /proc/cpuinfo; then UCODE=amd-ucode
else UCODE=""; fi
if [ -n "$UCODE" ]; then
	$C apk add "$UCODE" || warn "$UCODE failed to install."
fi
# Regenerate boot config so the microcode image is picked up.
if [ -f /mnt/boot/grub/grub.cfg ]; then
	$C grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
elif [ -x /mnt/sbin/update-extlinux ]; then
	$C update-extlinux >/dev/null 2>&1
fi

# ------------------------------------------------------------ secure boot setup
sb_setup() {
	ESPPART="${ESP_CHOSEN:-$(lsblk -lnpo NAME,FSTYPE "$DISK" | awk '$2=="vfat"{print $1; exit}')}"
	[ -n "$ESPPART" ] || { warn "No EFI system partition found."; return 1; }
	mkdir -p /mnt/boot/efi
	mountpoint -q /mnt/boot/efi || mount "$ESPPART" /mnt/boot/efi || return 1

	$C apk add secureboot-hook systemd-efistub efibootmgr sbctl || return 1

	# Point the UKI generator at the new root filesystem.
	ROOTUUID=$(blkid -s UUID -o value "$ROOTPART")
	CONF=/mnt/etc/kernel-hooks.d/secureboot.conf
	mkdir -p /mnt/etc/kernel-hooks.d
	touch "$CONF"
	sed -i -e '/^cmdline=/d' -e '/^output_dir=/d' -e '/^output_name=/d' "$CONF"
	cat >> "$CONF" <<SBEOF
cmdline="root=UUID=$ROOTUUID rootfstype=ext4 modules=sd-mod,usb-storage,ext4 quiet"
output_dir="/boot/efi/EFI/Linux"
output_name="alpine-linux-{flavor}.efi"
SBEOF

	$C apk fix kernel-hooks >/dev/null 2>&1
	UKI=$(ls /mnt/boot/efi/EFI/Linux/alpine-linux-*.efi 2>/dev/null | head -1)
	[ -n "$UKI" ] || { warn "Unified kernel image was not generated."; return 1; }

	# Own keys + sign the UKI (and keep it signed across kernel upgrades).
	$C sbctl create-keys || return 1
	$C sbctl sign -s "${UKI#/mnt}" || return 1
	mkdir -p /mnt/etc/apk/commit_hooks.d
	cat > /mnt/etc/apk/commit_hooks.d/sbctl-sign.sh <<'SBEOF'
#!/bin/sh
[ "$1" = "post-commit" ] || exit 0
sbctl sign-all >/dev/null 2>&1 || true
exit 0
SBEOF
	chmod 755 /mnt/etc/apk/commit_hooks.d/sbctl-sign.sh

	# Firmware boot entry for the signed UKI.
	mountpoint -q /sys/firmware/efi/efivars || mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null
	PN=$(cat "/sys/class/block/${ESPPART#/dev/}/partition")
	efibootmgr --create --disk "$DISK" --part "$PN" --label "Alpine Linux" \
		--loader "\\EFI\\Linux\\$(basename "$UKI")" >/dev/null \
		|| warn "Could not create the firmware boot entry."

	# Enroll keys (works only while the firmware is in Setup Mode).
	mkdir -p /mnt/sys/firmware/efi/efivars
	mountpoint -q /mnt/sys/firmware/efi/efivars \
		|| mount -t efivarfs efivarfs /mnt/sys/firmware/efi/efivars 2>/dev/null
	if $C sbctl enroll-keys -m; then
		SB_ENROLLED=1
	else
		warn "Key enrollment failed (firmware probably not in Setup Mode)."
	fi
	return 0
}

SB_DONE=0
if [ "$SB" = 1 ]; then
	say "Configuring Secure Boot..."
	if sb_setup; then SB_DONE=1
	else warn "Secure Boot setup incomplete. GRUB still boots with Secure Boot OFF."; fi
fi

# ------------------------------------------------------------ system config
say "Configuring system..."
echo "$HOST" > /mnt/etc/hostname
printf '127.0.0.1\tlocalhost %s\n::1\t\tlocalhost %s\n' "$HOST" "$HOST" > /mnt/etc/hosts

# NetworkManager owns the real interfaces; ifupdown only brings up loopback.
mkdir -p /mnt/etc/network
printf 'auto lo\niface lo inet loopback\n' > /mnt/etc/network/interfaces
# Carry the Wi-Fi network chosen during install over to NetworkManager.
WPA=/etc/wpa_supplicant/wpa_supplicant.conf
if [ -f "$WPA" ]; then
	W_SSID=$(sed -n 's/^[[:space:]]*ssid="\(.*\)"[[:space:]]*$/\1/p' "$WPA" | head -1)
	W_PSK=$(sed -n 's/^[[:space:]]*psk=\(.*\)$/\1/p' "$WPA" | head -1 | sed 's/^"\(.*\)"$/\1/')
	if [ -n "$W_SSID" ] && [ -n "$W_PSK" ]; then
		mkdir -p /mnt/etc/NetworkManager/system-connections
		cat > /mnt/etc/NetworkManager/system-connections/corin-wifi.nmconnection <<NMEOF
[connection]
id=$W_SSID
type=wifi

[wifi]
ssid=$W_SSID
mode=infrastructure

[wifi-security]
key-mgmt=wpa-psk
psk=$W_PSK

[ipv4]
method=auto

[ipv6]
method=auto
NMEOF
		chmod 600 /mnt/etc/NetworkManager/system-connections/corin-wifi.nmconnection
	fi
fi

# ------------------------------------------------------------ display manager
mkdir -p /mnt/usr/share/xsessions /mnt/usr/share/sddm/themes /mnt/etc/sddm.conf.d
cat > /mnt/usr/share/xsessions/berry.desktop <<'XEOF'
[Desktop Entry]
Name=Berry
Comment=Berry window manager (Victoria Housekeeping Co.)
Exec=berry
Type=Application
XEOF
cp -a /usr/local/share/corin/sddm-theme /mnt/usr/share/sddm/themes/corin
BG=$(ls /usr/local/share/corin/skel/.local/share/corin/wallpaper.* 2>/dev/null | head -1)
if [ -n "$BG" ]; then
	cp "$BG" "/mnt/usr/share/sddm/themes/corin/background.${BG##*.}"
	sed -i "s|@BG@|background.${BG##*.}|" /mnt/usr/share/sddm/themes/corin/Main.qml
fi
cat > /mnt/etc/sddm.conf.d/corin.conf <<'XEOF'
[Theme]
Current=corin

[Users]
RememberLastUser=true
RememberLastSession=true
XEOF

for s in udev udev-trigger udev-settle; do $C rc-update add $s sysinit >/dev/null; done
$C rc-update add udev-postmount default >/dev/null
$C rc-update add dbus default >/dev/null
$C rc-update add elogind default >/dev/null
$C rc-update add polkit default >/dev/null
$C rc-update add sddm default >/dev/null
$C rc-update add networking boot >/dev/null
$C rc-update add networkmanager default >/dev/null
if [ "$SWAP_MB" -gt 0 ] || [ -n "$SWAPPART" ]; then $C rc-update add swap boot >/dev/null; fi

mkdir -p /mnt/etc/X11/xorg.conf.d
cat > /mnt/etc/X11/xorg.conf.d/40-libinput.conf <<'XEOF'
Section "InputClass"
	Identifier "libinput touchpad"
	MatchIsTouchpad "on"
	MatchDevicePath "/dev/input/event*"
	Driver "libinput"
	Option "Tapping" "on"
	Option "DisableWhileTyping" "on"
EndSection
XEOF

mkdir -p /mnt/etc/doas.d
printf 'permit persist :wheel\npermit nopass :wheel cmd reboot\npermit nopass :wheel cmd poweroff\n' > /mnt/etc/doas.d/doas.conf

# ------------------------------------------------------------ users
say "Creating user '$USERNAME'..."
$C adduser -D -s "$USER_SHELL" "$USERNAME" || die "adduser failed."
for g in wheel video audio input; do $C addgroup "$USERNAME" $g 2>/dev/null; done
# shadow's chpasswd wants the method in capitals (SHA512); busybox's takes lowercase.
# Try both, then fall back to the system default hashing.
setpw() {
	printf '%s:%s\n' "$1" "$PW1" | $C chpasswd -c SHA512 2>/dev/null && return 0
	printf '%s:%s\n' "$1" "$PW1" | $C chpasswd -c sha512 2>/dev/null && return 0
	printf '%s:%s\n' "$1" "$PW1" | $C chpasswd
}
setpw "$USERNAME" || die "Could not set the password for $USERNAME."
setpw root        || die "Could not set the root password."

# ------------------------------------------------------------ dotfiles
H="/mnt/home/$USERNAME"
cp -a "$SKEL"/. "$H"/
sed -i "s|@BROWSER@|$BROWSER_CMD|" "$H/.config/sxhkd/sxhkdrc"
$C chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
mkdir -p /mnt/usr/local/bin
for f in corin-apps corin-powermenu corin-pkg; do
	cp /usr/local/bin/$f /mnt/usr/local/bin/$f
	chmod 755 /mnt/usr/local/bin/$f
done

# ------------------------------------------------------------ finish
sync
swapoff -a 2>/dev/null
umount /mnt/sys/firmware/efi/efivars 2>/dev/null
umount /mnt/dev /mnt/proc /mnt/sys 2>/dev/null
umount /mnt/boot/efi 2>/dev/null
umount /mnt 2>/dev/null

echo
printf "${R}>>${N} ${W}Installation complete. The place is spotless.${N}\n"
printf "   Log in as ${W}%s${N} at the SDDM screen (session: Berry).\n\n" "$USERNAME"
if [ "$SB_DONE" = 1 ]; then
	if [ "$SB_ENROLLED" = 1 ]; then
		printf "   ${W}Secure Boot:${N} keys enrolled. Open firmware setup and ${W}enable Secure Boot${N},\n"
		printf "   then boot the \"Alpine Linux\" entry (the signed kernel image).\n\n"
	else
		printf "   ${W}Secure Boot:${N} keys created but NOT enrolled. Clear the Secure Boot keys in\n"
		printf "   firmware setup (Setup Mode), boot, run: ${W}doas sbctl enroll-keys -m${N}\n"
		printf "   then enable Secure Boot in firmware setup.\n\n"
	fi
fi
ask "Reboot now? [Y/n]: "
case "$REPLY" in n|N) ;; *) reboot ;; esac
EOF

cat > "$OV/usr/local/bin/corin-wifi-fix" <<'EOF'
#!/bin/sh
# corin-wifi-fix - walks through the standard Wi-Fi troubleshooting steps.
#   corin-wifi-fix           diagnose and try to fix what it can
#   corin-wifi-fix --report  diagnose only, change nothing
R='\033[1;31m'; W='\033[1;37m'; P='\033[1;35m'; GR='\033[1;32m'; N='\033[0m'
FIX=1
[ "${1:-}" = "--report" ] && FIX=0
[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }

step()   { printf "\n${P}== Step %s: %s ==${N}\n" "$1" "$2"; }
info()   { printf "   %s\n" "$*"; }
good()   { printf "   ${GR}ok${N}  %s\n" "$*"; }
bad()    { printf "   ${R}!!${N}  %s\n" "$*"; }
act()    { printf "   ${W}->${N}  %s\n" "$*"; }
indent() { sed 's/^/      /'; }
online() { ping -c1 -W3 dl-cdn.alpinelinux.org >/dev/null 2>&1; }
norm()   { echo "$1" | tr - _; }

wifi_ifaces() {
	for d in /sys/class/net/*; do
		if [ -d "$d/wireless" ] || [ -d "$d/phy80211" ]; then basename "$d"; fi
	done
}
rescan_modalias() {
	find /sys/devices -name modalias -type f -exec cat {} + 2>/dev/null \
		| xargs modprobe -b -a 2>/dev/null
}

# Map a missing firmware file to the Alpine per-vendor package.
fw_pkg() {
	case "$1" in
		iwlwifi-*|intel/*)           echo linux-firmware-intel ;;
		ath10k/*)                    echo linux-firmware-ath10k ;;
		ath11k/*)                    echo linux-firmware-ath11k ;;
		ath12k/*)                    echo linux-firmware-ath12k ;;
		ath9k_htc/*|htc_*)           echo linux-firmware-ath9k_htc ;;
		rtlwifi/*)                   echo linux-firmware-rtlwifi ;;
		rtw88/*)                     echo linux-firmware-rtw88 ;;
		rtw89/*)                     echo linux-firmware-rtw89 ;;
		rtl_nic/*)                   echo linux-firmware-rtl_nic ;;
		brcm/*|cypress/*)            echo linux-firmware-brcm ;;
		mediatek/*|mt76*|mt79*|mt7*) echo linux-firmware-mediatek ;;
		mrvl/*|mwlwifi/*)            echo linux-firmware-mrvl ;;
		qca/*)                       echo linux-firmware-qca ;;
	esac
}

# Install firmware .apk files from a USB stick (offline path).
from_usb() {
	printf "   Insert a USB stick containing linux-firmware-*.apk files, then press Enter (s = skip): "
	read -r a
	[ "$a" = "s" ] && return 1
	sleep 2
	found=""
	mkdir -p /tmp/fwusb
	for dev in $(lsblk -lnpo NAME,TYPE,FSTYPE 2>/dev/null | awk '$2=="part" && $3!="" {print $1}'); do
		mp="/tmp/fwusb/$(basename "$dev")"
		mkdir -p "$mp"
		mount -o ro "$dev" "$mp" 2>/dev/null || continue
		for f in $(find "$mp" -maxdepth 3 \( -name 'linux-firmware-*.apk' -o -name 'wireless-regdb-*.apk' \) 2>/dev/null); do
			found="$found $f"
		done
	done
	if [ -z "$found" ]; then
		bad "No linux-firmware-*.apk files found on any attached drive."
		return 1
	fi
	info "Found:"; for f in $found; do info "  $f"; done
	apk add --allow-untrusted --no-network $found && good "installed from USB" || bad "apk add from USB failed"
	for m in /tmp/fwusb/*; do umount "$m" 2>/dev/null; done
}

# =================================================================== 1
step 1 "Is the hardware visible at all?"
info "Interfaces: $(ls /sys/class/net | tr '\n' ' ')"
WL=$(wifi_ifaces)
if [ -n "$WL" ]; then good "Wi-Fi interface present: $WL"; else bad "No Wi-Fi interface (wlan0 / wlp*) exists."; fi
act "PCI network devices  [vendor:device]"
PCINET=$(lspci -nn 2>/dev/null | grep -i -E 'network|wireless|802\.11')
[ -n "$PCINET" ] && echo "$PCINET" | indent || info "(none)"
act "USB devices that could be Wi-Fi / Bluetooth"
USBNET=$(lsusb 2>/dev/null | grep -i -E 'wireless|wlan|wi-?fi|802\.11|bluetooth|realtek|mediatek|ralink|atheros|broadcom')
[ -n "$USBNET" ] && echo "$USBNET" | indent || info "(none)"
if [ -z "$PCINET$USBNET" ]; then
	bad "No Wi-Fi device is enumerated. Check the Fn/airplane key, a BIOS wireless toggle, or whether the card is seated."
fi
CANDS=$(lspci -nnk 2>/dev/null | awk '
	/^[^ \t]/ { f = ($0 ~ /Network controller|802\.11|Wireless/); next }
	f && /Kernel modules:/ { sub(/.*Kernel modules: */, ""); gsub(/,/, " "); print }')
[ -n "$CANDS" ] && info "Driver(s) the kernel suggests: $CANDS"

# =================================================================== 2
step 2 "Looking for firmware errors"
dmesg | grep -i -E 'firmware|iwlwifi|ath|brcm|rtw|rtl|mt76' | tail -25 | indent
MISSING=$(dmesg | sed -n 's/.*Direct firmware load for \([^ ]*\) failed.*/\1/p' | sort -u)
if [ -n "$MISSING" ]; then
	bad "Driver loaded but firmware files are missing:"
	echo "$MISSING" | indent
else
	good "No 'Direct firmware load ... failed' messages."
fi

# =================================================================== 3
step 3 "Can the driver module load?"
KVER=$(uname -r)
if mount | grep -q modloop; then
	good "modloop is mounted"
else
	bad "modloop is NOT mounted"
	if [ "$FIX" = 1 ]; then act "rc-service modloop start"; rc-service modloop start 2>&1 | indent; fi
fi
if [ -d "/lib/modules/$KVER" ]; then
	good "/lib/modules/$KVER present"
	MODS=1
else
	bad "/lib/modules/$KVER is missing: kernel modules are unavailable, so no driver can load."
	MODS=0
fi
act "Loaded wireless-related modules"
lsmod | grep -i -E 'cfg80211|mac80211|iwl|ath|rtw|rtl8|mt76|mt79|brcm|mwifiex' | indent
if [ "$FIX" = 1 ] && [ "$MODS" = 1 ]; then
	rescan_modalias
	for m in $CANDS; do
		if lsmod | grep -q "^$(norm "$m") "; then
			good "$m is loaded"
		else
			act "modprobe $m"
			if err=$(modprobe "$m" 2>&1); then good "$m loaded"; else bad "modprobe $m: $err"; fi
		fi
	done
fi

# =================================================================== 4
step 4 "Checking rfkill blocks"
if command -v rfkill >/dev/null 2>&1; then
	rfkill list 2>&1 | indent
	if rfkill list 2>/dev/null | grep -qi 'Hard blocked: yes'; then
		bad "HARD blocked: use the laptop's Fn / airplane-mode key or hardware switch."
	fi
	if rfkill list 2>/dev/null | grep -qi 'Soft blocked: yes'; then
		bad "Soft blocked."
		if [ "$FIX" = 1 ]; then act "rfkill unblock wifi"; rfkill unblock wifi; rfkill unblock all; fi
	else
		good "No soft block."
	fi
else
	info "rfkill is not installed."
fi

# =================================================================== 5
step 5 "Firmware"
FWDONE=""
if [ "$FIX" = 1 ] && command -v corin-fw-load >/dev/null 2>&1; then
	act "Installing firmware from the ISO's own package repo (offline)"
	corin-fw-load 2>&1 | indent
	[ -n "$(wifi_ifaces)" ] && { good "Wi-Fi interface appeared"; FWDONE=1; }
fi
PKGS=""
add_pkg() { case " $PKGS " in *" $1 "*) ;; *) PKGS="$PKGS $1" ;; esac; }
for f in $MISSING; do p=$(fw_pkg "$f"); [ -n "$p" ] && add_pkg "$p"; done
dmesg | grep -i -E -q 'iwlwifi.*(no suitable firmware|failed to load|not found)' && add_pkg linux-firmware-intel

if [ -z "$PKGS" ] || [ -n "$FWDONE" ]; then
	good "No further firmware needed."
elif [ "$FIX" = 0 ]; then
	info "Would install:$PKGS"
else
	info "Firmware packages needed:$PKGS"
	if online; then
		cat > /etc/apk/repositories <<REPOS
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
https://dl-cdn.alpinelinux.org/alpine/edge/testing
REPOS
		apk update -q
		UNRES=""
		for p in $PKGS; do
			if apk search -q -e "$p" | grep -q .; then
				act "apk add $p"
				apk add -q "$p" && good "installed $p" || bad "failed to install $p"
			else
				bad "$p does not exist in the repositories"
				UNRES="$UNRES $p"
			fi
		done
		if [ -n "$UNRES" ]; then
			printf "   Install the full linux-firmware instead (~750 MB of RAM)? [y/N]: "
			read -r a
			case "$a" in y|Y) apk add -q linux-firmware && good "installed linux-firmware" ;; esac
		fi
	else
		bad "No network, so the firmware cannot be downloaded."
		info "Option A: plug in Ethernet, or a phone with USB tethering, then run setup-interfaces."
		info "Option B: install firmware .apk files from a USB stick."
		from_usb
	fi
	# Reload the Wi-Fi drivers so they pick up the new firmware.
	act "Reloading Wi-Fi drivers"
	for m in $(lsmod | awk 'NR>1{print $1}' | grep -E '^(iwl|ath|rtw|rtl8|mt76|mt79|mt7|brcm|mwifiex|b43)'); do
		modprobe -r "$m" 2>/dev/null
	done
	sleep 1
	rescan_modalias
	for m in $CANDS; do modprobe "$m" 2>/dev/null; done
	sleep 3
fi

# =================================================================== 6
step 6 "Special cases"
info "Kernel: $KVER"
if echo "$PCINET$USBNET" | grep -qi -E '14e4|broadcom'; then
	info "Broadcom hardware detected. Newer chips use brcmfmac (needs linux-firmware-brcm);"
	info "older ones need b43 firmware or the proprietary wl driver."
	if [ -z "$(wifi_ifaces)" ] && [ "$FIX" = 1 ] && online; then
		BP="broadcom-wl-$(echo "$KVER" | sed 's/.*-//')"
		if apk search -q -e "$BP" | grep -q .; then
			printf "   Install %s (proprietary driver)? [y/N]: " "$BP"
			read -r a
			case "$a" in
				y|Y)
					apk add -q "$BP" && {
						modprobe -r b43 bcma ssb brcmsmac brcmfmac 2>/dev/null
						modprobe wl 2>&1 | indent
						sleep 2
					} ;;
			esac
		else
			info "No $BP package exists for this kernel flavor."
		fi
	fi
else
	info "No Broadcom hardware detected."
fi
info "Very new chips may need a newer kernel than this image ships."

# =================================================================== 7
step 7 "Result"
WL=$(wifi_ifaces)
if [ -n "$WL" ]; then
	good "Wi-Fi interface found: $WL. Run setup-interfaces to join a network."
	exit 0
fi
bad "Still no Wi-Fi interface."
info "The installed system gets the full linux-firmware, so Wi-Fi may work after install."
info "To install now, use Ethernet or USB tethering via setup-interfaces (the installer needs"
info "a connection anyway). To get help, send the output above plus the lspci -nn / lsusb lines."
exit 1
EOF

cat > "$OV/usr/local/bin/corin-fw-load" <<'EOF'
#!/bin/sh
# corin-fw-load - installs missing firmware from the ISO's own package repo
# (works offline), then reloads the network/Bluetooth drivers.
ISO_REPO=/etc/apk/repositories.iso
[ -f "$ISO_REPO" ] || cp /etc/apk/repositories "$ISO_REPO"
[ -d "/lib/modules/$(uname -r)" ] || { echo "Kernel modules are not available."; exit 1; }

MISSING=$(dmesg | sed -n 's/.*Direct firmware load for \([^ ]*\) failed.*/\1/p' | sort -u)
[ -n "$MISSING" ] || { echo "The kernel reported no missing firmware."; exit 0; }

# True if any version of this firmware file is already in /lib/firmware.
present() {
	case "$1" in
		*-*) pat="${1%-*}-" ;;
		*)   pat="${1%.*}" ;;
	esac
	ls /lib/firmware/"$pat"* >/dev/null 2>&1
}

# Which Alpine subpackages might contain this file.
cand() {
	case "$1" in
		iwlwifi-*) echo intel iwlwifi other ;;
		*/*)       echo "${1%%/*}" other ;;
		*)         echo other ;;
	esac
}

CHANGED=0
for f in $MISSING; do
	present "$f" && continue
	for c in $(cand "$f"); do
		pkg="linux-firmware-$c"
		apk info -e "$pkg" >/dev/null 2>&1 && continue
		if apk search -q -e --no-network --repositories-file "$ISO_REPO" "$pkg" | grep -q .; then
			echo "installing $pkg (for $f)"
			apk add -q --no-network --repositories-file "$ISO_REPO" "$pkg" && CHANGED=1
			present "$f" && break
		fi
	done
	present "$f" || echo "still missing: $f (not found in the ISO's firmware packages)"
done

if [ "$CHANGED" = 1 ]; then
	echo "reloading drivers"
	for m in $(lsmod | awk 'NR>1{print $1}' | grep -E '^(iwl|ath|rtw|rtl8|mt76|mt79|mt7|brcm|mwifiex|b43|btusb|btintel)'); do
		modprobe -r "$m" 2>/dev/null
	done
	sleep 1
	find /sys/devices -name modalias -type f -exec cat {} + 2>/dev/null | xargs modprobe -b -a 2>/dev/null
	sleep 3
fi
exit 0
EOF

cat > "$OV/usr/local/bin/corin-apps" <<'EOF'
#!/bin/sh
# Applications menu, dropped down from the left of the bar.
exec rofi -show drun -theme-str 'window {location: northwest; anchor: northwest; x-offset: 8px; y-offset: 34px; width: 380px;}'
EOF

cat > "$OV/usr/local/bin/corin-powermenu" <<'EOF'
#!/bin/sh
# Power menu, dropped down from the right of the bar.
THEME='window {location: northeast; anchor: northeast; x-offset: -8px; y-offset: 34px; width: 240px;} listview {lines: 5;}'
CHOICE=$(printf 'Lock\nSleep\nLog Out\nRestart\nShutdown\n' \
	| rofi -dmenu -i -no-custom -p 'Power' -theme-str "$THEME")
lock() { i3lock -c 0b0b10 -e -f; }
case "$CHOICE" in
	"Lock")    lock ;;
	"Sleep")   lock; sleep 1; loginctl suspend ;;
	"Log Out") berryc quit ;;
	"Restart") loginctl reboot || doas reboot ;;
	"Shutdown") loginctl poweroff || doas poweroff ;;
esac
EOF

cat > "$OV/usr/local/bin/corin-pkg" <<'EOF'
#!/bin/sh
# corin-pkg - small terminal package manager (fzf + apk). Very light on resources.
command -v fzf >/dev/null 2>&1 || { echo "fzf is required: doas apk add fzf"; exit 1; }
SUDO=""
[ "$(id -u)" = 0 ] || SUDO="doas"
INDEX=0
pause() { printf '\nPress Enter to continue... '; read -r _; }
# strip "-<version>-r<N>" from apk search output
names() { sed -E 's/-[0-9][0-9A-Za-z._]*-r[0-9]+$//' | sort -u; }

while :; do
	CHOICE=$(printf 'Install packages\nRemove packages\nUpgrade all packages\nRefresh package index\nQuit\n' \
		| fzf --reverse --border --height=40% --prompt='corin-pkg > ' \
		      --header='Victoria Housekeeping package manager')
	case "$CHOICE" in
		"Install packages")
			if [ "$INDEX" = 0 ]; then $SUDO apk update && INDEX=1; fi
			PICKS=$(apk search -q | names | fzf -m --reverse --border --height=90% \
				--prompt='install > ' --header='Tab = mark   Enter = install   Esc = back' \
				--preview 'apk info -d -s {} 2>/dev/null' --preview-window=right,50%,wrap)
			if [ -n "$PICKS" ]; then echo; $SUDO apk add $PICKS; pause; fi ;;
		"Remove packages")
			PICKS=$(apk info | sort -u | fzf -m --reverse --border --height=90% \
				--prompt='remove > ' --header='Tab = mark   Enter = remove   Esc = back' \
				--preview 'apk info -d -s {} 2>/dev/null' --preview-window=right,50%,wrap)
			if [ -n "$PICKS" ]; then echo; $SUDO apk del $PICKS; pause; fi ;;
		"Upgrade all packages")
			$SUDO apk update && $SUDO apk upgrade; INDEX=1; pause ;;
		"Refresh package index")
			$SUDO apk update; INDEX=1; pause ;;
		*) exit 0 ;;
	esac
done
EOF

cat > "$OV/usr/local/bin/corin-netdiag" <<'EOF'
#!/bin/sh
exec corin-wifi-fix --report
EOF
chmod 755 "$OV/usr/local/bin/corin-greeter" "$OV/usr/local/bin/corin-install" "$OV/usr/local/bin/corin-netdiag" "$OV/usr/local/bin/corin-wifi-fix" "$OV/usr/local/bin/corin-fw-load" "$OV/usr/local/bin/corin-apps" "$OV/usr/local/bin/corin-powermenu" "$OV/usr/local/bin/corin-pkg"

# =====================================================================
# Skeleton for the installed user's home
# =====================================================================
# Shared login logic: read by ash/sh directly, by bash via .bash_profile,
# and by zsh via .zprofile. Keep it POSIX.
cat > "$SKEL/.profile" <<'EOF'
export EDITOR=nano
export ENV="$HOME/.ashrc"
# The desktop is started by SDDM. To run it manually from a tty: startx
EOF

# ash / sh interactive config
cat > "$SKEL/.ashrc" <<'EOF'
PS1='\[\e[1;31m\]\u\[\e[0m\]@\[\e[1;37m\]\h\[\e[0m\]:\w \[\e[1;35m\]\$\[\e[0m\] '
alias ls='ls --color=auto'
EOF

# bash
cat > "$SKEL/.bash_profile" <<'EOF'
[ -f "$HOME/.profile" ] && . "$HOME/.profile"
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
EOF

cat > "$SKEL/.bashrc" <<'EOF'
[[ $- != *i* ]] && return
PS1='\[\e[1;31m\]\u\[\e[0m\]@\[\e[1;37m\]\h\[\e[0m\]:\w \[\e[1;35m\]\$\[\e[0m\] '
alias ls='ls --color=auto'
alias ll='ls -lah'
HISTSIZE=5000
HISTCONTROL=ignoredups
EOF

# zsh
cat > "$SKEL/.zprofile" <<'EOF'
emulate sh -c '. "$HOME/.profile"'
EOF

cat > "$SKEL/.zshrc" <<'EOF'
PROMPT='%B%F{red}%n%f%b@%B%F{white}%m%f%b:%~ %B%F{magenta}%#%f%b '
alias ls='ls --color=auto'
alias ll='ls -lah'
HISTFILE=~/.zsh_history
HISTSIZE=5000
SAVEHIST=5000
setopt HIST_IGNORE_DUPS SHARE_HISTORY
autoload -Uz compinit && compinit
bindkey -e
bindkey '^[[H'    beginning-of-line
bindkey '^[[F'    end-of-line
bindkey '^[[3~'   delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
EOF

cat > "$SKEL/.xinitrc" <<'EOF'
#!/bin/sh
xsetroot -solid '#0b0b10' -cursor_name left_ptr
exec berry
EOF
chmod 755 "$SKEL/.xinitrc"

cat > "$SKEL/.local/share/applications/corin-pkg.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Package Installer
Comment=Install, remove and upgrade packages
Exec=kitty --title "Package Installer" corin-pkg
Icon=system-software-install
Terminal=false
Categories=System;
EOF

cat > "$SKEL/.config/kitty/kitty.conf" <<'EOF'
font_family      DejaVu Sans Mono
font_size        10.0
background       #0b0b10
foreground       #e8e8f0
cursor           #e3103c
selection_background #e3103c
selection_foreground #ffffff
window_padding_width 8
confirm_os_window_close 0
enable_audio_bell no
color0  #0b0b10
color1  #e3103c
color2  #8c8c99
color3  #ff9db8
color4  #5a5a6e
color5  #ff5c8a
color6  #c9c9d6
color7  #e8e8f0
color8  #2a2a35
color9  #ff2d55
color10 #b0b0bd
color11 #ffc2d4
color12 #7a7a90
color13 #ff85a8
color14 #e0e0ea
color15 #ffffff
EOF

cat > "$SKEL/.config/berry/autostart" <<'EOF'
#!/bin/sh
# berry window manager startup
berryc border_width 3
berryc inner_border_width 0
berryc top_gap 28
berryc focus_color e3103c
berryc unfocus_color 2a2a35
xsetroot -solid '#0b0b10' -cursor_name left_ptr

WP=$(ls "$HOME"/.local/share/corin/wallpaper.* 2>/dev/null | head -1)
[ -n "$WP" ] && feh --bg-fill "$WP"

sxhkd &
sleep 1
polybar corin &
conky -c "$HOME/.config/conky/conky.conf" &
EOF
chmod 755 "$SKEL/.config/berry/autostart"

cat > "$SKEL/.config/sxhkd/sxhkdrc" <<'EOF'
# Terminal / launchers
super + Return
	kitty
super + d
	rofi -show drun
super + period
	rofi -show emoji -modi emoji
super + b
	@BROWSER@
super + p
	kitty --title "Package Installer" corin-pkg

# Menus / session
super + Escape
	corin-powermenu
super + l
	i3lock -c 0b0b10 -e -f

# Windows
super + q
	berryc window_close
super + f
	berryc window_monocle
super + shift + f
	berryc fullscreen
super + c
	berryc window_center
super + Left
	berryc snap_left
super + Right
	berryc snap_right
super + Tab
	berryc cycle_focus

# Workspaces
super + {1-4}
	berryc switch_workspace {0-3}
super + shift + {1-4}
	berryc send_to_workspace {0-3}

# Session
super + shift + r
	pkill -USR1 -x sxhkd
super + shift + e
	berryc quit
EOF

cat > "$SKEL/.config/conky/conky.conf" <<'EOF'
conky.config = {
  alignment = 'top_right',
  gap_x = 24,
  gap_y = 44,
  minimum_width = 320,
  maximum_width = 320,
  own_window = true,
  own_window_type = 'desktop',
  own_window_transparent = true,
  own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
  double_buffer = true,
  use_xft = true,
  font = 'DejaVu Sans Mono:size=10',
  default_color = 'e8e8f0',
  color1 = 'e3103c',
  color2 = 'ff5c8a',
  draw_borders = false,
  draw_shades = false,
  draw_outline = false,
  update_interval = 5,
}

conky.text = [[
${color1}${font DejaVu Sans Mono:bold:size=11}VICTORIA HOUSEKEEPING CO.${font}${color}
${color1}${hr 2}${color}
${color2}Super+Enter${color}${alignr}Terminal
${color2}Super+D${color}${alignr}App launcher
${color2}Super+.${color}${alignr}Emoji picker
${color2}Super+B${color}${alignr}Browser
${color2}Super+Q${color}${alignr}Close window
${color2}Super+F${color}${alignr}Monocle
${color2}Super+Shift+F${color}${alignr}Fullscreen
${color2}Super+C${color}${alignr}Center window
${color2}Super+Left/Right${color}${alignr}Snap window
${color2}Super+Tab${color}${alignr}Cycle focus
${color2}Super+1-4${color}${alignr}Workspace
${color2}Super+Shift+1-4${color}${alignr}Send to workspace
${color2}Super+Shift+R${color}${alignr}Reload shortcuts
${color2}Super+Shift+E${color}${alignr}Quit session
${color2}Super+Esc${color}${alignr}Power menu
${color2}Super+L${color}${alignr}Lock screen
${color2}Super+P${color}${alignr}Package installer
${color1}${hr 1}${color}
${color2}CPU${color} ${cpu}%${alignr}${color2}RAM${color} ${memperc}%
]]
EOF

cat > "$SKEL/.config/polybar/config.ini" <<'EOF'
[colors]
bg = #ee0b0b10
fg = #e8e8f0
accent = #e3103c
pink = #ff5c8a

[bar/corin]
width = 100%
height = 26
background = ${colors.bg}
foreground = ${colors.fg}
border-bottom-size = 2
border-bottom-color = ${colors.accent}
font-0 = DejaVu Sans Mono:size=10;2
padding = 2
module-margin = 2
modules-left = apps title
modules-right = cpu memory date power

[module/apps]
type = custom/text
content = " ≡ Applications "
content-foreground = ${colors.pink}
click-left = corin-apps

[module/power]
type = custom/text
content = " Power ▾ "
content-foreground = ${colors.accent}
click-left = corin-powermenu

[module/title]
type = custom/text
content = VICTORIA HOUSEKEEPING CO.
content-foreground = ${colors.accent}

[module/cpu]
type = internal/cpu
interval = 2
label = CPU %percentage%%
format-prefix = " "
format-prefix-foreground = ${colors.pink}

[module/memory]
type = internal/memory
interval = 3
label = RAM %percentage_used%%
format-prefix = " "
format-prefix-foreground = ${colors.pink}

[module/date]
type = internal/date
interval = 5
date = %a %d %b
time = %H:%M
label = %date%  %time%
label-foreground = ${colors.fg}
EOF

cat > "$SKEL/.config/rofi/config.rasi" <<'EOF'
configuration {
  modes: "drun,run,emoji";
  font: "DejaVu Sans Mono 11";
  show-icons: false;
}

* {
  bg: #0b0b10f2;
  fg: #e8e8f0;
  accent: #e3103c;
}

window {
  background-color: @bg;
  border: 2px;
  border-color: @accent;
  width: 560px;
}
mainbox { background-color: transparent; }
inputbar {
  children: [prompt, entry];
  padding: 8px;
  background-color: transparent;
}
prompt { text-color: @accent; padding: 0 8px 0 0; }
entry  { text-color: @fg; }
listview { lines: 10; background-color: transparent; }
element { padding: 4px 8px; text-color: @fg; background-color: transparent; }
element selected { background-color: @accent; text-color: #ffffff; }
EOF

# =====================================================================
# SDDM theme (plain QtQuick, no extra dependencies)
# =====================================================================
TH="$OV/usr/local/share/corin/sddm-theme"

cat > "$TH/metadata.desktop" <<'EOF'
[SddmGreeterTheme]
Name=Corin
Description=Victoria Housekeeping Co. login
Author=local
Version=1.0
Type=sddm-theme
MainScript=Main.qml
ConfigFile=theme.conf
QTVersion=6
EOF
: > "$TH/theme.conf"

cat > "$TH/Main.qml" <<'EOF'
import QtQuick 2.0

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#0b0b10"
    property int sessionIndex: sessionModel.lastIndex

    Image {
        anchors.fill: parent
        source: "@BG@"
        fillMode: Image.PreserveAspectCrop
    }
    Rectangle { anchors.fill: parent; color: "#0b0b10"; opacity: 0.6 }

    Column {
        anchors.centerIn: parent
        spacing: 14

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "VICTORIA HOUSEKEEPING CO."
            color: "#e3103c"
            font.pixelSize: 34
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Sign in to begin your shift"
            color: "#8c8c99"
            font.pixelSize: 16
        }

        Rectangle {
            width: 360; height: 44; color: "#14141c"; border.width: 2
            border.color: userField.activeFocus ? "#e3103c" : "#2a2a35"
            TextInput {
                id: userField
                anchors.fill: parent; anchors.margins: 10
                verticalAlignment: TextInput.AlignVCenter
                color: "#e8e8f0"; font.pixelSize: 20; clip: true
                text: userModel.lastUser
                KeyNavigation.tab: passField
                Keys.onReturnPressed: passField.forceActiveFocus()
                Keys.onEnterPressed: passField.forceActiveFocus()
            }
        }
        Rectangle {
            width: 360; height: 44; color: "#14141c"; border.width: 2
            border.color: passField.activeFocus ? "#e3103c" : "#2a2a35"
            TextInput {
                id: passField
                anchors.fill: parent; anchors.margins: 10
                verticalAlignment: TextInput.AlignVCenter
                color: "#e8e8f0"; font.pixelSize: 20; clip: true
                echoMode: TextInput.Password
                KeyNavigation.backtab: userField
                Keys.onReturnPressed: sddm.login(userField.text, passField.text, root.sessionIndex)
                Keys.onEnterPressed: sddm.login(userField.text, passField.text, root.sessionIndex)
            }
        }
        Text {
            id: msg
            anchors.horizontalCenter: parent.horizontalCenter
            text: ""
            color: "#ff5c8a"
            font.pixelSize: 16
        }
    }

    Row {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 24
        spacing: 24
        Text {
            text: "Reboot"; color: "#ff5c8a"; font.pixelSize: 16
            visible: sddm.canReboot
            MouseArea { anchors.fill: parent; onClicked: sddm.reboot() }
        }
        Text {
            text: "Power off"; color: "#e3103c"; font.pixelSize: 16
            visible: sddm.canPowerOff
            MouseArea { anchors.fill: parent; onClicked: sddm.powerOff() }
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            msg.text = "Login failed. Try again."
            passField.text = ""
            passField.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        if (userField.text === "") userField.forceActiveFocus()
        else passField.forceActiveFocus()
    }
}
EOF

# =====================================================================
# Build inside an Alpine container
# =====================================================================
chmod -R a+rX "$WORK"

cat > "$WORK/fwlist.sh" <<'EOF'
#!/bin/sh
# Lists the network-related linux-firmware-* subpackages in the repository.
apk update -q
apk search -q 'linux-firmware-*' \
	| sed -E 's/-[0-9][0-9A-Za-z._]*-r[0-9]+$//' \
	| sort -u \
	| grep -E '^linux-firmware-(intel|iwlwifi|ath[0-9a-z_]*|atheros|rtl[0-9a-z_]*|rtw[0-9a-z_]*|realtek|brcm|cypress|mediatek|mt[0-9a-z_]*|mrvl|libertas|ralink|rsi|wfx|ti-connectivity|qca|other|bnx2x?|tigon|e100|mwl[0-9a-z_]*)$' \
	| tr '\n' ' '
EOF

cat > "$WORK/inner.sh" <<EOF
#!/bin/sh
set -eu
apk add --no-cache alpine-sdk alpine-conf xorriso squashfs-tools mtools \
	dosfstools grub grub-efi syslinux git sudo openssl rsvg-convert font-dejavu
adduser -D build
addgroup build abuild
${WALL_CMD}
chmod a+r /home/build/wallpaper.*
sh /work/fwlist.sh > /home/build/fwpkgs
chmod a+r /home/build/fwpkgs
echo 'Firmware packages bundled on the ISO:'
cat /home/build/fwpkgs
echo
# Generate the signing key explicitly (abuild-keygen's output path depended on HOME).
su -s /bin/sh build -c '
set -eu
mkdir -p /home/build/.abuild
cd /home/build/.abuild
openssl genrsa -out build-key.rsa 4096
openssl rsa -in build-key.rsa -pubout -out build-key.rsa.pub
echo "PACKAGER_PRIVKEY=/home/build/.abuild/build-key.rsa" > abuild.conf
'
cp /home/build/.abuild/build-key.rsa.pub /etc/apk/keys/

su -s /bin/sh build -c '
set -eu
export HOME=/home/build
cd /home/build
git clone --depth=1 -b ${BRANCH} https://gitlab.alpinelinux.org/alpine/aports.git
cp /work/mkimg.corin.sh /work/genapkovl-corin.sh aports/scripts/
# mkimage looks up the apkovl generator under ~/.mkimage
mkdir -p /home/build/.mkimage
cp /work/genapkovl-corin.sh /home/build/.mkimage/genapkovl-corin.sh
chmod +x /home/build/.mkimage/genapkovl-corin.sh aports/scripts/genapkovl-corin.sh
cd aports/scripts
sh mkimage.sh --tag ${ALPINE_VER} --outdir /out --arch x86_64 \
	--repository https://dl-cdn.alpinelinux.org/alpine/${ALPINE_VER}/main \
	--repository https://dl-cdn.alpinelinux.org/alpine/${ALPINE_VER}/community \
	--profile corin
'
EOF

docker run --rm \
	-v "$WORK:/work:ro" \
	-v "$HERE/out:/out" \
	"alpine:${ALPINE_VER}" sh /work/inner.sh

echo
echo "Done:"
ls -lh "$HERE/out"/*.iso
echo "Write to USB (replace sdX, double-check it!):"
echo "  sudo dd if=out/alpine-corin-*.iso of=/dev/sdX bs=4M status=progress conv=fsync"
