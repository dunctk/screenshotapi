#!/bin/bash

# Screenshot API Build Script for AWS Lambda

set -e

echo "🚀 Building Screenshot API for AWS Lambda..."

# Check if cargo-lambda is installed
if ! command -v cargo-lambda &> /dev/null; then
    echo "📦 Installing cargo-lambda..."
    cargo install cargo-lambda
fi

# Clean previous builds
echo "🧹 Cleaning previous builds..."
cargo clean

# Build for Lambda
echo "🔨 Building for Lambda runtime..."
cargo lambda build --release

echo "✅ Build complete!"
echo ""
echo "🚀 Ready for deployment!"
echo ""
echo "💡 Deploy using cargo-lambda:"
echo "   cargo lambda deploy --iam-role arn:aws:iam::YOUR_ACCOUNT:role/lambda-execution-role"
echo ""
echo "Or deploy with custom settings:"
echo "   cargo lambda deploy \\"
echo "     --iam-role arn:aws:iam::YOUR_ACCOUNT:role/lambda-execution-role \\"
echo "     --memory 1024 \\"
echo "     --timeout 30 \\"
echo "     --env-var RUST_LOG=info"
echo ""
echo "📋 Next steps after deployment:"
echo "   1. Note the Lambda function ARN from the output"
echo "   2. Set up API Gateway integration"
echo "   3. Test your endpoint!" 