## Problem

**VS Code "Attach to Running Container" hung forever** on Ascend 910B containers.

### Root causes (two independent issues that compounded)

**1. `set_env.sh` in shell startup files**

The Ascend base image (`quay.io/ascend/cann:9.0.0-910b-...`) automatically injects `source set_env.sh` into profile, bash.bashrc, `/etc/profile.d/*.sh`, `/root/.bashrc`, and others. VS Code's Dev Containers extension probes the container environment by launching a `loginInteractiveShell` (`bash --login -i`), which triggers all those startup files. `set_env.sh` takes **10–30 seconds** to execute → probe times out → attach hangs.

**2. `LD_PRELOAD=libhccl.so` set as Docker `ENV`**

The Dockerfile had `ENV LD_PRELOAD=.../libhccl.so` so that simpler's `host_runtime.so` could resolve its weak HCCL symbol references at load time (without it: `SIGSEGV` on `comm_init`). The problem: Docker `ENV` is inherited by **every process** in the container. VS Code's `userEnvProbe` shell captures `LD_PRELOAD` from the environment and **injects it into the VS Code server's node process** — which then loads `libhccl.so` on startup, triggering HCCL hardware initialization → **hang**.

---

## Debugging approach

### Step 1 — read the Dev Containers log

The key signal was in the Dev Containers output panel (`> Dev Containers: Show Log`):

```
[2644 ms] userEnvProbe: loginInteractiveShell (default)
[2644 ms] userEnvProbe: not found in cache
[2644 ms] userEnvProbe shell: /bin/bash
... (no output for 30+ seconds) ...
```

The probe was stalling. The `loginInteractiveShell` mode means VS Code spawns
`bash --login -i` inside the container and captures its environment. That shell
sources all startup files before returning.

### Step 2 — identify `set_env.sh` as the slow path

Searching the image for `set_env.sh` references:

```bash
docker exec <container> grep -r 'set_env' \
  /etc/profile /etc/bash.bashrc /etc/profile.d/ \
  /root/.bashrc /root/.profile /root/.bash_profile 2>/dev/null
```

Multiple matches confirmed the base image had injected it into several files.
`set_env.sh` calls `acl_check_version`, probes CANN installation paths, and
sets ~30 env vars — all of which requires filesystem traversal and takes 10–30s.

**First fix attempted:** remove `set_env.sh` from `/etc/bash.bashrc` only.
This was insufficient — other files (`/etc/profile`, `/etc/profile.d/*.sh`) still
sourced it and a `loginInteractiveShell` reads all of them.

**Correct fix:** strip it from every startup file with `sed -i`.

### Step 3 — probe completed but attach still hung

After fixing `set_env.sh`, the probe completed in ~3–5s and returned a PATH.
The Dev Containers log showed:

```
[73533 ms] userEnvProbe PATHs:
Probe:     '/opt/ptoas-bin:/opt/ptoas-bin/bin:/usr/local/Ascend/...'
```

But attach still hung at the VS Code server startup phase. The key observation:
the probed PATH contained Ascend paths — meaning the probe was still running
something that set them. More importantly, the probe's **entire captured
environment** (not just PATH) was being injected into the server process.

### Step 4 — find `LD_PRELOAD` in the container env

```bash
docker exec <container> env | grep -E 'LD_PRELOAD|LD_LIBRARY'
```

Output:
```
LD_PRELOAD=/usr/local/Ascend/cann-9.0.0/aarch64-linux/lib64/libhccl.so
```

`LD_PRELOAD` was set as a Docker `ENV` instruction — present in every process
from container start. When VS Code's server node binary launched, the OS
automatically loaded `libhccl.so` before any application code ran. HCCL init
requires hardware communication setup, NPU device probing, and MPI-level
coordination → node hung indefinitely before even starting the server.

### Step 5 — understand why `LD_PRELOAD` was there in the first place

`simpler`'s `host_runtime.so` declares WEAK undefined symbols for
`HcclGetRootInfo`, `HcclCommInitRootInfo`, `HcclBarrier`, `HcclCommDestroy`
but does not add `libhccl.so` to `DT_NEEDED`. The dynamic linker only resolves
WEAK symbols from libraries already loaded globally — `LD_LIBRARY_PATH` is not
enough. Without `LD_PRELOAD`, those symbols stay NULL and `comm_init` segfaults.
`LD_PRELOAD` was the correct solution for HCCL — just in the wrong scope.

### Step 6 — approaches considered for LD_PRELOAD

| Approach | Problem |
|----------|---------|
| Keep `ENV LD_PRELOAD=...` | Injected into VS Code server → hang |
| Set in `/etc/bash.bashrc` | VS Code's `userEnvProbe` shell captures bashrc env and still injects it into the server |
| Bake `devcontainer.json` with `"userEnvProbe": "none"` | Fixes the inject, but user preferred not to add devcontainer infrastructure to the image |
| **Set manually in shell before HCCL tests** | ✅ Chosen: users set it explicitly; VS Code never sees it |

The critical insight about the bashrc approach: `userEnvProbe` doesn't just
run the shell to get PATH — it captures the **full environment** snapshot and
merges it into the server process's env. So even a bashrc-only `LD_PRELOAD`
would be captured and injected.

---

## Solution

Two Dockerfile changes:

**1. Strip `set_env.sh` from all startup files at build time:**
```dockerfile
RUN for f in /etc/profile /etc/bash.bashrc /root/.profile /root/.bashrc /root/.bash_profile; do \
      [ -f "$f" ] && sed -i '/set_env\.sh/d' "$f" || true; \
    done && \
    for f in /etc/profile.d/*.sh; do \
      [ -f "$f" ] && sed -i '/set_env\.sh/d' "$f" || true; \
    done
```
All needed CANN env vars are set via `ENV` instructions instead — no shell sourcing required.

**2. Remove `LD_PRELOAD` from Docker `ENV`; set it manually before HCCL tests:**
```bash
export LD_PRELOAD=${CANN_HOME}/aarch64-linux/lib64/libhccl.so
```
This keeps HCCL working in interactive shells without poisoning VS Code's server process.

---

## What did NOT work (and why)

| Attempt | Why it failed |
|---------|---------------|
| Remove `set_env.sh` from `/etc/bash.bashrc` only | `loginInteractiveShell` also sources `/etc/profile` and `/etc/profile.d/*.sh` |
| Move `LD_PRELOAD` from `ENV` to `/etc/bash.bashrc` | `userEnvProbe` captures the full shell env snapshot and injects it into the server |
| Rely on `LD_LIBRARY_PATH` alone for HCCL | Not enough: WEAK symbol resolution happens at `host_runtime.so` load time, before any HCCL call |

---

**Result:** VS Code attaches in <5 seconds. HCCL tests still work (set `LD_PRELOAD` in the shell first). Both fixes and their rationale are documented in `../../pypto-tooling/debugging_skills/SKILL.md` (VS Code attach hang section) and `SKILL.md` (CANN environment + HCCL requirements sections).