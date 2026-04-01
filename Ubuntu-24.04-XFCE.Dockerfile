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
RUN locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
    # Set global environment variables
    echo 'XDG_RUNTIME_DIR=/tmp/runtime' >> /etc/environment && \
    # Configure SSH (Disable Root Login)
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # Create default user directories
    xdg-user-dirs-update && \
    # Remove default ubuntu user if it exists
    deluser --remove-home ubuntu || true

# Fix DHCP in the container
RUN mkdir -p /etc/systemd/network && \
    cat <<'EOF' > /etc/systemd/network/10-eth-dhcp.network
[Match]
Name=eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
UseDNS=yes
UseDomains=yes
RouteMetric=100
EOF

# Apply Android compatibility fixes (Systemd and Udev)
RUN <<EOF
# Fix internet (DNS configuration)
mkdir -p /etc/systemd/resolved.conf.d
cat <<EOT > /etc/systemd/resolved.conf.d/dns.conf
[Resolve]
DNSStubListener=no
EOT

# Enable systemd-resolved and systemd-networkd
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /lib/systemd/system/systemd-resolved.service /etc/systemd/system/multi-user.target.wants/systemd-resolved.service
ln -sf /lib/systemd/system/systemd-networkd.service /etc/systemd/system/multi-user.target.wants/systemd-networkd.service

# Mask systemd-networkd-wait-online.service
ln -sf /dev/null /etc/systemd/system/systemd-networkd-wait-online.service

# Disable power button handling in systemd-logind
mkdir -p /etc/systemd/logind.conf.d
cat <<EOT > /etc/systemd/logind.conf.d/99-disable-power-button.conf
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=ignore
HandlePowerKeyLongPressHibernate=ignore
EOT

# Mask dangerous standard udev triggers
ln -sf /dev/null /etc/systemd/system/systemd-udev-trigger.service
ln -sf /dev/null /etc/systemd/system/systemd-udev-settle.service

# Create a SAFE udev trigger service
cat <<EOT > /etc/systemd/system/safe-udev-trigger.service
[Unit]
Description=Safe Udev Trigger for Android
After=systemd-udevd-kernel.socket systemd-udevd-control.socket
Wants=systemd-udevd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=-/usr/bin/udevadm trigger --subsystem-match=usb --subsystem-match=block --subsystem-match=input --subsystem-match=tty

[Install]
WantedBy=multi-user.target
EOT

# Enable the safe trigger and ensure the main daemon is unmasked
rm -f /etc/systemd/system/systemd-udevd.service
ln -sf /etc/systemd/system/safe-udev-trigger.service /etc/systemd/system/multi-user.target.wants/safe-udev-trigger.service
EOF

# Update icon and font caches in a final setup layer
RUN gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true && \
    gtk-update-icon-cache -f /usr/share/icons/Adwaita 2>/dev/null || true && \
    gtk-update-icon-cache -f /usr/share/icons/Papirus 2>/dev/null || true && \
    gtk-update-icon-cache -f /usr/share/icons/Tango 2>/dev/null || true && \
    fc-cache -fv

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
