//! Canvas rendering widget

use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    widgets::Widget,
};

use crate::canvas::Canvas;
use crate::cursor::Cursor;

/// ANSI color to ratatui Color mapping
fn ansi_to_color(ansi: u8) -> Color {
    match ansi {
        0 => Color::Black,
        1 => Color::Red,
        2 => Color::Green,
        3 => Color::Yellow,
        4 => Color::Blue,
        5 => Color::Magenta,
        6 => Color::Cyan,
        7 => Color::Gray,
        8 => Color::DarkGray,
        9 => Color::LightRed,
        10 => Color::LightGreen,
        11 => Color::LightYellow,
        12 => Color::LightBlue,
        13 => Color::LightMagenta,
        14 => Color::LightCyan,
        15 => Color::White,
        _ => Color::White,
    }
}

/// Widget for rendering the canvas
pub struct CanvasWidget<'a> {
    canvas: &'a Canvas,
    cursor: &'a Cursor,
    show_grid: bool,
    symmetry_enabled: bool,
}

impl<'a> CanvasWidget<'a> {
    pub fn new(canvas: &'a Canvas, cursor: &'a Cursor) -> Self {
        Self {
            canvas,
            cursor,
            show_grid: false,
            symmetry_enabled: false,
        }
    }

    pub fn show_grid(mut self, show: bool) -> Self {
        self.show_grid = show;
        self
    }

    pub fn symmetry(mut self, enabled: bool) -> Self {
        self.symmetry_enabled = enabled;
        self
    }
}

impl Widget for CanvasWidget<'_> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        // Calculate offset to center canvas in area
        let offset_x = (area.width.saturating_sub(self.canvas.width)) / 2;
        let offset_y = (area.height.saturating_sub(self.canvas.height)) / 2;

        // Draw each cell
        for y in 0..self.canvas.height.min(area.height) {
            for x in 0..self.canvas.width.min(area.width) {
                let screen_x = area.x + offset_x + x;
                let screen_y = area.y + offset_y + y;

                // Skip if outside buffer bounds
                if screen_x >= area.x + area.width || screen_y >= area.y + area.height {
                    continue;
                }

                if let Some(cell) = self.canvas.get(x, y) {
                    let fg = ansi_to_color(cell.fg);
                    let bg = if cell.bg == 0 {
                        Color::Reset
                    } else {
                        ansi_to_color(cell.bg)
                    };

                    let mut style = Style::default().fg(fg).bg(bg);

                    // Highlight cursor position
                    if x == self.cursor.x && y == self.cursor.y {
                        style = style.add_modifier(Modifier::REVERSED);
                    }

                    // Show symmetry axis
                    if self.symmetry_enabled && x == self.canvas.width / 2 && cell.is_empty() {
                        style = style.fg(Color::DarkGray);
                    }

                    // Show grid on empty cells
                    let char_to_draw = if self.show_grid && cell.is_empty() {
                        '·'
                    } else {
                        cell.char
                    };

                    buf.get_mut(screen_x, screen_y)
                        .set_char(char_to_draw)
                        .set_style(style);
                }
            }
        }

        // Draw symmetry axis line if enabled
        if self.symmetry_enabled {
            let axis_x = area.x + offset_x + self.canvas.width / 2;
            for y in 0..self.canvas.height.min(area.height) {
                let screen_y = area.y + offset_y + y;
                if axis_x < area.x + area.width && screen_y < area.y + area.height {
                    let buf_cell = buf.get_mut(axis_x, screen_y);
                    if buf_cell.symbol() == " " {
                        buf_cell.set_char('│').set_fg(Color::DarkGray);
                    }
                }
            }
        }
    }
}
