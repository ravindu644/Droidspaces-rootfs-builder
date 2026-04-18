# syntax=docker/dockerfile:1
# Dockerfile (GUI)
# Stage 1: Build and customize the rootfs for development
ARG TARGETPLATFORM
FROM ubuntu:24.04 AS customizer

ENV DEBIAN_FRONTEND=noninteractive

# Update base system
RUN apt-get update && apt-get upgrade -y

# Install Custom Mesa (Turnip) before anything else
COPY scripts/install_mesa.sh /tmp/install_mesa.sh
RUN chmod +x /tmp/install_mesa.sh && /tmp/install_mesa.sh && rm /tmp/install_mesa.sh

# Copy custom scripts first
COPY scripts/download-firmware /usr/local/bin/

# Copy our bashrc script to the rootfs
COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/download-firmware /etc/profile.d/ds-aliases.sh

# This is the main installation layer. All package installations, PPA additions,
# and setup are done here to minimize layers and maximize build speed.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # Essentials for adding PPAs
    software-properties-common \
    gnupg \
    # Add PPAs for fastfetch and Firefox ESR
    && add-apt-repository ppa:zhangsongcui3371/fastfetch -y && \
    add-apt-repository ppa:mozillateam/ppa -y && \
    # Update package lists again after adding PPAs
    apt-get update && \
    # Install all packages in a single command
    apt-get install -y --no-install-recommends \
    # Core utilities
    bash \
    dialog \
    coreutils \
    file \
    findutils \
    grep \
    sed \
    gawk \
    curl \
    wget \
    ca-certificates \
    locales \
    bash-completion \
    udev \
    systemd-resolved \
    iptables \
    kmod \
    procps \
    systemd-sysv \
    # Compression tools
    zip \
    unzip \
    p7zip-full \
    bzip2 \
    xz-utils \
    tar \
    gzip \
    # System tools
    htop \
    btop \
    vim \
    nano \
    git \
    sudo \
    openssh-server \
    net-tools \
    iputils-ping \
    iproute2 \
    dnsutils \
    usbutils \
    pciutils \
    lsof \
    psmisc \
    # Wireless networking tools for hotspot functionality
    iw \
    wpasupplicant \
    isc-dhcp-client \
    network-manager \
    # Logging & Rotation
    logrotate \
    # C/C++ Development
    build-essential \
    gcc \
    g++ \
    gdb \
    make \
    cmake \
    autoconf \
    automake \
    libtool \
    pkg-config \
    # File system tools
    gparted \
    dosfstools \
    exfatprogs \
    btrfs-progs \
    ntfs-3g \
    xfsprogs \
    jfsutils \
    hfsprogs \
    reiserfsprogs \
    cryptsetup \
    nilfs-tools \
    udftools \
    f2fs-tools \
    # Python Development
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    python-is-python3 \
    # Additional dev tools
    clang \
    llvm \
    valgrind \
    strace \
    ltrace \
    # XFCE Desktop Environment and essential tools
    xfce4 \
    desktop-base \
    xfce4-terminal \
    xfce4-session \
    xscreensaver \
    xfce4-goodies \
    xubuntu-wallpapers \
    xfce4-taskmanager \
    mousepad \
    galculator \
    nemo-fileroller \
    ristretto \
    xfce4-screenshooter \
    catfish \
    mugshot \
    xcursor-themes \
    dmz-cursor-theme \
    xfce4-clipman-plugin \
    xinit \
    xorg \
    xserver-xorg-core \
    xterm \
    xserver-xorg-video-fbdev \
    xserver-xorg-input-libinput \
    dbus-x11 \
    dbus \
    at-spi2-core \
    tumbler \
    fonts-lklug-sinhala \
    # Icon themes
    adwaita-icon-theme-full \
    hicolor-icon-theme \
    gnome-icon-theme \
    tango-icon-theme \
    # GTK theme engines and popular themes
    gtk2-engines-murrine \
    gtk2-engines-pixbuf \
    arc-theme \
    numix-gtk-theme \
    materia-gtk-theme \
    papirus-icon-theme \
    greybird-gtk-theme \
    # Essential fonts for GUI rendering
    fonts-dejavu-core \
    fonts-liberation \
    fonts-liberation2 \
    fonts-noto-core \
    fonts-noto-ui-core \
    fonts-ubuntu \
    # File manager and GUI utilities
    thunar \
    thunar-volman \
    thunar-archive-plugin \
    thunar-media-tags-plugin \
    gvfs \
    gvfs-backends \
    gvfs-fuse \
    x11-xserver-utils \
    x11-utils \
    xclip \
    xsel \
    xfwm4 \
    xfconf \
    zenity \
    notification-daemon \
    # User directory management
    xdg-user-dirs \
    # Packages from PPAs
    fastfetch \
    firefox-esr \
    # PolicyKit for permissions
    policykit-1 \
    && apt-get purge -y gdm3 gnome-session gnome-shell whoopsie && \
    apt-get autoremove -y

