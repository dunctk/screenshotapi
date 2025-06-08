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
    #[error("Timeout waiting for page to load")]
    Timeout,
}

pub struct ScreenshotService;

impl ScreenshotService {
    pub fn new() -> Result<Self, ScreenshotError> {
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
        ];

        // Create launch options
        let chrome_path = find_chrome_executable();
        let options = LaunchOptions {
            path: chrome_path,
            args: chrome_args,
            headless: true,
            sandbox: false,
            ..LaunchOptions::default()
        };

        // Launch browser
        println!("Launching browser with headless_chrome...");
        let browser = Browser::new(options)
            .map_err(|e| ScreenshotError::BrowserLaunch(e.to_string()))?;
        
        println!("Browser launched successfully");

        let result = self.capture_screenshot_internal(
            &browser, 
            url, 
            width.unwrap_or(1920), 
            height.unwrap_or(1080), 
            wait_time.unwrap_or(1000)
        );

        result
    }

    fn capture_screenshot_internal(
        &self,
        browser: &Browser,
        url: &str,
        _width: u32,
        _height: u32,
        wait_time: u64,
    ) -> Result<Vec<u8>, ScreenshotError> {
        // Create new page
        println!("Creating new page...");
        let tab = browser
            .new_tab()
            .map_err(|e| ScreenshotError::Navigation(e.to_string()))?;

        // Set viewport size (skip for now and use default)

        // Navigate to URL
        println!("Navigating to URL: {}", url);
        tab.navigate_to(url)
            .map_err(|e| ScreenshotError::Navigation(e.to_string()))?;

        println!("Waiting for page to load...");
        // Wait for navigation to complete
        tab.wait_until_navigated()
            .map_err(|e| ScreenshotError::Navigation(e.to_string()))?;

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
            .map_err(|e| ScreenshotError::Screenshot(e.to_string()))?;
        
        println!("Screenshot captured successfully, size: {} bytes", screenshot_data.len());

        Ok(screenshot_data)
    }
}

/// Try to find Chrome executable in common locations
fn find_chrome_executable() -> Option<PathBuf> {
    let possible_paths = [
        "/usr/bin/chromium-browser",
        "/usr/bin/chromium",
        "/usr/bin/google-chrome",
        "/usr/bin/google-chrome-stable",
        "/snap/bin/chromium",
        "/var/lib/snapd/snap/bin/chromium",
        "/usr/bin/chromium-snap",
        "/snap/chromium/current/usr/lib/chromium-browser/chrome",
    ];
    
    println!("Searching for Chrome executable...");
    for path in &possible_paths {
        let path_buf = PathBuf::from(path);
        println!("Checking path: {}", path);
        if path_buf.exists() {
            println!("Found Chrome at: {}", path);
            return Some(path_buf);
        }
    }
    
    println!("No Chrome executable found in standard locations");
    
    // Try to find via which command
    if let Ok(output) = std::process::Command::new("which")
        .arg("chromium-browser")
        .output() {
        if output.status.success() {
            let path_string = String::from_utf8_lossy(&output.stdout);
            let path_str = path_string.trim();
            if !path_str.is_empty() {
                println!("Found Chrome via 'which': {}", path_str);
                return Some(PathBuf::from(path_str));
            }
        }
    }
    
    None
} 