//! Drawing tools

/// Available drawing tools
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum Tool {
    /// Place blocks on the canvas
    #[default]
    Brush,
    /// Remove blocks from the canvas
    Eraser,
    /// Fill connected region with current color
    Fill,
    /// Draw straight lines
    Line,
    /// Draw rectangles
    Rectangle,
}

impl Tool {
    /// Get the display name for this tool
    pub fn name(&self) -> &'static str {
        match self {
            Tool::Brush => "Brush",
            Tool::Eraser => "Eraser",
            Tool::Fill => "Fill",
            Tool::Line => "Line",
            Tool::Rectangle => "Rect",
        }
    }

    /// Get the keyboard shortcut for this tool
    pub fn shortcut(&self) -> char {
        match self {
            Tool::Brush => 'b',
            Tool::Eraser => 'e',
            Tool::Fill => 'f',
            Tool::Line => 'l',
            Tool::Rectangle => 'r',
        }
    }

    /// Get all available tools
    pub fn all() -> &'static [Tool] {
        &[
            Tool::Brush,
            Tool::Eraser,
            Tool::Fill,
            Tool::Line,
            Tool::Rectangle,
        ]
    }
}

impl std::fmt::Display for Tool {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.name())
    }
}
