#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_FUNCTION_NAME="screenshotapi"
DEFAULT_MEMORY=1024
DEFAULT_TIMEOUT=30
DEFAULT_REGION=${AWS_DEFAULT_REGION:-"us-east-1"}

# Parse command line arguments
FUNCTION_NAME=${1:-$DEFAULT_FUNCTION_NAME}
MEMORY=${2:-$DEFAULT_MEMORY}
TIMEOUT=${3:-$DEFAULT_TIMEOUT}
REGION=${4:-$DEFAULT_REGION}

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
REPO_NAME="screenshot-api"
IMAGE_TAG="latest"
FULL_IMAGE_URI="${ECR_URI}/${REPO_NAME}:${IMAGE_TAG}"

echo -e "${BLUE}🐳 Screenshot API Docker Deployment${NC}"
echo -e "${BLUE}====================================${NC}"
echo ""
echo -e "Function Name: ${GREEN}$FUNCTION_NAME${NC}"
echo -e "Memory: ${GREEN}${MEMORY}MB${NC}"
echo -e "Timeout: ${GREEN}${TIMEOUT}s${NC}"
echo -e "Region: ${GREEN}$REGION${NC}"
echo -e "ECR Repository: ${GREEN}$REPO_NAME${NC}"
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}📋 Checking prerequisites...${NC}"
    
    if ! command_exists docker; then
        echo -e "${RED}❌ Docker not found. Please install Docker first.${NC}"
        exit 1
    fi
    
    if ! command_exists aws; then
        echo -e "${RED}❌ AWS CLI not found. Please install AWS CLI first.${NC}"
        exit 1
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo -e "${RED}❌ AWS credentials not configured. Please run 'aws configure' first.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Function to create ECR repository if it doesn't exist
create_ecr_repo() {
    echo -e "${BLUE}📦 Setting up ECR repository...${NC}"
    
    if aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$REGION" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ ECR repository '$REPO_NAME' already exists${NC}"
    else
        echo -e "${YELLOW}⚠️  Creating ECR repository '$REPO_NAME'...${NC}"
        aws ecr create-repository --repository-name "$REPO_NAME" --region "$REGION" >/dev/null
        echo -e "${GREEN}✅ ECR repository '$REPO_NAME' created${NC}"
    fi
}

# Function to login to ECR
ecr_login() {
    echo -e "${BLUE}🔐 Logging in to ECR...${NC}"
    aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_URI"
    echo -e "${GREEN}✅ ECR login successful${NC}"
}

# Function to build Docker image
build_image() {
    echo -e "${BLUE}🔨 Building Docker image...${NC}"
    
    if [ ! -f "Dockerfile" ]; then
        echo -e "${RED}❌ Dockerfile not found. Please ensure Dockerfile exists in the current directory.${NC}"
        exit 1
    fi
    
    # Create buildx builder if it doesn't exist
    if ! docker buildx ls | grep -q "multiarch"; then
        echo -e "${YELLOW}⚠️  Creating multi-architecture builder...${NC}"
        docker buildx create --name multiarch --use
    else
        docker buildx use multiarch
    fi
    
    # Use buildx for cross-platform build
    docker buildx build --platform linux/amd64 --load -t "$REPO_NAME:$IMAGE_TAG" .
    docker tag "$REPO_NAME:$IMAGE_TAG" "$FULL_IMAGE_URI"
    
    echo -e "${GREEN}✅ Docker image built successfully${NC}"
}

# Function to push image to ECR
push_image() {
    echo -e "${BLUE}📤 Pushing image to ECR...${NC}"
    
    docker push "$FULL_IMAGE_URI"
    
    echo -e "${GREEN}✅ Image pushed successfully${NC}"
}

# Function to create or update Lambda function
deploy_lambda() {
    echo -e "${BLUE}🚀 Deploying Lambda function...${NC}"
    
    # Check if function exists
    if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Updating existing function...${NC}"
        aws lambda update-function-code \
            --function-name "$FUNCTION_NAME" \
            --image-uri "$FULL_IMAGE_URI" \
            --region "$REGION" >/dev/null
        
        aws lambda update-function-configuration \
            --function-name "$FUNCTION_NAME" \
            --memory-size "$MEMORY" \
            --timeout "$TIMEOUT" \
            --environment Variables='{RUST_LOG=info}' \
            --region "$REGION" >/dev/null
    else
        echo -e "${YELLOW}⚠️  Creating new function...${NC}"
        
        # Create execution role if it doesn't exist
        ROLE_NAME="screenshot-api-lambda-role"
        if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠️  Creating IAM role...${NC}"
            
            cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
            
            aws iam create-role \
                --role-name "$ROLE_NAME" \
                --assume-role-policy-document file://trust-policy.json >/dev/null
            
            aws iam attach-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" >/dev/null
            
            rm trust-policy.json
            
            # Wait for role propagation
            echo -e "${YELLOW}⏳ Waiting for IAM role propagation...${NC}"
            sleep 10
        fi
        
        ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"
        
        aws lambda create-function \
            --function-name "$FUNCTION_NAME" \
            --package-type Image \
            --code ImageUri="$FULL_IMAGE_URI" \
            --role "$ROLE_ARN" \
            --memory-size "$MEMORY" \
            --timeout "$TIMEOUT" \
            --environment Variables='{RUST_LOG=info}' \
            --region "$REGION" >/dev/null
    fi
    
    echo -e "${GREEN}✅ Lambda function deployed successfully${NC}"
}

