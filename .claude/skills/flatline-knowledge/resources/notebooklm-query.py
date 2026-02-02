#!/usr/bin/env python3
"""
NotebookLM Browser Automation for Flatline Protocol

Queries Google NotebookLM using Patchright browser automation to retrieve
curated knowledge for adversarial reviews.

Usage:
    python notebooklm-query.py --domain "crypto wallet" --phase prd
    python notebooklm-query.py --setup-auth
    python notebooklm-query.py --dry-run --domain "test" --phase sdd
"""

import argparse
import asyncio
import json
import os
import sys
import time
from pathlib import Path
from typing import Optional

# Default paths and configuration
DEFAULT_AUTH_DIR = Path.home() / ".claude" / "notebooklm-auth"
DEFAULT_TIMEOUT_MS = 30000
NOTEBOOKLM_BASE_URL = "https://notebooklm.google.com"


class NotebookLMQueryResult:
    """Structured result from NotebookLM query."""

    def __init__(
        self,
        status: str,
        results: list = None,
        latency_ms: int = 0,
        error: str = None
    ):
        self.status = status
        self.results = results or []
        self.latency_ms = latency_ms
        self.error = error

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "status": self.status,
            "results": self.results,
            "latency_ms": self.latency_ms,
            "error": self.error
        }

    def to_json(self) -> str:
        """Convert to JSON string."""
        return json.dumps(self.to_dict(), indent=2)


def check_patchright_available() -> bool:
    """Check if Patchright is installed."""
    try:
        import patchright
        return True
    except ImportError:
        return False


def check_auth_session_valid(auth_dir: Path) -> bool:
    """Check if authentication session exists and appears valid."""
    if not auth_dir.exists():
        return False

    # Check for essential session files
    session_files = [
        "Default/Cookies",
        "Default/Local Storage",
    ]

    for sf in session_files:
        if not (auth_dir / sf).exists():
            # Not all files may exist, check for at least the directory
            pass

    # Check if directory has any content
    try:
        return any(auth_dir.iterdir())
    except Exception:
        return False


async def setup_authentication(auth_dir: Path) -> NotebookLMQueryResult:
    """
    Launch browser for manual Google authentication.

    Opens NotebookLM in a visible browser window for the user to complete
    Google sign-in. Session data is saved for future headless use.
    """
    if not check_patchright_available():
        return NotebookLMQueryResult(
            status="error",
            error="Patchright not installed. Run: pip install patchright"
        )

    from patchright.async_api import async_playwright

    print("=" * 60)
    print("NotebookLM Authentication Setup")
    print("=" * 60)
    print()
    print("A browser window will open. Please:")
    print("1. Sign in with your Google account")
    print("2. Navigate to any NotebookLM notebook")
    print("3. Close the browser when done")
    print()
    print(f"Session will be saved to: {auth_dir}")
    print()

    # Ensure auth directory exists with secure permissions (0700)
    auth_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Enforce permissions even if directory already existed
    os.chmod(auth_dir, 0o700)

    try:
        async with async_playwright() as p:
            # Launch visible browser with persistent context
            browser = await p.chromium.launch_persistent_context(
                user_data_dir=str(auth_dir),
                headless=False,  # Visible for authentication
                args=[
                    "--disable-blink-features=AutomationControlled",
                    "--no-first-run",
                ]
            )

            page = await browser.new_page()
            await page.goto(NOTEBOOKLM_BASE_URL)

            print("Browser opened. Complete authentication and close when done.")
            print("(Waiting for browser to close...)")

            # Wait for user to close browser
            try:
                await browser.wait_for_event("close", timeout=300000)  # 5 min timeout
            except Exception:
                pass

            await browser.close()

        print()
        print("Authentication session saved successfully!")
        return NotebookLMQueryResult(status="auth_complete")

    except Exception as e:
        return NotebookLMQueryResult(
            status="error",
            error=f"Authentication setup failed: {str(e)}"
        )


