ARG RUST_VERSION=1.78
ARG APP_NAME=screenshotapi

# 1) Start with base image and install chromium first for faster iteration
FROM public.ecr.aws/lambda/provided:al2023 AS base

# Copy tar utility (we'll need it later)
# Install build dependencies first
RUN dnf install -y gcc make openssl-devel tar xz brotli

# Download and install the latest stable sparticuz-chromium build
ENV CHROMIUM_VERSION=123.0.1
RUN curl -Ls -o /tmp/chromium.tar \
      "https://github.com/Sparticuz/chromium/releases/download/v${CHROMIUM_VERSION}/chromium-v${CHROMIUM_VERSION}-pack.tar" \
        && tar -xf /tmp/chromium.tar -C /tmp \
        # create the final target directory
        && mkdir -p /opt/chromium \
        # 1) platform specific libs
        && tar --use-compress-program=brotli -xf /tmp/al2023.tar.br   -C /opt/chromium \
        # 2) the headless_shell binary
        && brotli -d /tmp/chromium.br -o /opt/chromium/chrome \
        # 3) optional fonts and SwiftShader
        && tar --use-compress-program=brotli -xf /tmp/fonts.tar.br     -C /opt/chromium \
        && tar --use-compress-program=brotli -xf /tmp/swiftshader.tar.br -C /opt/chromium \
        && chmod +x /opt/chromium/chrome \
        && rm -rf /tmp/*.br /tmp/chromium.tar

# Set up Chrome environment
ENV PATH="/opt/chromium:${PATH}"
ENV FONTCONFIG_PATH="/opt/chromium"
ENV CHROME_NO_SANDBOX=1
ENV DISPLAY=:99

# Create a basic fonts.conf for Chrome
RUN echo '<?xml version="1.0"?>' > /opt/chromium/fonts.conf && \
    echo '<fontconfig>' >> /opt/chromium/fonts.conf && \
    echo '  <dir>/opt/chromium</dir>' >> /opt/chromium/fonts.conf && \
    echo '  <cachedir>/tmp/.fontconfig</cachedir>' >> /opt/chromium/fonts.conf && \
    echo '  <config>' >> /opt/chromium/fonts.conf && \
    echo '    <rescan><int>30</int></rescan>' >> /opt/chromium/fonts.conf && \
    echo '  </config>' >> /opt/chromium/fonts.conf && \
    echo '</fontconfig>' >> /opt/chromium/fonts.conf

# Create necessary directories for Chrome with proper permissions
RUN mkdir -p /tmp/chrome-data /tmp/chrome-cache /tmp/chrome-user-data /tmp/.config /tmp/.cache /tmp/.local/share /tmp/.fontconfig \
    && chmod -R 755 /tmp/chrome-data /tmp/chrome-cache /tmp/chrome-user-data /tmp/.config /tmp/.cache /tmp/.local /tmp/.fontconfig

# 2) Set up Rust toolchain and cargo-chef
FROM base AS chef

# Install Zig, which is required by cargo-lambda
ENV ZIG_VERSION=0.13.0
RUN curl -L "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz && \
    tar -xf /tmp/zig.tar.xz -C /usr/local/ && \
    mv /usr/local/zig-linux-x86_64-${ZIG_VERSION} /usr/local/zig && \
    rm /tmp/zig.tar.xz
ENV PATH="/usr/local/zig:${PATH}"

# Install Rust & cargo tools
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN cargo install cargo-chef cargo-lambda

WORKDIR /src

# 3) Prepare the recipe file
FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

# 4) Build dependencies (this layer will be cached)
FROM chef AS builder
COPY --from=planner /src/recipe.json recipe.json
# Build dependencies - this is the caching Docker layer!
RUN cargo chef cook --release --recipe-path recipe.json --target x86_64-unknown-linux-gnu

# Build application
COPY . .
RUN cargo lambda build --release --bin screenshotapi

# 5) Final image: copy everything together
FROM base

# Copy the built binary from the builder stage
COPY --from=builder /src/target/lambda/screenshotapi/bootstrap /var/runtime/

# Set the command for the Lambda function.
CMD ["bootstrap"] 