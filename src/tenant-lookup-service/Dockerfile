# Build stage
FROM rust:1.88.0-alpine AS builder

# Install build dependencies
RUN apk add --no-cache musl-dev openssl-dev openssl-libs-static pkgconfig

WORKDIR /usr/src/app

# Copy manifests
COPY Cargo.toml Cargo.lock ./

# Create dummy main to cache dependencies
RUN mkdir src && echo "fn main() {}" > src/main.rs

# Build dependencies
RUN cargo build --release --target x86_64-unknown-linux-musl
RUN rm -rf src

# Copy source code
COPY src ./src

# Build the application statically
RUN touch src/main.rs && cargo build --release --target x86_64-unknown-linux-musl

# Runtime stage - using scratch for minimal size
FROM alpine:3.19

# Install ca-certificates for HTTPS
RUN apk add --no-cache ca-certificates

# Copy the static binary from builder
COPY --from=builder /usr/src/app/target/x86_64-unknown-linux-musl/release/tenant-lookup /usr/local/bin/tenant-lookup

# Create non-root user
RUN adduser -D -u 1000 service

USER service

EXPOSE 8080

CMD ["tenant-lookup"]