# Install Docker and set iptables-legacy
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && \
    curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh && \
    rm get-docker.sh

# Configure locales, environment, SSH, Docker, and user setup in a single layer
RUN <<EOF
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Set global environment variables
echo 'XDG_RUNTIME_DIR=/tmp/runtime' >> /etc/environment

# Configure SSH (Allow Root Login)
mkdir -p /var/run/sshd
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Create default user directories
xdg-user-dirs-update

# Remove default ubuntu user if it exists
deluser --remove-home ubuntu || true

# Android network group setup (required for socket access on Android kernels)
grep -q '^aid_inet:' /etc/group    || echo 'aid_inet:x:3003:'    >> /etc/group
grep -q '^aid_net_raw:' /etc/group || echo 'aid_net_raw:x:3004:' >> /etc/group
grep -q '^aid_net_admin:' /etc/group || echo 'aid_net_admin:x:3005:' >> /etc/group

# Root gets required permissions for networking, input, and display
usermod -a -G aid_inet,aid_net_raw,input,video,tty root

# _apt needs aid_inet as primary group so apt works
grep -q '^_apt:' /etc/passwd && usermod -g aid_inet _apt || true

# Future users created with adduser automatically get network access
sed -i '/^EXTRA_GROUPS=/d; /^ADD_EXTRA_GROUPS=/d' /etc/adduser.conf
echo 'ADD_EXTRA_GROUPS=1'               >> /etc/adduser.conf
echo 'EXTRA_GROUPS="aid_inet aid_net_raw input video tty"' >> /etc/adduser.conf

# Mask systemd-journald-audit.socket to prevent deadlocks on Android kernels
ln -sf /dev/null /etc/systemd/system/systemd-journald-audit.socket

# Configure journald to skip problematic bits (Audit, KMsg, etc)
cat >> /etc/systemd/journald.conf << EOT
[Journal]
ReadKMsg=no
Audit=no
Storage=volatile
EOT

# Enable essential services (dbus, udev, network, resolved)
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /lib/systemd/system/dbus.service /etc/systemd/system/multi-user.target.wants/dbus.service
ln -sf /lib/systemd/system/systemd-udevd.service /etc/systemd/system/multi-user.target.wants/systemd-udevd.service
ln -sf /lib/systemd/system/systemd-resolved.service /etc/systemd/system/multi-user.target.wants/systemd-resolved.service
ln -sf /lib/systemd/system/systemd-networkd.service /etc/systemd/system/multi-user.target.wants/systemd-networkd.service

# Force LightDM to use VT7
mkdir -p /etc/lightdm/lightdm.conf.d
cat <<EOT > /etc/lightdm/lightdm.conf.d/90-force-vt.conf
[LightDM]
minimum-vt=7

[Seat:*]
xserver-command=X -vt7
EOT

# Configure Xorg to catch input events via libinput
mkdir -p /etc/X11/xorg.conf.d
cat <<EOT > /etc/X11/xorg.conf.d/99-input.conf
Section "InputClass"
    Identifier "libinput pointer catchall"
    MatchIsPointer "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
