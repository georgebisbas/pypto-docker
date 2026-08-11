---
name: pypto-dockerfile-construction
description: >-
  Build and debug standalone/server Ascend NPU Docker images for PyPTO,
  simpler, and pytorch-hccl-tests. Covers ARG-driven paths, git-clone
  patterns, HCCL runtime flags, build order, and common failures.
triggers:
  - "create a Dockerfile"
  - "add to Dockerfile"
  - "update Dockerfile"
  - "Dockerfile is stale"
  - "Dockerfile build fails"
  - "Dockerfile error"
  - "docker build fails"
  - "container fails"
  - "import error in container"
  - "HCCL fails in container"
  - "simpler_init failed"
  - "ChipBufferSpec"
  - "aclInit failed"
---

# PyPTO Dockerfile construction

> **Location:** the Dockerfiles, `scripts/`, and `docker-entrypoint-cann.sh` described
> here live in this repo (the repo root). Run build and update commands from the repo root;
> this file is the construction knowledge that
> accompanies them.

## When to use this skill

```text
Task starts
├─ User says "update this Dockerfile"?  → "When to update" per-Dockerfile checklist
├─ Creating a NEW Dockerfile?  → "Dockerfile inventory" + "Build-time patterns"
├─ Existing Dockerfile won't BUILD? → "Common failures" symptom table
├─ Container RUNS but tests FAIL? → ../../pypto-tooling/debugging_skills/SKILL.md first, then return
├─ Need to understand a PATTERN? → Jump to named h3 below
└─ Debugging interactively?        → "Interactive debugging" checklist
```

## Dockerfile inventory

| Dockerfile | What it builds | Build command | Needs NPU? |
|-----------|---------------|---------------|------------|
| `Dockerfile.hw-native-sys.cann9.0` | pypto + simpler + pto-isa + ptoas | `docker build -t img - < Dockerfile...` | Yes (a2a3) |
| `Dockerfile.simpler.cann9.0` | simpler + pto-isa only | `docker build -t img - < Dockerfile...` | Yes (a2a3) |
| `Dockerfile.hw-native-sys.sim.ubuntu22.04` | pypto + pto-isa (sim mode) | `docker build -t img -f Dockerfile... .` | No |
| `Dockerfile.simpler.sim.ubuntu22.04` | simpler + pto-isa (sim mode) | `docker build -t img -f Dockerfile... .` | No |
| `Dockerfile.pypto-lib.sim.ubuntu22.04` | pypto-lib on top of `pypto3-hw-native-sys:sim` | `docker build -t img -f Dockerfile... .` | No |
| `Dockerfile.pypto-lib.cann9.0` | pypto-lib on top of `pypto3-hw-native-sys:cann9` | `docker build -t img - < Dockerfile...` | Yes (a2a3) |
| `Dockerfile.pytorch-hccl-tests.cann9.0` | HCCL benchmarks | `docker build -t img - < Dockerfile...` | Yes (a2a3) |
| `Dockerfile.server.cann:9.0` | pypto dev workspace | `docker build -t img -f Dockerfile... .` | Yes (a2a3) |

All use `quay.io/ascend/cann:9.0.0-910b-ubuntu22.04-py3.12` as base image.

## When to update Dockerfiles

Each Dockerfile pins specific external versions. When asked to update one, run the corresponding checklist below. Each check produces a diff command — if it outputs anything, an update is needed.

### `Dockerfile.hw-native-sys.cann9.0` — pypto + simpler + pto-isa + ptoas

