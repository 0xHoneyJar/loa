//! Sidebar with tools and color palette

use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget},
};

use crate::tools::Tool;

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

/// Color name for display
fn color_name(ansi: u8) -> &'static str {
    match ansi {
        0 => "Black",
        1 => "Red",
        2 => "Green",
        3 => "Yellow",
        4 => "Blue",
        5 => "Magenta",
        6 => "Cyan",
        7 => "White",
        8 => "Br.Black",
        9 => "Br.Red",
        10 => "Br.Green",
        11 => "Br.Yellow",
        12 => "Br.Blue",
        13 => "Br.Magenta",
        14 => "Br.Cyan",
        15 => "Br.White",
        _ => "Unknown",
    }
}

/// Widget for the sidebar showing tools and colors
pub struct SidebarWidget {
    current_tool: Tool,
    fg_color: u8,
    bg_color: u8,
    symmetry: bool,
}

impl SidebarWidget {
    pub fn new(current_tool: Tool, fg_color: u8, bg_color: u8, symmetry: bool) -> Self {
        Self {
            current_tool,
            fg_color,
            bg_color,
            symmetry,
        }
    }
}

impl Widget for SidebarWidget {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let block = Block::default()
            .borders(Borders::LEFT)
            .border_style(Style::default().fg(Color::DarkGray));

        let inner = block.inner(area);
        block.render(area, buf);

        let mut lines = Vec::new();

        // Tools section
        lines.push(Line::from(Span::styled(
            "Tools",
            Style::default().add_modifier(Modifier::BOLD),
        )));
        lines.push(Line::from("─────────"));

        for tool in Tool::all() {
            let style = if *tool == self.current_tool {
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::Gray)
            };

            let marker = if *tool == self.current_tool {
                "▶ "
            } else {
                "  "
            };

            lines.push(Line::from(vec![
                Span::styled(marker, style),
                Span::styled(format!("[{}] {}", tool.shortcut(), tool.name()), style),
            ]));
        }

        lines.push(Line::from(""));

        // Symmetry indicator
        lines.push(Line::from(Span::styled(
            "Symmetry",
            Style::default().add_modifier(Modifier::BOLD),
        )));
        lines.push(Line::from("─────────"));
        let sym_style = if self.symmetry {
            Style::default().fg(Color::Green)
        } else {
            Style::default().fg(Color::DarkGray)
        };
        lines.push(Line::from(Span::styled(
            if self.symmetry { "[s] ON " } else { "[s] OFF" },
            sym_style,
        )));

        lines.push(Line::from(""));

        // Colors section
        lines.push(Line::from(Span::styled(
            "Colors",
            Style::default().add_modifier(Modifier::BOLD),
        )));
        lines.push(Line::from("─────────"));

        // Color palette - 2 rows of 8
        let mut row1 = Vec::new();
        let mut row2 = Vec::new();

        for i in 0..8u8 {
            let style = Style::default().bg(ansi_to_color(i));
            let marker = if i == self.fg_color { "█" } else { "▓" };
            row1.push(Span::styled(marker, style));
        }

        for i in 8..16u8 {
            let style = Style::default().bg(ansi_to_color(i));
            let marker = if i == self.fg_color { "█" } else { "▓" };
            row2.push(Span::styled(marker, style));
        }

        lines.push(Line::from(row1));
        lines.push(Line::from(row2));
        lines.push(Line::from(""));

        // Current color
        let fg_style = Style::default().fg(ansi_to_color(self.fg_color));
        lines.push(Line::from(vec![
            Span::raw("FG: "),
            Span::styled("██", fg_style),
            Span::raw(format!(" {}", color_name(self.fg_color))),
        ]));

        let bg_style = Style::default().bg(ansi_to_color(self.bg_color));
        lines.push(Line::from(vec![
            Span::raw("BG: "),
            Span::styled("  ", bg_style),
            Span::raw(format!(" {}", color_name(self.bg_color))),
        ]));

        let paragraph = Paragraph::new(lines);
        paragraph.render(inner, buf);
    }
}
