# Screenshot API - AWS Lambda Function

![Screenshot API Logo](docs/screenshot-api.png)

## 🚀 **Ready to Use? Skip the Setup!**

**Get instant access to our hosted Screenshot API on RapidAPI for just 1¢ per screenshot!**

✅ **No monthly commitment** - Pay only for what you use  
✅ **No subscription fees** - Simple, transparent pricing  
✅ **Instant setup** - Start taking screenshots in seconds  
✅ **99.9% uptime** - Production-ready infrastructure  

**[🔥 Get Started on RapidAPI →](https://rapidapi.com/dunctk/api/screenshot-web-api)**

---

*Want to self-host instead? Continue reading for deployment instructions.*

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
- `API_KEY`: **Optional.** If set, every request must provide this value either in the `x-api-key` HTTP header **or** as the `key` query-string parameter. Omit the variable to disable authentication (useful for local testing).

### Setting `API_KEY`

Once the Lambda function exists you can set / change the key at any time:

```bash
# one-off update (keeps existing image & config)
aws lambda update-function-configuration \
  --function-name screenshotapi \
  --environment "Variables={API_KEY=your-secret-value}" \
  --region eu-central-1
```

The key persists for the lifetime of the function. **However:** the sample `deploy-working.sh` script currently deletes and recreates the function on each deploy. If you use that script you have two options:

1. Add `--environment "Variables={API_KEY=your-secret-value}"` to the `aws lambda create-function` call inside the script so the key is applied on every deploy.
2. Stop deleting the function (remove the `aws lambda delete-function` call). Updating an existing function keeps its environment variables intact.

### Calling the API with the key

```bash
# Header style
curl -H "x-api-key: your-secret-value" "${FUNCTION_URL}?url=https://example.com" | jq .

# Query-string style (handy for quick browser tests)
curl "${FUNCTION_URL}?url=https://example.com&key=your-secret-value" | jq .
```

Requests without the correct key receive:

```json
HTTP/1.1 401 Unauthorized
{
  "error": "UNAUTHORIZED",
  "message": "Invalid or missing API key"
}
```

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

---

## 🎯 **Ready to Start Taking Screenshots?**

**Why spend hours setting up infrastructure when you can start immediately?**

Our hosted Screenshot API on RapidAPI gives you:
- **Instant access** - No deployment, no configuration
- **Only 1¢ per screenshot** - The most affordable solution
- **No monthly fees** - Pay as you go
- **Enterprise-grade reliability** - 99.9% uptime 

### **[🚀 Start Using the API Now →](https://rapidapi.com/dunctk/api/screenshot-web-api)**


