# Task-queue admin note — `hng-atlas02` (192.168.150.12)

*Verified against the live queue on 2026-09-28. Companion to [TASK_QUEUE.md](TASK_QUEUE.md),
which covers normal queue usage; this note is for the admin and covers two host-specific
actions: **(1) opening all 8 cards to users** and **(2) fixing the broker's health probe**.*

---

## 1. Findings

1. **The broker-side pool is already all 8 cards.** The `tq-broker` container runs with
   `TASKQUEUE_WHITELIST=0,1,2,3,4,5,6,7`.
2. **Only the client-side file blocks cards 4–7.** `/var/lib/taskqueue/available_devices`
   (root-owned, mode 644) contains `0,1,2,3`. `task-submit` checks it locally and rejects
   `--device 4..7` with *"card(s) 4 are not in your reserved set"*; `--list` shows `(x/4)`;
   `--device-num` larger than the list is refused up front.
   - Whitelist precedence in the broker (`bin/task-broker`, `load_runtime_devices`):
     `TASKQUEUE_WHITELIST` env → `/var/lib/taskqueue/available_devices` → `AVAILABLE_DEVICES`
     env → auto-detect `/dev/davinci*`. When the env is set, the broker ignores the shared
     file (and `--devices` SIGHUP is inert) — that is the secure boundary for shared hosts.
3. **The health probe is blind.** `tq-broker` is `ubuntu:24.04`, unprivileged, and mounts
   only the queue volume — no `npu-smi`, no `/dev/davinci*`, no `/usr/local/Ascend/driver`.
   Every probe logs `health probe: unhealthy/unreachable cards: 0..7 (healthy: none)`
   (every 12 h; `device_health` stays empty). Non-fatal today (empty healthy-set ⇒
   preference disabled) but auto-assignment cannot demote genuinely bad cards.
4. The host has **no** `/etc/taskqueue.conf`; root invocations must pass
   `TASKQUEUE_CONF=/var/lib/taskqueue/taskqueue.conf`.

## 2. Action 1 — align the client whitelist (unblocks cards 4–7)

Preferred (no stray signals):

```bash
sudo sh -c 'echo "0,1,2,3,4,5,6,7" > /var/lib/taskqueue/available_devices && chmod 644 /var/lib/taskqueue/available_devices'
```

Canonical client form (identical result; prints a confirmation, but tries to SIGHUP the
recorded broker PID — in container mode that is `1`, the container-namespace PID, so the
signal hits host init harmlessly; the broker's pool comes from the env anyway):

```bash
sudo env TASKQUEUE_CONF=/var/lib/taskqueue/taskqueue.conf \
  /var/lib/taskqueue/bin/task-submit --devices "0,1,2,3,4,5,6,7"
```

Verify:

```bash
cat /var/lib/taskqueue/available_devices    # → 0,1,2,3,4,5,6,7
task-submit --devices                       # → Current available-device whitelist: 0,1,2,3,4,5,6,7
task-submit --list                          # → Device occupancy (0/8) · all free [0,1,2,3,4,5,6,7]
```

Users can run on cards 4–7 immediately after this step — **no broker change required**.

## 3. Action 2 — fix the broker health probe (recommended)

Recreate the broker container with NPU access (same mounts as the dev-container recipe in
[TASK_QUEUE.md](TASK_QUEUE.md) §3), keeping the env vars:

```bash
docker rm -f tq-broker
docker run -d --name tq-broker --restart unless-stopped \
  -e TASKQUEUE_WHITELIST=0,1,2,3,4,5,6,7 \
  -e TASKQUEUE_CONF=/var/lib/taskqueue/taskqueue.conf \
  --privileged \
  -v /dev:/dev \
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
  -v /var/lib/taskqueue:/var/lib/taskqueue \
  ubuntu:24.04 /var/lib/taskqueue/bin/task-broker
```

Notes:

- **Keep `TASKQUEUE_WHITELIST`** — it is the secure boundary; without it the broker falls
  back to the shared file, which any user who is root inside their own container can rewrite.
- `docker rm -f` does **not** kill running tasks: each task supervisor holds its own flock
  and the broker reclaims only flock-free tasks; the pending spool survives. Scheduling
  pauses only for the container swap (~seconds). The `broker.lock` flock guard prevents a
  double broker.
- Optional: `-e HEALTH_PROBE_INTERVAL=1800` for a 30-minute probe cadence (default 12 h;
  a probe also runs immediately at startup).

Verify:

```bash
docker exec tq-broker npu-smi info | head -6
grep -E 'LOCKED|started|health probe' /var/lib/taskqueue/taskqueue.log | tail -5
cat /var/lib/taskqueue/device_health       # → 0,1,2,3,4,5,6,7
```

## 4. End-to-end verification (as a normal user)

```bash
export PATH="$PATH:/var/lib/taskqueue/bin"; export TASKQUEUE_CONF=/var/lib/taskqueue/taskqueue.conf
for d in 4 5 6 7; do
  task-submit --device $d --timeout 60 --max-time 60 \
    --run 'echo card=$TASK_DEVICE visible=$ASCEND_RT_VISIBLE_DEVICES; npu-smi info -t usages -i 0 | grep -E "HBM Usage"'
done
task-submit --device auto --device-num 2 --timeout 60 --max-time 60 --run 'echo got=$TASK_DEVICE'
```

Happy path prints `[npu-lock] acquired lock on device N` → output → `released` → `exit=0`.
`$TASK_DEVICE` is the logical id (`0` for a single-card grant); `ASCEND_RT_VISIBLE_DEVICES`
carries the granted physical card.

## 5. Rollback

- Re-restrict clients: `sudo sh -c 'echo "0,1,2,3" > /var/lib/taskqueue/available_devices'`
- Revert the broker container if needed (old form mounts only the queue volume; the probe
  stays blind).

## 6. Operational notes

- Keep the two whitelist sources in sync: `TASKQUEUE_WHITELIST` (broker, authoritative) and
  `available_devices` (client checks + `--list` display).
- With env mode active, whitelist changes = edit env + recreate the container; the file
  needs no reload.
- If file-driven mode is ever adopted: reload the broker with
  `docker kill --signal=HUP tq-broker` (or
  `kill -HUP $(docker inspect -f '{{.State.Pid}}' tq-broker)`), **not** the client's
  auto-notify — `task-broker.pid` holds the container-namespace PID (`1`).
- `MAX_CONCURRENT=8` in `taskqueue.conf` already matches an 8-card pool.
- Before expanding, confirm cards 4–7 are not earmarked for another workload (the
  `0,1,2,3` file may have been deliberate; the broker env suggests otherwise).

## 7. Verified state at time of writing

- Queue idle; all client-visible cards free; smoke tasks `exit=0`.
- Per-card grants verified on cards 0–3 (`--device 0..3`); rejection verified for 4–7
  (client-side).
- Health log shows `healthy: none` on every probe since 2026-09-24 (see §3).
