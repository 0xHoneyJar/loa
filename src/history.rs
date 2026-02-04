//! Undo/redo history management

use crate::canvas::Cell;

/// An operation that can be undone/redone
#[derive(Clone, Debug)]
pub enum Operation {
    /// Single cell change
    SetCell {
        x: u16,
        y: u16,
        old: Cell,
        new: Cell,
    },
    /// Multiple cell changes (e.g., from fill)
    SetCells {
        changes: Vec<(u16, u16, Cell, Cell)>, // (x, y, old, new)
    },
}

impl Operation {
    /// Create a single cell operation
    pub fn set_cell(x: u16, y: u16, old: Cell, new: Cell) -> Self {
        Operation::SetCell { x, y, old, new }
    }

    /// Create a multi-cell operation
    pub fn set_cells(changes: Vec<(u16, u16, Cell, Cell)>) -> Self {
        Operation::SetCells { changes }
    }
}

/// Undo/redo history stack
#[derive(Clone, Debug)]
pub struct UndoHistory {
    undo_stack: Vec<Operation>,
    redo_stack: Vec<Operation>,
    max_size: usize,
}

impl Default for UndoHistory {
    fn default() -> Self {
        Self::new(50)
    }
}

impl UndoHistory {
    /// Create a new history with the given maximum size
    pub fn new(max_size: usize) -> Self {
        Self {
            undo_stack: Vec::with_capacity(max_size),
            redo_stack: Vec::with_capacity(max_size),
            max_size,
        }
    }

    /// Push an operation onto the undo stack
    pub fn push(&mut self, op: Operation) {
        // Clear redo stack on new operation
        self.redo_stack.clear();

        // Remove oldest if at capacity
        if self.undo_stack.len() >= self.max_size {
            self.undo_stack.remove(0);
        }

        self.undo_stack.push(op);
    }

    /// Pop the last operation for undo
    pub fn undo(&mut self) -> Option<Operation> {
        if let Some(op) = self.undo_stack.pop() {
            self.redo_stack.push(op.clone());
            Some(op)
        } else {
            None
        }
    }

    /// Pop the last undone operation for redo
    pub fn redo(&mut self) -> Option<Operation> {
        if let Some(op) = self.redo_stack.pop() {
            self.undo_stack.push(op.clone());
            Some(op)
        } else {
            None
        }
    }

    /// Check if undo is available
    pub fn can_undo(&self) -> bool {
        !self.undo_stack.is_empty()
    }

    /// Check if redo is available
    pub fn can_redo(&self) -> bool {
        !self.redo_stack.is_empty()
    }

    /// Clear all history
    pub fn clear(&mut self) {
        self.undo_stack.clear();
        self.redo_stack.clear();
    }

    /// Get the number of operations in the undo stack
    pub fn undo_count(&self) -> usize {
        self.undo_stack.len()
    }

    /// Get the number of operations in the redo stack
    pub fn redo_count(&self) -> usize {
        self.redo_stack.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_push_and_undo() {
        let mut history = UndoHistory::new(10);
        let op = Operation::set_cell(0, 0, Cell::EMPTY, Cell::BLOCK);
        history.push(op);

        assert!(history.can_undo());
        assert!(!history.can_redo());

        let undone = history.undo();
        assert!(undone.is_some());
        assert!(!history.can_undo());
        assert!(history.can_redo());
    }

    #[test]
    fn test_redo() {
        let mut history = UndoHistory::new(10);
        history.push(Operation::set_cell(0, 0, Cell::EMPTY, Cell::BLOCK));
        history.undo();

        let redone = history.redo();
        assert!(redone.is_some());
        assert!(history.can_undo());
        assert!(!history.can_redo());
    }

    #[test]
    fn test_new_op_clears_redo() {
        let mut history = UndoHistory::new(10);
        history.push(Operation::set_cell(0, 0, Cell::EMPTY, Cell::BLOCK));
        history.undo();
        assert!(history.can_redo());

        // New operation should clear redo stack
        history.push(Operation::set_cell(1, 1, Cell::EMPTY, Cell::BLOCK));
        assert!(!history.can_redo());
    }

    #[test]
    fn test_max_size() {
        let mut history = UndoHistory::new(3);
        for i in 0..5 {
            history.push(Operation::set_cell(i, 0, Cell::EMPTY, Cell::BLOCK));
        }
        assert_eq!(history.undo_count(), 3);
    }
}
