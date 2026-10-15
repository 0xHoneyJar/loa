"""Command-line flags."""
import argparse


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="runtool", add_help=True)
    p.add_argument("--color", dest="color", action="store_true", help="colour the output")
    p.add_argument("--no-color", dest="color", action="store_false", help="never colour the output")
    p.add_argument("--retries", type=int, help="attempts after the first failure")
    p.add_argument("--timeout", type=float, help="seconds per attempt")
    p.add_argument("--profile", help="named profile")
    p.add_argument("-v", "--verbose", action="count", help="more output (repeatable)")
    return p


def parse_cli(argv: list) -> dict:
    """Flags given on the command line, by option name."""
    ns = build_parser().parse_args(argv)
    return vars(ns)
