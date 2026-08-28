# pypto-docker

Dockerfiles, image build scripts, and runtime guidance for the PyPTO / simpler /
pypto-lib / pytorch-hccl-tests stack on Ascend 910B (CANN images) and x86_64 simulation.

> Split out of the [`pypto-tooling`](../pypto-tooling/) umbrella. Construction knowledge and
> incident logs live in `dockerfile_skills/`; NPU/docker debugging in
> `../pypto-tooling/debugging_skills/`; the profiling harness in
> [`../pypto-profiling`](../pypto-profiling/); the MCP server in
> [`../mcp-hw-native-sys`](../mcp-hw-native-sys/).

## Repository Contents

- [README.md](README.md): Repository index and quick usage.
- [Dockerfile.hw-native-sys.cann9.0](Dockerfile.hw-native-sys.cann9.0): Standalone PyPTO image that clones all sources from GitHub at build time.
- [Dockerfile.server.cann:9.0](Dockerfile.server.cann:9.0): Server/dev image that uses a local pypto build context.
- [Dockerfile.simpler.cann9.0](Dockerfile.simpler.cann9.0): Standalone simpler image with pinned commit support and HCCL-safe runtime defaults.
- [Dockerfile.pytorch-hccl-tests.cann9.0](Dockerfile.pytorch-hccl-tests.cann9.0): Standalone HCCL micro-benchmark image (`torchrun` + pytorch-hccl-tests fork).
- [Dockerfile.hw-native-sys.sim.ubuntu22.04](Dockerfile.hw-native-sys.sim.ubuntu22.04): Standalone local simulation image for PyPTO (`a2a3sim`/`a5sim`) on x86_64 without NPU devices.
- [Dockerfile.simpler.sim.ubuntu22.04](Dockerfile.simpler.sim.ubuntu22.04): Standalone simpler-only simulation image (`a2a3sim`/`a5sim`) for L3 worker STs without pypto or CANN.
- [Dockerfile.pypto-lib.sim.ubuntu22.04](Dockerfile.pypto-lib.sim.ubuntu22.04): Thin layer on `pypto3-hw-native-sys:sim` with a baked `pypto-lib` checkout for example/model sim smoke tests.
- [Dockerfile.pypto-lib.cann9.0](Dockerfile.pypto-lib.cann9.0): Thin layer on `pypto3-hw-native-sys:cann9` with a baked `pypto-lib` checkout for onboard NPU model runs.
- [docker-entrypoint-cann.sh](docker-entrypoint-cann.sh): Runtime helper for workspace/runtime symlink handling.
- [scripts/](scripts/): Image build scripts (`build-npu-images.sh`, `build-sim-images.sh`, `build-npu-dev-images.sh`, `fetch-pull-mains.sh`, `run-simpler-l3-sim.sh`).

## Purpose of Each File

- [README.md](README.md): Top-level index of the repository, with build commands and runtime guidance.
- [Dockerfile.hw-native-sys.cann9.0](Dockerfile.hw-native-sys.cann9.0): Build a standalone PyPTO image by cloning repositories during build; best for reproducible CI-like setup without local source dependencies.
- [Dockerfile.server.cann:9.0](Dockerfile.server.cann:9.0): Build a server/dev image from a local hw-native-sys workspace where pypto is copied from build context; best for local iteration.
- [Dockerfile.simpler.cann9.0](Dockerfile.simpler.cann9.0): Build a standalone simpler-only image for runtime and worker validation when pypto is not required.
- [Dockerfile.pytorch-hccl-tests.cann9.0](Dockerfile.pytorch-hccl-tests.cann9.0): Build a standalone HCCL benchmark image for baseline latency/bandwidth/allreduce comparisons (not for pypto/simpler composite tests).
- [Dockerfile.hw-native-sys.sim.ubuntu22.04](Dockerfile.hw-native-sys.sim.ubuntu22.04): Build a standalone simulation-only PyPTO image for local development/testing on CPU-hosted simulators (`a2a3sim`, `a5sim`).
- [Dockerfile.simpler.sim.ubuntu22.04](Dockerfile.simpler.sim.ubuntu22.04): Build a standalone simpler-only simulation image for L3 worker/collective STs on `a2a3sim` without pypto or CANN.
- [Dockerfile.pypto-lib.sim.ubuntu22.04](Dockerfile.pypto-lib.sim.ubuntu22.04): Build a pypto-lib sim image (extends `pypto3-hw-native-sys:sim`) for example/model smoke tests on `a2a3sim`/`a5sim`.
- [Dockerfile.pypto-lib.cann9.0](Dockerfile.pypto-lib.cann9.0): Build a pypto-lib NPU image (extends `pypto3-hw-native-sys:cann9`) for onboard model runs on Ascend 910B.
- [docker-entrypoint-cann.sh](docker-entrypoint-cann.sh): Runtime helper script that normalizes runtime layout (workspace/runtime symlink behavior) before launching the container command.

