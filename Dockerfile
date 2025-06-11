ARG RUST_VERSION=1.78
ARG APP_NAME=screenshotapi

# 1) Compile your Rust binary in a builder stage
FROM public.ecr.aws/lambda/provided:al2023 AS builder

# Install build dependencies, including tar and xz
RUN dnf install -y gcc make openssl-devel tar xz

# Install Zig, which is required by cargo-lambda
ENV ZIG_VERSION=0.13.0
RUN curl -L "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz && \
    tar -xf /tmp/zig.tar.xz -C /usr/local/ && \
    mv /usr/local/zig-linux-x86_64-${ZIG_VERSION} /usr/local/zig && \
    rm /tmp/zig.tar.xz
ENV PATH="/usr/local/zig:${PATH}"

# Install Rust & cargo-lambda
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN cargo install cargo-lambda

# Copy your source code
WORKDIR /src
COPY . .

# Build for x86_64
RUN cargo lambda build --release --bin screenshotapi

# 2) Final image: install Chromium and copy your function
FROM public.ecr.aws/lambda/provided:al2023

# Copy tar from the builder stage.
COPY --from=builder /usr/bin/tar /usr/bin/

# Download and install the latest stable sparticuz-chromium build
ENV CHROMIUM_VERSION=123.0.1
RUN dnf install -y brotli 
RUN curl -Ls -o /tmp/chromium.tar \
      "https://github.com/Sparticuz/chromium/releases/download/v${CHROMIUM_VERSION}/chromium-v${CHROMIUM_VERSION}-pack.tar" \
        && tar -xf /tmp/chromium.tar -C /tmp \
        # create the final target directory
        && mkdir -p /opt/chromium \
        # 1) platform specific libs
        && tar --use-compress-program=br -xf /tmp/al2023.tar.br   -C /opt/chromium \
        # 2) the headless_shell binary
        && brotli -d /tmp/chromium.br -o /opt/chromium/chrome \
        # 3) optional fonts and SwiftShader
        && tar --use-compress-program=br -xf /tmp/fonts.tar.br     -C /opt/chromium \
        && tar --use-compress-program=br -xf /tmp/swiftshader.tar.br -C /opt/chromium \
        && chmod +x /opt/chromium/chrome \
        && rm -rf /tmp/*.br /tmp/chromium.tar
ENV PATH="/opt:${PATH}"

# Extract the package and clean up
RUN tar -xf /tmp/chromium.tar -C /opt/ && \
    rm /tmp/chromium.tar

RUN chmod +x /opt/chrome
# Copy the built binary from the builder stage
COPY --from=builder /src/target/lambda/screenshotapi/bootstrap /var/runtime/

# Set the command for the Lambda function.
CMD ["bootstrap"] 