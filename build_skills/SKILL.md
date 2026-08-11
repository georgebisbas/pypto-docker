---
name: pypto-container-rebuild
description: >-
  Rebuild PyPTO pypto_core after branch pull in hw-native-sys Docker (/opt/pypto
  or mounted workspace). Use for slow or failed pip install, cmake/nanobind/ninja
  errors, or broken pypto.pypto_core imports (e.g. DataType).
---

# PyPTO container rebuild (pypto_core)

Use this skill when working **inside a running Docker container** after `git pull`,
`git checkout`, or `git reset` on PyPTO — not when building the image itself (see
[dockerfile_skills/SKILL.md](../dockerfile_skills/SKILL.md)).

The images and `scripts/` live in this repo; this skill covers the in-container pypto
rebuild workflow.

The hw-native-sys images pre-install PyPTO via `pip install --no-build-isolation`
at image build time. That install does **not** leave a reusable `build/CMakeCache.txt`
for arbitrary SHAs you check out later.

---

## When to rebuild

| Change | Rebuild? |
|--------|----------|
| `src/`, `include/`, `python/bindings/` (C++ / codegen) | **Yes** |
| Branch pull / `git reset` on codegen fixes | **Yes** |
| Python-only (`python/pypto/`, tests) | Optional if `.so` unchanged |
| Simpler runtime only (`runtime/`) | Rebuild runtime only (below) |

---

## Working directories

| Image | `cd` to |
|-------|---------|
| `Dockerfile.hw-native-sys.cann9.0` (standalone) | `/opt/pypto` |
| `Dockerfile.server.cann:9.0` (mounted workspace) | `/workspace/hw-native-sys/pypto` |

Use the **same** `python` / `pip` for configure and install (`which python3 pip`).

---

## Preferred path (after branch pull or C++ edit)

Aligns with image build in [Dockerfile.hw-native-sys.cann9.0](../Dockerfile.hw-native-sys.cann9.0):

```bash
cd /opt/pypto   # or /workspace/hw-native-sys/pypto

rm -rf build

pip install -e . --no-deps --no-build-isolation -v

python -c "import pypto.pypto_core as m; print(m.__file__, hasattr(m, 'DataType'))"
```

Expect a real `.so` path and `True` for `DataType`. If `__file__` is missing or
`unknown location`, the build failed or Python is loading a broken stub.

---

## Why `pip install -e ".[dev]"` feels forever

- PyPTO is a **large C++ extension** (scikit-build-core + CMake + Ninja, `RelWithDebInfo`).
- `[dev]` pulls extras (pytest, pyright, ruff, **clang-tidy**) — already in the image.
- First configure + compile can take many minutes on ARM / few cores.

For iteration in a pre-built image, prefer:

```bash
pip install -e . --no-deps --no-build-isolation -v
```

Use `".[dev]"` only when you need to (re)install dev tools on a bare machine.

---

## Incremental rebuild (after one successful pip install)

Once `build/CMakeCache.txt` exists with generator **Ninja**:

```bash
cmake --build build --target pypto_core -j"$(nproc)"
pip install -e . --no-deps --no-build-isolation
```

Quick pytest without refreshing site-packages (verify which `.so` loads):

```bash
export PYTHONPATH="$PWD/python:$PWD/build/python/bindings:$PYTHONPATH"
python -c "import pypto.pypto_core as m; print(m.__file__)"
pytest tests/st/distributed/test_l3_allreduce.py -v --platform=a2a3 --device=0,1 --forked
```

`__file__` should be under `build/python/bindings/`, not only `site-packages`.

---

## Manual CMake (optional)

Only if you must drive CMake yourself. **Always** use Ninja and nanobind’s CMake dir:

```bash
rm -rf build

cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -Dnanobind_DIR="$(python -c 'import nanobind; print(nanobind.cmake_dir())')"

cmake --build build --target pypto_core -j"$(nproc)"
pip install -e . --no-deps --no-build-isolation
```

If `import nanobind` fails:

```bash
pip install "nanobind>=2.0.0"
```

---

## Troubleshooting

| Symptom | Root cause | Fix |
|---------|------------|-----|
| `Error: not a CMake build directory (missing CMakeCache.txt)` | No configure yet after pull | Run preferred pip path above; do not `cmake --build` alone |
| `Could not find nanobind` (bare `cmake -B build`) | Manual cmake lacks scikit-build paths | Use pip path, or `-Dnanobind_DIR=...` (see above) |
| `ninja: error: Makefile:5: expected '=', got ':'` | **Makefile** cache + **Ninja** build (mixed generators) | `rm -rf build`, then pip install only |
| `gmake: Makefile: No such file or directory` | Incomplete / wrong generator cache | `rm -rf build`, then pip install |
| `ImportError: cannot import name 'DataType' from pypto.pypto_core` | Failed or partial install | `rm -rf build`, full pip reinstall, verify import |
| Stale codegen / missing passes after pull | Old `pypto_core.so` in site-packages | Rebuild; do not put `.../pypto/python` first on `PYTHONPATH` when testing the **image** install |

---

## Anti-patterns

- Running `cmake -B build` **without** `-G Ninja`, then `pip install -e` (pollutes `build/`).
- `cmake --build build` when `CMakeCache.txt` is missing.
- Full cold `pip install -e ".[dev]"` on every small C++ fix (use incremental path).
- Putting source `python/` ahead of site-packages when validating the **baked** image wheel.

---

## Simpler runtime only

If only `runtime/` (simpler submodule) changed:

```bash
cd /opt/pypto/runtime   # or .../pypto/runtime in server image
pip install --no-build-isolation .
```

PyPTO’s distributed tests import `simpler.task_interface`; rebuild simpler **before**
re-running dist ST if runtime APIs changed.

---

## Related docs

| Topic | Location |
|-------|----------|
| Image build order | [dockerfile_skills/SKILL.md](../dockerfile_skills/SKILL.md) |
| Vec tile alignment / dist ST | [debugging_skills/SKILL.md](../../pypto-tooling/debugging_skills/SKILL.md) |
| 910B runbook | [bz910b-reproduce.md](../../pypto-tooling/bz910b-reproduce.md) |
| PyPTO upstream testing | `pypto/.claude/skills/testing/SKILL.md` |
