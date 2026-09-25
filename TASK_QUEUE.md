# Running pypto-docker containers under the NPU task queue (`task-submit`)

*Verified end-to-end on `192.168.150.11` (`hng-atlas01`, 8×910B2 / a2a3) with
`pypto3-hw-native-sys:cann9`, 2026-09-25. General CLI reference:
`../pypto-tooling/task-submit/task-submit.md` and the `taskqueue` repo, `docs/GUIDE.md`.*

**When this applies.** The shared NPU hosts run a per-card lock queue: `task-submit`
takes an exclusive lock on granted card(s), pins them via `ASCEND_RT_VISIBLE_DEVICES`
(re-indexed to `0` for your job) and only then runs your command. **Every NPU command
on a queue host — including tests run inside these containers — must go through it.**

| Where | Queue? |
|---|---|
| `192.168.150.11` (`hng-atlas01`) | ✅ mandatory |
| `192.168.150.12` | ✅ mandatory |
| `192.168.150.13` | ❌ none — use the plain recipes in [README.md](README.md) |
| Any host, `:sim` images | ❌ none — simulation needs no card |

---

## 0. TL;DR

```bash
# A. Build (no card needed; can run anywhere) — see README for full build docs
docker build -t pypto3-hw-native-sys:cann9 - < Dockerfile.hw-native-sys.cann9.0

# B. Create a container joined to the queue (run on the queue host)
docker run -d --name pypto-dev-queue \
  --privileged --ipc=host --pid=host \
  --cap-add=SYS_PTRACE --security-opt seccomp=unconfined \
  -v /dev:/dev \
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
  -v /var/lib/taskqueue:/var/lib/taskqueue \
  -v "$HOME:/mounted_home" \
  pypto3-hw-native-sys:cann9 sleep infinity
scripts/attach-taskqueue.sh pypto-dev-queue        # symlinks + verify

# C. Small test through the queue (from inside the container)
docker exec -it pypto-dev-queue bash
task-submit --device auto --max-time 1800 --timeout 0 \
  --run 'cd /opt/pypto && pytest tests/st/runtime/ops/test_vector_misc.py -v --platform=a2a3 --device=$TASK_DEVICE'

# D. Distributed (HCCL) test through the queue — 2 cards
task-submit --device auto --device-num 2 --max-time 3600 --timeout 0 \
  --run 'cd /opt/pypto && LD_PRELOAD=$CANN_HOME/aarch64-linux/lib64/libhccl.so \
         pytest tests/st/distributed/collectives/test_l3_allreduce.py::TestL3AllReduce::test_allreduce[2] \
         -v --device=$TASK_DEVICE'
```

---

## 1. What needs to change vs. the README recipes

The **Dockerfiles need no changes** — they are already queue-compatible (no
`ASCEND_RT_VISIBLE_DEVICES`, no image-wide `LD_PRELOAD`, no `set_env.sh` auto-sourcing).
What changes is the **launch layer**:

| # | Change | Where |
|---|--------|-------|
| 1 | Bind-mount the shared queue volume at the **same path as the host** | `docker run`: add `-v /var/lib/taskqueue:/var/lib/taskqueue` (real bind-mount; never overlay/tmpfs) |
| 2 | Expose the queue tools inside the container | one-time symlinks — `scripts/attach-taskqueue.sh <container>` |
| 3 | Confirm the join | `docker exec <container> task-submit --list` |
| 4 | Wrap NPU commands in `task-submit --device auto … --run '…'`, using `$TASK_DEVICE` | inside the container (§4), or on the host for one-shot runs (§6) |
| 5 | Scope `LD_PRELOAD` to the **job command**, not the client shell | `--run 'LD_PRELOAD=… pytest …'` — see pitfall **P1** |
| 6 | Keep `--pid=host` at `docker run` for HCCL/distributed (already in the README recipes) | `docker run` |

**Do not:** bake `ASCEND_RT_VISIBLE_DEVICES` / `TASK_DEVICE` into an image; `export
LD_PRELOAD` before `task-submit`; nest `task-submit` inside a task; run the broker; or run
NVIDIA-style "pick a free card by hand" commands on a queue host.

