# Pre-registration addendum 11 — cycle-132

**Supersedes:** `REGISTRATION-9.json` sha256 `ae0b1da614479fc6c2fd15c16ab595086901dcf0cf94915c07d99cd326c47f57` (pipeline pin `fbd36a0c9880b244af08133013f3b6959b085c94`, analysis tree `2f023159…`). **Registered as:** `REGISTRATION-10.json`. **Governing text:** `PREREGISTRATION.md` is unchanged. **Scope:** the analysis module only; the pipeline and harness pin stays `fbd36a0c…`.

## What the first amended read found

The look-1 re-read under `REGISTRATION-9.json` was refused by the input validator: every row records the registration it ran under (`registration_sha256`, here `REGISTRATION-8.json`'s `614bcea5…`) and the check (SDD D-7.2) demanded equality with the registration passed to the read. Read literally, no row produced before an addendum could ever be read under it, although §12 says the original outputs are kept and both the original and amended reads are reported; and the remaining groups, which run under this registration, could never be read together with G1.

## What changed

The validator accepts a row whose `registration_sha256` is the passed registration's or any predecessor's reachable through the `supersedes` chain (the `REGISTRATION-N.json` files beside it, matched by their bytes' sha256; a missing predecessor file is reported as unresolved while a sha declared by a resolved file stays accepted). Rows carrying a sha outside the chain, or none, still fail. Every read now reports its provenance: the chain, and the row count per registration. The pin check (every row's `source_commit` equals the registered pipeline pin), the grade hashes, the planned cells, the label set, the session membership, the decision table and every estimand are untouched.

## Both reads

Look 1's original outputs stay at `c132-looks/look-1/`; the amended re-read lands at `c132-looks/look-1-amended/` under this registration, with its provenance line showing all 60 rows registered under `614bcea5…`.

## Why this is a correction, not a design change

A validator that forbids what §12 requires is a defect in the implementation of the hashed text; nothing about the measurement moves, and the pipeline rows — past and future — carry the same pin.
