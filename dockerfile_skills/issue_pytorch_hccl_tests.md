**Issue: `pytorch-hccl-tests:cann9` benchmark image — three failure modes hit while running OSU bandwidth benchmarks on NPU**

This documents three independent traps encountered running `Dockerfile.pytorch-hccl-tests.cann9.0` (OSU-style HCCL micro-benchmarks via `torchrun`). All three are "green on CPU/gloo or in the build, broken at runtime on NPU / after a branch switch" — the worst kind to debug blind.

---

**Environment**

| Component | Value |
|---|---|
| Image | `pytorch-hccl-tests:cann9` (`Dockerfile.pytorch-hccl-tests.cann9.0`) |
| Repo | `georgebisbas/pytorch-hccl-tests` (upstream `huawei-csl/pytorch-hccl-tests`) |
| Package | `pytorch_hccl_tests` — flat layout, installed into a py3.10 venv at `/opt/venvs/pytorch-hccl-tests` |
| Backend | `torch-npu==2.9.0` (cp310-only wheels → py3.10 venv), HCCL |
| Run flags | `--privileged --ipc=host --pid=host` (mandatory); **no** `LD_PRELOAD` |

---

## 1. ImportError after `git checkout <branch>` — editable-install shadow

**Symptom**

After `git checkout feat/osu-mbw-mr` inside the container, **every** benchmark fails at import:

```
ImportError: cannot import name 'mbw_mr' from 'pytorch_hccl_tests.osu.p2p'
  (/opt/venvs/pytorch-hccl-tests/lib/python3.10/site-packages/pytorch_hccl_tests/osu/p2p/__init__.py)
```

Note the path: the import resolves from **site-packages**, not the working tree.

**Root cause**

The image runs the upstream `make ${PT_HCCL_INSTALL_TARGET}` (`install-npu-arm`), whose recipe is `pip install --force-reinstall torch-npu==2.9.0` + `pip install .`. The `pip install .` drops a **flat copy** of the `pytorch_hccl_tests/` package into site-packages. A later `pip install -e .` does **not** remove that copy, and because the package is run as a script (`torchrun pytorch_hccl_tests/cli.py`, so `sys.path[0]` is the package's *own* dir, not the repo root), the top-level `import pytorch_hccl_tests` resolves the **site-packages copy** — which is frozen at the build-time `master` commit and lacks `mbw_mr`. Switching branches changes the working tree but not the shadowing copy, so it breaks every benchmark (the import is at the top of `cli.py`).

**Fix** (baked into the Dockerfile venv RUN)

Uninstall the copy, *then* install editable:

```dockerfile
make "${PT_HCCL_INSTALL_TARGET}" && \
pip uninstall -y pytorch_hccl_tests && \
pip install -e . && \
python -c "import pytorch_hccl_tests as p; print('pytorch_hccl_tests ok', p.__file__)"
```

The final import is a build-time sanity check: the path **must** be under `/opt/pytorch-hccl-tests/...`, not `site-packages`.

**Repro / diagnostic**

```bash
# Is the working tree authoritative, or is a copy shadowing it?
python -c "import pytorch_hccl_tests as p; print(p.__file__)"
#   editable (good): /opt/pytorch-hccl-tests/pytorch_hccl_tests/__init__.py
#   shadowed (bad):  /opt/venvs/.../site-packages/pytorch_hccl_tests/__init__.py
```

Unblock an already-running (old) container without rebuild:

```bash
pip uninstall -y pytorch_hccl_tests && pip install -e .
# or sidestep entirely:
PYTHONPATH=/opt/pytorch-hccl-tests WORLD_SIZE=8 make mbw-mr DEVICE=npu
```

---

## 2. `WORLD_SIZE=N make ...` silently ignored — Makefile shadows the env

**Symptom**

`WORLD_SIZE=8 make mbw-mr DEVICE=npu` runs only 2 ranks; the echoed `torchrun` line shows `--nproc_per_node 2`.

**Root cause**

The Makefile declares `export WORLD_SIZE = 2`. In GNU make, a variable **assigned in the Makefile beats an environment variable** (unless `-e` or a command-line override is used). So the `WORLD_SIZE=8` env prefix is shadowed. (`DEVICE=npu` worked only because it was passed *after* `make`, i.e. as a command-line argument, which does win.)

**Fix**

Upstream Makefile: `export WORLD_SIZE ?= 2` (conditional — an env var counts as already-set). Fixed on `feat/osu-mbw-mr`. Until a checkout has it, override per-invocation:

```bash
make mbw-mr WORLD_SIZE=8 DEVICE=npu     # command-line arg (always wins)
make -e mbw-mr WORLD_SIZE=8 DEVICE=npu  # or force env precedence
```

**Repro / diagnostic**

```bash
make -n mbw-mr WORLD_SIZE=8 DEVICE=npu   # dry-run; inspect the echoed --nproc_per_node
```

---

## 3. HCCL crash on `float64` reduce — `at::kDouble` unsupported

**Symptom**

On NPU (passes on CPU/gloo):

```
RuntimeError: HCCL reduce: Unsupported data type at::kDouble
[ERROR] ... ERR02007 DIST feature not supported
```

**Root cause**

`osu_mbw_mr` reduced its per-pair timing sum as a `torch.float64` tensor: `dist.reduce(torch.tensor(local_t_sec, dtype=torch.float64), ...)`. Ascend HCCL supports int32 / fp16 / fp32 / bf16 reductions but **not fp64/double**. CPU/gloo supports fp64, so it only surfaced on hardware.

**Fix**

Reduce in `float32` — a sum of per-rank seconds needs no double precision:

```python
t_sum = torch.tensor(local_t_sec, dtype=torch.float32).to(device)
dist.reduce(t_sum, 0, op=dist.ReduceOp.SUM)
```

Fixed on `feat/osu-mbw-mr` (`a5ae7a5`).

**General rule:** any `dist.{reduce,all_reduce,reduce_scatter}` on HCCL must use a HCCL-supported dtype. fp64 tensors that work on gloo will crash on NPU.

---

## Durable facts (pytorch-hccl-tests)

- `bibw` and `bw` are **point-to-point, exactly 2 ranks** (`Utils.check_numprocs(..., limit=2)`); `--nproc_per_node 2` always.
- `mbw_mr` is multi-pair: `world_size // 2` concurrent sender/receiver pairs; scale via `WORLD_SIZE`.
- Benchmark switcher keys use underscores (`--benchmark mbw_mr`); Makefile targets use hyphens (`make mbw-mr`).
- The image needs `--pid=host` for multi-rank collectives and does **not** use `LD_PRELOAD` (torch-npu's own HCCL, not `host_runtime.so`).
- torch-npu 2.9.0 ships cp310 wheels only → the venv is Python 3.10 even though the base image is py3.12.

## Cross-references

- Upstream PR #9 (`osu_mbw_mr` multi-pair bandwidth) — fixes #2 and #3 landed on `feat/osu-mbw-mr` (`a5ae7a5`).
- Fix #1 lives in `Dockerfile.pytorch-hccl-tests.cann9.0` (uninstall + `pip install -e .`).
- See `SKILL.md` → "Dockerfile.pytorch-hccl-tests.cann9.0" and the Symptom → fix table.