---

## 2. Build

Unchanged by the queue, and needs no card:

```bash
docker build -t pypto3-hw-native-sys:cann9 - < Dockerfile.hw-native-sys.cann9.0
docker build -t simpler-cann9 - < Dockerfile.simpler.cann9.0
# personal dev layer (needs scripts/dev-identity.env — see README § Personal Dev Setup):
docker build -t pypto3-dev:cann9 - < Dockerfile.hw-native-sys.dev.cann9.0
```

(Pin commits per `Dockerfile.*` headers if you need a specific `PYPTO_COMMIT`/`PTOAS_VERSION`.)

## 3. Create + join a container (verified recipe)

```bash
docker run -d --name pypto-dev-queue \
  --privileged --ipc=host --pid=host \
  --cap-add=SYS_PTRACE --security-opt seccomp=unconfined \
  -v /dev:/dev \
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
  -v /var/lib/taskqueue:/var/lib/taskqueue \
  -v "$HOME:/mounted_home" \
  pypto3-hw-native-sys:cann9 sleep infinity
```

Why each queue-relevant flag:

- `-v /var/lib/taskqueue:/var/lib/taskqueue` — **the** shared queue volume (spool + locks +
  client). It must be the same path/inode as the host's, or the container cannot coordinate
  with the host's broker at all.
- `--privileged` (or explicit `--device /dev/davinciN`) — NPU device access.
- `--pid=host` — required for HCCL / multi-rank runs (Ascend IPC validates host PIDs).
- `--cap-add=SYS_PTRACE --security-opt seccomp=unconfined` — the repo's standard HCCL set.
- `-v "$HOME:/mounted_home"` — your scripts/workspaces, so `--run` can call them
  (`/mounted_home/...` inside the container).

Join (idempotent; or `scripts/attach-taskqueue.sh pypto-dev-queue`):

```bash
docker exec pypto-dev-queue bash -lc '
  ln -sf /var/lib/taskqueue/bin/task-submit /usr/local/bin/task-submit
  ln -sf /var/lib/taskqueue/bin/npu-lock    /usr/local/bin/npu-lock
  ln -sf /var/lib/taskqueue/taskqueue.conf  /etc/taskqueue.conf'
docker exec pypto-dev-queue task-submit --list
```

Expected output (shape):

```text
=== Device occupancy (x/8) ===
  in use [0,1,2,3] → someuser
  free [4,5,6,7]
```

> A bind-mount **cannot** be added to a live container — if the queue volume is missing,
> recreate the container (keeping its flags/mounts). Nothing else needs `docker exec` at
> runtime: the client runs in place, as the caller.

## 4. Run tests through the queue (verified)

From inside the container (`docker exec -it pypto-dev-queue bash`):

```bash
cd /opt/pypto
task-submit --device auto --max-time 1800 --timeout 0 \
  --run 'pytest tests/st/runtime/ops/test_vector_misc.py::TestVectorMisc::test_tile_muls[16x16] \
         -v --platform=a2a3 --device=$TASK_DEVICE'
```

Observed (verified): `[npu-lock] acquired lock on device 0` → `1 passed in 15.37s` →
`[npu-lock] released lock on device 0` → `=== task completed (exit=0) ===`.

Rules that matter in `--run`:

- **Use `$TASK_DEVICE`** (single quotes so it expands at run time). It is the *logical*
  id — always `0`, or `0,1,…` for multi-card. Aside from being correct, its presence
  suppresses the client's **auto-append** of `--device <id>` to plain commands: without
  it, `--run 'bash myscript.sh'` becomes `bash myscript.sh --device 0` and a script that
  parses `$1` gets `--device` instead. Scripts should read the env var `TASK_DEVICE`,
  not positional args.
- `--max-time` is the **kill deadline** (default 300 s, **hard cap 3600 s**); `--timeout`
  only bounds how long the client waits (`0` = forever). Split anything longer than an hour.
- **Do not nest `task-submit`** inside an already-submitted task (rejected by design).
- Extra outputs: `--status`, `--log`, `--watch`, `--kill <task-id>`;
  `task-submit --list` shows occupancy + recent history.