## Recommended Image: `Dockerfile.hw-native-sys.cann9.0`

`Dockerfile.hw-native-sys.cann9.0` is now standalone:

- No local source checkout is required.
- Build works from any directory using stdin input.
- Repositories (`pypto`, `pto-isa`) are cloned during build.
- Key behavior is controlled via build args (`CANN_VERSION`, `INSTALL_PREFIX`, `PYPTO_COMMIT`, `PTO_ISA_COMMIT`).

## Build Commands

Build standalone hw-native-sys image (defaults):

```bash
docker build -t pypto3-hw-native-sys:cann9 - < Dockerfile.hw-native-sys.cann9.0
```

Build standalone hw-native-sys image (custom commit/pinning):

```bash
docker build \
  --build-arg PYPTO_COMMIT=28cf265e2ea20160631f78b9a36f6f8d29e6ab33 \
  --build-arg PTO_ISA_COMMIT=be5ccb765a4ce5d14ca5da8b0e2f182d7f003369 \
  -t pypto3-hw-native-sys:cann9 \
  - < Dockerfile.hw-native-sys.cann9.0
```

Build server/dev image (requires local pypto in build context):

```bash
docker build --no-cache -f "Dockerfile.server.cann:9.0" -t pypto3-dev-env:cann9 .
```

Build standalone simpler image (defaults):

```bash
docker build -t simpler-cann9 - < Dockerfile.simpler.cann9.0
```

Build standalone simpler image (custom commit/pinning):

```bash
docker build \
  --build-arg SIMPLER_COMMIT=89ba2a3f8373ec92b9f3c54f351dbaee66495c89 \
  --build-arg PTO_ISA_COMMIT=be5ccb765a4ce5d14ca5da8b0e2f182d7f003369 \
  -t simpler-cann9 \
  - < Dockerfile.simpler.cann9.0
```

Build standalone pytorch-hccl-tests image (defaults):

```bash
docker build -t pytorch-hccl-tests:cann9 - < Dockerfile.pytorch-hccl-tests.cann9.0
```

Build standalone pytorch-hccl-tests image (x86 host / custom ref):

```bash
docker build \
  --build-arg PT_HCCL_INSTALL_TARGET=install-npu-x86 \
  -t pytorch-hccl-tests:cann9 \
  - < Dockerfile.pytorch-hccl-tests.cann9.0
```

Build standalone local simulation image (no NPU required):

```bash
docker build -t pypto3-hw-native-sys:sim -f Dockerfile.hw-native-sys.sim.ubuntu22.04 .
```

Build standalone local simulation image (pinned commits):

```bash
docker build --build-arg PYPTO_COMMIT=28cf265e2ea20160631f78b9a36f6f8d29e6ab33 --build-arg PTO_ISA_COMMIT=be5ccb765a4ce5d14ca5da8b0e2f182d7f003369 -t pypto3-hw-native-sys:sim -f Dockerfile.hw-native-sys.sim.ubuntu22.04 .
```

Build standalone simpler simulation image (no NPU, no pypto):

```bash
docker build -t simpler-hw-native-sys:sim -f Dockerfile.simpler.sim.ubuntu22.04 .
```

