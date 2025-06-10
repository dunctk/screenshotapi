ARG RUST_VERSION=1.78
ARG APP_NAME=screenshotapi

# 1) Compile your Rust binary in a builder stage
FROM public.ecr.aws/lambda/provided:al2023 AS builder

# Install build dependencies, including tar
RUN dnf install -y gcc make openssl-devel tar

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

# Download and install the sparticuz-chromium build using tar
ENV CHROMIUM_VERSION=121.0.0
RUN curl -Ls https://github.com/Sparticuz/chromium/releases/download/v${CHROMIUM_VERSION}/chromium-v${CHROMIUM_VERSION}-pack.tar.gz | tar -xz -C /opt

# Copy the built binary from the builder stage
COPY --from=builder /src/target/lambda/screenshotapi/bootstrap /var/runtime/

# Set the command for the Lambda function.
CMD ["bootstrap"] 