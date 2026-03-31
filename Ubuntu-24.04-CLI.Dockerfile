# Dockerfile (CLI)
# Stage 1: Build and customize the rootfs for development
ARG TARGETPLATFORM
FROM --platform=${TARGETPLATFORM:-linux/arm64} ubuntu:24.04 AS customizer

ENV DEBIAN_FRONTEND=noninteractive

# Update base system
RUN apt-get update && apt-get upgrade -y

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
    # Update package lists again after adding PPAs
    apt-get update && \
    # Install all packages in a single command
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
    vim \
    nano \
    git \
    sudo \
    openssh-server \
    net-tools \
    iptables \
    iputils-ping \
    iproute2 \
    dnsutils \
    usbutils \
    pciutils \
    lsof \
    psmisc \
    procps \
    fastfetch \
    # Wireless networking tools for hotspot functionality
    iw \
    hostapd \
    isc-dhcp-server \
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

# Final cleanup of APT cache
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Stage 2: Export to scratch for extraction
FROM scratch AS export

# Copy the entire filesystem from the customizer stage
COPY --from=customizer / /