Build standalone simpler simulation image (pinned commits):

```bash
docker build \
  --build-arg SIMPLER_COMMIT=89ba2a3f8373ec92b9f3c54f351dbaee66495c89 \
  --build-arg PTO_ISA_COMMIT=be5ccb765a4ce5d14ca5da8b0e2f182d7f003369 \
  -t simpler-hw-native-sys:sim \
  -f Dockerfile.simpler.sim.ubuntu22.04 .
```

Build pypto-lib simulation image (requires `pypto3-hw-native-sys:sim` base):

```bash
docker build -t pypto3-hw-native-sys:sim -f Dockerfile.hw-native-sys.sim.ubuntu22.04 .
docker build -t pypto-lib-hw-native-sys:sim -f Dockerfile.pypto-lib.sim.ubuntu22.04 .
```

Build pypto-lib simulation image (pinned pypto-lib commit):

```bash
docker build \
  --build-arg PYPTO_LIB_COMMIT=af1cc8b9e29dd7e0336f92a48d41fb536586d3df \
  -t pypto-lib-hw-native-sys:sim \
  -f Dockerfile.pypto-lib.sim.ubuntu22.04 .
```

Build pypto-lib NPU image (requires `pypto3-hw-native-sys:cann9` base):

```bash
docker build -t pypto3-hw-native-sys:cann9 - < Dockerfile.hw-native-sys.cann9.0
docker build -t pypto-lib-hw-native-sys:cann9 - < Dockerfile.pypto-lib.cann9.0
```

## Runtime Notes (Local Simulation)

This mode is for local CPU-hosted simulator workflows only (`a2a3sim`, `a5sim`):

```bash
docker run --rm -it pypto3-hw-native-sys:sim
```

Inside the container:

```bash
cd /opt/pypto
python -c "import pypto; print('pypto ok')"
which ptoas && ptoas --version

# Unit tests
pytest tests/ut -n auto --maxprocesses 8 -v

# Full ST matrix on simulators (long run)
pytest tests/st -v --forked --platform=a2a3sim,a5sim
```

Optional CI-aligned simulator subset:

```bash
pytest tests/st/runtime/ops/test_assemble.py tests/st/runtime/ops/test_mscatter.py tests/st/runtime/framework_and_models/test_qwen3_decode_scope3_mixed.py tests/st/runtime/control_flow/test_dyn_orch_shape.py::TestDynOrchShapeOperations::test_dyn_orch_paged_attention -v --platform=a5sim --forked -k "not TestMscatter"
pytest tests/st/runtime/cross_core/test_cross_core.py -v --forked --platform=a5sim
pytest tests/st/runtime/cross_core/test_cross_core.py -v --forked --platform=a2a3sim
```

Simulation image scope notes:

- No `--privileged`, no `/dev` mount, and no `/usr/local/Ascend/driver` mount are required.
- Do not use this image for onboard NPU execution (`a2a3`, `a5`); use the CANN-based Dockerfiles instead.

### Sim Dev Iteration Workflow (local code changes)

When iterating on C++/Python code changes, do **not** rebuild the image. Build it once, then bind-mount your workspace and reinstall:

```bash
# One-time: build the sim image (~15-30 min)
docker build -t pypto3-hw-native-sys:sim -f Dockerfile.hw-native-sys.sim.ubuntu22.04 .

# Every code change: mount workspace + pip install -e (~2-5 min)
docker run --rm \
  -v /home/gb4018/workspace/hw-native-sys/pypto:/opt/pypto \
  pypto3-hw-native-sys:sim \
  bash -c "pip install --no-build-isolation -e '/opt/pypto[dev]' 2>&1 | tail -1 && \
           pytest tests/ut/codegen/test_orchestration_codegen.py -v"

# Pre-commit checks (MUST run inside Docker — host may have root-owned cache):
docker run --rm \
  -v /home/gb4018/workspace/hw-native-sys/pypto:/opt/pypto \
  pypto3-hw-native-sys:sim \
  bash -c "ruff check ."

# Full unit test suite (before pushing):
docker run --rm \
  -v /home/gb4018/workspace/hw-native-sys/pypto:/opt/pypto \
  pypto3-hw-native-sys:sim \
  bash -c "pip install --no-build-isolation -e '/opt/pypto[dev]' 2>&1 | tail -1 && \
           pytest tests/ut -n auto --maxprocesses 8 -v"
```

