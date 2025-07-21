#!/bin/bash
set -e

echo "Building WASM filter..."

# Install wasm32 target if not already installed
rustup target add wasm32-unknown-unknown

# Build the WASM module
cargo build --target wasm32-unknown-unknown --release

# Copy the built WASM file
cp target/wasm32-unknown-unknown/release/tenant_router.wasm ../tenant-router.wasm

echo "WASM filter built successfully: ../tenant-router.wasm"
echo "Size: $(ls -lh ../tenant-router.wasm | awk '{print $5}')"

# Optional: Optimize with wasm-opt if available
if command -v wasm-opt &> /dev/null; then
    echo "Optimizing WASM with wasm-opt..."
    wasm-opt -Os ../tenant-router.wasm -o ../tenant-router-optimized.wasm
    mv ../tenant-router-optimized.wasm ../tenant-router.wasm
    echo "Optimized size: $(ls -lh ../tenant-router.wasm | awk '{print $5}')"
fi