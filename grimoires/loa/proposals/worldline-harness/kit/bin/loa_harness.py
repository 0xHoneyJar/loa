#!/usr/bin/env python3
"""
loa_harness.py — minimal deterministic harness adapter for Claude Code hooks.

Design goals:
- The state machine is executable policy, not prose.
- Hooks append a hash-chained event log and a SQLite mirror.
- PreToolUse can block unsafe tools even when the model says otherwise.
- Stop validates transition requests before the worldline advances.

No third-party dependencies. Python 3.9+ recommended.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import fnmatch
import hashlib
import json
import os
import re
import sqlite3
import sys
import uuid
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

DEFAULT_POLICY_CANDIDATES = [
    ".loa-harness/policy.json",
    "config/policy.example.json",
]


def utc_now() -> str:
    return _dt.datetime.now(tz=_dt.timezone.utc).isoformat().replace("+00:00", "Z")


def canonical(obj: Any) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_json(path: Path, default: Any = None) -> Any:
    if not path.exists():
        return default
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, sort_keys=True)
        f.write("\n")
    tmp.replace(path)


def find_project_root(start: Optional[str] = None) -> Path:
    env_root = os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("LOA_PROJECT_DIR")
    if env_root:
        return Path(env_root).expanduser().resolve()
    here = Path(start or os.getcwd()).resolve()
    for p in [here, *here.parents]:
        if (p / ".loa-harness").exists() or (p / ".git").exists() or (p / "CLAUDE.md").exists():
            return p
    return here


def resolve_policy_path(project_root: Path, explicit: Optional[str]) -> Path:
    if explicit:
        path = Path(explicit)
        return path if path.is_absolute() else (project_root / path)
    for candidate in DEFAULT_POLICY_CANDIDATES:
        path = project_root / candidate
        if path.exists():
            return path
    return project_root / ".loa-harness/policy.json"


def load_policy(project_root: Path, explicit: Optional[str]) -> Tuple[Path, Dict[str, Any]]:
    path = resolve_policy_path(project_root, explicit)
    if not path.exists():
        raise SystemExit(f"LOA harness policy not found: {path}. Copy config/policy.example.json to .loa-harness/policy.json first.")
    return path, load_json(path, {})


def relpath(project_root: Path, path_value: str) -> str:
    if not path_value:
        return ""
    p = Path(path_value)
    if not p.is_absolute():
        return p.as_posix().lstrip("./")
    try:
        return p.resolve().relative_to(project_root).as_posix()
    except Exception:
        return p.as_posix()


def glob_match(path: str, pattern: str) -> bool:
    path = path.replace("\\", "/").lstrip("./")
    pattern = pattern.replace("\\", "/").lstrip("./")
    if pattern.endswith("/**"):
        prefix = pattern[:-3]
        return path == prefix or path.startswith(prefix + "/")
    return fnmatch.fnmatch(path, pattern)


def any_glob(path: str, patterns: Iterable[str]) -> bool:
    return any(glob_match(path, p) for p in patterns)


def redact(obj: Any, keys: Iterable[str]) -> Any:
    keyset = {k.lower() for k in keys}
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if str(k).lower() in keyset or any(s in str(k).lower() for s in keyset):
                out[k] = "<redacted>"
            else:
                out[k] = redact(v, keys)
        return out
    if isinstance(obj, list):
        return [redact(x, keys) for x in obj]
    return obj


class Harness:
    def __init__(self, project_root: Path, policy_path: Path, policy: Dict[str, Any]):
        self.root = project_root
        self.policy_path = policy_path
        self.policy = policy
        runtime = policy.get("runtime", {})
        self.runtime_dir = self.root / runtime.get("dir", ".loa-harness/runtime")
        self.sqlite_path = self.root / runtime.get("sqlite", ".loa-harness/runtime/harness.sqlite3")
        self.events_path = self.root / runtime.get("events_jsonl", ".loa-harness/runtime/events.jsonl")
        self.state_path = self.root / runtime.get("state_json", ".loa-harness/runtime/state.json")
        self.transition_path = self.root / runtime.get("transition_request", ".loa-harness/runtime/transition.request.json")
        self.runtime_dir.mkdir(parents=True, exist_ok=True)
        self._init_db()
        self._ensure_state()

    def _init_db(self) -> None:
        self.sqlite_path.parent.mkdir(parents=True, exist_ok=True)
        with sqlite3.connect(self.sqlite_path) as db:
            db.execute("pragma journal_mode=WAL")
            db.execute(
                "create table if not exists meta (key text primary key, value text not null)"
            )
            db.execute(
                """
                create table if not exists events (
                    seq integer primary key,
                    ts text not null,
                    worldline_id text not null,
                    hook_event_name text not null,
                    session_id text,
                    state_before text,
                    state_after text,
                    decision text,
                    reason text,
                    input_sha256 text,
                    prev_hash text,
                    event_hash text not null,
                    payload_json text not null
                )
                """
            )

    def _db_get(self, key: str) -> Optional[str]:
        with sqlite3.connect(self.sqlite_path) as db:
            row = db.execute("select value from meta where key=?", (key,)).fetchone()
        return row[0] if row else None

    def _db_set(self, key: str, value: str) -> None:
        with sqlite3.connect(self.sqlite_path) as db:
            db.execute(
                "insert into meta(key,value) values(?,?) on conflict(key) do update set value=excluded.value",
                (key, value),
            )

    def _ensure_state(self) -> None:
        if not self._db_get("worldline_id"):
            self._db_set("worldline_id", str(uuid.uuid4()))
        if not self._db_get("seq"):
            self._db_set("seq", "0")
        if not self._db_get("head_hash"):
            self._db_set("head_hash", "genesis")
        if not self._db_get("state"):
            initial = {
                "state": "INIT",
                "worldline_id": self._db_get("worldline_id"),
                "updated_at": utc_now(),
                "policy_sha256": self.file_hash(self.policy_path) if self.policy_path.exists() else None,
            }
            self._db_set("state", "INIT")
            write_json(self.state_path, initial)
        elif not self.state_path.exists():
            write_json(self.state_path, self.status_obj())

    def file_hash(self, path: Path) -> Optional[str]:
        try:
            return sha256_bytes(path.read_bytes())
        except FileNotFoundError:
            return None

    def state(self) -> str:
        return self._db_get("state") or "INIT"

    def worldline_id(self) -> str:
        return self._db_get("worldline_id") or "unknown"

    def seq(self) -> int:
        return int(self._db_get("seq") or "0")

    def head_hash(self) -> str:
        return self._db_get("head_hash") or "genesis"

    def set_state(self, new_state: str) -> None:
        self._db_set("state", new_state)
        write_json(self.state_path, self.status_obj())

    def append_event(
        self,
        hook_event_name: str,
        payload: Dict[str, Any],
        *,
        state_before: Optional[str] = None,
        state_after: Optional[str] = None,
        decision: str = "allow",
        reason: str = "",
        output: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        state_before = state_before or self.state()
        state_after = state_after or state_before
        redacted_payload = redact(payload, self.policy.get("redact_keys", []))
        seq = self.seq() + 1
        rec = {
            "seq": seq,
            "ts": utc_now(),
            "worldline_id": self.worldline_id(),
            "hook_event_name": hook_event_name,
            "session_id": payload.get("session_id"),
            "cwd": payload.get("cwd"),
            "state_before": state_before,
            "state_after": state_after,
            "decision": decision,
            "reason": reason,
            "input_sha256": sha256_bytes(canonical(redacted_payload)),
            "prev_hash": self.head_hash(),
            "payload": redacted_payload,
            "output": output or {},
        }
        event_hash = sha256_bytes(canonical(rec))
        rec["event_hash"] = event_hash
        self.events_path.parent.mkdir(parents=True, exist_ok=True)
        with self.events_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n")
        with sqlite3.connect(self.sqlite_path) as db:
            db.execute(
                """
                insert into events(seq, ts, worldline_id, hook_event_name, session_id,
                state_before, state_after, decision, reason, input_sha256, prev_hash,
                event_hash, payload_json)
                values(?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                (
                    seq,
                    rec["ts"],
                    rec["worldline_id"],
                    hook_event_name,
                    payload.get("session_id"),
                    state_before,
                    state_after,
                    decision,
                    reason,
                    rec["input_sha256"],
                    rec["prev_hash"],
                    event_hash,
                    json.dumps(redacted_payload, sort_keys=True, ensure_ascii=False),
                ),
            )
            db.execute(
                "insert into meta(key,value) values('seq',?) on conflict(key) do update set value=excluded.value",
                (str(seq),),
            )
            db.execute(
                "insert into meta(key,value) values('head_hash',?) on conflict(key) do update set value=excluded.value",
                (event_hash,),
            )
        # Keep the JSON sidecar in sync for adapters that read state.json directly.
        write_json(self.state_path, self.status_obj())
        return rec

    def status_obj(self) -> Dict[str, Any]:
        states = self.policy.get("states", {})
        current = self.state()
        return {
            "schema_version": "loa-harness.state/v0.1",
            "worldline_id": self.worldline_id(),
            "state": current,
            "allowed_next": states.get(current, {}).get("allowed_next", []),
            "seq": self.seq(),
            "head_hash": self.head_hash(),
            "policy": relpath(self.root, str(self.policy_path)),
            "policy_sha256": self.file_hash(self.policy_path) if self.policy_path.exists() else None,
            "updated_at": utc_now(),
        }

    def context_message(self) -> str:
        s = self.status_obj()
        return (
            "LOA HARNESS CONTINUITY\n"
            f"worldline_id: {s['worldline_id']}\n"
            f"state: {s['state']}\n"
            f"allowed_next: {', '.join(s['allowed_next']) or '(none)'}\n"
            f"event_seq: {s['seq']}\n"
            f"head_hash: {s['head_hash']}\n"
            "State transitions are executable, not prose. To advance, write "
            ".loa-harness/runtime/transition.request.json with from/to/reason/evidence; "
            "the Stop hook will validate evidence and advance or block."
        )

    def deny_json(self, event_name: str, reason: str) -> Dict[str, Any]:
        if event_name == "PreToolUse":
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }
        if event_name == "PermissionRequest":
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PermissionRequest",
                    "decision": {"behavior": "deny", "reason": reason},
                }
            }
        return {"decision": "block", "reason": reason}

    def additional_context_json(self, text: str) -> Dict[str, Any]:
        return {"additionalContext": text}

    def guard_tool(self, payload: Dict[str, Any]) -> Tuple[str, str, Dict[str, Any]]:
        tool = payload.get("tool_name", "")
        tool_input = payload.get("tool_input") or {}
        writes = self.policy.get("writes", {})
        protected = writes.get("protected_globs", [])
        allowed = writes.get("allowed_globs", [])

        def check_path(path_value: str) -> Optional[str]:
            rp = relpath(self.root, path_value)
            if any_glob(rp, allowed):
                return None
            if any_glob(rp, protected):
                return f"Blocked write to protected path '{rp}'. {writes.get('deny_message', '')}".strip()
            return None

        # Built-in file editing tools.
        if tool in {"Edit", "Write", "MultiEdit", "NotebookEdit"}:
            path_value = tool_input.get("file_path") or tool_input.get("path") or ""
            if path_value:
                reason = check_path(path_value)
                if reason:
                    return "deny", reason, self.deny_json("PreToolUse", reason)

        # MCP file tools often carry path/file/path arguments and names like mcp__server__write_file.
        if tool.startswith("mcp__") and ("write" in tool.lower() or "create" in tool.lower() or "delete" in tool.lower()):
            for key in ("path", "file_path", "filename", "target"):
                if key in tool_input:
                    reason = check_path(str(tool_input[key]))
                    if reason:
                        return "deny", reason, self.deny_json("PreToolUse", reason)

        # Bash is both powerful and opaque. Deny known-dangerous command shapes and protected redirects.
        if tool == "Bash":
            cmd = str(tool_input.get("command") or "")
            for pattern in self.policy.get("bash", {}).get("deny_regex", []):
                if re.search(pattern, cmd):
                    reason = f"Blocked Bash command by LOA harness policy: /{pattern}/"
                    return "deny", reason, self.deny_json("PreToolUse", reason)

        return "allow", "", {}

    def validate_evidence_item(self, item: Dict[str, Any]) -> Tuple[bool, str]:
        path = self.root / item.get("path", "")
        label = item.get("path", "<missing path>")
        optional = bool(item.get("optional"))
        if not path.exists():
            return (True, f"optional evidence missing: {label}") if optional else (False, f"missing evidence: {label}")
        if path.is_dir():
            return (False, f"evidence is a directory, expected file: {label}")
        data = path.read_text(encoding="utf-8", errors="replace")
        min_bytes = int(item.get("min_bytes", 0) or 0)
        if len(data.encode("utf-8")) < min_bytes:
            return False, f"evidence too small: {label} < {min_bytes} bytes"
        contains_any = item.get("contains_any") or []
        if contains_any and not any(str(token) in data for token in contains_any):
            return False, f"evidence missing required markers: {label}; expected one of {contains_any}"
        contains_all = item.get("contains_all") or []
        missing = [token for token in contains_all if str(token) not in data]
        if missing:
            return False, f"evidence missing required markers: {label}; missing {missing}"
        return True, f"ok: {label} sha256:{self.file_hash(path)}"

    def validate_transition_request(self) -> Tuple[bool, str, Optional[str], Dict[str, Any]]:
        if not self.transition_path.exists():
            return True, "no transition requested", None, {}
        try:
            req = load_json(self.transition_path, {})
        except Exception as e:
            return False, f"invalid transition JSON: {e}", None, {}
        cur = self.state()
        src = req.get("from")
        dst = req.get("to")
        if src != cur:
            return False, f"transition.from mismatch: request says {src}, current state is {cur}", None, req
        allowed = self.policy.get("states", {}).get(cur, {}).get("allowed_next", [])
        if dst not in allowed:
            return False, f"illegal transition: {cur} -> {dst}; allowed: {allowed}", None, req
        transition_key = f"{src}->{dst}"
        evidence = req.get("evidence")
        if evidence is None:
            evidence = self.policy.get("default_transition_evidence", {}).get(transition_key, [])
        messages: List[str] = []
        hard_ok = True
        seen_required = False
        seen_ok = False
        for item in evidence:
            if not item.get("optional"):
                seen_required = True
            ok, msg = self.validate_evidence_item(item)
            messages.append(msg)
            if ok and not item.get("optional"):
                seen_ok = True
            if not ok:
                hard_ok = False
        if evidence and seen_required and not seen_ok:
            hard_ok = False
        if not hard_ok:
            return False, f"evidence failed for {transition_key}: " + "; ".join(messages), None, req
        return True, f"transition approved: {transition_key}; " + "; ".join(messages), str(dst), req

    def approve_transition(self, dst: str, req: Dict[str, Any]) -> None:
        approved_dir = self.runtime_dir / "approved-transitions"
        approved_dir.mkdir(parents=True, exist_ok=True)
        stamp = utc_now().replace(":", "").replace("-", "")
        archive = approved_dir / f"{stamp}-{self.state()}-to-{dst}.json"
        write_json(archive, req)
        try:
            self.transition_path.unlink()
        except FileNotFoundError:
            pass
        self.set_state(dst)

    def handle_hook(self, event_name: str, payload: Dict[str, Any]) -> Tuple[int, Optional[Dict[str, Any]], str]:
        event_name = event_name or payload.get("hook_event_name") or "Unknown"
        before = self.state()
        decision = "allow"
        reason = ""
        output: Dict[str, Any] = {}
        exit_code = 0

        if event_name in {"SessionStart", "UserPromptSubmit", "PostCompact"}:
            output = self.additional_context_json(self.context_message())

        if event_name == "UserPromptSubmit":
            prompt = str(payload.get("prompt") or "")
            if re.search(r"(?i)skip|ignore|bypass", prompt) and re.search(r"(?i)harness|state.?machine|review|audit", prompt):
                reason = "Prompt appears to request bypassing governance gates. Ask for an explicit transition request with evidence instead."
                decision = "block"
                output = self.deny_json(event_name, reason)

        if event_name == "PreToolUse":
            decision, reason, output = self.guard_tool(payload)

        if event_name == "Stop":
            # Avoid Claude Code's Stop-hook block loop: if this hook already blocked and Claude is retrying, allow the stop.
            if payload.get("stop_hook_active") is True:
                decision = "allow"
                reason = "stop_hook_active=true; avoiding block loop"
            else:
                ok, msg, dst, req = self.validate_transition_request()
                reason = msg
                if ok and dst:
                    self.approve_transition(dst, req)
                    decision = "transition"
                    output = self.additional_context_json(f"LOA harness advanced state to {dst}. {msg}")
                elif not ok:
                    decision = "block"
                    output = self.deny_json("Stop", msg)

        after = self.state()
        self.append_event(event_name, payload, state_before=before, state_after=after, decision=decision, reason=reason, output=output)
        return exit_code, output or None, reason

    def verify_chain(self) -> Tuple[bool, List[str]]:
        messages: List[str] = []
        prev = "genesis"
        expected_seq = 1
        if not self.events_path.exists():
            return True, ["no events yet"]
        with self.events_path.open("r", encoding="utf-8") as f:
            for line_no, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception as e:
                    return False, [f"line {line_no}: invalid JSON: {e}"]
                if rec.get("seq") != expected_seq:
                    return False, [f"line {line_no}: expected seq {expected_seq}, got {rec.get('seq')}"]
                if rec.get("prev_hash") != prev:
                    return False, [f"line {line_no}: prev_hash mismatch expected {prev}, got {rec.get('prev_hash')}"]
                event_hash = rec.pop("event_hash", None)
                computed = sha256_bytes(canonical(rec))
                if event_hash != computed:
                    return False, [f"line {line_no}: event_hash mismatch expected {computed}, got {event_hash}"]
                prev = event_hash
                expected_seq += 1
        messages.append(f"ok: {expected_seq - 1} events; head_hash {prev}")
        if prev != self.head_hash():
            messages.append(f"warning: sqlite head_hash {self.head_hash()} differs from jsonl head {prev}")
        return True, messages


