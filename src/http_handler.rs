use lambda_http::{Body, Error, Request, RequestExt, Response};
use serde::Serialize;
use crate::screenshot::ScreenshotService;
use std::env;

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
    message: String,
}

#[derive(Serialize)]
struct SuccessResponse {
    success: bool,
    data: String, // base64 encoded image
    content_type: String,
}

/// Main function handler for the screenshot API
pub(crate) async fn function_handler(event: Request) -> Result<Response<Body>, Error> {
    // --- Authentication ---
    let expected_api_key = env::var("API_KEY").unwrap_or_default();
    let rapidapi_secret = env::var("RAPIDAPI_PROXY_SECRET").unwrap_or_default();

    let mut authorized = false;

    // If no keys are configured, allow the request (e.g. for local dev)
    if expected_api_key.is_empty() && rapidapi_secret.is_empty() {
        authorized = true;
    }

    // 1. Check for RapidAPI Proxy Secret
    if !authorized && !rapidapi_secret.is_empty() {
        if let Some(proxy_secret) = event
            .headers()
            .get("X-RapidAPI-Proxy-Secret")
            .and_then(|v| v.to_str().ok())
        {
            if proxy_secret == rapidapi_secret {
                authorized = true;
            }
        }
    }

    // 2. Check for standard API key (header or query param)
    if !authorized && !expected_api_key.is_empty() {
        // Try to read from `x-api-key` header first
        let provided_key_header = event
            .headers()
            .get("x-api-key")
            .and_then(|v| v.to_str().ok());

        // Fallback: query parameter `key`
        let query_params = event.query_string_parameters();
        let provided_key_query = query_params.first("key");

        let provided_key = provided_key_header.or(provided_key_query);

        if provided_key == Some(expected_api_key.as_str()) {
            authorized = true;
        }
    }

    if !authorized {
        // Unauthorized
        let error_response = ErrorResponse {
            error: "UNAUTHORIZED".to_string(),
            message: "Invalid or missing API key".to_string(),
        };

        let resp = Response::builder()
            .status(401)
            .header("content-type", "application/json")
            .body(serde_json::to_string(&error_response)?.into())
            .map_err(Box::new)?;

        return Ok(resp);
    }

    match handle_screenshot_request(event).await {
        Ok(response) => Ok(response),
        Err(e) => {
            eprintln!("Error processing request: {}", e);
            let error_response = ErrorResponse {
                error: "INTERNAL_ERROR".to_string(),
                message: e.to_string(),
            };
            
            let resp = Response::builder()
                .status(500)
                .header("content-type", "application/json")
                .body(serde_json::to_string(&error_response)?.into())
                .map_err(Box::new)?;
            Ok(resp)
        }
    }
}

async fn handle_screenshot_request(
    event: Request,
) -> Result<Response<Body>, Box<dyn std::error::Error + Send + Sync>> {
    // Extract query parameters
    let params = event.query_string_parameters();
    
    // Get required URL parameter
    let url = params
        .first("url")
        .ok_or("Missing required 'url' parameter")?;

    // Get optional parameters
    let width = params
        .first("width")
        .and_then(|w| w.parse::<u32>().ok())
        .unwrap_or(1920);
    
    let height = params
        .first("height")
        .and_then(|h| h.parse::<u32>().ok())
        .unwrap_or(1080);
    
    let wait_time = params
        .first("wait")
        .and_then(|w| w.parse::<u64>().ok())
        .unwrap_or(1000);

    let format = params
        .first("format")
        .unwrap_or("png");

    // Validate format
    if format != "png" && format != "jpeg" {
        return Err("Invalid format. Only 'png' and 'jpeg' are supported".into());
    }

    // Handle the request based on method
    match event.method().as_str() {
        "GET" => take_screenshot(url, Some(width), Some(height), Some(wait_time), format).await,
        "POST" => {
            // For POST, we could accept JSON body with more complex parameters
            // For now, just use the same logic as GET
            take_screenshot(url, Some(width), Some(height), Some(wait_time), format).await
        }
        _ => {
            let error_response = ErrorResponse {
                error: "METHOD_NOT_ALLOWED".to_string(),
                message: "Only GET and POST methods are supported".to_string(),
            };
            
            let resp = Response::builder()
                .status(405)
                .header("content-type", "application/json")
                .body(serde_json::to_string(&error_response)?.into())
                .map_err(Box::new)?;
            Ok(resp)
        }
    }
}

async fn take_screenshot(
    url: &str,
    width: Option<u32>,
    height: Option<u32>,
    wait_time: Option<u64>,
    format: &str,
) -> Result<Response<Body>, Box<dyn std::error::Error + Send + Sync>> {
    
    // Create screenshot service
    let screenshot_service = ScreenshotService::new()
        .map_err(|e| format!("Failed to initialize browser: {}", e))?;

    // Take screenshot
    let screenshot_data = screenshot_service
        .take_screenshot(url, width, height, wait_time)
        .await
        .map_err(|e| format!("Failed to take screenshot: {}", e))?;

    // Check if client wants JSON response or direct image
    let content_type = match format {
        "png" => "image/png",
        "jpeg" => "image/jpeg",
        _ => "image/png",
    };

    // Encode as base64 for JSON response
    use base64::Engine;
    let encoded_image = base64::engine::general_purpose::STANDARD.encode(&screenshot_data);
    
    let success_response = SuccessResponse {
        success: true,
        data: encoded_image,
        content_type: content_type.to_string(),
    };

    let resp = Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .header("access-control-allow-origin", "*") // Enable CORS
        .header("access-control-allow-methods", "GET, POST, OPTIONS")
        .header("access-control-allow-headers", "Content-Type")
        .body(serde_json::to_string(&success_response)?.into())
        .map_err(Box::new)?;
    
    Ok(resp)
}

#[cfg(test)]
mod tests {
    use super::*;
    use lambda_http::Request;

    #[tokio::test]
    async fn test_missing_url_parameter() {
        let request = Request::default();
        let response = function_handler(request).await.unwrap();
        assert_eq!(response.status(), 500);
    }
}
