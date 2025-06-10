#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_FUNCTION_NAME="screenshotapi-docker"
DEFAULT_MEMORY=1024
DEFAULT_TIMEOUT=30
DEFAULT_REGION=${AWS_DEFAULT_REGION:-"us-east-1"}

# Parse command line arguments
FUNCTION_NAME=${1:-$DEFAULT_FUNCTION_NAME}
MEMORY=${2:-$DEFAULT_MEMORY}
TIMEOUT=${3:-$DEFAULT_TIMEOUT}
REGION=${4:-$DEFAULT_REGION}

echo -e "${BLUE}🐳 Screenshot API Docker Deployment Script${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""
echo -e "Function Name: ${GREEN}$FUNCTION_NAME${NC}"
echo -e "Memory: ${GREEN}${MEMORY}MB${NC}"
echo -e "Timeout: ${GREEN}${TIMEOUT}s${NC}"
echo -e "Region: ${GREEN}$REGION${NC}"
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI and credentials
check_aws() {
    echo -e "${BLUE}📋 Checking AWS CLI and credentials...${NC}"
    
    if ! command_exists aws; then
        echo -e "${RED}❌ AWS CLI not found. Please install AWS CLI first.${NC}"
        exit 1
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo -e "${RED}❌ AWS credentials not configured. Please run 'aws configure' first.${NC}"
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo -e "${GREEN}✅ AWS CLI configured for account: $ACCOUNT_ID${NC}"
}

# Function to check Docker
check_docker() {
    echo -e "${BLUE}🐳 Checking Docker...${NC}"
    
    if ! command_exists docker; then
        echo -e "${RED}❌ Docker not found. Please install Docker first.${NC}"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker daemon not running. Please start Docker.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Docker is running${NC}"
}

# Function to create ECR repository if it doesn't exist
create_ecr_repo() {
    echo -e "${BLUE}📦 Setting up ECR repository...${NC}"
    
    REPO_NAME="screenshotapi"
    ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME"
    
    # Check if repository exists
    if aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$REGION" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ ECR repository '$REPO_NAME' already exists${NC}"
    else
        echo -e "${YELLOW}⚠️  Creating ECR repository '$REPO_NAME'...${NC}"
        aws ecr create-repository --repository-name "$REPO_NAME" --region "$REGION" >/dev/null
        echo -e "${GREEN}✅ ECR repository '$REPO_NAME' created${NC}"
    fi
    
    echo -e "${GREEN}✅ ECR URI: $ECR_URI${NC}"
}

# Function to push Docker image to ECR
push_to_ecr() {
    echo -e "${BLUE}🚀 Pushing Docker image to ECR...${NC}"
    
    # Login to ECR
    echo -e "${YELLOW}⚠️  Logging into ECR...${NC}"
    aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
    
    # Tag the image
    echo -e "${YELLOW}⚠️  Tagging image...${NC}"
    docker tag screenshotapi-lambda:latest "$ECR_URI:latest"
    
    # Push the image
    echo -e "${YELLOW}⚠️  Pushing image to ECR...${NC}"
    docker push "$ECR_URI:latest"
    
    echo -e "${GREEN}✅ Image pushed to ECR successfully${NC}"
}

# Function to create or update Lambda function
deploy_lambda() {
    echo -e "${BLUE}⚡ Deploying Lambda function...${NC}"
    
    # Check if function exists
    if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Updating existing Lambda function...${NC}"
        
        # Update function code
        aws lambda update-function-code \
            --function-name "$FUNCTION_NAME" \
            --image-uri "$ECR_URI:latest" \
            --region "$REGION" >/dev/null
        
        # Update function configuration
        aws lambda update-function-configuration \
            --function-name "$FUNCTION_NAME" \
            --memory-size "$MEMORY" \
            --timeout "$TIMEOUT" \
            --environment Variables="{RUST_LOG=info,CHROME_PATH=/usr/bin/google-chrome-stable}" \
            --region "$REGION" >/dev/null
        
        echo -e "${GREEN}✅ Lambda function updated successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Creating new Lambda function...${NC}"
        
        # Use existing IAM role (assuming it exists from previous deployment)
        ROLE_NAME="screenshot-api-lambda-role"
        ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"
        echo -e "${GREEN}✅ Using existing IAM role: $ROLE_NAME${NC}"
        
        # Create Lambda function
        aws lambda create-function \
            --function-name "$FUNCTION_NAME" \
            --package-type Image \
            --code ImageUri="$ECR_URI:latest" \
            --role "$ROLE_ARN" \
            --memory-size "$MEMORY" \
            --timeout "$TIMEOUT" \
            --environment Variables="{RUST_LOG=info,CHROME_PATH=/usr/bin/google-chrome-stable}" \
            --region "$REGION" >/dev/null
        
        echo -e "${GREEN}✅ Lambda function created successfully${NC}"
    fi
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
    "AllowHeaders": ["content-type", "x-amz-date", "authorization", "x-api-key"],
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

# Function to test the deployment
test_deployment() {
    echo -e "${BLUE}🧪 Testing deployment...${NC}"
    
    if [ -n "$FUNCTION_URL" ]; then
        echo -e "${YELLOW}⏳ Testing with example.com...${NC}"
        
        # Test with a simple request
        RESPONSE=$(curl -s "${FUNCTION_URL}?url=https://example.com" | jq -r '.success // "null"')
        
        if [ "$RESPONSE" = "true" ]; then
            echo -e "${GREEN}✅ Deployment test successful!${NC}"
        else
            echo -e "${YELLOW}⚠️  Test returned: $RESPONSE${NC}"
            echo -e "${YELLOW}   This might be normal if the function is still warming up.${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  No function URL available for testing${NC}"
    fi
}

# Function to display usage examples
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
    else
        echo -e "${YELLOW}Function URL not available. Check AWS Lambda console for the URL.${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}📝 Notes:${NC}"
    echo "• This deployment includes Chrome browser in the container"
    echo "• Viewport size limits: 320-3840 pixels"
    echo "• Wait time: milliseconds to wait after page load"
    echo "• Response format: JSON with base64-encoded PNG image"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}Starting Docker deployment process...${NC}"
    echo ""
    
    check_aws
    check_docker
    create_ecr_repo
    push_to_ecr
    deploy_lambda
    setup_function_url
    test_deployment
    show_examples
    
    echo ""
    echo -e "${GREEN}🎉 Docker deployment completed successfully!${NC}"
    echo -e "${GREEN}Function Name: $FUNCTION_NAME${NC}"
    echo -e "${GREEN}Function URL: $FUNCTION_URL${NC}"
    echo -e "${GREEN}ECR Repository: $ECR_URI${NC}"
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
    echo "  $0                                    # Use all defaults"
    echo "  $0 my-function                       # Custom function name"
    echo "  $0 my-function 2048                  # Custom memory"
    echo "  $0 my-function 2048 60               # Custom memory and timeout"
    echo ""
    exit 0
fi

# Run main function
main 