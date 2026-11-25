# Parrot OS on Apple Silicon Mac with UTM

A start-to-finish guide for running Parrot Security OS as a GUI virtual machine on an Apple Silicon Mac (M1–M4), using the free UTM app and Parrot's ready-made ARM64 UTM image. No installer to click through: download, import, boot.

Everything in sections 1–7 was run exactly as written on this setup:

| | |
|---|---|
| Host | MacBook, Apple M4 Pro, 24 GB RAM, macOS 27 |
| Hypervisor | UTM 5.0.9 (QEMU backend, Apple Hypervisor acceleration) |
| Guest | Parrot Security 7.4 "echo", ARM64, KDE Plasma on Wayland |
| VM defaults | 8 CPU, 8 GB RAM, 64 GB disk, shared (NAT) network |

Section 8 holds common customisations. Those are standard commands but were not all run on this setup, so take a snapshot first (section 8.6).

## Contents

1. [Why UTM and not VMware or VirtualBox](#1-why-utm-and-not-vmware-or-virtualbox)
2. [Check the Mac](#2-check-the-mac)
3. [Install UTM](#3-install-utm)
4. [Download the Parrot image](#4-download-the-parrot-image)
5. [Import and boot](#5-import-and-boot)
6. [Create your own user](#6-create-your-own-user)
7. [Fix tiny text on Retina displays](#7-fix-tiny-text-on-retina-displays)
8. [Customise](#8-customise)
9. [Everyday commands](#9-everyday-commands)
10. [Troubleshooting](#10-troubleshooting)

## 1. Why UTM and not VMware or VirtualBox

Apple Silicon Macs are ARM64. A VM runs at near-native speed only when the guest is ARM64 too. Parrot publishes an ARM64 image already packaged as a `.utm` bundle, so UTM is the shortest path. VMware Fusion also works on Apple Silicon but needs a manual install from the ARM64 ISO. The `amd64` images (`.ova`, `.vmdk`) are for Intel machines and would only run under slow emulation here.

## 2. Check the Mac

```bash
uname -m                              # arm64 = Apple Silicon
sysctl -n machdep.cpu.brand_string    # chip name
sysctl -n kern.hv_support             # 1 = hypervisor available
sysctl -n hw.memsize                  # RAM in bytes
/bin/df -h /System/Volumes/Data       # free disk
```

Plan for at least 16 GB RAM on the Mac (the VM takes 8 GB) and about 25 GB free disk during setup: 9.7 GB download plus 13 GB extracted. The download can be deleted afterwards.

## 3. Install UTM

```bash
brew install --cask utm
```

This installs `/Applications/UTM.app` and the `utmctl` command-line tool. Without Homebrew, download UTM from <https://mac.getutm.app/>.

## 4. Download the Parrot image

Releases are listed at <https://deb.parrot.sh/parrot/iso/>. Pick the newest version folder and the file ending in `_arm64.utm.tar.gz`:

| Edition | File | Size |
|---|---|---|
| Security (pentest tools included) | `Parrot-security-7.4_arm64.utm.tar.gz` | 9.7 GB |
| Home (lighter, no tool suite) | `Parrot-home-7.4_arm64.utm.tar.gz` | 3.9 GB |

A single connection to the mirror can be slow. `aria2c` opens several connections and resumes after a dropped connection:

```bash
brew install aria2
mkdir -p ~/Downloads/parrot-utm && cd ~/Downloads/parrot-utm

aria2c -c -x16 -s16 -k1M --file-allocation=none \
  --max-tries=0 --retry-wait=5 --timeout=30 \
  https://deb.parrot.sh/parrot/iso/7.4/Parrot-security-7.4_arm64.utm.tar.gz
```

`--max-tries=0` means retry forever. If the command is interrupted, run the same line again and it continues where it stopped. The download is finished only when the `.aria2` control file next to it has disappeared.

### Verifying the download

Parrot's `signed-hashes.txt` for 7.4 lists the ISO files but has no entry for the UTM images, so a checksum comparison is not possible for this file. Two checks still catch a broken download:

```bash
# size must equal the server's content-length
curl -sIL https://deb.parrot.sh/parrot/iso/7.4/Parrot-security-7.4_arm64.utm.tar.gz | grep -i content-length
/usr/bin/stat -f %z Parrot-security-7.4_arm64.utm.tar.gz

# gzip has a built-in CRC; extraction fails loudly on a damaged file
```

## 5. Import and boot

Extract to a permanent location. UTM references the bundle where it sits, so do not move or delete it later.

```bash
mkdir -p ~/VMs && cd ~/VMs
tar -xzf ~/Downloads/parrot-utm/Parrot-security-7.4_arm64.utm.tar.gz

open -a UTM ~/VMs/Parrot-security-7.4_arm64.utm    # registers the VM
utmctl list                                        # shows its UUID and status
```

The first `utmctl` call makes macOS ask for permission to control UTM. Allow it.

Start the VM, either with the play button in UTM or:

```bash
VM="ParrotOS 7.4 security Edition"     # name or UUID from `utmctl list`
utmctl start "$VM"
utmctl ip-address "$VM"                # prints an address once the guest is up
```

The image logs in automatically to a KDE desktop.

**Default account in the image:** username `user`, password `parrot`, with passwordless sudo. This is published in Parrot's documentation, so treat it as public knowledge and replace it (next section).

Once the VM runs, the download is no longer needed:

```bash
rm -r ~/Downloads/parrot-utm
```

## 6. Create your own user

The image ships with the QEMU guest agent, so commands can be run inside the guest as root straight from the Mac terminal with `utmctl exec`. The same commands work in a terminal inside Parrot if prefixed with `sudo`.

Using the script in this repo, which asks for the password without showing it:

```bash
./scripts/create-user.sh "ParrotOS 7.4 security Edition" parrot
```

Or step by step. Replace `parrot` and `CHANGE_ME` with your own username and password:

```bash
VM="ParrotOS 7.4 security Edition"
x() { utmctl exec "$VM" --cmd /bin/bash -c "$1"; }

# new user with the same group memberships as the stock user (sudo, audio, video, ...)
x 'G=$(id -nG user | tr " " "\n" | grep -vx user | paste -sd,); useradd -m -s /bin/bash -G "$G" parrot'

# set the password
x 'echo "parrot:CHANGE_ME" | chpasswd'

# log this user in automatically at boot
x 'sed -i "s/^autologin-user=.*/autologin-user=parrot/" /etc/lightdm/lightdm.conf.d/50-autologin.conf'

# restart into the new desktop session
x 'reboot'
```

Verify after the reboot:

```bash
x 'loginctl list-sessions --no-legend'    # session owner should be the new user
x 'id parrot'                             # should include the sudo group
```

Optional hardening once the new account works:

```bash
# remove the stock account, its home directory and its passwordless-sudo rule
x 'deluser --remove-home user && rm /etc/sudoers.d/20-parrot-virtual'

# or keep it and only disable its password
x 'passwd -l user'

# require a password at the login screen instead of auto-login
x 'rm /etc/lightdm/lightdm.conf.d/50-autologin.conf'
```

## 7. Fix tiny text on Retina displays

The VM draws at the Mac's full Retina resolution (3024×1816 on a 14-inch MacBook Pro) at about 100% scale, so text comes out very small. Raise the KDE display scale.

Using the script:

```bash
./scripts/set-scale.sh "ParrotOS 7.4 security Edition" parrot 2      # 2 = 200%
```

Or by hand from the Mac:

```bash
VM="ParrotOS 7.4 security Edition"
U=parrot
utmctl exec "$VM" --cmd /bin/bash -c "
  uid=\$(id -u $U)
  su $U -c \"XDG_RUNTIME_DIR=/run/user/\$uid WAYLAND_DISPLAY=wayland-0 kscreen-doctor output.Virtual-1.scale.2\"
"
```

Or inside Parrot: **System Settings → Display & Monitor → Scale**, or in a Parrot terminal:

```bash
kscreen-doctor -o                              # show output name, modes, current scale
kscreen-doctor output.Virtual-1.scale.2        # 200%
kscreen-doctor output.Virtual-1.scale.1.5      # 150%, a middle ground
```

KDE stores the setting, so it survives reboots.

## 8. Customise

Shut the VM down before changing hardware settings, and quit UTM before editing `config.plist` by hand, otherwise UTM overwrites the file.

```bash
utmctl stop "$VM"
osascript -e 'quit app "UTM"'
CFG=~/VMs/Parrot-security-7.4_arm64.utm/config.plist
```

### 8.1 CPU and memory

In UTM: right-click the VM → **Edit → System**. From the terminal:

```bash
plutil -replace System.MemorySize -integer 12288 "$CFG"    # MB of RAM
plutil -replace System.CPUCount   -integer 6     "$CFG"
plutil -p "$CFG" | grep -E 'MemorySize|CPUCount'
```

Leave at least 8 GB of RAM and a few cores for macOS.

### 8.2 Bigger disk

The disk is 64 GB and thin: the file on the Mac only grows as Parrot fills it. To enlarge it, resize the image on the Mac and then grow the partition and filesystem inside the guest.

```bash
# on the Mac, VM stopped
brew install qemu
qemu-img resize ~/VMs/Parrot-security-7.4_arm64.utm/Data/Parrot-security-7.4_arm64.qcow2 128G

# start the VM, then inside Parrot
sudo apt install -y cloud-guest-utils     # provides growpart
sudo growpart /dev/vda 2
sudo btrfs filesystem resize max /
df -h /
```

The root filesystem is btrfs on `/dev/vda2`. Check with `lsblk` before running `growpart`.

### 8.3 Share a Mac folder with Parrot

In UTM: **Edit → Sharing**, choose a directory. The image is set to VirtFS mode. Inside Parrot:

```bash
sudo mkdir -p /mnt/mac
sudo mount -t 9p -o trans=virtio,version=9p2000.L share /mnt/mac

# mount at every boot
echo 'share /mnt/mac 9p trans=virtio,version=9p2000.L,rw,_netdev,nofail 0 0' | sudo tee -a /etc/fstab
```

Clipboard sharing between Mac and Parrot is already on (SPICE agent).

### 8.4 SSH from the Mac

The SSH server is installed but disabled.

```bash
# inside Parrot
sudo systemctl enable --now ssh

# on the Mac
ssh parrot@"$(utmctl ip-address "$VM" | head -1)"
```

With shared networking the VM is reachable from the Mac but not from the rest of the network. To expose it on the LAN, switch **Edit → Network → Network Mode** to Bridged.

### 8.5 Update Parrot

```bash
sudo parrot-upgrade
```

Parrot recommends this wrapper over a plain `apt upgrade`.

### 8.6 Snapshots and clones

```bash
utmctl clone "$VM" --name "Parrot backup"     # full copy, VM stopped

# qcow2 internal snapshots, VM stopped
D=~/VMs/Parrot-security-7.4_arm64.utm/Data/Parrot-security-7.4_arm64.qcow2
qemu-img snapshot -c clean-install "$D"       # create
qemu-img snapshot -l "$D"                     # list
qemu-img snapshot -a clean-install "$D"       # roll back
```

### 8.7 Display resolution instead of scaling

To give the guest fewer pixels rather than scaling them: **Edit → Display** and turn off **Retina Mode**. Text becomes larger without any setting inside Parrot, at the cost of sharpness.

## 9. Everyday commands

```bash
VM="ParrotOS 7.4 security Edition"

utmctl list                    # all VMs and their state
utmctl start "$VM"             # boot, or resume if suspended
utmctl suspend "$VM"           # pause to memory
utmctl stop "$VM"              # shut down
utmctl status "$VM"
utmctl ip-address "$VM"

# run a command in the guest as root
utmctl exec "$VM" --cmd /bin/bash -c 'df -h /'

# copy files through the guest agent
utmctl file push "$VM" /home/parrot/notes.txt < notes.txt
utmctl file pull "$VM" /etc/os-release > os-release.txt

utmctl help <subcommand>       # full options
```

`utmctl delete` removes a VM with no confirmation.

## 10. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `df` prints a help screen on the Mac | `df` is aliased to another tool. Call `/bin/df`. |
| Download stops short, `.aria2` file still there | Network dropped. Run the same `aria2c` command again; it resumes. |
| `gzip: data stream error` or `tar: Truncated input file` | The archive is incomplete. Finish the download before extracting. |
| `utmctl` returns nothing or an event error | UTM is not running, or the macOS Automation permission was denied. Open UTM; check **System Settings → Privacy & Security → Automation**. |
| `utmctl exec` or `ip-address` fails right after start | The guest is still booting. Wait about 30–45 seconds. |
| `VBoxManage: No such file or directory` | A leftover symlink from an old VirtualBox install. Unrelated to UTM; safe to ignore or remove. |
| Text tiny in the guest | Section 7. |
| VM missing from UTM after moving the bundle | UTM points to the original path. Move it back, or `open -a UTM <new path>` to register it again. |
| GUI programs fail under `utmctl exec` with a Qt display error | `exec` runs as root with no desktop session. Run them as the desktop user with `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY` set, as in section 7. |

## Legal

Parrot Security includes penetration-testing tools. Use them only on systems you own or have written permission to test.