Key rules:
- **Never rebuild the image for code changes** — `-v` mount + `pip install -e` is the iteration loop.
- **Always run ruff inside Docker** — the host `.ruff_cache` gets root-owned from previous Docker runs.
- **Test targeted suites first, then full suite before pushing.**

### Simpler-only simulation (`Dockerfile.simpler.sim.ubuntu22.04`)

```bash
docker run --rm -it --shm-size=4g simpler-hw-native-sys:sim
```

Inside the container:

```bash
cd /opt/simpler
python -c "import simpler; print('simpler ok')"

# L3 distributed/collective STs on a2a3sim (CI-aligned)
/opt/pypto-tooling/scripts/run-simpler-l3-sim.sh distributed
```

Use `--shm-size=4g` on `docker run` when running L3 tests (forked workers + torch shared memory exhaust default `/dev/shm`).

### pypto-lib simulation (`Dockerfile.pypto-lib.sim.ubuntu22.04`)

```bash
docker run --rm -it --shm-size=4g pypto-lib-hw-native-sys:sim
```

Inside the container:

```bash
cd /opt/pypto-lib
python examples/beginner/hello_world.py -p a2a3sim
python examples/advanced/allreduce.py -p a2a3sim
python models/deepseek/v4/moe.py -p a2a3sim
pytest tests/golden -v
```

Local branch iteration (mount both worktrees; reinstall pypto only when pypto sources change):

```bash
docker run --rm -it --shm-size=4g \
  -v /path/to/pypto:/opt/pypto \
  -v /path/to/pypto-lib:/opt/pypto-lib \
  pypto-lib-hw-native-sys:sim
# inside: pip install --no-build-isolation -e '/opt/pypto[dev]'
```

Distributed sim examples (`allreduce.py`, DeepSeek EP models) need `--shm-size=4g` at `docker run` time.

Local branch (mount workspace `simpler/`):

```bash
docker run --rm -it --shm-size=4g -v /path/to/simpler:/opt/simpler simpler-hw-native-sys:sim
# inside: pip install --no-build-isolation -e '.[test]'
#         /opt/pypto-tooling/scripts/run-simpler-l3-sim.sh distributed
```

## Runtime Notes (Ascend 910B)

Single-device / non-HCCL run:

```bash
docker run --rm -it \
  --privileged \
  --ipc=host \
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
  -v /dev:/dev \
  pypto3-hw-native-sys:cann9
```

Multi-device distributed / HCCL run (must include `--pid=host`):

```bash
docker run --rm -it \
  --privileged \
  --ipc=host \
  --pid=host \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
  -v /dev:/dev \
  pypto3-hw-native-sys:cann9
```

The same runtime rule applies to `simpler-cann9` and `pytorch-hccl-tests:cann9`: include `--pid=host` for distributed/HCCL workflows.

Before HCCL tests in **pypto** or **simpler** images, export `LD_PRELOAD` in your shell (not baked into the image):

```bash
export LD_PRELOAD=${CANN_HOME}/aarch64-linux/lib64/libhccl.so
```

The **pytorch-hccl-tests** image uses torch HCCL directly and does not need `LD_PRELOAD`; it still requires `--pid=host` for multi-rank NPU collectives.

Mount only the host driver path at runtime:

```text
/usr/local/Ascend/driver
```

Do not mount /usr/local/Ascend from host, because it can shadow the image's baked CANN version.

### HCCL Bandwidth Benchmarks (`pytorch-hccl-tests:cann9`)

OSU-style micro-benchmarks measuring HCCL bandwidth via `torch_npu` directly (no
pypto/simpler). Launch the container with the **multi-device / HCCL run** flags
above (`--pid=host` is mandatory). This image uses torch HCCL and does **not**
need `LD_PRELOAD`.

