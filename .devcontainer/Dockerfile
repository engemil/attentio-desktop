FROM ubuntu:24.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update and Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libudev-dev \
    libusb-1.0-0-dev \
    git \
    curl \
    unzip \
    zip \
    xz-utils \
    minicom \
    dfu-util \
    usbutils \
    sudo \
    # Linux Desktop app prerequisites for Flutter
    clang \
    cmake \
    ninja-build \
    libgtk-3-dev \
    liblzma-dev \
    libstdc++-12-dev \
    mesa-utils \
    libgl1-mesa-dev \
    libegl1-mesa-dev \
    x11-apps \
    xauth \
    dbus-x11 \
    locales \
    libcanberra-gtk-module \
    libcanberra-gtk3-module \
    libayatana-appindicator3-dev \
    && rm -rf /var/lib/apt/lists/*

# Set up locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Prepare User
ARG USERNAME=engemil

# Remove default ubuntu user if exists, to clear UID/GID conflicts
RUN userdel -r ubuntu || true
RUN groupadd $USERNAME || true
# Create user 'engemil' with home directory and bash shell
RUN useradd -m -s /bin/bash -g $USERNAME $USERNAME || true
# Add user to sudo group
RUN usermod -aG sudo $USERNAME || true
# Allow passwordless sudo
RUN echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to the new user
USER $USERNAME
WORKDIR /home/$USERNAME

# Install Rust toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
RUN echo 'source $HOME/.cargo/env' >> /home/$USERNAME/.bashrc

# Flutter SDK is provided as a git submodule at attentio-desktop/flutter (pinned
# to 3.41.7). The workspace mounts at /workspace at runtime, so we just put the
# submodule's bin/ on PATH here — `flutter doctor` runs as a postCreateCommand
# in devcontainer.json once the mount is available.
ENV FLUTTER_HOME=/workspace/attentio-desktop/flutter
ENV PATH="$FLUTTER_HOME/bin:/home/$USERNAME/.cargo/bin:$PATH"

# Force software GL rendering so Flutter Linux apps work on the host X server
# even when the host uses an NVIDIA GPU whose DRI/GLX driver is inaccessible
# from inside the container.
ENV LIBGL_ALWAYS_SOFTWARE=1
ENV GDK_RENDERING=image

# Pre-install flutter_rust_bridge_codegen
RUN cargo install flutter_rust_bridge_codegen@^2.0.0

# Install OpenCode CLI
RUN sudo curl -fsSL https://opencode.ai/install | bash || true

# Mark workspace as a safe git directory
RUN git config --global --add safe.directory /workspace

# Make workspace directory (the mount point)
RUN sudo mkdir -p /workspace && sudo chown $USERNAME:$USERNAME /workspace
WORKDIR /workspace