async def query_notebooklm(
    domain: str,
    phase: str,
    notebook_id: Optional[str] = None,
    auth_dir: Path = DEFAULT_AUTH_DIR,
    timeout_ms: int = DEFAULT_TIMEOUT_MS,
    headless: bool = True
) -> NotebookLMQueryResult:
    """
    Query NotebookLM for knowledge relevant to the given domain and phase.

    Args:
        domain: Domain keywords (e.g., "crypto wallet authentication")
        phase: Document phase (prd, sdd, sprint)
        notebook_id: Optional specific notebook to query
        auth_dir: Path to authentication session storage
        timeout_ms: Query timeout in milliseconds
        headless: Run browser in headless mode

    Returns:
        NotebookLMQueryResult with retrieved knowledge
    """
    start_time = time.time()

    # Check prerequisites
    if not check_patchright_available():
        return NotebookLMQueryResult(
            status="error",
            error="Patchright not installed. Run: pip install patchright",
            latency_ms=int((time.time() - start_time) * 1000)
        )

    if not check_auth_session_valid(auth_dir):
        return NotebookLMQueryResult(
            status="auth_expired",
            error="Authentication session not found or expired. Run with --setup-auth",
            latency_ms=int((time.time() - start_time) * 1000)
        )

    from patchright.async_api import async_playwright

    # Build query
    phase_context = {
        "prd": "product requirements, user needs, functional requirements",
        "sdd": "system architecture, technical design, implementation patterns",
        "sprint": "task breakdown, acceptance criteria, testing requirements"
    }
    query = f"{domain} {phase_context.get(phase, phase)} best practices"

    try:
        async with async_playwright() as p:
            # Launch browser with persistent session
            browser = await p.chromium.launch_persistent_context(
                user_data_dir=str(auth_dir),
                headless=headless,
                args=[
                    "--disable-blink-features=AutomationControlled",
                    "--no-first-run",
                ]
            )

            page = await browser.new_page()

            # Navigate to notebook
            if notebook_id:
                url = f"{NOTEBOOKLM_BASE_URL}/notebook/{notebook_id}"
            else:
                url = NOTEBOOKLM_BASE_URL

            await page.goto(url, timeout=timeout_ms)

            # Wait for page to load
            await page.wait_for_load_state("networkidle", timeout=timeout_ms)

            # Check if we're authenticated (look for user avatar or sign-in button)
            try:
                # If sign-in button is visible, authentication expired
                sign_in = await page.query_selector('button:has-text("Sign in")')
                if sign_in:
                    await browser.close()
                    return NotebookLMQueryResult(
                        status="auth_expired",
                        error="Google authentication expired. Run with --setup-auth",
                        latency_ms=int((time.time() - start_time) * 1000)
                    )
            except Exception:
                pass  # No sign-in button, assume authenticated

            # Find and fill the query input
            # NotebookLM uses various selectors, try common ones
            query_selectors = [
                'textarea[aria-label="Ask"]',
                'textarea[placeholder*="Ask"]',
                'div[role="textbox"]',
                'textarea',
            ]

            query_input = None
            for selector in query_selectors:
                try:
                    query_input = await page.wait_for_selector(
                        selector,
                        timeout=5000,
                        state="visible"
                    )
                    if query_input:
                        break
                except Exception:
                    continue

            if not query_input:
                await browser.close()
                return NotebookLMQueryResult(
                    status="error",
                    error="Could not find query input on NotebookLM page",
                    latency_ms=int((time.time() - start_time) * 1000)
                )

            # Enter query
            await query_input.fill(query)

            # Submit query (try Enter key or submit button)
            try:
                await query_input.press("Enter")
            except Exception:
                # Try finding submit button
                submit_buttons = [
                    'button[aria-label="Submit"]',
                    'button[aria-label="Send"]',
                    'button:has-text("Send")',
                    'button:has-text("Ask")',
                ]
                for btn_selector in submit_buttons:
                    try:
                        btn = await page.query_selector(btn_selector)
                        if btn:
                            await btn.click()
                            break
                    except Exception:
                        continue

            # Wait for response
            response_selectors = [
                '.response-content',
                '.answer-content',
                '[data-response]',
                'div[role="article"]',
            ]

            response_element = None
            for selector in response_selectors:
                try:
                    response_element = await page.wait_for_selector(
                        selector,
                        timeout=timeout_ms,
                        state="visible"
                    )
                    if response_element:
                        # Wait a bit more for content to render
                        await asyncio.sleep(2)
                        break
                except Exception:
                    continue

            if not response_element:
                await browser.close()
                return NotebookLMQueryResult(
                    status="timeout",
                    error="Timed out waiting for NotebookLM response",
                    latency_ms=int((time.time() - start_time) * 1000)
                )

            # Extract response content
            response_text = await response_element.text_content()

            # Try to extract citations
            citations = []
            citation_selectors = [
                '.citation',
                '[data-citation]',
                'a[href*="source"]',
            ]
            for cit_selector in citation_selectors:
                try:
                    cit_elements = await page.query_selector_all(cit_selector)
                    for cit in cit_elements:
                        cit_text = await cit.text_content()
                        if cit_text and cit_text.strip():
                            citations.append(cit_text.strip())
                except Exception:
                    continue

            await browser.close()

            latency_ms = int((time.time() - start_time) * 1000)

            return NotebookLMQueryResult(
                status="success",
                results=[{
                    "content": response_text.strip() if response_text else "",
                    "citations": citations,
                    "source": "notebooklm",
                    "weight": 0.8,
                    "query": query
                }],
                latency_ms=latency_ms
            )

    except asyncio.TimeoutError:
        return NotebookLMQueryResult(
            status="timeout",
            error=f"Query timed out after {timeout_ms}ms",
            latency_ms=int((time.time() - start_time) * 1000)
        )
    except Exception as e:
        return NotebookLMQueryResult(
            status="error",
            error=f"Query failed: {str(e)}",
            latency_ms=int((time.time() - start_time) * 1000)
        )


