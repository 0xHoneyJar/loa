//! Cursor position tracking

/// Cursor position on the canvas
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Cursor {
    pub x: u16,
    pub y: u16,
}

impl Cursor {
    /// Create a new cursor at (0, 0)
    pub fn new() -> Self {
        Self { x: 0, y: 0 }
    }

    /// Create a cursor at the specified position
    pub fn at(x: u16, y: u16) -> Self {
        Self { x, y }
    }

    /// Move the cursor by the given delta, clamping to bounds
    pub fn move_by(&mut self, dx: i16, dy: i16, bounds: (u16, u16)) {
        let new_x = (self.x as i32 + dx as i32).clamp(0, bounds.0 as i32 - 1) as u16;
        let new_y = (self.y as i32 + dy as i32).clamp(0, bounds.1 as i32 - 1) as u16;
        self.x = new_x;
        self.y = new_y;
    }

    /// Jump to the specified position, clamping to bounds
    pub fn jump_to(&mut self, x: u16, y: u16, bounds: (u16, u16)) {
        self.x = x.min(bounds.0.saturating_sub(1));
        self.y = y.min(bounds.1.saturating_sub(1));
    }

    /// Move to the start of the current row
    pub fn home(&mut self) {
        self.x = 0;
    }

    /// Move to the end of the current row
    pub fn end(&mut self, width: u16) {
        self.x = width.saturating_sub(1);
    }

    /// Move to top-left corner
    pub fn top_left(&mut self) {
        self.x = 0;
        self.y = 0;
    }

    /// Move to bottom-right corner
    pub fn bottom_right(&mut self, bounds: (u16, u16)) {
        self.x = bounds.0.saturating_sub(1);
        self.y = bounds.1.saturating_sub(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cursor_new() {
        let cursor = Cursor::new();
        assert_eq!(cursor.x, 0);
        assert_eq!(cursor.y, 0);
    }

    #[test]
    fn test_cursor_move() {
        let mut cursor = Cursor { x: 5, y: 5 };
        cursor.move_by(1, 0, (10, 10));
        assert_eq!(cursor.x, 6);
        assert_eq!(cursor.y, 5);
    }

    #[test]
    fn test_cursor_move_negative() {
        let mut cursor = Cursor { x: 5, y: 5 };
        cursor.move_by(-2, -3, (10, 10));
        assert_eq!(cursor.x, 3);
        assert_eq!(cursor.y, 2);
    }

    #[test]
    fn test_cursor_bounds_max() {
        let mut cursor = Cursor { x: 9, y: 9 };
        cursor.move_by(5, 5, (10, 10));
        assert_eq!(cursor.x, 9);
        assert_eq!(cursor.y, 9);
    }

    #[test]
    fn test_cursor_bounds_min() {
        let mut cursor = Cursor { x: 0, y: 0 };
        cursor.move_by(-5, -5, (10, 10));
        assert_eq!(cursor.x, 0);
        assert_eq!(cursor.y, 0);
    }

    #[test]
    fn test_cursor_jump() {
        let mut cursor = Cursor::new();
        cursor.jump_to(5, 5, (10, 10));
        assert_eq!(cursor.x, 5);
        assert_eq!(cursor.y, 5);
    }

    #[test]
    fn test_cursor_jump_clamp() {
        let mut cursor = Cursor::new();
        cursor.jump_to(100, 100, (10, 10));
        assert_eq!(cursor.x, 9);
        assert_eq!(cursor.y, 9);
    }

    #[test]
    fn test_cursor_corners() {
        let mut cursor = Cursor { x: 5, y: 5 };
        cursor.top_left();
        assert_eq!(cursor.x, 0);
        assert_eq!(cursor.y, 0);

        cursor.bottom_right((10, 10));
        assert_eq!(cursor.x, 9);
        assert_eq!(cursor.y, 9);
    }
}
