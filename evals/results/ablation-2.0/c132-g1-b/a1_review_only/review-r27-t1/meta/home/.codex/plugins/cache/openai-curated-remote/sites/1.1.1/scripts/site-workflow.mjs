import { spawn } from "node:child_process";
import { cpSync, existsSync, lstatSync, mkdtempSync, readFileSync, readdirSync, realpathSync, renameSync, rmSync } from "node:fs";
import path from "node:path";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "node:url";
import { validateArchiveDestination } from "./archive-path.mjs";
import { runCommand, runMeasuredOperation, WorkflowError } from "./workflow-metrics.mjs";

const [flag, projectId, ...extra] = process.argv.slice(2);
let credential;
let mode = "open";
const buildHelper = realpathSync(fileURLToPath(new URL("./build-site.mjs", import.meta.url)));
const packageHelper = realpathSync(fileURLToPath(new URL("./package-site.mjs", import.meta.url)));
const phaseDurations = new Map();

await runMeasuredOperation(async () => {
  try {
    if (flag !== "--project-id" || !projectId || extra.length) {
      throw new WorkflowError("Usage: site-workflow.mjs --project-id <project_id>", 64);
    }
    const input = await readWorkflowInput();
    credential = input.credential;
    mode = input.archivePath ? "publish" : "open";
    if (["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"].some((key) => process.env[key])) {
      throw new WorkflowError("Run from the Site checkout without Git directory or index overrides.");
    }
    // Reject archive/source collisions before opening or changing remote source,
    // and before any caller-supplied preparation commands run.
    if (mode === "publish") {
      validateArchiveDestination(input.source?.checkout_path ?? process.cwd(), input.archivePath);
    }
    if (input.source) {
      if (input.source.project_id !== projectId || !path.isAbsolute(input.source.checkout_path ?? "")) {
        throw new WorkflowError("Use the opening result for the selected Site.");
      }
      process.chdir(input.source.checkout_path);
    } else {
      await selectCheckout();
    }
    if (mode === "publish") validateArchiveDestination(process.cwd(), input.archivePath);
    if (lstatSync(".git", { throwIfNoEntry: false })?.isSymbolicLink()) throw new WorkflowError("The Site's .git entry must not be a symlink to another repository.");
    let commitSha;
    if (input.source) {
      await validateCheckout();
      requireProject(readFileSync(".openai/hosting.json", "utf8"));
      commitSha = await currentHead();
    } else {
      commitSha = await openSource();
    }
    let archive;
    if (mode === "publish") {
      for (const args of input.commands ?? []) await runStep(args);
      validateArchiveDestination(process.cwd(), input.archivePath);
      commitSha = await saveSource();
      archive = input.archivePath;
      await runStep([process.execPath, packageHelper, process.cwd(), archive]);
    }
    console.log(JSON.stringify({ project_id: projectId, checkout_path: realpathSync("."), commit_sha: commitSha, ...(archive ? { archive } : {}) }));
    return {
      code: 0,
      dimensions: { mode },
      // One observation per phase per successful workflow. Repeated builds
      // contribute to the workflow's total build time, not extra observations.
      additionalMeasurements: [...phaseDurations].map(([name, value]) => ({
        name, value, dimensions: { outcome: "success", mode },
      })),
    };
  } catch (error) {
    // Keep the shared measurement contract for both operational failures and
    // process-group cancellation; never print an input credential or Git argv.
    process.stderr.write(`${error instanceof WorkflowError ? error.message : "Unable to prepare the Site."}\n`);
    return { code: error.exitCode ?? 1, signal: error.signal, dimensions: { mode } };
  }
});

async function runStep(args) {
  if (!Array.isArray(args) || !args.length || !args.every((arg) => typeof arg === "string")) {
    throw new WorkflowError("Provide each preparation command as an argument array.", 64);
  }
  const env = { ...process.env };
  delete env.CODEX_PLUGIN_METRICS_OUTPUT;
  const startedAt = performance.now();
  const result = await runCommand(args, { env, preserveCancellation: true });
  if (result.code !== 0 || result.signal) {
    const error = new WorkflowError("Site preparation command failed.", result.code || 1);
    error.signal = result.signal;
    throw error;
  }
  // Only the plugin's own direct Node helpers have known phase semantics.
  // Arbitrary preparation commands remain included in the outer duration.
  if ([process.execPath, "node"].includes(args[0])) {
    let helper;
    try { helper = realpathSync(args[1]); } catch { return; }
    const name = helper === buildHelper ? "app_build_duration_ms"
      : helper === packageHelper ? "package_duration_ms" : undefined;
    if (name) phaseDurations.set(name, (phaseDurations.get(name) ?? 0) + performance.now() - startedAt);
  }
}

