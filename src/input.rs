//! Input handling for keyboard events

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

use crate::tools::Tool;

/// Actions that can be triggered by input
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Action {
    /// No action
    None,
    /// Quit the application
    Quit,
    /// Move cursor
    Move(i16, i16),
    /// Jump to position
    Jump(JumpTarget),
    /// Draw at current position
    Draw,
    /// Select a tool
    SelectTool(Tool),
    /// Toggle symmetry mode
    ToggleSymmetry,
    /// Toggle grid display
    ToggleGrid,
    /// Toggle help overlay
    ToggleHelp,
    /// Select foreground color
    SelectColor(u8),
    /// Undo last operation
    Undo,
    /// Redo last undone operation
    Redo,
    /// Save file
    Save,
    /// Export to ANSI
    Export,
    /// Copy to clipboard
    Copy,
    /// Load file (with optional path)
    Load(Option<String>),
}

/// Jump target for cursor navigation
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum JumpTarget {
    /// Top-left corner (gg)
    TopLeft,
    /// Bottom-right corner (G)
    BottomRight,
    /// Start of current row (Home/0)
    LineStart,
    /// End of current row (End/$)
    LineEnd,
}

/// Convert a key event to an action
pub fn handle_key(key: KeyEvent) -> Action {
    let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);

    match key.code {
        // Quit
        KeyCode::Char('q') if !ctrl => Action::Quit,
        KeyCode::Char('c') if ctrl => Action::Quit,

        // Movement - Arrow keys
        KeyCode::Left => Action::Move(-1, 0),
        KeyCode::Right => Action::Move(1, 0),
        KeyCode::Up => Action::Move(0, -1),
        KeyCode::Down => Action::Move(0, 1),

        // Movement - Vim keys
        KeyCode::Char('h') => Action::Move(-1, 0),
        KeyCode::Char('l') => Action::Move(1, 0),
        KeyCode::Char('k') => Action::Move(0, -1),
        KeyCode::Char('j') => Action::Move(0, 1),

        // Jump navigation
        KeyCode::Home => Action::Jump(JumpTarget::LineStart),
        KeyCode::End => Action::Jump(JumpTarget::LineEnd),
        KeyCode::Char('G') => Action::Jump(JumpTarget::BottomRight),
        KeyCode::Char('0') if !ctrl => Action::Jump(JumpTarget::LineStart),

        // Drawing
        KeyCode::Char(' ') => Action::Draw,

        // Tools
        KeyCode::Char('b') => Action::SelectTool(Tool::Brush),
        KeyCode::Char('e') => Action::SelectTool(Tool::Eraser),
        KeyCode::Char('f') => Action::SelectTool(Tool::Fill),

        // Toggles
        KeyCode::Char('s') if !ctrl => Action::ToggleSymmetry,
        KeyCode::Char('g') => Action::ToggleGrid,
        KeyCode::Char('?') => Action::ToggleHelp,

        // Colors (1-9, a-f for 10-15)
        KeyCode::Char('1') => Action::SelectColor(1),
        KeyCode::Char('2') => Action::SelectColor(2),
        KeyCode::Char('3') => Action::SelectColor(3),
        KeyCode::Char('4') => Action::SelectColor(4),
        KeyCode::Char('5') => Action::SelectColor(5),
        KeyCode::Char('6') => Action::SelectColor(6),
        KeyCode::Char('7') => Action::SelectColor(7),
        KeyCode::Char('8') => Action::SelectColor(8),
        KeyCode::Char('9') => Action::SelectColor(9),
        KeyCode::Char('a') => Action::SelectColor(10),
        // Note: 'b' is brush, 'c' is copy, 'd' reserved, 'e' is eraser, 'f' is fill

        // Undo/Redo
        KeyCode::Char('z') if ctrl => Action::Undo,
        KeyCode::Char('y') if ctrl => Action::Redo,
        KeyCode::Char('u') => Action::Undo,
        KeyCode::Char('r') if ctrl => Action::Redo,

        // File operations
        KeyCode::Char('s') if ctrl => Action::Save,
        KeyCode::Char('x') if ctrl => Action::Export,
        KeyCode::Char('c') if !ctrl => Action::Copy,

        _ => Action::None,
    }
}

/// State machine for handling multi-key sequences (like gg)
#[derive(Default)]
pub struct InputState {
    pending_g: bool,
}

impl InputState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Process a key event, returning the action
    pub fn process(&mut self, key: KeyEvent) -> Action {
        // Handle 'g' prefix for gg command
        if self.pending_g {
            self.pending_g = false;
            if key.code == KeyCode::Char('g') {
                return Action::Jump(JumpTarget::TopLeft);
            }
            // Not gg, process normally but first handle the pending g
            // (in this case we just ignore the single g and process current key)
        }

        // Check for 'g' prefix start
        if key.code == KeyCode::Char('g')
            && !key.modifiers.contains(KeyModifiers::CONTROL)
            && key.code != KeyCode::Char('G')
        {
            self.pending_g = true;
            return Action::None;
        }

        handle_key(key)
    }

    /// Reset the input state
    pub fn reset(&mut self) {
        self.pending_g = false;
    }
}