def parse_stdin_json() -> Dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except Exception as e:
        print(f"LOA harness: invalid JSON on stdin: {e}", file=sys.stderr)
        return {"_raw": raw, "_parse_error": str(e)}


def build_harness(args: argparse.Namespace) -> Harness:
    root = find_project_root(getattr(args, "cwd", None))
    policy_path, policy = load_policy(root, getattr(args, "policy", None))
    return Harness(root, policy_path, policy)


def cmd_init(args: argparse.Namespace) -> int:
    root = find_project_root(getattr(args, "cwd", None))
    policy_path, policy = load_policy(root, getattr(args, "policy", None))
    h = Harness(root, policy_path, policy)
    print(json.dumps(h.status_obj(), indent=2, sort_keys=True))
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    h = build_harness(args)
    print(json.dumps(h.status_obj(), indent=2, sort_keys=True))
    return 0


def cmd_hook(args: argparse.Namespace) -> int:
    h = build_harness(args)
    payload = parse_stdin_json()
    event_name = args.event or payload.get("hook_event_name") or "Unknown"
    exit_code, output, reason = h.handle_hook(event_name, payload)
    if output:
        print(json.dumps(output, separators=(",", ":"), ensure_ascii=False))
    elif reason and args.verbose:
        print(reason, file=sys.stderr)
    return exit_code