### Script-from-mount pattern (recommended for anything non-trivial)

Keep the command in a script under `/mounted_home` and pass `$TASK_DEVICE` in:

```bash
docker exec pypto-dev-queue task-submit --device auto --max-time 1800 --timeout 0 \
  --run 'bash /mounted_home/pypto-docker-scripts/my-test.sh $TASK_DEVICE'
```

(`scripts/queue-smoke.sh` in this repo is a ready example: it runs one a2a3 ST case and
prints the granted ids.)

## 5. Distributed / HCCL tests through the queue (verified)

Requirements, in addition to §3's flags:

1. `--pid=host` **at `docker run`** (already in the recipe).
2. Preload `libhccl.so` **inside the `--run` string** (see pitfall P1 for why not in the shell):

   `LD_PRELOAD=$CANN_HOME/aarch64-linux/lib64/libhccl.so` (path is baked in the image;
   `${CANN_HOME}` expands at job-run time too).
3. Grant exactly as many cards as the test needs: `--device num N` → `$TASK_DEVICE="0,1,…"`.

Verified — 2-card L3 allreduce:

```bash
task-submit --device auto --device-num 2 --max-time 3600 --timeout 0 \
  --run 'cd /opt/pypto && LD_PRELOAD=$CANN_HOME/aarch64-linux/lib64/libhccl.so \
         pytest tests/st/distributed/collectives/test_l3_allreduce.py::TestL3AllReduce::test_allreduce[2] \
         -v --device=$TASK_DEVICE'
```

Observed: locks acquired on **0 and 1** → `1 passed, 2 warnings in 38.96s` → locks released.

Verified — 4-card case of the same file (separate grant, because the case needs exactly 4):

```bash
task-submit --device auto --device-num 4 --max-time 3600 --timeout 0 \
  --run 'cd /opt/pypto && LD_PRELOAD=$CANN_HOME/aarch64-linux/lib64/libhccl.so \
         pytest tests/st/distributed/collectives/test_l3_allreduce.py::TestL3AllReduce::test_allreduce[4] \
         -v --device=$TASK_DEVICE'
```

Observed: locks on **1,2,3,4** → `1 passed, 4 warnings in 44.89s`.

Full suite — split to stay under the 3600 s cap (CI parity):

```bash
task-submit --device auto --device-num 4 --max-time 3600 --timeout 0 \
  --run 'cd /opt/pypto && LD_PRELOAD=$CANN_HOME/aarch64-linux/lib64/libhccl.so \
         pytest tests/st/distributed -v --device=$TASK_DEVICE \
         --ignore=tests/st/distributed/collectives --ignore=tests/st/distributed/test_l2_multi_orch.py'

task-submit --device auto --device-num 4 --max-time 3600 --timeout 0 \
  --run 'cd /opt/pypto && LD_PRELOAD=$CANN_HOME/aarch64-linux/lib64/libhccl.so \
         pytest tests/st/distributed/collectives -v --device=$TASK_DEVICE'
```

> Platform note: STs are gated by `@pytest.mark.platforms(...)`. A test that does not
> declare your `--platform` (e.g. `-platform a2a3`) is **deselected** — pytest exits **5**
> with "N deselected / 0 selected". Confirm with `--collect-only` before assuming a failure.

## 6. One-shot runs from the host (no long-lived container) (verified)

You can also keep the container ephemeral and run the whole thing from the host — useful
for CI-style invocations. The host needs the client (`export PATH="$PATH:/var/lib/taskqueue/bin"`,
`export TASKQUEUE_CONF=/var/lib/taskqueue/taskqueue.conf`), then:

```bash
task-submit --device auto --max-time 600 --timeout 0 --run 'docker run --rm \
    --privileged --ipc=host --pid=host \
    --cap-add=SYS_PTRACE --security-opt seccomp=unconfined \
    -v /dev:/dev \
    -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro \
    -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
    -e ASCEND_RT_VISIBLE_DEVICES \
    pypto3-hw-native-sys:cann9 \
    bash -lc "cd /opt/pypto && pytest tests/st/runtime/ops/test_vector_misc.py::TestVectorMisc::test_tile_muls[16x16] -v --platform=a2a3 --device=$TASK_DEVICE"'
```

