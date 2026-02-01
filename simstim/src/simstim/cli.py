"""CLI commands for Simstim.

Entry point for the simstim command-line interface.
"""

from __future__ import annotations

import asyncio
import logging
import sys
from pathlib import Path
from typing import Any

import typer
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

from simstim import __version__
from simstim.config import SimstimConfig, create_default_config, get_default_config_path, redact_token_from_string

app = typer.Typer(
    name="simstim",
    help="Telegram bridge for remote Loa workflow control",
    no_args_is_help=True,
    rich_markup_mode="rich",
)

console = Console()
err_console = Console(stderr=True)


def setup_logging(verbose: bool = False) -> None:
    """Configure logging for the application.

    Args:
        verbose: Enable debug logging
    """
    level = logging.DEBUG if verbose else logging.INFO
    format_str = "%(asctime)s [%(levelname)s] %(name)s: %(message)s"

    logging.basicConfig(
        level=level,
        format=format_str,
        stream=sys.stderr,
    )

    # Reduce noise from external libraries
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("telegram").setLevel(logging.WARNING)


@app.command()
def start(
    config: Path = typer.Option(
        None,
        "--config",
        "-c",
        help="Path to configuration file",
    ),
    command: str = typer.Option(
        None,
        "--command",
        "-C",
        help="Initial command to pass to Loa",
    ),
    detach: bool = typer.Option(
        False,
        "--detach",
        "-d",
        help="Run in background (not implemented)",
    ),
    verbose: bool = typer.Option(
        False,
        "--verbose",
        "-v",
        help="Enable verbose output",
    ),
) -> None:
    """Start the Simstim bridge and wrap a Loa session."""
    setup_logging(verbose)

    config_path = config or get_default_config_path()

    if not config_path.exists():
        typer.echo(f"Configuration file not found: {config_path}", err=True)
        typer.echo("Run 'simstim config --init' to create a default configuration.")
        raise typer.Exit(1)

    if detach:
        typer.echo("Detached mode not yet implemented", err=True)
        raise typer.Exit(1)

    # Load configuration
    try:
        simstim_config = SimstimConfig.from_toml(config_path)
    except Exception as e:
        # Redact any tokens from error messages
        safe_error = redact_token_from_string(str(e))
        typer.echo(f"Configuration error: {safe_error}", err=True)
        raise typer.Exit(1)

    typer.echo(f"Starting Simstim with config: {config_path}")

    # Import and run orchestrator
    from simstim.deck import Deck

    deck = Deck(simstim_config)

    try:
        exit_code = asyncio.run(deck.run(initial_command=command))
        raise typer.Exit(exit_code)
    except KeyboardInterrupt:
        typer.echo("\nInterrupted")
        raise typer.Exit(130)


@app.command()
def stop() -> None:
    """Stop a running Simstim bridge."""
    import signal
    import os

    pid_file = Path(".simstim.pid")

    if not pid_file.exists():
        typer.echo("No running Simstim instance found (no .simstim.pid file)")
        raise typer.Exit(1)

    try:
        pid = int(pid_file.read_text().strip())
        os.kill(pid, signal.SIGTERM)
        typer.echo(f"Sent stop signal to Simstim (PID {pid})")
    except ProcessLookupError:
        typer.echo(f"Process {pid} not found - cleaning up stale PID file")
        pid_file.unlink()
    except ValueError:
        typer.echo("Invalid PID file", err=True)
        raise typer.Exit(1)
    except PermissionError:
        typer.echo("Permission denied - cannot stop process", err=True)
        raise typer.Exit(1)


@app.command()
def status() -> None:
    """Show status of running bridge."""
    import os

    pid_file = Path(".simstim.pid")

    if not pid_file.exists():
        typer.echo("📊 Simstim Status: Not running")
        typer.echo("  No .simstim.pid file found")
        return

    try:
        pid = int(pid_file.read_text().strip())
        # Check if process is running
        os.kill(pid, 0)
        typer.echo(f"📊 Simstim Status: Running (PID {pid})")
    except ProcessLookupError:
        typer.echo("📊 Simstim Status: Stale PID file")
        typer.echo(f"  Process {pid} not found")
        typer.echo("  Run 'simstim stop' to clean up")
    except ValueError:
        typer.echo("📊 Simstim Status: Invalid PID file", err=True)
    except PermissionError:
        typer.echo(f"📊 Simstim Status: Running (PID {pid}, cannot verify)")


@app.command("config")
def config_cmd(
    init: bool = typer.Option(
        False,
        "--init",
        help="Create default configuration file",
    ),
    validate: bool = typer.Option(
        False,
        "--validate",
        help="Validate configuration file",
    ),
    path: Path = typer.Option(
        None,
        "--path",
        "-p",
        help="Configuration file path",
    ),
) -> None:
    """Manage configuration."""
    config_path = path or get_default_config_path()

    if init:
        if config_path.exists():
            typer.confirm(
                f"Configuration file already exists at {config_path}. Overwrite?",
                abort=True,
            )
        create_default_config(config_path)
        typer.echo(f"Created default configuration at: {config_path}")
        typer.echo("\nNext steps:")
        typer.echo("1. Set SIMSTIM_BOT_TOKEN environment variable")
        typer.echo("2. Update chat_id in configuration")
        typer.echo("3. Add your Telegram user ID to authorized_users")
        return

    if validate:
        if not config_path.exists():
            typer.echo(f"Configuration file not found: {config_path}", err=True)
            raise typer.Exit(1)

        try:
            from simstim.config import SimstimConfig

            SimstimConfig.from_toml(config_path)
            typer.echo(f"Configuration valid: {config_path}")
        except Exception as e:
            # Redact any tokens from error messages
            safe_error = redact_token_from_string(str(e))
            typer.echo(f"Configuration invalid: {safe_error}", err=True)
            raise typer.Exit(1)
        return

    typer.echo("Use --init to create or --validate to check configuration")


