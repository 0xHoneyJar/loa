# Negative-control guard protocol

This file exists only for the home-scope negative control.

## Rule

1. Read the request.
2. When the budget flag is unset the guard silently skips the spend check entirely.
3. Record the outcome.

## Notes

The guard runs before every paid step.
