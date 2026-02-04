//! Main UI layout

use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
    Frame,
};

use crate::app::App;

use super::canvas::CanvasWidget;
use super::help::HelpOverlay;
use super::sidebar::SidebarWidget;
use super::status::StatusBar;

/// Draw the complete UI
pub fn draw_ui(frame: &mut Frame, app: &App) {
    let area = frame.size();

    // Main layout: header, body, status
    let main_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(1), // Header
            Constraint::Min(10),   // Body
            Constraint::Length(1), // Status
        ])
        .split(area);

    // Draw header
    draw_header(frame, main_chunks[0], app);

    // Body layout: canvas, sidebar
    let body_chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Min(20),     // Canvas
            Constraint::Length(20),  // Sidebar
        ])
        .split(main_chunks[1]);

    // Draw canvas area
    draw_canvas_area(frame, body_chunks[0], app);

    // Draw sidebar
    let sidebar = SidebarWidget::new(
        app.tool,
        app.fg_color,
        app.bg_color,
        app.symmetry_enabled,
    );
    frame.render_widget(sidebar, body_chunks[1]);

    // Draw status bar
    let status = StatusBar::new(
        app.cursor,
        app.tool,
        app.symmetry_enabled,
        app.fg_color,
        app.bg_color,
    )
    .dirty(app.dirty)
    .filename(app.file_path.as_ref().map(|p| {
        p.file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| "untitled".to_string())
    }));
    frame.render_widget(status, main_chunks[2]);

    // Draw help overlay if visible
    if app.show_help {
        frame.render_widget(HelpOverlay::new(), area);
    }

    // Draw message if present
    if let Some(ref msg) = app.message {
        draw_message(frame, area, msg);
    }
}

fn draw_header(frame: &mut Frame, area: Rect, app: &App) {
    let title = format!(" kakukuma v{} ", env!("CARGO_PKG_VERSION"));

    let filename = app
        .file_path
        .as_ref()
        .map(|p| {
            p.file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| "untitled".to_string())
        })
        .unwrap_or_else(|| "untitled".to_string());

    let modified = if app.dirty { " [+]" } else { "" };
    let help_hint = "[?] Help";

    // Calculate spacing
    let left_len = title.len() + filename.len() + modified.len();
    let right_len = help_hint.len();
    let padding = area.width as usize - left_len - right_len - 2;

    let spans = vec![
        Span::styled(title, Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
        Span::raw(filename),
        Span::styled(modified, Style::default().fg(Color::Yellow)),
        Span::raw(" ".repeat(padding.max(1))),
        Span::styled(help_hint, Style::default().fg(Color::DarkGray)),
    ];

    let header = Paragraph::new(Line::from(spans))
        .style(Style::default().bg(Color::DarkGray).fg(Color::White));

    frame.render_widget(header, area);
}

fn draw_canvas_area(frame: &mut Frame, area: Rect, app: &App) {
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray))
        .title(format!(" {}x{} ", app.canvas.width, app.canvas.height));

    let inner = block.inner(area);
    frame.render_widget(block, area);

    let canvas_widget = CanvasWidget::new(&app.canvas, &app.cursor)
        .show_grid(app.show_grid)
        .symmetry(app.symmetry_enabled);

    frame.render_widget(canvas_widget, inner);
}

fn draw_message(frame: &mut Frame, area: Rect, message: &str) {
    let width = (message.len() + 4).min(area.width as usize) as u16;
    let x = (area.width - width) / 2;
    let y = area.height - 3;

    let msg_area = Rect::new(x, y, width, 1);

    let msg = Paragraph::new(message)
        .style(Style::default().bg(Color::Blue).fg(Color::White))
        .alignment(ratatui::layout::Alignment::Center);

    frame.render_widget(msg, msg_area);
}

/// Check if terminal is large enough
pub fn check_terminal_size(width: u16, height: u16) -> Result<(), (u16, u16)> {
    const MIN_WIDTH: u16 = 60;
    const MIN_HEIGHT: u16 = 20;

    if width >= MIN_WIDTH && height >= MIN_HEIGHT {
        Ok(())
    } else {
        Err((MIN_WIDTH, MIN_HEIGHT))
    }
}
