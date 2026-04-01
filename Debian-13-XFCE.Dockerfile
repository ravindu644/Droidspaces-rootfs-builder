# Dockerfile (GUI)
# Stage 1: Build and customize the rootfs for development (GUI - Debian 13)
ARG TARGETPLATFORM
FROM debian:trixie AS customizer

ENV DEBIAN_FRONTEND=noninteractive

# Update base system and enable non-free/contrib for hfsprogs
RUN (sed -i 's/main/main contrib non-free/g' /etc/apt/sources.list 2>/dev/null || sed -i 's/Components: main/Components: main contrib non-free/g' /etc/apt/sources.list.d/debian.sources) && \
    apt-get update && apt-get upgrade -y

# Install Custom Mesa (Turnip) before anything else
COPY scripts/install_mesa.sh /tmp/install_mesa.sh
RUN chmod +x /tmp/install_mesa.sh && /tmp/install_mesa.sh && rm /tmp/install_mesa.sh

# Copy custom scripts first
COPY scripts/download-firmware /usr/local/bin/

# Copy our bashrc script to the rootfs
COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/download-firmware /etc/profile.d/ds-aliases.sh

# Main installation layer for everything (Minimal + CLI + GUI)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # Core utilities
    bash \
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
    dbus \
    systemd-sysv \
    # Basic tools
    git \
    nano \
    sudo \
    procps \
    # Networking & SSH
    openssh-server \
    net-tools \
    iptables \
    iputils-ping \
    iproute2 \
    dnsutils \
    systemd-resolved \
    # Logging & Rotation
    logrotate \
    # Wireless networking tools
    iw \
    # Compression tools
    zip \
    unzip \
    p7zip-full \
    bzip2 \
    xz-utils \
    tar \
    gzip \
    # Development tools
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
    # Python Development
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    # File system tools
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
    # XFCE Desktop Environment and essential tools
    xfce4 \
    desktop-base \
    xfce4-terminal \
    xfce4-session \
    xfce4-goodies \
    xfce4-taskmanager \
    mousepad \
    galculator \
    nemo-fileroller \
    ristretto \
    xfce4-screenshooter \
    catfish \
    xcursor-themes \
    xfce4-clipman-plugin \
    xinit \
    xorg \
    dbus-x11 \
    at-spi2-core \
    tumbler \
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
    papirus-icon-theme \
    greybird-gtk-theme \
    # Essential fonts for GUI rendering
    fonts-dejavu-core \
    fonts-liberation \
    fonts-liberation2 \
    fonts-noto-core \
    fonts-noto-ui-core \
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
    # Browser (Firefox ESR)
    firefox-esr \
    # User directory management
    xdg-user-dirs \
    # PolicyKit for permissions
    polkitd \
    mate-polkit \
    && apt-get autoremove -y

# Install Docker and set iptables-legacy
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && \
    curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh && \
    rm get-docker.sh

# Configure locales, environment, SSH, and user setup
RUN locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
    # Set global environment variables
    echo 'XDG_RUNTIME_DIR=/tmp/runtime' >> /etc/environment && \
    # Configure SSH (Disable Root Login)
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # Initialize default user directories for GUI apps
    xdg-user-dirs-update && \
    # Remove default user if it exists
    deluser --remove-home debian || true

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

# Install QEMU and binfmt
RUN apt-get update && \
    apt-get install -y --no-install-recommends qemu-user-static binfmt-support

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
