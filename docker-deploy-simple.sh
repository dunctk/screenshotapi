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
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPOSITORY="screenshot-api"
ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPOSITORY"

echo -e "${BLUE}🐳 Simple Docker Screenshot API Deployment${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""
echo -e "Function Name: ${GREEN}$FUNCTION_NAME${NC}"
echo -e "Region: ${GREEN}$REGION${NC}"
echo -e "ECR Repository: ${GREEN}$ECR_REPOSITORY${NC}"
echo ""

# Check if binary exists
if [ ! -f "target/release/screenshotapi" ]; then
    echo -e "${RED}❌ Binary not found. Building first...${NC}"
    cargo build --release
    echo -e "${GREEN}✅ Binary built successfully${NC}"
fi

# Create minimal runtime Dockerfile
cat > Dockerfile.runtime << 'EOF'
FROM --platform=linux/amd64 public.ecr.aws/lambda/provided:al2-x86_64

# Install Chrome and dependencies in one layer
RUN yum update -y && yum install -y \
    wget \
    libX11 libXcomposite libXdamage libXext libXi libXtst libXrandr \
    alsa-lib pango atk cairo-gobject gtk3 gdk-pixbuf2 libdrm libxss \
    xorg-x11-fonts-100dpi xorg-x11-fonts-75dpi xorg-x11-utils \
    xorg-x11-fonts-cyrillic xorg-x11-fonts-Type1 xorg-x11-fonts-misc \
    liberation-fonts && \
    wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm && \
    yum install -y google-chrome-stable_current_x86_64.rpm && \
    rm google-chrome-stable_current_x86_64.rpm && \
    yum clean all

# Copy the pre-built binary
COPY target/release/screenshotapi ${LAMBDA_RUNTIME_DIR}/bootstrap
RUN chmod +x ${LAMBDA_RUNTIME_DIR}/bootstrap

# Set environment variables
ENV RUST_LOG=info
ENV CHROME_PATH=/usr/bin/google-chrome-stable

CMD ["bootstrap"]
EOF

echo -e "${BLUE}🔨 Building Docker image...${NC}"

# Build the Docker image using regular docker (not buildx)
if docker build --platform linux/amd64 -f Dockerfile.runtime -t $ECR_REPOSITORY:latest .; then
    echo -e "${GREEN}✅ Docker image built successfully${NC}"
else
    echo -e "${RED}❌ Docker build failed${NC}"
    rm Dockerfile.runtime
    exit 1
fi

# Get ECR login token
echo -e "${BLUE}🔐 Logging in to ECR...${NC}"
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URI

# Create ECR repository if it doesn't exist
echo -e "${BLUE}📦 Ensuring ECR repository exists...${NC}"
if ! aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $REGION >/dev/null 2>&1; then
    aws ecr create-repository --repository-name $ECR_REPOSITORY --region $REGION
    echo -e "${GREEN}✅ ECR repository created${NC}"
else
    echo -e "${GREEN}✅ ECR repository already exists${NC}"
fi

# Tag and push image
echo -e "${BLUE}📤 Pushing to ECR...${NC}"
docker tag $ECR_REPOSITORY:latest $ECR_URI:latest
docker push $ECR_URI:latest

# Update Lambda function
echo -e "${BLUE}🚀 Updating Lambda function...${NC}"
aws lambda update-function-code \
    --function-name $FUNCTION_NAME \
    --image-uri $ECR_URI:latest \
    --region $REGION

echo -e "${GREEN}✅ Deployment complete!${NC}"

# Clean up
rm Dockerfile.runtime

# Test the function
echo -e "${BLUE}🧪 Testing the function...${NC}"
FUNCTION_URL=$(aws lambda get-function-url-config --function-name $FUNCTION_NAME --region $REGION --query FunctionUrl --output text 2>/dev/null || echo "")

if [ -n "$FUNCTION_URL" ]; then
    echo -e "${GREEN}Testing with example.com...${NC}"
    curl -s "$FUNCTION_URL?url=https://example.com" | head -c 200
    echo ""
    echo -e "${GREEN}✅ Function URL: $FUNCTION_URL${NC}"
else
    echo -e "${YELLOW}⚠️  No function URL found${NC}"
fi 