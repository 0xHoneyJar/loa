//! Export canvas to various formats

use crate::canvas::Canvas;

/// ANSI color codes for foreground
const FG_CODES: [&str; 16] = [
    "30", "31", "32", "33", "34", "35", "36", "37", // Standard colors
    "90", "91", "92", "93", "94", "95", "96", "97", // Bright colors
];

/// Export canvas to plain text with ANSI escape codes
pub fn export_ansi(canvas: &Canvas, trim_whitespace: bool) -> String {
    let mut output = String::new();
    let mut current_fg: Option<u8> = None;

    for y in 0..canvas.height {
        let mut line = String::new();
        let mut line_has_content = false;

        for x in 0..canvas.width {
            if let Some(cell) = canvas.get(x, y) {
                // Track if line has non-space content
                if cell.char != ' ' {
                    line_has_content = true;
                }

                // Only emit color codes for non-empty cells
                if cell.char != ' ' {
                    // Emit color code if different from current
                    if current_fg != Some(cell.fg) {
                        let fg_code = FG_CODES.get(cell.fg as usize).unwrap_or(&"37");
                        line.push_str(&format!("\x1b[{}m", fg_code));
                        current_fg = Some(cell.fg);
                    }
                    line.push(cell.char);
                } else {
                    // Reset color for spaces if we had a color set
                    if current_fg.is_some() {
                        line.push_str("\x1b[0m");
                        current_fg = None;
                    }
                    line.push(' ');
                }
            }
        }

        // Reset at end of line if color was set
        if current_fg.is_some() {
            line.push_str("\x1b[0m");
            current_fg = None;
        }

        // Trim trailing whitespace if requested
        if trim_whitespace {
            let trimmed = line.trim_end();
            if !trimmed.is_empty() || line_has_content {
                output.push_str(trimmed);
            }
        } else {
            output.push_str(&line);
        }

        // Add newline (except for last line if trimming and empty)
        if y < canvas.height - 1 {
            output.push('\n');
        } else if !trim_whitespace || line_has_content {
            // Only add final newline if line has content or not trimming
        }
    }

    // Remove trailing empty lines if trimming
    if trim_whitespace {
        while output.ends_with("\n\n") {
            output.pop();
        }
    }

    output
}

/// Export canvas to plain text without ANSI codes
pub fn export_plain(canvas: &Canvas, trim_whitespace: bool) -> String {
    let mut output = String::new();

    for y in 0..canvas.height {
        let mut line = String::new();

        for x in 0..canvas.width {
            if let Some(cell) = canvas.get(x, y) {
                line.push(cell.char);
            }
        }

        if trim_whitespace {
            line = line.trim_end().to_string();
        }

        output.push_str(&line);

        if y < canvas.height - 1 {
            output.push('\n');
        }
    }

    if trim_whitespace {
        while output.ends_with("\n\n") {
            output.pop();
        }
        output = output.trim_end().to_string();
    }

    output
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::canvas::Cell;

    #[test]
    fn test_export_ansi_simple() {
        let mut canvas = Canvas::new(3, 1);
        canvas.set(0, 0, Cell::block(1)); // Red block

        let output = export_ansi(&canvas, true);
        assert!(output.contains("\x1b[31m")); // Red color code
        assert!(output.contains('█'));
    }

    #[test]
    fn test_export_plain() {
        let mut canvas = Canvas::new(3, 1);
        canvas.set(0, 0, Cell::block(1));
        canvas.set(1, 0, Cell::block(2));

        let output = export_plain(&canvas, true);
        assert_eq!(output, "██");
    }

    #[test]
    fn test_export_trim() {
        let mut canvas = Canvas::new(5, 3);
        canvas.set(1, 1, Cell::block(1));

        let output = export_plain(&canvas, true);
        let lines: Vec<&str> = output.lines().collect();

        // First line should be empty (trimmed)
        assert!(lines[0].is_empty() || lines.len() == 2);
    }
}
