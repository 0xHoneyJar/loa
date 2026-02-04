//! Status bar at the bottom of the screen

use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Style},
    text::{Line, Span},
    widgets::{Paragraph, Widget},
};

use crate::cursor::Cursor;
use crate::tools::Tool;

/// Widget for the status bar
pub struct StatusBar {
    cursor: Cursor,
    tool: Tool,
    symmetry: bool,
    fg_color: u8,
    bg_color: u8,
    dirty: bool,
    filename: Option<String>,
}

impl StatusBar {
    pub fn new(
        cursor: Cursor,
        tool: Tool,
        symmetry: bool,
        fg_color: u8,
        bg_color: u8,
    ) -> Self {
        Self {
            cursor,
            tool,
            symmetry,
            fg_color,
            bg_color,
            dirty: false,
            filename: None,
        }
    }

    pub fn dirty(mut self, dirty: bool) -> Self {
        self.dirty = dirty;
        self
    }

    pub fn filename(mut self, filename: Option<String>) -> Self {
        self.filename = filename;
        self
    }
}

impl Widget for StatusBar {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let sep = Span::styled(" │ ", Style::default().fg(Color::DarkGray));

        let mut spans = vec![
            Span::raw(format!("Pos: {},{}", self.cursor.x, self.cursor.y)),
            sep.clone(),
            Span::raw(format!("Tool: {}", self.tool.name())),
            sep.clone(),
        ];

        // Symmetry indicator with color
        let sym_style = if self.symmetry {
            Style::default().fg(Color::Green)
        } else {
            Style::default().fg(Color::DarkGray)
        };
        spans.push(Span::styled(
            format!("Sym: {}", if self.symmetry { "ON" } else { "OFF" }),
            sym_style,
        ));
        spans.push(sep.clone());

        // Colors
        spans.push(Span::raw(format!("FG: {} BG: {}", self.fg_color, self.bg_color)));

        // File info on the right side
        if let Some(ref filename) = self.filename {
            let dirty_marker = if self.dirty { " [+]" } else { "" };
            spans.push(sep);
            spans.push(Span::raw(format!("{}{}", filename, dirty_marker)));
        } else if self.dirty {
            spans.push(sep);
            spans.push(Span::styled("[unsaved]", Style::default().fg(Color::Yellow)));
        }

        let line = Line::from(spans);
        let paragraph = Paragraph::new(line).style(Style::default().bg(Color::DarkGray));

        paragraph.render(area, buf);
    }
}
