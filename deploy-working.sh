#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FUNCTION_NAME="screenshotapi"
REGION="eu-central-1"
ROLE_NAME="screenshot-api-lambda-role"

echo -e "${BLUE}🚀 Working Screenshot API Deployment${NC}"
echo -e "${BLUE}====================================${NC}"
echo ""

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"

echo -e "${BLUE}📋 Configuration:${NC}"
echo -e "Function: ${GREEN}$FUNCTION_NAME${NC}"
echo -e "Region: ${GREEN}$REGION${NC}"
echo -e "Role: ${GREEN}$ROLE_ARN${NC}"
echo ""

# Step 1: Cross-compile for x86_64
echo -e "${BLUE}🔨 Step 1: Cross-compiling for x86_64...${NC}"
export CC_x86_64_unknown_linux_gnu=x86_64-linux-gnu-gcc
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=x86_64-linux-gnu-gcc

# Clean and build
rm -rf target/
cargo build --release --target x86_64-unknown-linux-gnu

# Create Lambda package
rm -f bootstrap lambda-deployment.zip
cp target/x86_64-unknown-linux-gnu/release/screenshotapi bootstrap
chmod +x bootstrap
zip lambda-deployment.zip bootstrap

echo -e "${GREEN}✅ Build complete${NC}"

# Step 2: Deploy to Lambda
echo -e "${BLUE}🚀 Step 2: Deploying to AWS Lambda...${NC}"

# Delete existing function if it exists
aws lambda delete-function --function-name $FUNCTION_NAME --region $REGION 2>/dev/null || true

# Create new function with x86_64 architecture
aws lambda create-function \
    --function-name $FUNCTION_NAME \
    --runtime provided.al2 \
    --role $ROLE_ARN \
    --handler bootstrap \
    --zip-file fileb://lambda-deployment.zip \
    --architectures x86_64 \
    --memory-size 2048 \
    --timeout 60 \
    --environment "Variables={RUST_LOG=info,CHROME_PATH=/opt/chromium/chrome}" \
    --region $REGION > /dev/null

echo -e "${GREEN}✅ Function deployed${NC}"

# Step 3: Wait for function to be ready, then attach Chrome layer
echo -e "${BLUE}📦 Step 3: Waiting for function to be ready...${NC}"

# Wait for function to be active
echo -e "${YELLOW}⏳ Waiting for function to initialize...${NC}"
aws lambda wait function-active \
    --function-name $FUNCTION_NAME \
    --region $REGION

echo -e "${BLUE}📦 Attaching Chrome layer...${NC}"
CHROME_LAYER_ARN="arn:aws:lambda:${REGION}:764866452798:layer:chrome-aws-lambda:46"

aws lambda update-function-configuration \
    --function-name $FUNCTION_NAME \
    --layers $CHROME_LAYER_ARN \
    --region $REGION > /dev/null

echo -e "${GREEN}✅ Chrome layer attached${NC}"

# Step 4: Create function URL (delete existing first if needed)
echo -e "${BLUE}🌐 Step 4: Setting up Function URL...${NC}"

# Delete existing function URL if it exists
aws lambda delete-function-url-config \
    --function-name $FUNCTION_NAME \
    --region $REGION 2>/dev/null || true

# Create new function URL
aws lambda create-function-url-config \
    --function-name $FUNCTION_NAME \
    --auth-type NONE \
    --cors '{"AllowCredentials":false,"AllowMethods":["GET","POST"],"AllowOrigins":["*"],"AllowHeaders":["*"],"MaxAge":86400}' \
    --region $REGION > /dev/null

FUNCTION_URL=$(aws lambda get-function-url-config \
    --function-name $FUNCTION_NAME \
    --region $REGION \
    --query 'FunctionUrl' \
    --output text)

echo -e "${GREEN}✅ Function URL created${NC}"

# Step 5: Test deployment
echo -e "${BLUE}🧪 Step 5: Testing deployment...${NC}"

echo -e "${YELLOW}⏳ Testing function...${NC}"
sleep 2

RESPONSE=$(curl -s "$FUNCTION_URL?url=https://example.com" | head -c 100)
echo "Response: $RESPONSE"

echo ""
echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
echo -e "${GREEN}Function URL: $FUNCTION_URL${NC}"
echo ""
echo -e "${BLUE}📋 Final Configuration:${NC}"
echo -e "• Architecture: ${GREEN}x86_64${NC}"
echo -e "• Chrome Layer: ${GREEN}Attached${NC}"
echo -e "• Memory: ${GREEN}2048MB${NC}"
echo -e "• Timeout: ${GREEN}60s${NC}"
echo ""
echo -e "${BLUE}Test the API:${NC}"
echo "curl \"$FUNCTION_URL?url=https://example.com\"" 