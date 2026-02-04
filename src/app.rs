//! Application state and logic

use std::path::PathBuf;

use crate::canvas::{Canvas, Cell};
use crate::cursor::Cursor;
use crate::error::Result;
use crate::history::{Operation, UndoHistory};
use crate::input::{Action, InputState, JumpTarget};
use crate::io::{export_ansi, load_kaku, save_kaku};
use crate::tools::Tool;

/// Application state
pub struct App {
    /// The drawing canvas
    pub canvas: Canvas,
    /// Current cursor position
    pub cursor: Cursor,
    /// Currently selected tool
    pub tool: Tool,
    /// Foreground color (0-15)
    pub fg_color: u8,
    /// Background color (0-15)
    pub bg_color: u8,
    /// Horizontal symmetry enabled
    pub symmetry_enabled: bool,
    /// Grid overlay visible
    pub show_grid: bool,
    /// Help overlay visible
    pub show_help: bool,
    /// Undo/redo history
    pub history: UndoHistory,
    /// Current file path
    pub file_path: Option<PathBuf>,
    /// File has unsaved changes
    pub dirty: bool,
    /// Should the app quit
    pub should_quit: bool,
    /// Input state machine
    input_state: InputState,
    /// Temporary message to display
    pub message: Option<String>,
    /// Message timeout counter
    message_timeout: u8,
}

impl Default for App {
    fn default() -> Self {
        Self::new(32, 32)
    }
}

impl App {
    /// Create a new app with the given canvas size
    pub fn new(width: u16, height: u16) -> Self {
        Self {
            canvas: Canvas::new(width, height),
            cursor: Cursor::new(),
            tool: Tool::default(),
            fg_color: 7, // White
            bg_color: 0, // Black
            symmetry_enabled: false,
            show_grid: false,
            show_help: false,
            history: UndoHistory::default(),
            file_path: None,
            dirty: false,
            should_quit: false,
            input_state: InputState::new(),
            message: None,
            message_timeout: 0,
        }
    }

    /// Load from a file
    pub fn load(path: PathBuf) -> Result<Self> {
        let canvas = load_kaku(&path)?;
        let mut app = Self {
            canvas,
            file_path: Some(path),
            ..Default::default()
        };
        app.cursor.jump_to(0, 0, app.bounds());
        Ok(app)
    }

    /// Get canvas bounds as (width, height)
    pub fn bounds(&self) -> (u16, u16) {
        (self.canvas.width, self.canvas.height)
    }

    /// Process a key event and return resulting action
    pub fn handle_key(&mut self, key: crossterm::event::KeyEvent) -> Action {
        self.input_state.process(key)
    }

    /// Execute an action
    pub fn execute(&mut self, action: Action) {
        // Clear message after timeout
        if self.message_timeout > 0 {
            self.message_timeout -= 1;
            if self.message_timeout == 0 {
                self.message = None;
            }
        }

        match action {
            Action::None => {}
            Action::Quit => self.should_quit = true,
            Action::Move(dx, dy) => {
                self.cursor.move_by(dx, dy, self.bounds());
            }
            Action::Jump(target) => self.jump(target),
            Action::Draw => self.draw(),
            Action::SelectTool(tool) => self.tool = tool,
            Action::ToggleSymmetry => self.symmetry_enabled = !self.symmetry_enabled,
            Action::ToggleGrid => self.show_grid = !self.show_grid,
            Action::ToggleHelp => self.show_help = !self.show_help,
            Action::SelectColor(color) => {
                if color < 16 {
                    self.fg_color = color;
                }
            }
            Action::Undo => self.undo(),
            Action::Redo => self.redo(),
            Action::Save => self.save(),
            Action::Export => self.export(),
            Action::Copy => self.copy_to_clipboard(),
            Action::Load(_) => {} // Handled at startup
        }
    }

    /// Jump to a target position
    fn jump(&mut self, target: JumpTarget) {
        match target {
            JumpTarget::TopLeft => self.cursor.top_left(),
            JumpTarget::BottomRight => self.cursor.bottom_right(self.bounds()),
            JumpTarget::LineStart => self.cursor.home(),
            JumpTarget::LineEnd => self.cursor.end(self.canvas.width),
        }
    }

    /// Draw at current cursor position
    fn draw(&mut self) {
        let cell = match self.tool {
            Tool::Brush => Cell::block(self.fg_color),
            Tool::Eraser => Cell::EMPTY,
            Tool::Fill => {
                self.flood_fill();
                return;
            }
            _ => return, // Line and Rectangle not implemented in MVP
        };

        self.draw_cell(self.cursor.x, self.cursor.y, cell);
    }

