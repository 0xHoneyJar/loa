//! Error types for kakukuma

use thiserror::Error;

/// Result type alias for kakukuma operations
pub type Result<T> = std::result::Result<T, KakuError>;

/// Error types for kakukuma operations
#[derive(Debug, Error)]
pub enum KakuError {
    #[error("Failed to read file: {0}")]
    FileRead(#[from] std::io::Error),

    #[error("Invalid file format: {0}")]
    InvalidFormat(String),

    #[error("Canvas size exceeds maximum: {0}x{1}")]
    CanvasTooLarge(u16, u16),

    #[error("Terminal too small: need {needed_width}x{needed_height}, got {actual_width}x{actual_height}")]
    TerminalTooSmall {
        needed_width: u16,
        needed_height: u16,
        actual_width: u16,
        actual_height: u16,
    },

    #[error("Clipboard error: {0}")]
    Clipboard(String),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}