async function selectCheckout() {
  const metadata = lstatSync(".git", { throwIfNoEntry: false });
  const names = readdirSync(".");
  const entries = names.filter((name) => ![".git", ".agents", ".codex", ".sites-checkout", "node_modules", ".sites-runtime"].includes(name) && !name.startsWith(".sites-checkout-"));
  if (!metadata && (entries.length || names.length === 0)) return;
  if (metadata?.isSymbolicLink()) throw new WorkflowError("The Site's .git entry must not be a symlink to another repository.");
  const repository = metadata ? await git(["rev-parse", "--show-toplevel"], { check: false }) : null;
  const usable = repository?.code === 0 && realpathSync(repository.stdout.trim()) === realpathSync(".");
  if (usable && (entries.length || await currentHead() || names.every((name) => name === ".git"))) return;
  // Keep workspace scaffolding outside restored Site source and later commits.
  // Only empty, unborn repositories may use this path without a Site manifest.
  // Scratch workspaces can mount an invalid, read-only .git placeholder. Keep
  // it untouched; never discard potentially damaged real Git history.
  if (metadata && !usable && (!metadata.isDirectory() || ["objects", "refs"].some((name) => existsSync(path.join(".git", name))))) {
    throw new WorkflowError("Git metadata is unreadable. Preserve this checkout and repair its .git history before retrying open.");
  }
  const destination = path.resolve(".sites-checkout");
  const existing = lstatSync(destination, { throwIfNoEntry: false });
  if (existing) {
    if (existing.isSymbolicLink() || !existing.isDirectory()) {
      throw new WorkflowError("The reserved .sites-checkout path must be a directory, not a symlink. Preserve it and choose another Site workspace.");
    }
    if (readdirSync(destination).some((name) => name !== ".git")) {
      requireProject(readFileSync(path.join(destination, ".openai/hosting.json"), "utf8"));
    }
  } else {
    if (entries.length) requireProject(readFileSync(".openai/hosting.json", "utf8"));
    const temporary = mkdtempSync(path.resolve(".sites-checkout-"));
    try {
      for (const entry of entries) {
        cpSync(entry, path.join(temporary, entry), { recursive: true, dereference: false, verbatimSymlinks: true, force: false, errorOnExist: true });
      }
      renameSync(temporary, destination);
    } catch {
      try { rmSync(temporary, { recursive: true, force: true }); } catch {}
      throw new WorkflowError("Could not create the Site checkout at .sites-checkout. Original source is unchanged; make the workspace writable and retry open.");
    }
  }
  process.chdir(destination);
}

// Opening is the only operation that initializes or brings remote source into
// the checkout. Do this before building; saving never changes the source base.
async function openSource() {
  const empty = readdirSync(".").every((name) => name === ".git");
  if (!empty) requireProject(readFileSync(".openai/hosting.json", "utf8"));
  if (!existsSync(".git")) await git(["init", "--initial-branch", credential.branch, "."]);
  await validateCheckout();
  await validateDestination();
  const ref = `refs/heads/${credential.branch}`;
  const advertised = (await git(["ls-remote", "--heads", credential.remote_url, ref], { network: true })).stdout.trim();
  let remoteHead;
  if (advertised) {
    await git(["fetch", "--no-tags", credential.remote_url, ref], { network: true });
    remoteHead = (await git(["rev-parse", "--verify", "FETCH_HEAD^{commit}"])).stdout.trim();
    requireProject((await git(["show", `${remoteHead}:.openai/hosting.json`])).stdout);
  }
  const head = await currentHead();
  if (!head && remoteHead) {
    if (!empty) throw new WorkflowError("Existing remote source requires an empty checkout. Keep these local files and reopen the Site in an empty directory.");
    await git(["checkout", "-B", credential.branch, remoteHead]);
  } else if (head && remoteHead && head !== remoteHead) {
    const ahead = await git(["merge-base", "--is-ancestor", remoteHead, head], { check: false });
    if (ahead.code !== 0) {
      const behind = await git(["merge-base", "--is-ancestor", head, remoteHead], { check: false });
      if (behind.code !== 0) throw new WorkflowError("Local and remote Site history diverged. Reconcile the changes before retrying; no history was overwritten.");
      if ((await git(["status", "--porcelain"])).stdout.trim()) throw new WorkflowError("Remote Site source advanced while local edits are present. Preserve and reconcile those edits before retrying.");
      await git(["merge", "--ff-only", remoteHead]);
    }
  }
  requireProject(readFileSync(".openai/hosting.json", "utf8"));
  return currentHead();
}

