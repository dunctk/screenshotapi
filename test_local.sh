#!/bin/bash

# Local testing script for Screenshot API

set -e

echo "🧪 Testing Screenshot API locally..."

# Check if cargo-lambda is installed
if ! command -v cargo-lambda &> /dev/null; then
    echo "❌ cargo-lambda not found. Please install it first:"
    echo "   cargo install cargo-lambda"
    exit 1
fi

# Start local server in background
echo "🚀 Starting local Lambda server..."
cargo lambda watch &
SERVER_PID=$!

# Wait for server to start
echo "⏳ Waiting for server to start..."
sleep 5

# Function to cleanup
cleanup() {
    echo "🧹 Cleaning up..."
    kill $SERVER_PID 2>/dev/null || true
    exit
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

# Test basic functionality
echo "📸 Testing basic screenshot..."
curl -s "http://localhost:9000/lambda-url/screenshotapi/?url=https://example.com" | jq .

echo ""
echo "📸 Testing with custom parameters..."
curl -s "http://localhost:9000/lambda-url/screenshotapi/?url=https://httpbin.org/html&width=800&height=600&wait=2000" | jq .

echo ""
echo "✅ Local tests completed!"
echo "💡 You can also test manually with:"
echo "   curl 'http://localhost:9000/lambda-url/screenshotapi/?url=https://example.com'" 