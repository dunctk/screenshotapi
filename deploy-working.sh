#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Configuration ---
FUNCTION_NAME="screenshotapi"
REGION="eu-central-1"
# The name of the ECR repository
ECR_REPO_NAME="screenshotapi-repo" 
# Tag for the Docker image
IMAGE_TAG="latest"

echo -e "${BLUE}🚀 Screenshot API Container Deployment${NC}"
echo "========================================"
echo ""

# --- Get AWS Account ID ---
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Failed to get AWS Account ID. Is the AWS CLI configured?${NC}"
    exit 1
fi

ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/screenshot-api-lambda-role"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE_URI="${ECR_URI}/${ECR_REPO_NAME}:${IMAGE_TAG}"

echo -e "${BLUE}📋 Configuration:${NC}"
echo "Function Name: ${GREEN}$FUNCTION_NAME${NC}"
echo "Region:          ${GREEN}$REGION${NC}"
echo "ECR URI:         ${GREEN}$ECR_URI${NC}"
echo "Image URI:       ${GREEN}$IMAGE_URI${NC}"
echo "Role ARN:        ${GREEN}$ROLE_ARN${NC}"
echo ""

# --- Step 1: Login to ECR ---
echo -e "${BLUE}🔑 Step 1: Logging into ECR...${NC}"
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URI}
echo -e "${GREEN}✅ ECR login successful.${NC}"
echo ""

# --- Step 2: Build Docker Image ---
echo -e "${BLUE}🔨 Step 2: Building Docker image...${NC}"
# Build for the native architecture of the runner (which is x86_64)
docker build -t "${ECR_REPO_NAME}:${IMAGE_TAG}" .
echo -e "${GREEN}✅ Docker image built successfully.${NC}"
echo ""

# --- Step 3: Create ECR Repository if it doesn't exist ---
echo -e "${BLUE}📦 Step 3: Ensuring ECR repository exists...${NC}"
aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" --region "${REGION}" >/dev/null 2>&1 || \
    aws ecr create-repository \
        --repository-name "${ECR_REPO_NAME}" \
        --region "${REGION}" \
        --image-scanning-configuration scanOnPush=true \
        --image-tag-mutability MUTABLE > /dev/null
echo -e "${GREEN}✅ ECR repository is ready.${NC}"
echo ""

# --- Step 4: Tag and Push Image to ECR ---
echo -e "${BLUE}🚀 Step 4: Pushing image to ECR...${NC}"
docker tag "${ECR_REPO_NAME}:${IMAGE_TAG}" "${IMAGE_URI}"
docker push "${IMAGE_URI}"
echo -e "${GREEN}✅ Image pushed to ${IMAGE_URI}.${NC}"
echo ""

# --- Step 5: Deploy Lambda Function ---
echo -e "${BLUE}🚀 Step 5: Deploying Lambda function...${NC}"
# Delete the function if it exists to ensure a clean deployment
aws lambda delete-function --function-name "${FUNCTION_NAME}" --region "${REGION}" 2>/dev/null || true
echo "Waiting for old function to be deleted..."
sleep 5 

aws lambda create-function \
    --function-name "${FUNCTION_NAME}" \
    --package-type Image \
    --code ImageUri="${IMAGE_URI}" \
    --role "${ROLE_ARN}" \
    --region "${REGION}" \
    --memory-size 2048 \
    --timeout 60 \
    --architectures x86_64 > /dev/null

echo "Waiting for function to become active..."
aws lambda wait function-active-v2 --function-name "${FUNCTION_NAME}" --region "${REGION}"
echo -e "${GREEN}✅ Lambda function deployed successfully.${NC}"
echo ""

# --- Step 6: Configure Function URL ---
echo -e "${BLUE}🌐 Step 6: Setting up Function URL...${NC}"
# Delete existing URL config if it exists
aws lambda delete-function-url-config --function-name $FUNCTION_NAME --region $REGION 2>/dev/null || true
# Create new URL config
aws lambda create-function-url-config \
    --function-name "${FUNCTION_NAME}" \
    --auth-type NONE \
    --cors '{"AllowMethods":["GET","POST"],"AllowOrigins":["*"]}' \
    --region "${REGION}" > /dev/null
# Add permission for public access
aws lambda add-permission \
    --function-name "${FUNCTION_NAME}" \
    --statement-id FunctionURLAllowPublicAccess \
    --action lambda:InvokeFunctionUrl \
    --principal "*" \
    --function-url-auth-type NONE \
    --region "${REGION}" >/dev/null 2>&1 || true

FUNCTION_URL=$(aws lambda get-function-url-config \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}" \
    --query 'FunctionUrl' \
    --output text)

echo -e "${GREEN}✅ Function URL is ready: ${FUNCTION_URL}${NC}"
echo ""

# --- Step 7: Test Deployment ---
echo -e "${BLUE}🧪 Step 7: Testing deployment...${NC}"
# Add a small delay to ensure the URL is fully propagated
sleep 5 

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${FUNCTION_URL}" -H "Content-Type: application/json" -d '{"url":"https://example.com"}')
echo "Test Response HTTP Code: $RESPONSE"
echo ""

if [ "$RESPONSE" -eq 200 ]; then
    echo -e "${GREEN}🎉 Deployment successful! Test returned HTTP 200.${NC}"
else
    echo -e "${RED}⚠️ Deployment test failed with HTTP code: $RESPONSE${NC}"
    echo -e "${YELLOW}Check the function logs:${NC}"
    echo "aws logs tail /aws/lambda/$FUNCTION_NAME --follow"
fi

echo ""
echo -e "${BLUE}Test with:${NC}"
echo "curl -X POST \"${FUNCTION_URL}\" -H \"Content-Type: application/json\" -d '{\"url\":\"https://www.google.com\"}' --output screenshot.png"
echo ""