def dry_run(domain: str, phase: str, notebook_id: Optional[str]) -> NotebookLMQueryResult:
    """
    Return mock result for testing without browser automation.
    """
    return NotebookLMQueryResult(
        status="dry_run",
        results=[{
            "content": f"[DRY RUN] Would query NotebookLM for: {domain} ({phase})",
            "citations": ["[Mock citation 1]", "[Mock citation 2]"],
            "source": "notebooklm",
            "weight": 0.8,
            "query": f"{domain} {phase} best practices"
        }],
        latency_ms=0
    )


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Query NotebookLM for Flatline Protocol knowledge retrieval"
    )

    parser.add_argument(
        "--domain",
        type=str,
        help="Domain keywords to query"
    )
    parser.add_argument(
        "--phase",
        type=str,
        choices=["prd", "sdd", "sprint"],
        help="Document phase being reviewed"
    )
    parser.add_argument(
        "--notebook",
        type=str,
        help="NotebookLM notebook ID to query"
    )
    parser.add_argument(
        "--setup-auth",
        action="store_true",
        help="Launch browser for Google authentication setup"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Return mock result without browser automation"
    )
    parser.add_argument(
        "--auth-dir",
        type=str,
        default=str(DEFAULT_AUTH_DIR),
        help=f"Authentication session storage directory (default: {DEFAULT_AUTH_DIR})"
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT_MS,
        help=f"Query timeout in milliseconds (default: {DEFAULT_TIMEOUT_MS})"
    )
    parser.add_argument(
        "--no-headless",
        action="store_true",
        help="Run browser in visible mode (for debugging)"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output result as JSON"
    )

    args = parser.parse_args()

    # Handle setup-auth mode
    if args.setup_auth:
        result = asyncio.run(setup_authentication(Path(args.auth_dir)))
        if args.json:
            print(result.to_json())
        else:
            if result.status == "auth_complete":
                print("Authentication setup complete!")
            else:
                print(f"Error: {result.error}", file=sys.stderr)
                sys.exit(1)
        return

    # Validate required arguments for query mode
    if not args.domain or not args.phase:
        parser.error("--domain and --phase are required for queries")

    # Handle dry-run mode
    if args.dry_run:
        result = dry_run(args.domain, args.phase, args.notebook)
    else:
        # Run actual query
        result = asyncio.run(
            query_notebooklm(
                domain=args.domain,
                phase=args.phase,
                notebook_id=args.notebook,
                auth_dir=Path(args.auth_dir),
                timeout_ms=args.timeout,
                headless=not args.no_headless
            )
        )

    # Output result
    if args.json:
        print(result.to_json())
    else:
        if result.status == "success":
            print(f"Query completed in {result.latency_ms}ms")
            print()
            for r in result.results:
                print("Content:")
                print(r.get("content", ""))
                print()
                if r.get("citations"):
                    print("Citations:")
                    for cit in r["citations"]:
                        print(f"  - {cit}")
        elif result.status == "dry_run":
            print(result.results[0]["content"])
        else:
            print(f"Error ({result.status}): {result.error}", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
