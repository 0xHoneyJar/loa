//! kakukuma - Terminal-based ASCII art editor
//!
//! A WYSIWYG editor for creating ASCII art with solid blocks,
//! designed for CLI application developers and ASCII artists.

pub mod app;
pub mod canvas;
pub mod cursor;
pub mod error;
pub mod history;
pub mod input;
pub mod io;
pub mod tools;
pub mod ui;

pub use app::App;
pub use canvas::{Canvas, Cell};
pub use cursor::Cursor;
pub use error::KakuError;
pub use tools::Tool;