async function saveSource() {
  await validateCheckout();
  requireProject(readFileSync(".openai/hosting.json", "utf8"));
  await validateDestination();
  await git(["add", "--all", "--", "."]);
  const sourceTree = (await git(["write-tree"])).stdout.trim();
  requireProject((await git(["show", `${sourceTree}:.openai/hosting.json`])).stdout);
  const staged = await git(["diff", "--cached", "--quiet"], { check: false });
  if (staged.code > 1) throw new WorkflowError("Unable to inspect staged Site source.");
  if (staged.code === 1) {
    const identity = await git(["var", "GIT_AUTHOR_IDENT"], { check: false });
    const fallback = identity.code === 0 ? [] : ["-c", "user.name=Sites", "-c", "user.email=sites@users.noreply.openai.com"];
    await git([...fallback, "commit", "-m", "Update Site source"]);
  }
  const head = await currentHead();
  if ((await git(["rev-parse", `${head}^{tree}`])).stdout.trim() !== sourceTree || (await git(["status", "--porcelain"])).stdout.trim()) {
    throw new WorkflowError("Site source changed while committing. Rebuild and retry publishing.");
  }
  const ref = `refs/heads/${credential.branch}`;
  // Git's normal push is the concurrency check. A rejected push keeps the
  // local commit for recovery; it never triggers a fetch, merge, or force push.
  const push = await git(["push", credential.remote_url, `${head}:${ref}`], { network: true, check: false });
  if (push.code !== 0) {
    const detail = push.stderr.split(credential.token).join("[redacted]").trim();
    throw new WorkflowError(`${detail}\nLocal source and commits are retained. Reconcile remote changes and rebuild before retrying publishing.`, push.code);
  }
  const pushed = (await git(["ls-remote", "--heads", credential.remote_url, ref], { network: true })).stdout.trim().split(/\s+/)[0];
  if (pushed !== head || await currentHead() !== head || (await git(["status", "--porcelain"])).stdout.trim()) {
    throw new WorkflowError("Site source changed while saving. Rebuild and retry publishing.");
  }
  return head;
}

async function validateCheckout() {
  if (!existsSync(".git")) throw new WorkflowError("The opening result requires its original Git checkout.");
  const repository = await git(["rev-parse", "--show-toplevel"], { check: false });
  if (repository.code !== 0) throw new WorkflowError("This is not a usable Git checkout. Reopen the Site and use the returned checkout_path.");
  const root = repository.stdout.trim();
  if (realpathSync(root) !== realpathSync(".")) {
    throw new WorkflowError("Git must be rooted at the selected Site checkout.");
  }
  const gitDirectory = (await git(["rev-parse", "--absolute-git-dir"])).stdout.trim();
  if (["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply"].some((name) => existsSync(path.join(gitDirectory, name)))) {
    throw new WorkflowError("Finish the existing Git merge, rebase, or cherry-pick before opening or saving Site source.");
  }
}

async function validateDestination() {
  await git(["check-ref-format", `refs/heads/${credential.branch}`]);
  // These are local configuration checks, not network requests. Use the
  // connector's destination directly without configuring a persistent remote.
  const rewritten = (await git(["ls-remote", "--get-url", credential.remote_url])).stdout.trim();
  const rewrites = await git(["config", "--get-regexp", "^url\\..*\\.pushinsteadof$"], { check: false });
  const pushRewritten = rewrites.stdout.split("\n").some((line) => {
    const prefix = line.match(/^\S+\s+(.+)$/)?.[1];
    return prefix && credential.remote_url.startsWith(prefix);
  });
  if (rewritten !== credential.remote_url || pushRewritten) {
    throw new WorkflowError("The Site source URL is affected by Git URL rewriting; resolve it before retrying.");
  }
}

function requireProject(source) {
  let manifest;
  try { manifest = JSON.parse(source); } catch { throw new WorkflowError("Site source must contain a valid .openai/hosting.json."); }
  if (manifest?.project_id !== projectId) throw new WorkflowError("The source project_id does not match the selected Site.");
}