| # | Check | Command | What to update if drifted |
|---|-------|---------|--------------------------|
| 1 | pypto `origin/main` ahead of `PYPTO_COMMIT`? | `git -C /path/to/pypto rev-list --count ${PYPTO_COMMIT}..origin/main` | `ARG PYPTO_COMMIT` + header comment example |
| 2 | pto-isa commit changed? | Read `pypto/runtime/pto_isa.pin` — the single source of truth (auto-derived at Docker build time). | Auto-derived; no ARG update needed unless you want to hard-pin via `--build-arg` |
| 3 | PTOAS version or SHA256 changed? | Read `pypto/toolchain/versions.env` **at the commit you are pinning** — this is the **single source of truth** for PTOAS_VERSION and PTOAS_SHA256_{AARCH64,X86_64} (bumped via PRs like [#1921](https://github.com/hw-native-sys/pypto/pull/1921)). Do NOT grep `.github/workflows/ci.yml` for PTOAS. | `ARG PTOAS_VERSION` + `ARG PTOAS_SHA256` (aarch64 for cann/server, x86_64 for sim) |
| 4 | pip deps changed in pypto CI Dockerfile? | `diff <(grep 'pip install' pypto/.github/docker/github_ci.Dockerfile) <(grep 'pip install' Dockerfile.hw-native-sys.cann9.0)` | Update pip install RUN lines |
| 5 | Test commands in header comment match pypto CI? | Compare `.github/workflows/ci.yml` jobs with Dockerfile comment header | Update test command cheatsheet in header comment |
| 6 | `3rdparty` fallback clones match `pypto/.gitmodules`? | `git -C /path/to/pypto show origin/main:.gitmodules` vs the fallback `git clone` URLs/branches in the Dockerfile | Update the fallback URL/branch — see "Third-party fallback" pattern |

**PTOAS versions are not monotonic.** `versions.env` can move *backwards*: pypto bumped to v0.50 (#2076) then reverted to v0.48 (#2138) because that ptoas build was buggy. Always take the version from `versions.env` at the pypto commit you pin — never carry forward a higher number just because you set it last time, and never bump ahead of `versions.env` even when newer PTOAS releases exist.

### `Dockerfile.simpler.cann9.0` — simpler + pto-isa only

| # | Check | Command | What to update if drifted |
|---|-------|---------|--------------------------|
| 1 | simpler `origin/main` ahead of `SIMPLER_COMMIT`? | `git -C /path/to/simpler rev-list --count ${SIMPLER_COMMIT}..origin/main` | `ARG SIMPLER_COMMIT` + header comment |
| 2 | pto-isa commit changed? | Read `simpler/pto_isa.pin` — the single source of truth (auto-derived at Docker build time). | Auto-derived; no ARG update needed unless you want to hard-pin via `--build-arg` |
| 3 | `ENV LD_PRELOAD` absent? | `grep LD_PRELOAD Dockerfile.simpler.cann9.0` — should be comments only | Remove image-wide `ENV LD_PRELOAD` |
| 4 | `set_env.sh` stripped, not re-added to bashrc? | `grep set_env Dockerfile.simpler.cann9.0` — strip `RUN` only, no bashrc append | Align with hw-native-sys pattern |

Note: No PTOAS or pypto dependencies — simpler-only image.

### `Dockerfile.hw-native-sys.sim.ubuntu22.04` — pypto + pto-isa (x86_64 sim)

| # | Check | Command | What to update if drifted |
|---|-------|---------|--------------------------|
| 1 | pypto `origin/main` ahead of `PYPTO_COMMIT`? | Same as hw-native-sys check #1 | `ARG PYPTO_COMMIT` |
| 2 | pto-isa commit changed? | Read `pypto/runtime/pto_isa.pin` — the single source of truth (auto-derived at Docker build time). | Auto-derived; no ARG update needed unless you want to hard-pin via `--build-arg` |
| 3 | PTOAS x86_64 version/SHA256 changed? | Read `pypto/toolchain/versions.env` — use the **x86_64** SHA256 (`PTOAS_SHA256_X86_64`) from that file | `ARG PTOAS_VERSION` + `ARG PTOAS_SHA256` (x86_64 binary) |

Note: Uses **x86_64** `ptoas-bin-x86_64.tar.gz` with a **different SHA256** than the aarch64 binary used in hw-native-sys.

### `Dockerfile.simpler.sim.ubuntu22.04` — simpler + pto-isa (x86_64 sim)

| # | Check | Command | What to update if drifted |
|---|-------|---------|--------------------------|
| 1 | simpler `origin/main` ahead of `SIMPLER_COMMIT`? | `git -C /path/to/simpler rev-list --count ${SIMPLER_COMMIT}..origin/main` | `ARG SIMPLER_COMMIT` + header comment |
| 2 | pto-isa commit changed? | Read `simpler/pto_isa.pin` — the single source of truth (auto-derived at Docker build time). | Auto-derived; no ARG update needed unless you want to hard-pin via `--build-arg` |
| 3 | L3 sim pytest flags match `st-sim-a2a3`? | Compare `simpler/.github/workflows/ci.yml` `pytest examples tests/st --platform a2a3sim` with `scripts/run-simpler-l3-sim.sh` | Update script + Dockerfile header |

Note: No pypto, CANN, or ptoas — simpler-only sim image. Build context must include `scripts/run-simpler-l3-sim.sh` (build from this repo root).

### `Dockerfile.pypto-lib.sim.ubuntu22.04` — pypto-lib on `pypto3-hw-native-sys:sim`

| # | Check | Command | What to update if drifted |
|---|-------|---------|--------------------------|
| 1 | Base image (`pypto3-hw-native-sys:sim`) `PYPTO_COMMIT` drifted? | Run `Dockerfile.hw-native-sys.sim.ubuntu22.04` checks first; the pypto-lib sim image inherits from it | Rebuild base image, then rebuild this image |
| 2 | pypto-lib `origin/main` ahead of `PYPTO_LIB_COMMIT` example SHA in header? | `git -C /path/to/pypto-lib rev-parse origin/main` vs header `--build-arg PYPTO_LIB_COMMIT=` | Update build example comment in header |
| 3 | pypto-lib quick-check examples still valid? | Verify `examples/beginner/hello_world.py -p a2a3sim`, `examples/advanced/allreduce.py -p a2a3sim`, `models/deepseek/v4-flash/moe.py -p a2a3sim` exist in pypto-lib tree — model paths get renamed (pypto-lib #816 split `models/deepseek/v4/` into `v4-flash/` + `v4-pro/`) | Update header QUICK CHECKS comment |
| 4 | `pytest tests/golden -v` still the correct test command? | Check `pypto-lib/.claude/skills/test-with-golden/SKILL.md` | Update header test command |

Note: Pass-through image — no new build steps beyond `git clone pypto-lib`. All toolchain (pypto, ptoas, pto-isa) comes from the base image.

### `Dockerfile.pypto-lib.cann9.0` — pypto-lib on `pypto3-hw-native-sys:cann9`

| # | Check | Command | What to update if drifted |
|---|-------|---------|--------------------------|
| 1 | Base image (`pypto3-hw-native-sys:cann9`) `PYPTO_COMMIT` drifted? | Run `Dockerfile.hw-native-sys.cann9.0` checks first; the pypto-lib cann image inherits from it | Rebuild base image, then rebuild this image |
| 2 | pypto-lib `origin/main` ahead of `PYPTO_LIB_COMMIT` example SHA in header? | `git -C /path/to/pypto-lib rev-parse origin/main` vs header `--build-arg PYPTO_LIB_COMMIT=` | Update build example comment in header |
| 3 | pypto-lib quick-check examples still valid? | Verify `examples/beginner/hello_world.py -p a2a3 -d 0`, `examples/advanced/allreduce.py -p a2a3 -d 0,1` exist in pypto-lib tree | Update header QUICK CHECKS comment |
| 4 | `LD_PRELOAD` comment-only (no `ENV`)? | `grep LD_PRELOAD Dockerfile.pypto-lib.cann9.0` — should be comments only | Remove image-wide `ENV LD_PRELOAD` |
| 5 | `set_env.sh` not re-sourced? | Inherited from base image — already stripped there. If base image pattern changes, verify this image doesn't re-add it | Align with base image pattern |

Note: Pass-through image — no new build steps beyond `git clone pypto-lib`. All toolchain and HCCL env comes from the base image. HCCL collectives need `export LD_PRELOAD=${CANN_HOME}/aarch64-linux/lib64/libhccl.so` before running multi-card examples.

### `Dockerfile.pytorch-hccl-tests.cann9.0` — HCCL benchmarks only

| # | Check | Command | What to update if drifted |
|---|-------|---------|--------------------------|
| 1 | Fork `origin/master` ahead of `PT_HCCL_COMMIT`? | `git -C /path/to/pytorch-hccl-tests rev-list --count ${PT_HCCL_COMMIT}..origin/master` | `ARG PT_HCCL_COMMIT` |
| 2 | `ENV LD_PRELOAD` absent? | `grep LD_PRELOAD Dockerfile.pytorch-hccl-tests.cann9.0` — should be comments only | Remove image-wide `ENV LD_PRELOAD` |
| 3 | `set_env.sh` stripped, not re-added to bashrc? | `grep set_env Dockerfile.pytorch-hccl-tests.cann9.0` — strip `RUN` only, no bashrc append | Align strip `RUN` with hw-native-sys |
| 4 | Editable install (`pip uninstall` + `pip install -e .` after the make target)? | `grep -A1 'pip uninstall' Dockerfile.pytorch-hccl-tests.cann9.0` | Restore uninstall+editable so branch switches work — see below |

**Install contract:** `make ${PT_HCCL_INSTALL_TARGET}` does a non-editable `pip install .` (a flat copy into site-packages). That copy **shadows** a later `pip install -e .` on `sys.path`, so the image must `pip uninstall -y pytorch_hccl_tests` first, then `pip install -e .`. Without it, `git checkout <branch>` inside the container yields `ImportError` against the frozen copy. The build ends with `python -c "import pytorch_hccl_tests as p; print(p.__file__)"` — must print a path under `${PT_HCCL_DIR}`, not site-packages.

**Run recipes** (multi-device needs `--pid=host`; no `LD_PRELOAD`):

```bash
WORLD_SIZE=2 make bidirectional-bw DEVICE=npu   # bibw: point-to-point, exactly 2 ranks
WORLD_SIZE=8 make mbw-mr DEVICE=npu             # mbw_mr: world_size//2 concurrent pairs
```

As of `029e745b` the Makefile declares `export WORLD_SIZE ?= 2`, so a plain env prefix (`WORLD_SIZE=8 make mbw-mr`) is honoured. On older refs it was `export WORLD_SIZE = 2`, which shadows the env prefix — there you must pass it as a **make argument** (`make mbw-mr WORLD_SIZE=8`) or use `make -e`. Full debugging notes: `issue_pytorch_hccl_tests.md`.

### `Dockerfile.server.cann:9.0` — pypto dev workspace (host mount)

| # | Check | Command | What to update if drifted |
|---|-------|---------|--------------------------|
| 1 | pto-isa commit changed? | Same as hw-native-sys check #2 | The clone command inside the Dockerfile |
| 2 | PTOAS version/SHA256 changed? | Read `pypto/toolchain/versions.env` (same as hw-native-sys check #3) | `ARG PTOAS_VERSION` + `ARG PTOAS_SHA256` |
| 3 | pip deps changed in pypto CI Dockerfile? | Same as hw-native-sys check #4 | Update pip install RUN lines |

Note: pypto + simpler are mounted from host at runtime, not pinned in the Dockerfile. Only pto-isa and PTOAS are cloned/downloaded at build time.

### Quick bulk check (all Dockerfiles)

```bash
# Clone pypto, simpler, pypto-lib, and pytorch-hccl-tests if not already present
cd /tmp
git clone --depth 1 https://github.com/hw-native-sys/pypto.git 2>/dev/null || true
git clone --depth 1 https://github.com/hw-native-sys/simpler.git 2>/dev/null || true
git clone --depth 1 https://github.com/hw-native-sys/pypto-lib.git 2>/dev/null || true
git clone --depth 1 https://github.com/georgebisbas/pytorch-hccl-tests.git 2>/dev/null || true

# Run all checks at once (or use the MCP task: run_task pypto-docker dockerfile_sync)
cd ~/pypto-docker
echo "=== pypto origin/main ===" && git -C /tmp/pypto rev-parse --short HEAD
echo "=== simpler origin/main ===" && git -C /tmp/simpler rev-parse --short HEAD
echo "=== pypto-lib origin/main ===" && git -C /tmp/pypto-lib rev-parse --short HEAD
echo "=== pytorch-hccl-tests origin/master ===" && git -C /tmp/pytorch-hccl-tests rev-parse --short HEAD
echo "=== Current ARG SHAs ===" && rg '^ARG.*COMMIT=' Dockerfile.* && rg '^ARG PTOAS' Dockerfile.hw-native-sys.cann9.0 Dockerfile.hw-native-sys.sim.ubuntu22.04 Dockerfile.server.cann:9.0
echo "=== pto-isa (pypto pin) ===" && cat /tmp/pypto/runtime/pto_isa.pin 2>/dev/null || echo 'N/A'
echo "=== pto-isa (simpler pin) ===" && cat /tmp/simpler/pto_isa.pin
echo "=== PTOAS (toolchain/versions.env) ===" && grep -E '^(PTOAS_VERSION|PTOAS_SHA256)' /tmp/pypto/toolchain/versions.env
echo "=== pip deps (pypto CI Dockerfile) ===" && grep 'pip install' /tmp/pypto/.github/docker/github_ci.Dockerfile
```

---

## Build-time patterns

### 1. ARG-driven paths

Every path derives from two ARGs — never hardcoded:

```dockerfile
ARG CANN_VERSION=9.0.0
ARG INSTALL_PREFIX=/opt

ENV CANN_HOME=/usr/local/Ascend/cann-${CANN_VERSION}
ENV PYPTO_DIR=${INSTALL_PREFIX}/pypto \
    PTO_ISA_DIR=${INSTALL_PREFIX}/pto-isa \
    PTOAS_DIR=${INSTALL_PREFIX}/ptoas-bin
```

### 2. ARG scope resets after FROM

```dockerfile
ARG CANN_VERSION=9.0.0
FROM quay.io/ascend/cann:${CANN_VERSION}-910b-ubuntu22.04-py3.12
ARG CANN_VERSION=9.0.0          # ← re-declare after FROM
ARG INSTALL_PREFIX=/opt
```

### 3. Self-referencing ENV — split across multiple instructions

Docker does NOT expand `${VAR}` within the same ENV block. Split:

```dockerfile
ENV PYTHONPATH=/opt/pypto/runtime/python:/opt/pypto/runtime/examples/scripts
ENV PYTHONPATH=${PYTHONPATH}:/usr/local/Ascend/.../site-packages
ENV PYTHONPATH=${PYTHONPATH}:/usr/local/Ascend/.../opp/...
```

### 4. Build order (executable checklist)

```
[ ] 1. Clone source repos (pypto/simpler)
[ ] 2. Clone pto-isa (needed by simpler kernel compilation)
[ ] 3. Install PTOAS binary (needed by pypto tests; NOT needed by simpler-only)
[ ] 4. pip install scikit-build-core nanobind cmake ninja
[ ] 5. pip install numpy pytest torch (CPU, unversioned — matches CI)
[ ] 6. pip install --no-build-isolation ./runtime   ← simpler MUST be built before pypto
[ ] 7. pip install --no-build-isolation .[dev]       ← depends on simpler.task_interface
```

### 5. Simpler submodule (pypto's `runtime/`)

**Standalone image** — clone pypto, init submodules:

```dockerfile
RUN git clone --filter=blob:none https://github.com/hw-native-sys/pypto.git "${PYPTO_DIR}" && \
    git -C "${PYPTO_DIR}" checkout "${PYPTO_COMMIT}" && \
    for i in 1 2 3; do \
      git -C "${PYPTO_DIR}" submodule update --init --recursive && break || sleep 5; \
    done
```

**Server/dev image** — validate submodule exists on host:

```dockerfile
RUN test -f /workspace/hw-native-sys/pypto/runtime/pyproject.toml || \
  { echo 'BUILD ERROR: pypto/runtime/ missing. Run: git -C pypto submodule update --init --recursive'; exit 1; }
```

### 6. PTO-ISA clone (primary + fallback)

```dockerfile
RUN timeout 60 git clone https://github.com/hw-native-sys/pto-isa.git "${PTO_ISA_DIR}" \
      || { rm -rf "${PTO_ISA_DIR}"; timeout 300 git clone https://gitcode.com/luohuan40/pto-isa.git "${PTO_ISA_DIR}"; } && \
    git -C "${PTO_ISA_DIR}" checkout "${PTO_ISA_COMMIT}"
```

Auto-derive commit when not pinned via ARG:

```bash
# For pypto Dockerfiles:
PTO_ISA_COMMIT=$(tr -d '[:space:]' < runtime/pto_isa.pin)
# For simpler Dockerfiles:
PTO_ISA_COMMIT=$(tr -d '[:space:]' < pto_isa.pin)
```

### 7. Third-party fallback (libbacktrace, msgpack-c)

```dockerfile
RUN if [ ! -f 3rdparty/libbacktrace/configure.ac ]; then \
      rm -rf 3rdparty/libbacktrace && \
      git clone --depth 1 \
        https://github.com/ianlancetaylor/libbacktrace.git 3rdparty/libbacktrace; \
    fi && \
    if [ ! -f 3rdparty/msgpack-c/include/msgpack.hpp ]; then \
      rm -rf 3rdparty/msgpack-c && \
      git clone --depth 1 --branch cpp_master \
        https://github.com/msgpack/msgpack-c.git 3rdparty/msgpack-c; \
    fi
```

### 8. Python version

Use the CANN base image's Python. Do NOT install a different version.

### 9. Dockerfile types: standalone vs server/dev

| | Standalone (stdin) | Server/dev (context) |
|---|---|---|
| Build | `docker build -t img - < Dockerfile` | `docker build -t img -f Dockerfile .` |
| Source | `git clone` everything | `COPY` from host |
| Use case | CI, reproducible builds | Live editing, workspace mounts |

---

## Runtime patterns

### Docker run flags (all Ascend containers)

```bash
docker run --rm -it --privileged --ipc=host \
    -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro \
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
    -v /dev:/dev \
    <image>
```

Additional for HCCL / multi-device:

```bash
--pid=host --cap-add=SYS_PTRACE --security-opt seccomp=unconfined
```

### CANN mount rules

| Mount | OK? | Why |
|-------|-----|-----|
| `/usr/local/Ascend/driver` (ro) | ✅ | Kernel driver user-space libs |
| `/dev` | ✅ | NPU device files |
| `/usr/local/bin/npu-smi` (ro) | ✅ | Device management tool |
| `/usr/local/Ascend` (entire tree) | ❌ | Shadows image's CANN with host's |

### HCCL requirements

`--pid=host` is required because Ascend IPC validates host PIDs, not container PIDs.

`LD_PRELOAD=libhccl.so` is **NOT** set image-wide. Setting it as `ENV` or in `bashrc`
injects libhccl.so into every process including VS Code's server node → hang on attach.

- **pypto / simpler images:** set it manually in the shell before running HCCL tests:
- **pytorch-hccl-tests image:** `LD_PRELOAD` is not needed (torch HCCL path; no `host_runtime.so`).

```bash
export LD_PRELOAD=${CANN_HOME}/aarch64-linux/lib64/libhccl.so
```

→ See `../../pypto-tooling/debugging_skills/SKILL.md` → "`LD_PRELOAD=libhccl.so`" and "VS Code attach hang" for details.

### CANN environment

**Do NOT source `set_env.sh` from bashrc or any startup file.** The Ascend base
image already injects it into multiple startup files; if it runs during VS Code's
`userEnvProbe` it takes 10–30s → attach hangs. Strip it at build time:

```dockerfile
RUN for f in /etc/profile /etc/bash.bashrc /root/.profile /root/.bashrc /root/.bash_profile; do \
      [ -f "$f" ] && sed -i '/set_env\.sh/d' "$f" || true; \
    done && \
    for f in /etc/profile.d/*.sh; do \
      [ -f "$f" ] && sed -i '/set_env\.sh/d' "$f" || true; \
    done
```

All required CANN env vars (`ASCEND_HOME_PATH`, `LD_LIBRARY_PATH`, `PYTHONPATH`, etc.)
are set via `ENV` instructions — `set_env.sh` is not needed at runtime.

Unset stale `PTO2_RING_*` vars the host may leak in:

```dockerfile
RUN echo "unset PTO2_RING_HEAP PTO2_RING_TASK_WINDOW PTO2_RING_DEP_POOL 2>/dev/null || true" >> /etc/bash.bashrc
```

---

## Common failures

### Decision tree

```text
Error message contains...
├─ "WORKDIR: command not found"    → Trailing &&\ before WORKDIR
├─ "ChipBufferSpec"                → Stale simpler submodule
├─ "aclInit failed" / "aclrtSetDevice" → Missing --privileged or -v /dev:/dev
├─ "HcclGetRootInfo" / timeout 120s → HCCL network issue
├─ "507899" / "comm_alloc_windows"  → CANN/driver mismatch → ../../pypto-tooling/debugging_skills
├─ "COPY ... path not found"        → Using COPY in stdin build → use git clone
├─ "fatal error: 'tensor.h'"        → Wrong SIMPLER_ROOT
├─ "PTOAS SHA256 mismatch"          → CI bumped version → update ARGs
├─ "custom op ... unknown"          → PTOAS too old → update PTOAS_VERSION
├─ "cannot import name ..." from site-packages after checkout → non-editable copy shadows -e → issue_pytorch_hccl_tests
├─ "Unsupported data type at::kDouble" → fp64 reduce on HCCL → use float32 → issue_pytorch_hccl_tests
├─ WORLD_SIZE=N make ... ignored    → Makefile export shadows env → make arg / ?= → issue_pytorch_hccl_tests
└─ Segfault in comm_init + fork warn → ACL/HCCL + fork → use spawn/forkserver
```

### Symptom → fix table

| Symptom | Cause | Fix |
|---------|-------|-----|
| `WORKDIR: command not found` during build | Trailing `&& \` before WORKDIR | Terminate every RUN before WORKDIR |
| `ImportError: ChipBufferSpec` | Stale simpler submodule pin | `git -C runtime fetch origin main && git -C runtime checkout origin/main` |
| `aclInit` / `aclrtSetDevice` failed | Missing docker run flags | Add `--privileged -v /dev:/dev` |
| `HcclGetRootInfo` hangs (120s) | Wrong NIC / HCCL network | Try different device, check `HCCL_SOCKET_IFNAME` |
| `comm_alloc_windows` + **507899** | CANN 9.0 + driver < 26.0.rc1 | → ../../pypto-tooling/debugging_skills → "NPU error code reference" |
| segfault in `comm_init` + fork warning | ACL/HCCL loaded + multi-threaded fork | Use spawn/forkserver, avoid busy device 0 |
| `COPY` fails: "path not found" | Stdin build has no build context | Use `git clone` instead of `COPY` |
| `fatal error: 'tensor.h'` | Wrong `SIMPLER_ROOT` | Set to simpler source tree (`/opt/pypto/runtime`) |
| `ImportError: cannot import name 'X'` from `site-packages/...` after `git checkout` | Non-editable `pip install .` copy shadows `pip install -e .` | `pip uninstall -y <pkg> && pip install -e .`; verify `python -c "import <pkg> as p; print(p.__file__)"` is under the repo, not site-packages → `issue_pytorch_hccl_tests.md` |
| `WORLD_SIZE=N make ...` runs wrong rank count | Makefile `export VAR = n` shadows env prefix | Pass as make arg (`make t VAR=n`) or `make -e`; fix Makefile to `VAR ?= n` → `issue_pytorch_hccl_tests.md` |
| `HCCL reduce: Unsupported data type at::kDouble` (ERR02007) | fp64 `dist.reduce` unsupported on HCCL (works on gloo) | Reduce in `float32`; use only HCCL dtypes (int32/fp16/fp32/bf16) → `issue_pytorch_hccl_tests.md` |

For device health issues (dead NPUs, 507033): run `diagnose_npu.py` inside the container, or see `../../pypto-tooling/debugging_skills/SKILL.md`.

---

## Interactive debugging

```bash
# 1. Enter the image at the failing stage
docker run --rm -it <image> bash

# 2. Verify environment
env | sort
pip list | grep -i simpler
python -c "from simpler.task_interface import ChipBootstrapConfig"

# 3. Verify git checkouts
git -C /opt/pto-isa rev-parse --short HEAD
git -C /opt/pypto/runtime rev-parse --short HEAD

# 4. NPU health
python3 /opt/pypto/diagnose_npu.py   # if copied in
npu-smi info
```

## Quick reference: repo URLs

| Repo | URL | Notes |
|------|-----|-------|
| pypto | `github.com/hw-native-sys/pypto.git` | main repo |
| simpler | `github.com/hw-native-sys/simpler.git` | pypto submodule at `runtime/` |
| pto-isa | `github.com/hw-native-sys/pto-isa.git` | kernel ISA headers |
| pto-isa mirror | `gitcode.com/luohuan40/pto-isa.git` | fallback |
| PTOAS | `github.com/hw-native-sys/PTOAS/releases/download/${VER}/ptoas-bin-aarch64.tar.gz` | binary tarball |
| libbacktrace | `github.com/ianlancetaylor/libbacktrace.git` | upstream, default branch (pypto #2146 dropped the `Hzfengsy` fork + `macho-bundle-support` branch) |
| msgpack-c | `github.com/msgpack/msgpack-c.git` | `cpp_master` branch |

## See also

- `../../pypto-tooling/debugging_skills/SKILL.md` — NPU error codes, dead device diagnosis, Docker runtime tips, distributed bug recipes
- `diagnose_npu.py` — 10-point NPU health check (run inside container)
- `issue_pytorch_hccl_tests.md` — pytorch-hccl-tests benchmark image: editable-install shadow, WORLD_SIZE Makefile shadow, fp64 HCCL reduce crash
- `issue_0.md` — `comm_alloc_windows` / HCCL IPC driver mismatch
- `issue_vscode_summary.md` — VS Code attach hang (`set_env.sh` + `LD_PRELOAD`)
- `build_skills/` — build system debugging
