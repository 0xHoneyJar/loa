//! .kaku file format for saving/loading sessions

use std::path::Path;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::canvas::{Canvas, Cell};
use crate::error::{KakuError, Result};

/// A stored cell (sparse representation)
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StoredCell {
    pub x: u16,
    pub y: u16,
    pub char: char,
    pub fg: u8,
    pub bg: u8,
}

impl StoredCell {
    pub fn from_cell(x: u16, y: u16, cell: &Cell) -> Self {
        Self {
            x,
            y,
            char: cell.char,
            fg: cell.fg,
            bg: cell.bg,
        }
    }

    pub fn to_cell(&self) -> Cell {
        Cell {
            char: self.char,
            fg: self.fg,
            bg: self.bg,
        }
    }
}

/// Canvas data in the file format
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StoredCanvas {
    pub width: u16,
    pub height: u16,
    pub cells: Vec<StoredCell>,
}

/// File metadata
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Metadata {
    pub created: DateTime<Utc>,
    pub modified: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
}

impl Default for Metadata {
    fn default() -> Self {
        let now = Utc::now();
        Self {
            created: now,
            modified: now,
            author: None,
        }
    }
}

/// The .kaku file format
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct KakuFile {
    pub version: String,
    pub canvas: StoredCanvas,
    pub metadata: Metadata,
}

impl KakuFile {
    /// Current file format version
    pub const VERSION: &'static str = "1.0";

    /// Create a new KakuFile from a canvas
    pub fn from_canvas(canvas: &Canvas) -> Self {
        // Only store non-empty cells (sparse representation)
        let cells: Vec<StoredCell> = canvas
            .iter_non_empty()
            .map(|(x, y, cell)| StoredCell::from_cell(x, y, cell))
            .collect();

        Self {
            version: Self::VERSION.to_string(),
            canvas: StoredCanvas {
                width: canvas.width,
                height: canvas.height,
                cells,
            },
            metadata: Metadata::default(),
        }
    }

    /// Convert to a canvas
    pub fn to_canvas(&self) -> Canvas {
        let mut canvas = Canvas::new(self.canvas.width, self.canvas.height);

        for stored in &self.canvas.cells {
            canvas.set(stored.x, stored.y, stored.to_cell());
        }

        canvas
    }

    /// Update the modified timestamp
    pub fn touch(&mut self) {
        self.metadata.modified = Utc::now();
    }
}

/// Save a canvas to a .kaku file
pub fn save_kaku(canvas: &Canvas, path: &Path) -> Result<()> {
    let mut kaku = KakuFile::from_canvas(canvas);
    kaku.touch();

    let json = serde_json::to_string_pretty(&kaku)?;
    std::fs::write(path, json)?;

    Ok(())
}

/// Load a canvas from a .kaku file
pub fn load_kaku(path: &Path) -> Result<Canvas> {
    let json = std::fs::read_to_string(path)?;
    let kaku: KakuFile = serde_json::from_str(&json)?;

    // Validate version
    if !kaku.version.starts_with("1.") {
        return Err(KakuError::InvalidFormat(format!(
            "Unsupported file version: {}",
            kaku.version
        )));
    }

    Ok(kaku.to_canvas())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_roundtrip() {
        let mut canvas = Canvas::new(10, 10);
        canvas.set(2, 2, Cell::block(1));
        canvas.set(5, 5, Cell::block(2));

        let kaku = KakuFile::from_canvas(&canvas);
        let restored = kaku.to_canvas();

        assert_eq!(restored.get(2, 2), Some(&Cell::block(1)));
        assert_eq!(restored.get(5, 5), Some(&Cell::block(2)));
        assert_eq!(restored.get(0, 0), Some(&Cell::EMPTY));
    }

    #[test]
    fn test_save_load() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("test.kaku");

        let mut canvas = Canvas::new(10, 10);
        canvas.set(3, 3, Cell::block(5));

        save_kaku(&canvas, &path).unwrap();
        let loaded = load_kaku(&path).unwrap();

        assert_eq!(loaded.get(3, 3), Some(&Cell::block(5)));
    }

    #[test]
    fn test_sparse_storage() {
        let mut canvas = Canvas::new(32, 32);
        canvas.set(0, 0, Cell::block(1));

        let kaku = KakuFile::from_canvas(&canvas);

        // Should only store 1 cell, not 1024
        assert_eq!(kaku.canvas.cells.len(), 1);
    }
}
