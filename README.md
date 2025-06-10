# Screenshot API - AWS Lambda Function

A serverless screenshot API built with Rust and Chromium, designed to run on AWS Lambda.

## Features

- Take screenshots of any website
- Configurable viewport dimensions
- Adjustable wait times for page loading
- PNG format support
- Base64 encoded response for easy integration
- CORS enabled for web applications
- Optimized for AWS Lambda environment

## API Usage

### Endpoint

```
GET /?url=<URL>&width=<WIDTH>&height=<HEIGHT>&wait=<WAIT_TIME>
POST /?url=<URL>&width=<WIDTH>&height=<HEIGHT>&wait=<WAIT_TIME>
```

### Parameters

- `url` (required): The URL of the website to screenshot
- `width` (optional): Viewport width in pixels (default: 1920, min: 320, max: 3840)
- `height` (optional): Viewport height in pixels (default: 1080, min: 320, max: 3840)
- `wait` (optional): Additional wait time in milliseconds after page load (default: 1000)

**Note**: The `format` parameter is not currently implemented - all screenshots are returned as PNG.

### Example Requests

```bash
# Basic screenshot (uses default 1920x1080)
curl "https://your-api-gateway-url/?url=https://example.com"

# Custom dimensions and wait time
curl "https://your-api-gateway-url/?url=https://example.com&width=1280&height=720&wait=2000"

# Mobile viewport
curl "https://your-api-gateway-url/?url=https://example.com&width=375&height=667"

# Large desktop viewport
curl "https://your-api-gateway-url/?url=https://example.com&width=2560&height=1440"
```

### Response Format

#### Success Response (200)
```json
{
  "success": true,
  "data": "iVBORw0KGgoAAAANSUhEUgAA...", // Base64 encoded image
  "content_type": "image/png"
}
```

#### Error Response (4xx/5xx)
```json
{
  "error": "ERROR_CODE",
  "message": "Detailed error message"
}
```

## Building and Deployment

### Prerequisites

- Rust 1.70+
- AWS CLI configured
- Docker (for Lambda deployment)

### Local Development

```bash
# Install dependencies
cargo build

# Run tests
cargo test

# Check code
cargo check
```

### AWS Lambda Deployment

#### Option 1: Automated Deployment (Recommended)

```bash
# Build and deploy in one command
./deploy.sh

# Or with custom IAM role name
./deploy.sh my-lambda-role
```

This script will:
- Install cargo-lambda if needed
- Create IAM role if it doesn't exist
- Build the project
- Deploy to Lambda with optimal settings

#### Option 2: Manual Deployment

```bash
# Install cargo-lambda
cargo install cargo-lambda

# Build for Lambda
cargo lambda build --release

# Deploy with cargo lambda
cargo lambda deploy --iam-role arn:aws:iam::YOUR_ACCOUNT:role/lambda-execution-role
```

#### Option 3: With Custom Configuration

```bash
cargo lambda deploy \
  --iam-role arn:aws:iam::YOUR_ACCOUNT:role/lambda-execution-role \
  --memory 1024 \
  --timeout 30 \
  --env-var RUST_LOG=info
```

### API Gateway Setup

After deploying the Lambda function, you'll need to set up API Gateway to expose it as an HTTP endpoint:

#### Option 1: Function URL (Simplest)

```bash
# Enable Lambda Function URL (AWS CLI)
aws lambda create-function-url-config \
  --function-name screenshotapi \
  --auth-type NONE \
  --cors '{"AllowCredentials": false, "AllowMethods": ["GET", "POST"], "AllowOrigins": ["*"]}'
```

#### Option 2: API Gateway REST API

1. Create a new REST API in AWS API Gateway
2. Create a resource and method (GET/POST)
3. Set up Lambda proxy integration
4. Enable CORS if needed
5. Deploy the API

#### Option 3: API Gateway HTTP API (Recommended for new projects)

```bash
# Create HTTP API with Lambda integration
aws apigatewayv2 create-api \
  --name screenshot-api \
  --protocol-type HTTP \
  --target "arn:aws:lambda:REGION:ACCOUNT:function:screenshotapi"
```

### Environment Variables

The function works out of the box but you can configure:

- `RUST_LOG`: Set logging level (e.g., "info", "debug")

### Lambda Configuration Recommendations

- **Memory**: 1024 MB minimum (Chromium requires significant memory)
- **Timeout**: 30 seconds (for complex pages)
- **Runtime**: `provided.al2`

## Architecture

The API consists of three main components:

1. **HTTP Handler** (`src/http_handler.rs`): Processes incoming requests and responses
2. **Screenshot Service** (`src/screenshot.rs`): Manages Chromium browser and captures screenshots
3. **Main** (`src/main.rs`): Lambda runtime entry point

## Error Handling

The API handles various error scenarios:

- Invalid URLs
- Browser launch failures
- Navigation timeouts
- Screenshot capture errors
- Invalid parameters

## Security Considerations

- The browser runs in no-sandbox mode (required for Lambda)
- Input URL validation is performed
- CORS is enabled for web integration
- No persistent storage of screenshots

## Performance Notes

- Cold start time: ~2-3 seconds (includes Chromium initialization)
- Warm execution: ~1-2 seconds per screenshot
- Memory usage: ~200-500 MB depending on page complexity

## Limitations

- Maximum execution time limited by Lambda timeout (15 minutes max)
- Memory limited by Lambda configuration
- No support for authenticated pages (yet)
- PNG format only (JPEG planned)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License - see LICENSE file for details.