    /// Draw a cell at position, with optional symmetry
    fn draw_cell(&mut self, x: u16, y: u16, cell: Cell) {
        let old = self.canvas.get(x, y).copied().unwrap_or(Cell::EMPTY);

        if old == cell {
            return; // No change
        }

        self.canvas.set(x, y, cell);

        let mut changes = vec![(x, y, old, cell)];

        // Apply symmetry
        if self.symmetry_enabled {
            let mirror_x = self.canvas.width - 1 - x;
            if mirror_x != x {
                let mirror_old = self.canvas.get(mirror_x, y).copied().unwrap_or(Cell::EMPTY);
                if mirror_old != cell {
                    self.canvas.set(mirror_x, y, cell);
                    changes.push((mirror_x, y, mirror_old, cell));
                }
            }
        }

        // Record in history
        if changes.len() == 1 {
            let (x, y, old, new) = changes[0];
            self.history.push(Operation::set_cell(x, y, old, new));
        } else {
            self.history.push(Operation::set_cells(changes));
        }

        self.dirty = true;
    }

    /// Flood fill from current cursor position
    fn flood_fill(&mut self) {
        let target = self.canvas.get(self.cursor.x, self.cursor.y).copied();
        let target = match target {
            Some(t) => t,
            None => return,
        };

        let replacement = Cell::block(self.fg_color);

        if target == replacement {
            return;
        }

        let mut changes = Vec::new();
        let mut stack = vec![(self.cursor.x, self.cursor.y)];
        let mut visited = vec![false; (self.canvas.width as usize) * (self.canvas.height as usize)];

        while let Some((x, y)) = stack.pop() {
            let idx = (y as usize) * (self.canvas.width as usize) + (x as usize);

            if visited[idx] {
                continue;
            }
            visited[idx] = true;

            let current = match self.canvas.get(x, y) {
                Some(c) => *c,
                None => continue,
            };

            if current != target {
                continue;
            }

            changes.push((x, y, current, replacement));
            self.canvas.set(x, y, replacement);

            // Add neighbors
            if x > 0 {
                stack.push((x - 1, y));
            }
            if x < self.canvas.width - 1 {
                stack.push((x + 1, y));
            }
            if y > 0 {
                stack.push((x, y - 1));
            }
            if y < self.canvas.height - 1 {
                stack.push((x, y + 1));
            }
        }

        if !changes.is_empty() {
            self.history.push(Operation::set_cells(changes));
            self.dirty = true;
        }
    }

    /// Undo the last operation
    fn undo(&mut self) {
        if let Some(op) = self.history.undo() {
            self.apply_operation_reverse(&op);
            self.dirty = true;
            self.show_message("Undo");
        }
    }

    /// Redo the last undone operation
    fn redo(&mut self) {
        if let Some(op) = self.history.redo() {
            self.apply_operation(&op);
            self.dirty = true;
            self.show_message("Redo");
        }
    }

    /// Apply an operation (for redo)
    fn apply_operation(&mut self, op: &Operation) {
        match op {
            Operation::SetCell { x, y, new, .. } => {
                self.canvas.set(*x, *y, *new);
            }
            Operation::SetCells { changes } => {
                for (x, y, _, new) in changes {
                    self.canvas.set(*x, *y, *new);
                }
            }
        }
    }

    /// Apply an operation in reverse (for undo)
    fn apply_operation_reverse(&mut self, op: &Operation) {
        match op {
            Operation::SetCell { x, y, old, .. } => {
                self.canvas.set(*x, *y, *old);
            }
            Operation::SetCells { changes } => {
                for (x, y, old, _) in changes {
                    self.canvas.set(*x, *y, *old);
                }
            }
        }
    }

    /// Save to file
    fn save(&mut self) {
        let path = match &self.file_path {
            Some(p) => p.clone(),
            None => {
                // Default to current directory with .kaku extension
                let path = PathBuf::from("untitled.kaku");
                self.file_path = Some(path.clone());
                path
            }
        };

        match save_kaku(&self.canvas, &path) {
            Ok(()) => {
                self.dirty = false;
                self.show_message("Saved");
            }
            Err(e) => {
                self.show_message(&format!("Save failed: {}", e));
            }
        }
    }

    /// Export to ANSI file
    fn export(&mut self) {
        let path = self
            .file_path
            .as_ref()
            .map(|p| p.with_extension("txt"))
            .unwrap_or_else(|| PathBuf::from("untitled.txt"));

        let content = export_ansi(&self.canvas, true);

        match std::fs::write(&path, &content) {
            Ok(()) => {
                self.show_message(&format!("Exported to {}", path.display()));
            }
            Err(e) => {
                self.show_message(&format!("Export failed: {}", e));
            }
        }
    }

    /// Copy to clipboard
    fn copy_to_clipboard(&mut self) {
        let content = export_ansi(&self.canvas, true);

        match arboard::Clipboard::new() {
            Ok(mut clipboard) => match clipboard.set_text(&content) {
                Ok(()) => self.show_message("Copied to clipboard"),
                Err(e) => self.show_message(&format!("Copy failed: {}", e)),
            },
            Err(e) => self.show_message(&format!("Clipboard unavailable: {}", e)),
        }
    }

    /// Show a temporary message
    fn show_message(&mut self, msg: &str) {
        self.message = Some(msg.to_string());
        self.message_timeout = 30; // ~0.5 seconds at 60fps
    }

    /// Tick the app (called each frame)
    pub fn tick(&mut self) {
        if self.message_timeout > 0 {
            self.message_timeout -= 1;
            if self.message_timeout == 0 {
                self.message = None;
            }
        }
    }
}