def cmd_verify(args: argparse.Namespace) -> int:
    h = build_harness(args)
    ok, messages = h.verify_chain()
    print(json.dumps({"ok": ok, "messages": messages, "status": h.status_obj()}, indent=2, sort_keys=True))
    return 0 if ok else 2


def cmd_request_transition(args: argparse.Namespace) -> int:
    h = build_harness(args)
    cur = h.state()
    evidence = []
    for spec in args.evidence or []:
        # path[:min_bytes[:marker]]; use repeated --evidence for multiple artifacts.
        parts = spec.split(":", 2)
        item: Dict[str, Any] = {"path": parts[0]}
        if len(parts) >= 2 and parts[1]:
            item["min_bytes"] = int(parts[1])
        if len(parts) == 3 and parts[2]:
            item["contains_any"] = [parts[2]]
        evidence.append(item)
    req = {
        "schema_version": "loa-harness.transition-request/v0.1",
        "from": args.from_state or cur,
        "to": args.to,
        "reason": args.reason,
        "actor": args.actor,
        "created_at": utc_now(),
        "evidence": evidence if evidence else None,
    }
    # Drop null evidence so default policy evidence applies.
    if req["evidence"] is None:
        del req["evidence"]
    write_json(h.transition_path, req)
    print(json.dumps({"ok": True, "path": relpath(h.root, str(h.transition_path)), "request": req}, indent=2, sort_keys=True))
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="LOA portable deterministic harness")
    parser.add_argument("--policy", help="Path to policy JSON. Defaults to .loa-harness/policy.json")
    parser.add_argument("--cwd", help="Project root/cwd override")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_init = sub.add_parser("init", help="Initialize runtime state and event store")
    p_init.set_defaults(func=cmd_init)

    p_status = sub.add_parser("status", help="Print current worldline state")
    p_status.set_defaults(func=cmd_status)

    p_hook = sub.add_parser("hook", help="Claude Code hook entry point; reads hook JSON from stdin")
    p_hook.add_argument("--event", help="Hook event name if not supplied in stdin")
    p_hook.add_argument("--verbose", action="store_true")
    p_hook.set_defaults(func=cmd_hook)

    p_verify = sub.add_parser("verify", help="Verify hash chain and print status")
    p_verify.set_defaults(func=cmd_verify)

    p_req = sub.add_parser("request-transition", help="Create a transition.request.json for the Stop hook to validate")
    p_req.add_argument("--to", required=True, help="Destination state")
    p_req.add_argument("--from", dest="from_state", help="Source state; defaults to current")
    p_req.add_argument("--reason", default="", help="Why this transition should happen")
    p_req.add_argument("--actor", default="human-or-agent", help="Actor requesting transition")
    p_req.add_argument("--evidence", action="append", help="Evidence as path[:min_bytes[:marker]]; repeatable")
    p_req.set_defaults(func=cmd_request_transition)

    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
