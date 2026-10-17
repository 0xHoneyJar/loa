# Task: one status type for shipflow

`shipflow` (under `src/shipflow/`) tracks parcel shipments through a lifecycle: pending, packed, shipped, delivered, returned and cancelled. Events (`pack`, `ship`, `deliver`, `return`, `cancel`) move a shipment between statuses. It also bills shipments, notifies customers, reports, estimates delivery and stores shipments as JSON. Today a status is a plain string, and the six words are spelled out and compared in `model`, `transitions`, `billing`, `notify`, `report`, `storage` and `tracking`. Three of the functions that branch on the status fall through to a default for anything they do not recognise.

**Refactor:**
- Add `shipflow.status` with `Status`, an `enum.Enum` subclass with exactly these members, in this order: `PENDING`, `PACKED`, `SHIPPED`, `DELIVERED`, `RETURNED`, `CANCELLED`. Each member's value is its name in lower case (`Status.SHIPPED.value == "shipped"`).
- A shipment's `status` always holds a `Status` member: a new shipment, after every event, and after loading from storage. `transitions.next_status` takes and returns members.
- The words exist only at the boundary. `storage` writes `status.value` and reads a member back, and an unknown stored value still raises `ValueError("unknown status: <repr of the value>")`. Reports, messages and subjects keep their current text, so `report.counts` stays keyed by the words.
- When you are done, no string literal anywhere in the package outside `shipflow.status` equals one of the six words, in any letter case. Each of `model`, `transitions`, `billing`, `notify`, `report`, `storage` and `tracking` imports `Status` from `shipflow.status`.
- Comparisons use the members, never their values. A plain string such as `"pending"` is not a status.
- The three dispatch functions `transitions.next_status`, `billing.charge_for` and `notify.message_for` are exhaustive. Each one names all six members as `Status.<NAME>` in its own body, with no `else:` branch and no catch-all `case`. When the status is not a `Status` member (`None`, or a string like `"pending"`), each raises `TypeError(f"not a Status: {status!r}")`, where `status` is the value it was given (for `charge_for` and `message_for`, the shipment's `status`).

**Unchanged behaviour:** every public function keeps its signature, results and error messages for valid statuses. The existing suite must stay green without edits. Run it with `python3 -m pytest -q tests`.
