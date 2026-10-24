# s3-e report (D4): the sandbox must not reach the host gateway (KF-058; Sprint 274; SDD C-9, § 1.9, § 7.3)

Worktree `loa-wt-s3e` at `c31aad7cc`. Patch `~/.cache/loa/cycle-133/patches/s3-e.patch` (+ `.stat`); copy at `grimoires/loa/a2a/sprint-274/reviewer-e.md`.

## Reproduced first
From an `--internal` network the gateway answered `ConnectionRefused` on 22 and 80, so the host was reached. A host listener on the gateway, and port 5432, only timed out because this host's own firewall drops them. CI's runner has no such firewall (run 40074686664). Red log for the new EGR-8 on the old design: `~/.cache/loa/cycle-133/tests/s3e-egr8-red.log` (`172.28.0.1:22 … ECONNREFUSED`).

## What was built: a guard namespace per sandbox container
- **`evals/harness/Dockerfile.proxy`**: new entrypoint `loa-egress-guard` (`:112`) and label `org.loa.egress.guard="1"` (`:152`). It resolves the sidecar once and installs netfilter in its own namespace. iptables OUTPUT is DROP, allowing loopback, replies and `<sidecar>/32 tcp 8888`; everything else is `REJECT icmp-admin-prohibited`. INPUT is DROP except loopback and replies, and ip6tables matches. It then runs `setpriv` to uid 65534 with no capabilities and sleeps. The sidecar's own rules are unchanged. Tag stays `:259`; rebuilt here as `sha256:95c4c379107c…`, with the old image kept as `:259-pre-kf058` (`10fc90b6e85a…`).
- **`lib/egress-proxy.sh`**:
  - **`guard <batch> <name>`** (`:263`) starts the guard from the sidecar's image, on the internal network with `--dns 0.0.0.1`, `--cap-drop ALL` plus NET_ADMIN/SETUID/SETGID and no-new-privileges. It prints `container:<name>`. It refuses a missing sidecar, a bad name or a foreign container (exit 2), and replaces a stale guard of the batch.
  - **`up` and `down`**: `up` refuses a proxy image without the guard label (`:188`). `down` sweeps the batch's guards (`:249`).
  - **`record-address --guard G`** (`:382`) reads G's address and records `guard`. `watch` waits up to 120 s for the sandbox to appear, then removes G after the end record.
  - **`self-check`** runs the probe in its own guard. New `must_unreach` (`:480`) passes only on an in-namespace rejection (EHOSTUNREACH, ENETUNREACH, EACCES, EPERM). It covers both gateways on 22, 80, 443 and the listener port (`:517`), metadata, and the sidecar's ports 22 and 443. The new gateway listener (`GW_LISTENER` `:536`) binds the host on both gateway addresses. New lines: `host gateway listener` and `sandbox guard netfilter`.
- **`pipeline-run.sh`** (one block, `:954`–`:983`) and **`blind-session.sh`** (one block, `:306`–`:330`): each blocked container gets a uniquely named guard and `--network container:<guard>`, with no `--dns`. The watcher gets `--guard`. A failed guard is `infra` in pipeline-run and exit 1 in blind-session. Records add `guard`, and `network` stays `loa-egress-<batch>`.
- **`run-ablation.sh`** pre-flight (`:980`–`:982`) refuses a sidecar whose image has no guard, with the rebuild line.
- **`evals/harness/README.md`**: the egress section's Layout, Per arm, Refusal, self-check and Records.

## Tests (`evals/tests/egress-proxy.bats`)
- **EGR-8 rewritten** (the reproducing test). Both gateways on 22, 80, 443 and a listener the test binds on the host must be rejected in the namespace. The listener has a positive control, and exactly one accepted connection, the control, is allowed. Rebind, metadata, the stub and the sidecar's port 22 are covered. It was red on the old design and is green now.
- **EGR-13 new**: a root sandbox in the guard's namespace cannot flush the rules (Permission denied) and is still rejected. The guard's pid 1 is `sleep infinity` with Uid 65534 and CapEff 0. A stale guard is replaced, a foreign container is refused, and `down` sweeps guards.
- **EP-9 new**: `pipeline-run.sh` puts every phase container in its own guard with unique names. The guard argv and `meta/egress.jsonl` rows are checked. Without the block it uses bridge and no guard.
- **Updated**: sbx, EGR-10 and EGR-11 run in a guard, and EGR-11 checks that the watcher removes it. EGR-12 checks the new lines with at least 40 PASS. EP-3 and EP-8 refuse a stale image, and EP-7 checks the guard argv.
- **Release gate**, real containers on this host: `LOA_EGRESS_GATE=1 npx --no-install bats evals/tests/egress-proxy.bats` gives **22/22** (EP-1…9, EGR-1…13). Log: `~/.cache/loa/cycle-133/tests/s3e-egress-bats.log`.
- **Regression**: `npx --no-install bats evals/tests/pipeline-run.bats evals/tests/blind-session.bats evals/tests/run-ablation.bats` → **174/174** (`~/.cache/loa/cycle-133/tests/s3e-regression-bats.log`). The gate was re-run on the final code: 22/22, with no guard or network left behind.
- **Lints**: no-swallowed-jq, no-raw-sha256sum and no-raw-curl exit 0. The `eval.yml` source/eval scan of the four scripts is clean, and `bash -n` is clean.