Sanity-check the runtime first:

```bash
cd /opt/pytorch-hccl-tests
npu-smi info                       # confirm visible chip count
python -c "import torch_npu, torch.distributed as dist; \
  print('torch_npu', torch_npu.__version__); print('hccl', dist.is_hccl_available())"
```

#### Bidirectional bandwidth (`bibw`)

Point-to-point bidirectional bandwidth between two ranks — each rank sends and
receives simultaneously, and the benchmark reports the **aggregate GB/s across
both directions**. It is a 2-rank test (enforced internally), so always use
`--nproc_per_node 2`:

```bash
# direct invocation
torchrun --nnodes 1 --nproc_per_node 2 \
  pytorch_hccl_tests/cli.py --benchmark bibw --device npu

# Makefile shortcut
make bidirectional-bw DEVICE=npu
```

Pin the exact pair of chips to measure a specific link (count must be 2):

```bash
ASCEND_RT_VISIBLE_DEVICES=0,1 torchrun --nnodes 1 --nproc_per_node 2 \
  pytorch_hccl_tests/cli.py --benchmark bibw --device npu
```

Results print per message size as `Size (B)  Bandwidth (GB/s)` and are also
written to a CSV in the working directory, e.g. `osu_bibw_gbps-npu-float16-2.csv`.

Tunables (all optional): `--dtype` (default `float16`; e.g. `float32`,
`bfloat16`), `--min` / `--max` to bound the message-size sweep in bytes,
`--skip` warmup iterations, `--iterations` timed iterations:

```bash
torchrun --nnodes 1 --nproc_per_node 2 \
  pytorch_hccl_tests/cli.py --benchmark bibw --device npu \
  --dtype float32 --min 1024 --max 4194304 --skip 10 --iterations 100
```

For the unidirectional counterpart use `--benchmark bandwidth` (Makefile:
`make bandwidth DEVICE=npu`); both are part of the `make p2p DEVICE=npu` suite.

#### Collective bandwidth (allreduce, allgather, ...)

Collective benchmarks scale with rank count — set `--nproc_per_node` to the
number of chips (start at 2, scale to your visible count):

```bash
torchrun --nnodes 1 --nproc_per_node 4 \
  pytorch_hccl_tests/cli.py --benchmark allreduce --device npu

# Makefile shortcut (canonical OSU-style API)
WORLD_SIZE=4 make allreduce DEVICE=npu
```

> **`WORLD_SIZE` caveat.** The env-prefix form above is the intended API, but it
> only takes effect if the Makefile declares `WORLD_SIZE ?= 2` (conditional).
> Older checkouts use `export WORLD_SIZE = 2`, which **shadows** the env prefix
> (it silently stays at 2) — there, pass it as a make argument instead:
> `make allreduce WORLD_SIZE=4 DEVICE=npu`, or use `make -e`. Fix tracked in
> huawei-csl/pytorch-hccl-tests PR #9.

Enumerate every benchmark and flag in the pinned build (`bibw`, `bandwidth`,
`latency`, `allreduce`, `allgather`, `alltoall`, `broadcast`, `reducescatter`,
`barrier`, ...):

```bash
python pytorch_hccl_tests/cli.py --help
```

A CPU smoke test (`--device cpu`) validates the harness without NPUs but does not
measure NPU bandwidth.

#### Multi-pair bandwidth (`mbw-mr`)

The container ships an **editable** checkout on `master`, so switching branches
takes effect with no reinstall. The multi-pair bandwidth / message-rate
benchmark currently lives on the `feat/osu-mbw-mr` branch (PR #9):

```bash
cd /opt/pytorch-hccl-tests
git checkout feat/osu-mbw-mr
WORLD_SIZE=8 make mbw-mr DEVICE=npu        # world_size//2 concurrent sender/receiver pairs
```

(See the `WORLD_SIZE` caveat above — if the checkout still uses `export
WORLD_SIZE = 2`, pass it as `make mbw-mr WORLD_SIZE=8 …` instead.)

Update this to plain `master` once PR #9 merges.