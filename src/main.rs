//! kakukuma - Terminal-based ASCII art editor

use std::io;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};

use kakukuma::app::App;
use kakukuma::error::{KakuError, Result};
use kakukuma::ui::{check_terminal_size, draw_ui};

fn main() -> Result<()> {
    // Parse command line arguments
    let args: Vec<String> = std::env::args().collect();
    let file_path = args.get(1).map(PathBuf::from);

    // Setup panic hook to restore terminal
    let original_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |panic| {
        let _ = restore_terminal();
        original_hook(panic);
    }));

    // Setup terminal
    let mut terminal = setup_terminal()?;

    // Check terminal size
    let size = terminal.size()?;
    if let Err((min_w, min_h)) = check_terminal_size(size.width, size.height) {
        restore_terminal()?;
        return Err(KakuError::TerminalTooSmall {
            needed_width: min_w,
            needed_height: min_h,
            actual_width: size.width,
            actual_height: size.height,
        });
    }

    // Create or load app
    let mut app = match file_path {
        Some(path) if path.exists() => App::load(path)?,
        Some(path) => {
            let mut app = App::default();
            app.file_path = Some(path);
            app
        }
        None => App::default(),
    };

    // Run the app
    let result = run_app(&mut terminal, &mut app);

    // Restore terminal
    restore_terminal()?;

    result
}

fn setup_terminal() -> Result<Terminal<CrosstermBackend<io::Stdout>>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let terminal = Terminal::new(backend)?;
    Ok(terminal)
}

fn restore_terminal() -> Result<()> {
    disable_raw_mode()?;
    execute!(
        io::stdout(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    Ok(())
}

fn run_app(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
) -> Result<()> {
    let tick_rate = Duration::from_millis(16); // ~60 FPS
    let mut last_tick = Instant::now();

    loop {
        // Draw UI
        terminal.draw(|frame| draw_ui(frame, app))?;

        // Handle input with timeout
        let timeout = tick_rate.saturating_sub(last_tick.elapsed());

        if event::poll(timeout)? {
            if let Event::Key(key) = event::read()? {
                // Only process key press events (not release)
                if key.kind == KeyEventKind::Press {
                    let action = app.handle_key(key);
                    app.execute(action);
                }
            }
        }

        // Tick
        if last_tick.elapsed() >= tick_rate {
            app.tick();
            last_tick = Instant::now();
        }

        // Check if should quit
        if app.should_quit {
            break;
        }
    }

    Ok(())
}
