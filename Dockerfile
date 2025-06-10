# Use Amazon Linux 2 as base image for Lambda compatibility
FROM --platform=linux/amd64 public.ecr.aws/lambda/provided:al2-x86_64

# Install system dependencies and Chrome
RUN yum update -y && \
    # Install Chrome dependencies
    yum install -y \
    unzip \
    wget \
    which \
    libX11 \
    libXcomposite \
    libXdamage \
    libXext \
    libXi \
    libXtst \
    libXrandr \
    alsa-lib \
    pango \
    atk \
    cairo-gobject \
    gtk3 \
    gdk-pixbuf2 \
    libdrm \
    libxss \
    libgconf-2.so.4 \
    xorg-x11-fonts-100dpi \
    xorg-x11-fonts-75dpi \
    xorg-x11-utils \
    xorg-x11-fonts-cyrillic \
    xorg-x11-fonts-Type1 \
    xorg-x11-fonts-misc \
    liberation-fonts \
    && yum clean all

# Install Chrome - use the stable version directly
RUN wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm && \
    yum install -y google-chrome-stable_current_x86_64.rpm && \
    rm google-chrome-stable_current_x86_64.rpm

# Verify Chrome installation
RUN /usr/bin/google-chrome-stable --version

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

# Set working directory
WORKDIR ${LAMBDA_TASK_ROOT}

# Copy source code
COPY Cargo.toml Cargo.lock ./
COPY src ./src

# Build the application with increased stack size (use default target for native compilation)
ENV RUST_MIN_STACK=16777216
RUN cargo build --release

# Copy the binary to the Lambda runtime directory with correct name
RUN cp target/release/screenshotapi ${LAMBDA_RUNTIME_DIR}/bootstrap && \
    chmod +x ${LAMBDA_RUNTIME_DIR}/bootstrap

# Verify the binary exists and is executable
RUN ls -la ${LAMBDA_RUNTIME_DIR}/bootstrap

# Set environment variables for Lambda
ENV RUST_LOG=info
ENV CHROME_PATH=/usr/bin/google-chrome-stable

# Set the command
CMD ["bootstrap"] 