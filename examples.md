# Screenshot API Usage Examples

This document provides examples of how to use the Screenshot API from various programming languages.

## JavaScript/Node.js

### Using fetch (Browser/Node.js)

```javascript
async function takeScreenshot(url, options = {}) {
    const params = new URLSearchParams({
        url: url,
        width: options.width || 1920,
        height: options.height || 1080,
        wait: options.wait || 1000,
        format: options.format || 'png'
    });

    try {
        const response = await fetch(`https://your-api-gateway-url/screenshot?${params}`);
        const data = await response.json();
        
        if (data.success) {
            // Convert base64 to blob for download
            const imageData = atob(data.data);
            const bytes = new Uint8Array(imageData.length);
            for (let i = 0; i < imageData.length; i++) {
                bytes[i] = imageData.charCodeAt(i);
            }
            const blob = new Blob([bytes], { type: data.content_type });
            
            // Create download link
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'screenshot.png';
            a.click();
            URL.revokeObjectURL(url);
        } else {
            console.error('Screenshot failed:', data.message);
        }
    } catch (error) {
        console.error('Error:', error);
    }
}

// Usage
takeScreenshot('https://example.com', { width: 1280, height: 720 });
```

### Using axios (Node.js)

```javascript
const axios = require('axios');
const fs = require('fs');

async function takeScreenshot(url, filename = 'screenshot.png') {
    try {
        const response = await axios.get('https://your-api-gateway-url/screenshot', {
            params: {
                url: url,
                width: 1920,
                height: 1080,
                wait: 1000
            }
        });

        if (response.data.success) {
            // Save base64 image to file
            const buffer = Buffer.from(response.data.data, 'base64');
            fs.writeFileSync(filename, buffer);
            console.log(`Screenshot saved as ${filename}`);
        } else {
            console.error('Screenshot failed:', response.data.message);
        }
    } catch (error) {
        console.error('Error:', error.message);
    }
}

// Usage
takeScreenshot('https://example.com', 'example_screenshot.png');
```

## Python

### Using requests

```python
import requests
import base64
from typing import Optional

def take_screenshot(url: str, 
                   width: int = 1920, 
                   height: int = 1080, 
                   wait: int = 1000,
                   output_file: str = 'screenshot.png') -> bool:
    """
    Take a screenshot of a website and save it to a file.
    
    Args:
        url: The URL to screenshot
        width: Viewport width in pixels
        height: Viewport height in pixels
        wait: Wait time in milliseconds
        output_file: Output filename
    
    Returns:
        True if successful, False otherwise
    """
    
    params = {
        'url': url,
        'width': width,
        'height': height,
        'wait': wait,
        'format': 'png'
    }
    
    try:
        response = requests.get(
            'https://your-api-gateway-url/screenshot',
            params=params,
            timeout=30
        )
        response.raise_for_status()
        
        data = response.json()
        
        if data.get('success'):
            // Decode base64 and save to file
            image_data = base64.b64decode(data['data'])
            with open(output_file, 'wb') as f:
                f.write(image_data)
            print(f"Screenshot saved as {output_file}")
            return True
        else:
            print(f"Screenshot failed: {data.get('message', 'Unknown error')}")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"Request error: {e}")
        return False
    except Exception as e:
        print(f"Error: {e}")
        return False

# Usage
if __name__ == "__main__":
    take_screenshot('https://example.com', width=1280, height=720)
```

### Using aiohttp (Async)

```python
import aiohttp
import asyncio
import base64

async def take_screenshot_async(url: str, output_file: str = 'screenshot.png'):
    params = {
        'url': url,
        'width': 1920,
        'height': 1080,
        'wait': 1000
    }
    
    async with aiohttp.ClientSession() as session:
        try:
            async with session.get(
                'https://your-api-gateway-url/screenshot',
                params=params
            ) as response:
                data = await response.json()
                
                if data.get('success'):
                    image_data = base64.b64decode(data['data'])
                    with open(output_file, 'wb') as f:
                        f.write(image_data)
                    print(f"Screenshot saved as {output_file}")
                else:
                    print(f"Screenshot failed: {data.get('message')}")
                    
        except Exception as e:
            print(f"Error: {e}")

# Usage
asyncio.run(take_screenshot_async('https://example.com'))
```

## PHP

```php
<?php

