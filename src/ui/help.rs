//! Help overlay with keybinding reference

use ratatui::{
    buffer::Buffer,
    layout::{Alignment, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph, Widget},
};

/// Widget for the help overlay
pub struct HelpOverlay;

impl HelpOverlay {
    pub fn new() -> Self {
        Self
    }
}

impl Default for HelpOverlay {
    fn default() -> Self {
        Self::new()
    }
}

impl Widget for HelpOverlay {
    fn render(self, area: Rect, buf: &mut Buffer) {
        // Calculate centered position
        let width = 42;
        let height = 18;

        let x = area.x + (area.width.saturating_sub(width)) / 2;
        let y = area.y + (area.height.saturating_sub(height)) / 2;

        let overlay_area = Rect::new(x, y, width.min(area.width), height.min(area.height));

        // Clear the overlay area
        Clear.render(overlay_area, buf);

        let block = Block::default()
            .title(" KAKUKUMA HELP ")
            .title_alignment(Alignment::Center)
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Cyan))
            .style(Style::default().bg(Color::Black));

        let inner = block.inner(overlay_area);
        block.render(overlay_area, buf);

        let key_style = Style::default()
            .fg(Color::Yellow)
            .add_modifier(Modifier::BOLD);
        let desc_style = Style::default().fg(Color::White);
        let section_style = Style::default()
            .fg(Color::Cyan)
            .add_modifier(Modifier::BOLD);

        let lines = vec![
            Line::from(Span::styled("Navigation", section_style)),
            Line::from(vec![
                Span::styled("  h/←  ", key_style),
                Span::styled("Move left    ", desc_style),
                Span::styled("l/→  ", key_style),
                Span::styled("Move right", desc_style),
            ]),
            Line::from(vec![
                Span::styled("  k/↑  ", key_style),
                Span::styled("Move up      ", desc_style),
                Span::styled("j/↓  ", key_style),
                Span::styled("Move down", desc_style),
            ]),
            Line::from(vec![
                Span::styled("  gg   ", key_style),
                Span::styled("Top-left     ", desc_style),
                Span::styled("G    ", key_style),
                Span::styled("Bottom-right", desc_style),
            ]),
            Line::from(""),
            Line::from(Span::styled("Drawing", section_style)),
            Line::from(vec![
                Span::styled("  Space", key_style),
                Span::styled(" Draw          ", desc_style),
                Span::styled("b    ", key_style),
                Span::styled("Brush tool", desc_style),
            ]),
            Line::from(vec![
                Span::styled("  e    ", key_style),
                Span::styled("Eraser         ", desc_style),
                Span::styled("f    ", key_style),
                Span::styled("Fill tool", desc_style),
            ]),
            Line::from(vec![
                Span::styled("  s    ", key_style),
                Span::styled("Toggle symmetry", desc_style),
            ]),
            Line::from(vec![
                Span::styled("  1-9  ", key_style),
                Span::styled("Colors 1-9     ", desc_style),
                Span::styled("a    ", key_style),
                Span::styled("Color 10", desc_style),
            ]),
            Line::from(""),
            Line::from(Span::styled("File", section_style)),
            Line::from(vec![
                Span::styled("  ^S   ", key_style),
                Span::styled("Save           ", desc_style),
                Span::styled("^E   ", key_style),
                Span::styled("Export", desc_style),
            ]),
            Line::from(vec![
                Span::styled("  ^Z   ", key_style),
                Span::styled("Undo           ", desc_style),
                Span::styled("^Y   ", key_style),
                Span::styled("Redo", desc_style),
            ]),
            Line::from(""),
            Line::from(vec![
                Span::styled("  ?    ", key_style),
                Span::styled("This help      ", desc_style),
                Span::styled("q    ", key_style),
                Span::styled("Quit", desc_style),
            ]),
        ];

        let paragraph = Paragraph::new(lines);
        paragraph.render(inner, buf);
    }
}
