#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
FUNCTION_NAME="screenshotapi"
REGION="eu-central-1"

echo -e "${BLUE}🚀 Screenshot API Deployment with Chrome Layer${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

# Build the function
echo -e "${BLUE}🔨 Building Rust application...${NC}"
cargo lambda build --release

echo -e "${GREEN}✅ Build completed${NC}"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/screenshot-api-lambda-role"

echo -e "${BLUE}🚀 Deploying Lambda function...${NC}"

# Deploy the function with increased memory and timeout
cargo lambda deploy \
    --iam-role "$ROLE_ARN" \
    --memory 2048 \
    --timeout 60 \
    --env-var "RUST_LOG=info" \
    --env-var "CHROME_PATH=/opt/bin/chrome" \
    "$FUNCTION_NAME"

echo -e "${GREEN}✅ Function deployed${NC}"

# Public Chrome Lambda Layer ARNs (these are community-maintained layers)
echo -e "${BLUE}📦 Adding Chrome Lambda Layer...${NC}"

# Try to add a Chrome layer (this is region-specific)
CHROME_LAYER_ARN=""

# Try different Chrome layer options for eu-central-1
POTENTIAL_LAYERS=(
    "arn:aws:lambda:eu-central-1:764866452798:layer:chrome-aws-lambda:31"
    "arn:aws:lambda:eu-central-1:764866452798:layer:chrome-aws-lambda:30"
)

for layer in "${POTENTIAL_LAYERS[@]}"; do
    echo -e "${YELLOW}⚠️  Trying layer: $layer${NC}"
    if aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --layers "$layer" \
        --region "$REGION" >/dev/null 2>&1; then
        CHROME_LAYER_ARN="$layer"
        echo -e "${GREEN}✅ Successfully added Chrome layer: $layer${NC}"
        break
    else
        echo -e "${RED}❌ Failed to add layer: $layer${NC}"
    fi
done

if [ -z "$CHROME_LAYER_ARN" ]; then
    echo -e "${YELLOW}⚠️  No Chrome layer added. Function will work without screenshots.${NC}"
fi

# Test the function
echo -e "${BLUE}🧪 Testing the deployment...${NC}"

# Get function URL
FUNCTION_URL=$(aws lambda get-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --query FunctionUrl \
    --output text 2>/dev/null)

if [ -n "$FUNCTION_URL" ]; then
    echo -e "${GREEN}✅ Function URL: $FUNCTION_URL${NC}"
    
    echo -e "${BLUE}Testing with example.com...${NC}"
    RESPONSE=$(curl -s "$FUNCTION_URL?url=https://example.com" | head -c 300)
    echo "Response: $RESPONSE"
    
    if echo "$RESPONSE" | grep -q "base64"; then
        echo -e "${GREEN}🎉 Success! Screenshot API is working with Chrome!${NC}"
    elif echo "$RESPONSE" | grep -q "Chrome not found"; then
        echo -e "${YELLOW}⚠️  Chrome not available. Function deployed but screenshots won't work.${NC}"
    else
        echo -e "${YELLOW}⚠️  Function deployed, testing response received${NC}"
    fi
else
    echo -e "${RED}❌ Could not get function URL${NC}"
fi

echo ""
echo -e "${BLUE}📋 Deployment Summary:${NC}"
echo -e "Function: ${GREEN}$FUNCTION_NAME${NC}"
echo -e "Memory: ${GREEN}2048MB${NC}"
echo -e "Timeout: ${GREEN}60s${NC}"
if [ -n "$CHROME_LAYER_ARN" ]; then
    echo -e "Chrome Layer: ${GREEN}$CHROME_LAYER_ARN${NC}"
else
    echo -e "Chrome Layer: ${YELLOW}Not added${NC}"
fi
echo -e "Function URL: ${GREEN}$FUNCTION_URL${NC}" 