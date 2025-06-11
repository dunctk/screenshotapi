use headless_chrome::{Browser, LaunchOptions};
use headless_chrome::protocol::cdp::Page::CaptureScreenshotFormatOption;
use thiserror::Error;
use std::time::Duration;
use std::path::PathBuf;
use std::ffi::OsStr;

#[derive(Error, Debug)]
pub enum ScreenshotError {
    #[error("Failed to launch browser: {0}")]
    BrowserLaunch(String),
    #[error("Failed to navigate to URL: {0}")]
    Navigation(String),
    #[error("Failed to take screenshot: {0}")]
    Screenshot(String),
    #[error("Invalid URL: {0}")]
    InvalidUrl(String),
    #[error("Chrome not found: {0}")]
    ChromeNotFound(String),
}

pub struct ScreenshotService;

impl ScreenshotService {
    pub fn new() -> Result<Self, ScreenshotError> {
        // Verify Chrome is available on startup
        let chrome_path = find_chrome_executable()
            .ok_or_else(|| ScreenshotError::ChromeNotFound(
                "Chrome executable not found in any standard location".to_string()
            ))?;
        
        println!("Chrome found at: {:?}", chrome_path);
        Ok(Self)
    }

    pub async fn take_screenshot(
        &self,
        url: &str,
        width: Option<u32>,
        height: Option<u32>,
        wait_time: Option<u64>,
    ) -> Result<Vec<u8>, ScreenshotError> {
        // Validate URL
        url::Url::parse(url)
            .map_err(|e| ScreenshotError::InvalidUrl(e.to_string()))?;

        // Find Chrome executable
        let chrome_path = find_chrome_executable()
            .ok_or_else(|| ScreenshotError::ChromeNotFound(
                "Chrome executable not found".to_string()
            ))?;

        // Configure browser for Lambda environment
        let chrome_args: Vec<&OsStr> = vec![
            OsStr::new("--no-sandbox"),
            OsStr::new("--disable-setuid-sandbox"),
            OsStr::new("--disable-dev-shm-usage"),
            OsStr::new("--disable-gpu"),
            OsStr::new("--disable-gpu-sandbox"),
            OsStr::new("--disable-extensions"),
            OsStr::new("--disable-plugins"),
            OsStr::new("--disable-default-apps"),
            OsStr::new("--disable-sync"),
            OsStr::new("--disable-translate"),
            OsStr::new("--disable-web-security"),
            OsStr::new("--no-first-run"),
            OsStr::new("--no-default-browser-check"),
            OsStr::new("--headless"),
            OsStr::new("--hide-scrollbars"),
            OsStr::new("--mute-audio"),
            OsStr::new("--disable-background-networking"),
            OsStr::new("--memory-pressure-off"),
            OsStr::new("--disable-background-timer-throttling"),
            OsStr::new("--disable-renderer-backgrounding"),
            OsStr::new("--disable-backgrounding-occluded-windows"),
            OsStr::new("--disable-features=TranslateUI"),
            OsStr::new("--disable-ipc-flooding-protection"),
            OsStr::new("--single-process"), // Important for Lambda
        ];

        // Create launch options
        let options = LaunchOptions {
            path: Some(chrome_path),
            args: chrome_args,
            headless: true,
            sandbox: false,
            ..LaunchOptions::default()
        };

        // Launch browser
        println!("Launching browser with path: {:?}", options.path);
        let browser = Browser::new(options)
            .map_err(|e| ScreenshotError::BrowserLaunch(format!("Browser launch failed: {}", e)))?;
        
        println!("Browser launched successfully");

        // Validate and set viewport dimensions with reasonable limits
        let validated_width = Self::validate_dimension(width.unwrap_or(1920), "width")?;
        let validated_height = Self::validate_dimension(height.unwrap_or(1080), "height")?;

        let result = self.capture_screenshot_internal(
            &browser, 
            url, 
            validated_width, 
            validated_height, 
            wait_time.unwrap_or(1000)
        );

        result
    }

    /// Validate viewport dimensions within reasonable limits
    fn validate_dimension(value: u32, dimension_name: &str) -> Result<u32, ScreenshotError> {
        const MIN_SIZE: u32 = 320;  // Minimum reasonable size
        const MAX_SIZE: u32 = 3840; // Maximum reasonable size (4K width)
        
        if value < MIN_SIZE {
            return Err(ScreenshotError::InvalidUrl(format!(
                "{} must be at least {} pixels (got {})", 
                dimension_name, MIN_SIZE, value
            )));
        }
        
        if value > MAX_SIZE {
            return Err(ScreenshotError::InvalidUrl(format!(
                "{} must be at most {} pixels (got {})", 
                dimension_name, MAX_SIZE, value
            )));
        }
        
        Ok(value)
    }

    fn capture_screenshot_internal(
        &self,
        browser: &Browser,
        url: &str,
        width: u32,
        height: u32,
        wait_time: u64,
    ) -> Result<Vec<u8>, ScreenshotError> {
        // Create new page
        println!("Creating new page...");
        let tab = browser
            .new_tab()
            .map_err(|e| ScreenshotError::Navigation(format!("Failed to create new tab: {}", e)))?;

        // Set viewport size using emulation
        println!("Setting viewport size to {}x{}", width, height);
        tab.call_method(headless_chrome::protocol::cdp::Emulation::SetDeviceMetricsOverride {
            width,
            height,
            device_scale_factor: 1.0,
            mobile: false,
            scale: None,
            screen_width: None,
            screen_height: None,
            position_x: None,
            position_y: None,
            dont_set_visible_size: None,
            screen_orientation: None,
            viewport: None,
            device_posture: None,
            display_feature: None,
        })
        .map_err(|e| ScreenshotError::Navigation(format!("Failed to set viewport: {}", e)))?;

        // Navigate to URL
        println!("Navigating to URL: {}", url);
        tab.navigate_to(url)
            .map_err(|e| ScreenshotError::Navigation(format!("Failed to navigate to {}: {}", url, e)))?;

        println!("Waiting for page to load...");
        // Wait for navigation to complete
        tab.wait_until_navigated()
            .map_err(|e| ScreenshotError::Navigation(format!("Navigation timeout: {}", e)))?;

        // Additional wait time if specified
        if wait_time > 0 {
            println!("Waiting {} ms for page to fully load...", wait_time);
            std::thread::sleep(Duration::from_millis(wait_time));
        }

        // Take screenshot
        println!("Taking screenshot...");
        let screenshot_options = CaptureScreenshotFormatOption::Png;
        let screenshot_data = tab
            .capture_screenshot(screenshot_options, None, None, true)
            .map_err(|e| ScreenshotError::Screenshot(format!("Screenshot capture failed: {}", e)))?;
        
        println!("Screenshot captured successfully, size: {} bytes", screenshot_data.len());

        Ok(screenshot_data)
    }
}

/// Try to find Chrome executable in common locations
fn find_chrome_executable() -> Option<PathBuf> {
    for p in [
        "/opt/chromium/chrome",  // after full decompression
        "/opt/chrome",           // present in older layer zips
    ] {
        let pb = PathBuf::from(p);
        if pb.exists() {
            println!("Found Chromium at: {p}");
            return Some(pb);
        }
    }
    None
}