# Function to create or update function URL
setup_function_url() {
    echo -e "${BLUE}🌐 Setting up Function URL...${NC}"
    
    # Check if function URL already exists
    if aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --region "$REGION" >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Function URL already exists. Getting current URL...${NC}"
    else
        echo -e "${YELLOW}⚠️  Creating Function URL...${NC}"
        
        # Create CORS configuration file
        cat > cors-config.json << EOF
{
    "AllowCredentials": false,
    "AllowMethods": ["GET", "POST"],
    "AllowOrigins": ["*"],
    "AllowHeaders": ["*"],
    "MaxAge": 86400
}
EOF
        
        aws lambda create-function-url-config \
            --function-name "$FUNCTION_NAME" \
            --auth-type "NONE" \
            --cors file://cors-config.json \
            --region "$REGION" >/dev/null
        
        rm cors-config.json
    fi
    
    # Get the function URL
    FUNCTION_URL=$(aws lambda get-function-url-config \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" \
        --query FunctionUrl \
        --output text)
    
    echo -e "${GREEN}✅ Function URL: $FUNCTION_URL${NC}"
}

# Function to test deployment
test_deployment() {
    echo -e "${BLUE}🧪 Testing deployment...${NC}"
    
    if [ -n "$FUNCTION_URL" ]; then
        echo -e "${YELLOW}⏳ Testing with example.com...${NC}"
        
        # Wait a bit for the function to be ready
        sleep 5
        
        RESPONSE=$(curl -s "${FUNCTION_URL}?url=https://example.com" | jq -r '.success // "null"' 2>/dev/null || echo "error")
        
        if [ "$RESPONSE" = "true" ]; then
            echo -e "${GREEN}✅ Deployment test successful!${NC}"
        else
            echo -e "${YELLOW}⚠️  Test returned: $RESPONSE${NC}"
            echo -e "${YELLOW}   Function might still be warming up. Try again in a few moments.${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  No function URL available for testing${NC}"
    fi
}

# Function to show usage examples
show_examples() {
    echo ""
    echo -e "${BLUE}📖 Usage Examples:${NC}"
    echo -e "${BLUE}=================${NC}"
    echo ""
    
    if [ -n "$FUNCTION_URL" ]; then
        echo -e "${GREEN}Basic screenshot (default 1920x1080):${NC}"
        echo "curl \"${FUNCTION_URL}?url=https://example.com\""
        echo ""
        
        echo -e "${GREEN}Custom viewport size:${NC}"
        echo "curl \"${FUNCTION_URL}?url=https://example.com&width=800&height=600\""
        echo ""
        
        echo -e "${GREEN}Mobile viewport:${NC}"
        echo "curl \"${FUNCTION_URL}?url=https://example.com&width=375&height=667\""
        echo ""
        
        echo -e "${GREEN}With custom wait time:${NC}"
        echo "curl \"${FUNCTION_URL}?url=https://example.com&wait=2000\""
    fi
    
    echo ""
    echo -e "${BLUE}📝 Notes:${NC}"
    echo "• Viewport size limits: 320-3840 pixels"
    echo "• Wait time: milliseconds to wait after page load"
    echo "• Response format: JSON with base64-encoded PNG image"
    echo "• Docker-based deployment includes Chrome browser"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}Starting Docker deployment process...${NC}"
    echo ""
    
    check_prerequisites
    create_ecr_repo
    ecr_login
    build_image
    push_image
    deploy_lambda
    setup_function_url
    test_deployment
    show_examples
    
    echo ""
    echo -e "${GREEN}🎉 Docker deployment completed successfully!${NC}"
    echo -e "${GREEN}Function Name: $FUNCTION_NAME${NC}"
    echo -e "${GREEN}Function URL: $FUNCTION_URL${NC}"
    echo -e "${GREEN}ECR Image: $FULL_IMAGE_URI${NC}"
    echo ""
    echo -e "${BLUE}You can monitor your function in the AWS Lambda console:${NC}"
    echo -e "${BLUE}https://console.aws.amazon.com/lambda/home?region=$REGION#/functions/$FUNCTION_NAME${NC}"
}

# Show help if requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [FUNCTION_NAME] [MEMORY_MB] [TIMEOUT_SECONDS] [REGION]"
    echo ""
    echo "Arguments:"
    echo "  FUNCTION_NAME   Lambda function name (default: $DEFAULT_FUNCTION_NAME)"
    echo "  MEMORY_MB       Memory allocation in MB (default: $DEFAULT_MEMORY)"
    echo "  TIMEOUT_SECONDS Timeout in seconds (default: $DEFAULT_TIMEOUT)"
    echo "  REGION          AWS region (default: $DEFAULT_REGION)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Use all defaults"
    echo "  $0 my-function              # Custom function name"
    echo "  $0 my-function 2048 60      # Custom memory and timeout"
    echo ""
    echo "Prerequisites:"
    echo "  - Docker installed and running"
    echo "  - AWS CLI configured"
    echo "  - Dockerfile in current directory"
    echo ""
    exit 0
fi

# Run main function
main 