async function currentHead() {
  const result = await git(["rev-parse", "--verify", "HEAD^{commit}"], { check: false });
  return result.code === 0 ? result.stdout.trim() : null;
}

async function readWorkflowInput() {
  // A direct exec remains measurable. A writable terminal session can deliver
  // the JSON on stdin without putting the token in shell history or argv.
  const input = await new Promise((resolve, reject) => {
    let value = "";
    const terminal = process.stdin.isTTY;
    const finish = (error) => {
      process.stdin.removeListener("data", onData);
      process.stdin.removeListener("end", onEnd);
      if (terminal) process.stdin.setRawMode(false);
      process.stdin.pause();
      error ? reject(error) : resolve(value);
    };
    const onData = (chunk) => {
      value += chunk;
      if (value.includes("\u0003")) {
        const error = new WorkflowError("Source operation cancelled.", 130);
        error.signal = "SIGINT";
        finish(error);
      } else if (value.length > 65536) finish(new WorkflowError("Workflow input is too large.", 64));
      else if (value.includes("\n") || value.includes("\r")) finish();
    };
    const onEnd = () => finish();
    if (terminal) {
      process.stdin.setRawMode(true);
      process.stderr.write("Ready for Site workflow JSON on stdin (input is hidden).\n");
    }
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", onData);
    process.stdin.once("end", onEnd);
    process.stdin.resume();
  });
  let request;
  try { request = JSON.parse(input); } catch { throw new WorkflowError("Provide the workflow inputs as one JSON object on stdin.", 64); }
  const value = request?.credential;
  const privateAuth = value?.auth_mode === "work_proxy";
  const bearerAuth = value?.auth_mode === "http_extra_header" && typeof value.token === "string" && value.token && !/[\r\n\0]/.test(value.token);
  if ((!privateAuth && !bearerAuth) || typeof value.branch !== "string" || !value.branch || value.branch.startsWith("-")) {
    throw new WorkflowError("Use the returned source repository access with its auth_mode, remote_url, and branch.", 64);
  }
  let url;
  try { url = new URL(value.remote_url); } catch { throw new WorkflowError("The source credential remote_url must be an HTTPS URL.", 64); }
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash) throw new WorkflowError("Use the credential's HTTPS remote_url without embedded credentials, query, or fragment.", 64);
  if (value.token_expires_at && (!Number.isFinite(Date.parse(value.token_expires_at)) || Date.parse(value.token_expires_at) <= Date.now())) throw new WorkflowError("Renew the source credential for the same Site before retrying.");
  return request;
}

async function git(args, { network = false, check = true } = {}) {
  const env = { ...process.env, GIT_TERMINAL_PROMPT: "0" };
  const auth = [];
  if (network) {
    for (const key of Object.keys(env)) if (key.startsWith("GIT_TRACE") || key === "GIT_CURL_VERBOSE") delete env[key];
    auth.push("-c", "credential.helper=", "-c", "http.extraHeader=", "-c", "http.followRedirects=false");
    if (credential.auth_mode === "http_extra_header") {
      env.SITES_GIT_AUTHORIZATION = `Authorization: Bearer ${credential.token}`;
      auth.push(`--config-env=http.${credential.remote_url}.extraHeader=SITES_GIT_AUTHORIZATION`);
    }
  }
  const result = await new Promise((resolve) => {
    let stdout = "", stderr = "", receivedSignal;
    const handlers = ["SIGINT", "SIGTERM", "SIGHUP"].map((signal) => [signal, () => { receivedSignal ??= signal; }]);
    const child = spawn("git", [...auth, ...args], { env, stdio: ["ignore", "pipe", "pipe"] });
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    for (const [signal, handler] of handlers) process.on(signal, handler);
    child.once("error", () => { stderr = "Unable to start Git."; });
    child.once("close", (code, signal) => {
      for (const [name, handler] of handlers) process.removeListener(name, handler);
      resolve({ code: code ?? 1, signal: receivedSignal ?? signal, stdout, stderr });
    });
  });
  if (result.signal || check && result.code !== 0) {
    const detail = result.stderr.split(credential.token).join("[redacted]").trim();
    const error = new WorkflowError(detail || "Git could not complete the Site source operation.", result.code || 1);
    error.signal = result.signal;
    throw error;
  }
  return result;
}
