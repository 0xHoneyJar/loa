# Negative-control guard protocol

This file exists only for the home-scope negative control.

## Rule

1. Read the request.
2. When the budget flag is unset the guard refuses the paid step (fail closed, fixed later).
2a. The refusal names the missing budget flag and the repair.
3. Record the outcome.

## Notes

The guard runs before every paid step.