function takeScreenshot($url, $options = []) {
    $params = http_build_query([
        'url' => $url,
        'width' => $options['width'] ?? 1920,
        'height' => $options['height'] ?? 1080,
        'wait' => $options['wait'] ?? 1000,
        'format' => $options['format'] ?? 'png'
    ]);
    
    $apiUrl = "https://your-api-gateway-url/screenshot?" . $params;
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $apiUrl);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 30);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Content-Type: application/json'
    ]);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    if ($httpCode === 200) {
        $data = json_decode($response, true);
        
        if ($data['success']) {
            $imageData = base64_decode($data['data']);
            $filename = $options['filename'] ?? 'screenshot.png';
            
            if (file_put_contents($filename, $imageData)) {
                echo "Screenshot saved as $filename\n";
                return true;
            } else {
                echo "Failed to save screenshot\n";
                return false;
            }
        } else {
            echo "Screenshot failed: " . $data['message'] . "\n";
            return false;
        }
    } else {
        echo "HTTP Error: $httpCode\n";
        return false;
    }
}

// Usage
takeScreenshot('https://example.com', [
    'width' => 1280,
    'height' => 720,
    'filename' => 'example_screenshot.png'
]);
?>
```

## Go

```go
package main

import (
    "encoding/base64"
    "encoding/json"
    "fmt"
    "io"
    "net/http"
    "net/url"
    "os"
    "strconv"
    "time"
)

type ScreenshotResponse struct {
    Success     bool   `json:"success"`
    Data        string `json:"data"`
    ContentType string `json:"content_type"`
    Error       string `json:"error,omitempty"`
    Message     string `json:"message,omitempty"`
}

func takeScreenshot(targetURL string, width, height, wait int, outputFile string) error {
    // Build query parameters
    params := url.Values{}
    params.Add("url", targetURL)
    params.Add("width", strconv.Itoa(width))
    params.Add("height", strconv.Itoa(height))
    params.Add("wait", strconv.Itoa(wait))
    
    apiURL := "https://your-api-gateway-url/screenshot?" + params.Encode()
    
    // Create HTTP client with timeout
    client := &http.Client{
        Timeout: 30 * time.Second,
    }
    
    // Make request
    resp, err := client.Get(apiURL)
    if err != nil {
        return fmt.Errorf("request failed: %w", err)
    }
    defer resp.Body.Close()
    
    // Read response
    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return fmt.Errorf("failed to read response: %w", err)
    }
    
    // Parse JSON response
    var screenshotResp ScreenshotResponse
    if err := json.Unmarshal(body, &screenshotResp); err != nil {
        return fmt.Errorf("failed to parse response: %w", err)
    }
    
    if !screenshotResp.Success {
        return fmt.Errorf("screenshot failed: %s", screenshotResp.Message)
    }
    
    // Decode base64 image
    imageData, err := base64.StdEncoding.DecodeString(screenshotResp.Data)
    if err != nil {
        return fmt.Errorf("failed to decode image: %w", err)
    }
    
    // Save to file
    if err := os.WriteFile(outputFile, imageData, 0644); err != nil {
        return fmt.Errorf("failed to save file: %w", err)
    }
    
    fmt.Printf("Screenshot saved as %s\n", outputFile)
    return nil
}

func main() {
    err := takeScreenshot("https://example.com", 1920, 1080, 1000, "screenshot.png")
    if err != nil {
        fmt.Printf("Error: %v\n", err)
        os.Exit(1)
    }
}
```

## cURL Examples

### Basic screenshot
```bash
curl "https://your-api-gateway-url/screenshot?url=https://example.com" \
  | jq -r '.data' \
  | base64 -d > screenshot.png
```

### Custom dimensions
```bash
curl "https://your-api-gateway-url/screenshot?url=https://example.com&width=1280&height=720&wait=2000" \
  -o response.json

# Extract and save image
jq -r '.data' response.json | base64 -d > screenshot.png
```

### With error handling
```bash
#!/bin/bash
response=$(curl -s "https://your-api-gateway-url/screenshot?url=https://example.com")
success=$(echo "$response" | jq -r '.success')

if [ "$success" = "true" ]; then
    echo "$response" | jq -r '.data' | base64 -d > screenshot.png
    echo "Screenshot saved successfully"
else
    echo "Error: $(echo "$response" | jq -r '.message')"
fi
```

## Error Handling

All examples should include proper error handling for common scenarios:

- Network timeouts
- Invalid URLs
- API rate limits
- Invalid parameters
- Server errors

Make sure to:
1. Set appropriate timeouts (30+ seconds recommended)
2. Handle HTTP error codes
3. Validate the JSON response structure
4. Check the `success` field before processing the image data
5. Handle base64 decoding errors 