//! Canvas and Cell data structures

use serde::{Deserialize, Serialize};

/// A single cell on the canvas
#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
pub struct Cell {
    /// Character to display
    pub char: char,
    /// Foreground color (0-15 ANSI)
    pub fg: u8,
    /// Background color (0-15 ANSI)
    pub bg: u8,
}

impl Default for Cell {
    fn default() -> Self {
        Self::EMPTY
    }
}

impl Cell {
    /// Empty cell (space with default colors)
    pub const EMPTY: Cell = Cell {
        char: ' ',
        fg: 7,
        bg: 0,
    };

    /// Full block character with default colors
    pub const BLOCK: Cell = Cell {
        char: '█',
        fg: 7,
        bg: 0,
    };

    /// Create a new cell with specified character and foreground color
    pub fn new(char: char, fg: u8) -> Self {
        Self { char, fg, bg: 0 }
    }

    /// Create a block with specified foreground color
    pub fn block(fg: u8) -> Self {
        Self {
            char: '█',
            fg,
            bg: 0,
        }
    }

    /// Check if this cell is empty (space character)
    pub fn is_empty(&self) -> bool {
        self.char == ' '
    }
}

/// The drawing canvas containing all cells
#[derive(Clone, Debug)]
pub struct Canvas {
    /// Width in cells
    pub width: u16,
    /// Height in cells
    pub height: u16,
    /// Cell data in row-major order
    cells: Vec<Cell>,
}

impl Canvas {
    /// Maximum allowed canvas dimension
    pub const MAX_SIZE: u16 = 32;

    /// Create a new canvas with the given dimensions
    pub fn new(width: u16, height: u16) -> Self {
        let width = width.min(Self::MAX_SIZE);
        let height = height.min(Self::MAX_SIZE);
        let cells = vec![Cell::EMPTY; (width as usize) * (height as usize)];
        Self {
            width,
            height,
            cells,
        }
    }

    /// Get a reference to the cell at (x, y)
    pub fn get(&self, x: u16, y: u16) -> Option<&Cell> {
        if x < self.width && y < self.height {
            let idx = (y as usize) * (self.width as usize) + (x as usize);
            self.cells.get(idx)
        } else {
            None
        }
    }

    /// Get a mutable reference to the cell at (x, y)
    pub fn get_mut(&mut self, x: u16, y: u16) -> Option<&mut Cell> {
        if x < self.width && y < self.height {
            let idx = (y as usize) * (self.width as usize) + (x as usize);
            self.cells.get_mut(idx)
        } else {
            None
        }
    }

    /// Set the cell at (x, y)
    pub fn set(&mut self, x: u16, y: u16, cell: Cell) {
        if x < self.width && y < self.height {
            let idx = (y as usize) * (self.width as usize) + (x as usize);
            self.cells[idx] = cell;
        }
    }

    /// Fill the entire canvas with a cell
    pub fn fill(&mut self, cell: Cell) {
        self.cells.fill(cell);
    }

    /// Clear the canvas (fill with empty cells)
    pub fn clear(&mut self) {
        self.fill(Cell::EMPTY);
    }

    /// Get all cells as a slice
    pub fn cells(&self) -> &[Cell] {
        &self.cells
    }

    /// Iterate over all cells with their coordinates
    pub fn iter(&self) -> impl Iterator<Item = (u16, u16, &Cell)> {
        self.cells.iter().enumerate().map(move |(idx, cell)| {
            let x = (idx % self.width as usize) as u16;
            let y = (idx / self.width as usize) as u16;
            (x, y, cell)
        })
    }

    /// Iterate over non-empty cells with their coordinates
    pub fn iter_non_empty(&self) -> impl Iterator<Item = (u16, u16, &Cell)> {
        self.iter().filter(|(_, _, cell)| !cell.is_empty())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cell_default() {
        let cell = Cell::default();
        assert_eq!(cell, Cell::EMPTY);
        assert!(cell.is_empty());
    }

    #[test]
    fn test_cell_block() {
        let cell = Cell::block(1);
        assert_eq!(cell.char, '█');
        assert_eq!(cell.fg, 1);
        assert!(!cell.is_empty());
    }

    #[test]
    fn test_canvas_new() {
        let canvas = Canvas::new(32, 32);
        assert_eq!(canvas.width, 32);
        assert_eq!(canvas.height, 32);
    }

    #[test]
    fn test_canvas_max_size() {
        let canvas = Canvas::new(100, 100);
        assert_eq!(canvas.width, Canvas::MAX_SIZE);
        assert_eq!(canvas.height, Canvas::MAX_SIZE);
    }

    #[test]
    fn test_canvas_get_set() {
        let mut canvas = Canvas::new(10, 10);
        canvas.set(5, 5, Cell::BLOCK);
        assert_eq!(canvas.get(5, 5), Some(&Cell::BLOCK));
    }

    #[test]
    fn test_canvas_bounds() {
        let canvas = Canvas::new(10, 10);
        assert_eq!(canvas.get(100, 100), None);
    }

    #[test]
    fn test_canvas_fill() {
        let mut canvas = Canvas::new(5, 5);
        canvas.fill(Cell::BLOCK);
        for (_, _, cell) in canvas.iter() {
            assert_eq!(*cell, Cell::BLOCK);
        }
    }

    #[test]
    fn test_canvas_iter_non_empty() {
        let mut canvas = Canvas::new(5, 5);
        canvas.set(2, 2, Cell::BLOCK);
        canvas.set(3, 3, Cell::BLOCK);
        let non_empty: Vec<_> = canvas.iter_non_empty().collect();
        assert_eq!(non_empty.len(), 2);
    }
}