EndSection

Section "InputClass"
    Identifier "libinput keyboard catchall"
    MatchIsKeyboard "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
EndSection
EOT

# Add systemd overrides for udev services to prevent failure when paths are read-only
for unit in systemd-udevd.service systemd-udev-trigger.service systemd-udev-settle.service systemd-udevd-kernel.socket systemd-udevd-control.socket; do \
  mkdir -p /etc/systemd/system/\$unit.d; \
  printf "[Unit]\nConditionPathIsReadWrite=\n" > /etc/systemd/system/\$unit.d/override.conf; \
done

# Configure systemd-logind power key behavior
mkdir -p /etc/systemd/logind.conf.d
cat <<EOT > /etc/systemd/logind.conf.d/99-power-key.conf
[Login]
HandlePowerKey=suspend
EOT
EOF

# Update icon and font caches in a final setup layer
RUN gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true && \
    gtk-update-icon-cache -f /usr/share/icons/Adwaita 2>/dev/null || true && \
    gtk-update-icon-cache -f /usr/share/icons/Papirus 2>/dev/null || true && \
    gtk-update-icon-cache -f /usr/share/icons/Tango 2>/dev/null || true && \
    fc-cache -fv

# Fix xfwm4 vblank_mode for Turnip (Qualcomm GPU) - prevents XFCE compositor hang
# The sed fix 's/vblank_mode=auto/vblank_mode=off/' does NOT work on the XML format
# (the file uses value="auto" as an XML attribute, not a bare key=value pair).
# Instead we pre-place the complete xfwm4.xml with the correct value already set.
# xfconf will not regenerate the file if it already exists, so this is reliable.
#
# Coverage:
#   /etc/skel  → copied verbatim into every new user's $HOME by adduser
#   /root      → root's home is never seeded from /etc/skel, so patch it directly
#   /usr/share/xfwm4/defaults → xfwm4's key=value seed file, read before xfconf
COPY scripts/xfwm4.xml /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
COPY scripts/xfwm4.xml /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml

# /usr/share/xfwm4/defaults - key=value seed file xfwm4 reads before xfconf
RUN if [ -f /usr/share/xfwm4/defaults ]; then \
    if grep -q '^vblank_mode=' /usr/share/xfwm4/defaults; then \
        sed -i 's/^vblank_mode=.*/vblank_mode=off/' /usr/share/xfwm4/defaults; \
    else \
        echo 'vblank_mode=off' >> /usr/share/xfwm4/defaults; \
    fi; \
fi

# Purge and reinstall qemu and binfmt in the exact order specified
RUN apt-get purge -y qemu-* binfmt-support && \
    apt-get autoremove -y && \
    apt-get autoclean && \
    # Remove any leftover config files
    rm -rf /var/lib/binfmts/* && \
    rm -rf /etc/binfmt.d/* && \
    rm -rf /usr/lib/binfmt.d/qemu-* && \
    # Update package lists
    apt-get update && \
    # Install ONLY these packages (in this specific order)
    apt-get install -y qemu-user-static && \
    apt-get install -y binfmt-support

# Apply Logging Hardening (journald 200MB limit and logrotate maxsize 50M)
RUN <<EOF
# Configure journald to limit logs to 200MB
mkdir -p /etc/systemd/journald.conf.d
cat <<EOT > /etc/systemd/journald.conf.d/ds-logging.conf
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=200M
MaxRetentionSec=7day
MaxLevelStore=info
EOT

# Configure logrotate to rotate based on size (50MB) to prevent disk fill
sed -i 's/^#maxsize.*/maxsize 50M/' /etc/logrotate.conf
if ! grep -q "maxsize 50M" /etc/logrotate.conf; then
    echo "maxsize 50M" >> /etc/logrotate.conf
fi
EOF

# Final cleanup of APT cache
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Stage 2: Export to scratch for extraction
FROM scratch AS export

# Copy the entire filesystem from the customizer stage
COPY --from=customizer / /