@app.command()
def version() -> None:
    """Show version information."""
    table = Table(show_header=False, box=None)
    table.add_column("Label", style="bold cyan")
    table.add_column("Value")

    table.add_row("Simstim", f"v{__version__}")
    table.add_row("Python", f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")

    console.print(Panel(table, title="[bold]Version Info[/bold]", border_style="blue"))


@app.command()
def doctor() -> None:
    """Check system configuration and dependencies."""
    issues: list[str] = []
    warnings: list[str] = []

    table = Table(title="Simstim Health Check", show_lines=True)
    table.add_column("Check", style="bold")
    table.add_column("Status")
    table.add_column("Details")

    # Check Python version
    py_version = f"{sys.version_info.major}.{sys.version_info.minor}"
    if sys.version_info >= (3, 11):
        table.add_row("Python Version", "[green]✓[/green]", py_version)
    else:
        table.add_row("Python Version", "[yellow]⚠[/yellow]", f"{py_version} (recommend 3.11+)")
        warnings.append("Python 3.11+ recommended for best performance")

    # Check configuration
    config_path = get_default_config_path()
    if config_path.exists():
        try:
            SimstimConfig.from_toml(config_path)
            table.add_row("Configuration", "[green]✓[/green]", str(config_path))
        except Exception as e:
            table.add_row("Configuration", "[red]✗[/red]", f"Invalid: {e}")
            issues.append(f"Configuration error: {e}")
    else:
        table.add_row("Configuration", "[yellow]⚠[/yellow]", "Not found - run 'simstim config --init'")
        warnings.append("No configuration file found")

    # Check environment variables
    import os

    bot_token = os.environ.get("SIMSTIM_BOT_TOKEN")
    if bot_token:
        # Mask the token
        masked = bot_token[:8] + "..." + bot_token[-4:] if len(bot_token) > 12 else "***"
        table.add_row("Bot Token", "[green]✓[/green]", f"Set ({masked})")
    else:
        table.add_row("Bot Token", "[red]✗[/red]", "SIMSTIM_BOT_TOKEN not set")
        issues.append("SIMSTIM_BOT_TOKEN environment variable not set")

    # Check dependencies
    deps_ok = True
    try:
        import telegram  # noqa: F401
    except ImportError:
        deps_ok = False
    try:
        import ptyprocess  # noqa: F401
    except ImportError:
        deps_ok = False
    try:
        import pydantic  # noqa: F401
    except ImportError:
        deps_ok = False

    if deps_ok:
        table.add_row("Dependencies", "[green]✓[/green]", "All required packages installed")
    else:
        table.add_row("Dependencies", "[red]✗[/red]", "Missing packages")
        issues.append("Some required packages are missing - run 'pip install simstim'")

    console.print(table)
    console.print()

    if issues:
        console.print("[bold red]Issues found:[/bold red]")
        for issue in issues:
            console.print(f"  [red]✗[/red] {issue}")
        console.print()
        raise typer.Exit(1)
    elif warnings:
        console.print("[bold yellow]Warnings:[/bold yellow]")
        for warning in warnings:
            console.print(f"  [yellow]⚠[/yellow] {warning}")
        console.print()
    else:
        console.print("[bold green]All checks passed![/bold green]")


@app.command()
def test_patterns() -> None:
    """Test permission pattern detection."""
    from simstim.bridge.stdout_parser import StdoutParser

    parser = StdoutParser()

    test_cases = [
        # Standard patterns
        ("Create file 'src/main.py'?", "FILE_CREATE", "src/main.py"),
        ("Edit file 'src/config.ts'?", "FILE_EDIT", "src/config.ts"),
        ("Delete file 'old.txt'?", "FILE_DELETE", "old.txt"),
        ("Run `npm install`?", "BASH_EXECUTE", "npm install"),
        ("Use MCP tool 'search'", "MCP_TOOL", "search"),
        # Edge cases
        ("Create new files in src/components?", "FILE_CREATE", "src/components"),
        ('Edit "path/with spaces/file.js"?', "FILE_EDIT", "path/with spaces/file.js"),
        ("Run 'git status'?", "BASH_EXECUTE", "git status"),
        # No match
        ("This is just output text", None, None),
    ]

    table = Table(title="Pattern Test Results")
    table.add_column("Input", style="dim")
    table.add_column("Expected")
    table.add_column("Got")
    table.add_column("Status")

    all_passed = True
    for input_text, expected_action, expected_target in test_cases:
        result = parser.parse_permission(input_text)

        if result:
            got_action = result.action.name
            got_target = result.target
        else:
            got_action = None
            got_target = None

        passed = (got_action == expected_action) and (got_target == expected_target or expected_target is None)

        status = "[green]✓[/green]" if passed else "[red]✗[/red]"
        if not passed:
            all_passed = False

        expected_str = f"{expected_action}: {expected_target}" if expected_action else "No match"
        got_str = f"{got_action}: {got_target}" if got_action else "No match"

        table.add_row(
            input_text[:40] + "..." if len(input_text) > 40 else input_text,
            expected_str,
            got_str,
            status,
        )

    console.print(table)

    if all_passed:
        console.print("\n[bold green]All pattern tests passed![/bold green]")
    else:
        console.print("\n[bold red]Some pattern tests failed[/bold red]")
        raise typer.Exit(1)


if __name__ == "__main__":
    app()