## Pin self-check and spike
- **Self-check** at `loa-ablation:259` with the real 10-host allowlist and proxy `95c4c379…`: exit 0, **62 PASS, 0 FAIL**. Every allowlisted host connects 200, and the listener and guard lines pass. Log: `~/.cache/loa/cycle-133/tests/s3e-pin-selfcheck/self-check.log`.
- **Spike `user` arm** through the guard: **SPIKE-OK, exit 0, USD 0.0123, 0 denials**, canaries identical to the pre-fix record. I ran an adapted copy, `~/.cache/loa/cycle-133/spike/spike-3.0-guard.sh`. Three lines differ: ROOT is this worktree, a `guard` call, and `--network "$GNET"` without `--dns`. Output is in `spike/user/`. The previous record was copied to `spike/user.pre-s3e/` first.

## Acceptance criteria
- **Gateways unreachable** on every port, without host privileges and without weakening the allowlist: **Met** (EGR-8, EGR-13, self-check).
- **Deterministic gateway-listener probe** in EGR-8 and self-check: **Met**.
- **EGR-1…12 and EP-1…8 green**, never quarantined: **Met**, plus EGR-13 and EP-9.
- **Denials attributable per run**: **Met**. Each guard has its own address (EGR-11, self-check).
- **`self-check`, `down` and image 259 kept**: **Met**.
- **One contiguous block per launcher**, and the runner pre-flight checks the sidecar: **Met**. The pre-flight also checks the guard label.
- **Pin self-check log, and spike SPIKE-OK with 0 denials**: **Met**. The spike used the adapted copy.
- **`model-config.yaml` unchanged**: **Met**.

## Judgment calls
- **I used a guard namespace per container instead of the recommended shared sidecar namespace.** Each sandbox gets `--network container:<guard>`, and the guard's netfilter reaches loopback and the sidecar's port 8888 only. I rejected sharing because a shared namespace has one loopback and port space. Concurrent runs would collide, and "127.0.0.1:8888 only" also breaks a task's own localhost servers. A uid owner match trusts the uid: a root sandbox holds CAP_SETUID and could take the proxy uid. Attribution would also collapse to 127.0.0.1. The guard leaves the sidecar, the allowlist and per-address attribution unchanged, and the sandbox has no NET_ADMIN there (EGR-13). I also rejected host firewall rules (host privileges) and sandbox-installed rules (NET_ADMIN in the agent).
- **Only an in-namespace rejection passes.** The guard rejects with `icmp-admin-prohibited`, so a blocked connect gets EHOSTUNREACH. A connect, a host refusal or a timeout all FAIL. The old any-failure check was host-dependent: on this host the pre-fix listener "passed" by timeout.
- **The guard uses the sidecar's own image, still tagged 259.** The label `org.loa.egress.guard=1` marks it, and `up` and the runner refuse a stale image. I rejected a new tag, which would ripple into the pins, and the sandbox image, which would need iptables and capabilities.
- **Guard names are unique per container**, using a `$RANDOM$RANDOM` suffix. With a fixed name, a retry's leftover watcher could remove the next attempt's guard. Container names are not artefacts.
- **The watcher owns the guard's lifecycle.** It removes the guard after the end record, and only a container labelled as a guard; `down` sweeps any leftovers. This keeps each launcher to one contiguous block.
- **The guard runs unprivileged after setup.** It drops to nobody with no capabilities, and its INPUT is DROP except loopback and replies.
- **An unbindable gateway is a FAIL in self-check, the batch gate.** EGR-8 skips with the reason only after its 22, 80 and 443 checks have passed.
- **`--dns` moved to the guard**, because Docker refuses it with a container network. The records still say `dns: 0.0.0.1` with network `loa-egress-<batch>`, plus `guard`. The recorded address is the guard's, which is the sandbox's source address.
- **Self-check's probe runs with `--cap-drop ALL` and no-new-privileges.** I did not add these flags to the launchers' `docker run`, which is outside the network block. The guard does not rely on them; they are worth adding later.
- **Shared daemon:** I rebuilt `loa-egress-proxy:259` here and kept the old image as `:259-pre-kf058`. The spike wrote to `spike/user/` after I backed up the previous record. Logs are under `~/.cache/loa/cycle-133/tests/s3e-*`, following the s2d2 precedent.

## What the lead must do
- **Rebuild the proxy image elsewhere.** Rebuild `loa-egress-proxy:259` from the landed Dockerfile on other hosts; this host is done. A batch already up on the old image needs `down` and `up`, and the runner refuses it until then.
- **Pin rows.** The README Sprint 273 pin row (proxy `10fc90b6…`, 20/20) is historical and untouched. The Sprint 274 pin should name `95c4c379…` and the 22-case gate.
- **Ledger and decisions.** Record the KF-058 fix attempt and add DEC rows for the Judgment calls. Amend sprint.md Task 2.4's "join the network with `--dns 0.0.0.1`": the launchers now join a guard that does.