Key details:

- **`-e ASCEND_RT_VISIBLE_DEVICES` (bare) is mandatory** — it forwards the value the queue
  already put in the job environment into the container. Without it the container's CANN
  sees all cards and your job is **not pinned** to the locked one.
- `$TASK_DEVICE` (logical, e.g. `0`) is expanded by the task's shell before `docker run`
  sees it; the container then runs the test on logical device 0.
- Observed (verified): `[npu-lock] acquired lock on device 1` → container reports
  `ASCEND_RT_VISIBLE_DEVICES=1` → `1 passed in 15.61s` → `completed (exit=0)`.
- Reminder: don't set/override `ASCEND_RT_VISIBLE_DEVICES` yourself anywhere — the bare
  `-e` forward above is the one allowed use (it carries the queue's own value inward).

## 7. Pitfalls

**P1 — never `export LD_PRELOAD=libhccl.so` in the client's environment.**
`export LD_PRELOAD=… ; task-submit …` kills the task instantly: `completed (exit=137)`, no
task log/script on disk, and the broker log shows `granting: … (device=)` followed by
`reconcile: … dead (task lock free)`. It reproduces even with `--no-device`, while a
harmless lib (`libm`) preload works — so it is libhccl-specific. **Fix:** scope the preload
to the job command: `--run 'LD_PRELOAD=… pytest …'` (verified working; see §5).

**P2 — auto-appended `--device`.** With `--device auto`, the client appends `--device <id>`
to a command that does not already mention the device (`$TASK_DEVICE` / `{}` / `--device` /
`-d N` / a compound operator). Always reference `$TASK_DEVICE` in `--run` (see §4).

**P3 — `set -o pipefail` + early-exit pipelines.** `npu-smi info | head` SIGPIPEs npu-smi
(exit 141) and a `pipefail` script dies before the tests run. Capture to a file first.

**P4 — wrong platform = deselection, exit 5** (see the note at the end of §5).

**P5 — `--timeout` ≠ `--max-time`.** A job with `--timeout 1800` and no `--max-time` is
killed at 300 s. The 3600 s cap is a hard limit; split longer work.

**P6 — nesting is rejected.** One `task-submit` per job; wrap the whole script/loop.

**P7 — `--device N` outside your reserved set is rejected.** Use `--device auto`
(`--device auto --device-num N` for multiple cards).

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `task-submit: command not found` (in container) | Container not joined | §3 symlinks (`scripts/attach-taskqueue.sh`); check the queue volume is mounted |
| `--list` fails / jobs never start | Queue volume not the same path/inode | Recreate the container with `-v /var/lib/taskqueue:/var/lib/taskqueue` |
| Task `completed (exit=137)` instantly, no log | `LD_PRELOAD` in the client env | P1 — scope the preload into `--run` |
| Job stuck `pending` | No free card / asked for more than available | `task-submit --list`; reduce `--device-num` |
| `card(s) N are not in your reserved set` | Explicit card outside the whitelist | `--device auto` |
| SIGSEGV on `comm_init` (HCCL) | Missing `--pid=host` at `docker run`, or no preload | Add `--pid=host`; preload **inside** `--run` |
| `aclInit` / `aclrtSetDevice` failed | Missing device/driver mounts | Add `--privileged` + driver/npu-smi mounts (README recipes) |
| pytest exit 5, "0 selected" | Platform deselection | Add the right `--platform=` (P4) |
| Run numbers look noisy | Collected while another job runs on other cards | Expected on a shared box; the lock protects your card, not the host's bandwidth. Keep to your granted cards |

## 9. Housekeeping

- `task-submit --list` — occupancy + pending/running/recent-done; `--devices` — card whitelist.
- `--clean [--days N] [--done-days M]` prunes **everyone's** logs/metadata on the shared
  volume (defaults 1 / 7 days) — coordinate before running it by hand.
- Device logs are isolated per task automatically (`ASCEND_PROCESS_LOG_PATH`), so a failed
  run's log is where `--log`/`--watch` say it is.
