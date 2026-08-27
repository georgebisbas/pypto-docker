#!/usr/bin/env bash
# Check whether every Dockerfile in this repo pins the latest upstream commits
# and toolchain versions (PTOAS, pto-isa).
#
# Agent-agnostic: works under Claude, Codex, DeepSeek, Gemini, or a human. It
# never trusts local refs — it ALWAYS clones fresh upstream into a temp dir, so
# a stale local checkout cannot produce a false "up to date".
#
# Usage (from anywhere):
#   ./scripts/dockerfile-sync-check.sh
#   bash /path/to/pypto-docker/scripts/dockerfile-sync-check.sh
#
# Exit code: 0 = all pins current; 1 = drift detected (or network/clone failure).
#
# Repos checked (fresh clones, --depth 1):
#   pypto, simpler, pypto-lib  (hw-native-sys)
#   pytorch-hccl-tests        (georgebisbas fork)
#
# Toolchain truth comes from the freshly cloned pypto at its latest main:
#   PTOAS       -> pypto/toolchain/versions.env
#   pto-isa     -> pypto/runtime/pto_isa.pin, simpler/pto_isa.pin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
else
  C_RESET= C_BOLD= C_RED= C_GREEN= C_YELLOW= C_CYAN=
fi

ok()     { echo "${C_GREEN}$*${C_RESET}"; }
warn()   { echo "${C_YELLOW}$*${C_RESET}"; }
err()    { echo "${C_RED}$*${C_RESET}"; }
info()   { echo "${C_CYAN}$*${C_RESET}"; }

DRIFT=0

# clone <dir> <url> [branch]
clone() {
  local dir="$1" url="$2" branch="${3:-}"
  rm -rf "$dir"
  if [[ -n "$branch" ]]; then
    git clone --depth 1 --branch "$branch" --quiet "$url" "$dir" 2>/dev/null
  else
    git clone --depth 1 --quiet "$url" "$dir" 2>/dev/null
  fi
}

# clone_recursive <dir> <url> — shallow clone with submodules, so the simpler
# submodule (pypto/runtime) is present and its pto_isa.pin is readable.
clone_recursive() {
  local dir="$1" url="$2"
  rm -rf "$dir"
  git clone --depth 1 --recursive --quiet "$url" "$dir" 2>/dev/null
}

TMPDIR_CHECK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_CHECK"' EXIT

info "=== Cloning fresh upstream into $TMPDIR_CHECK (this is the source of truth) ==="
clone "$TMPDIR_CHECK/pypto"   "https://github.com/hw-native-sys/pypto.git"
# pypto's runtime/ is the simpler submodule — its pto_isa.pin lives there, so
# the pypto clone must be recursive to surface runtime/pto_isa.pin.
clone_recursive "$TMPDIR_CHECK/pypto" "https://github.com/hw-native-sys/pypto.git"
clone "$TMPDIR_CHECK/simpler" "https://github.com/hw-native-sys/simpler.git"
clone "$TMPDIR_CHECK/pypto-lib" "https://github.com/hw-native-sys/pypto-lib.git"
clone "$TMPDIR_CHECK/pt-hccl" "https://github.com/georgebisbas/pytorch-hccl-tests.git"
echo

PYPTO_UP="$(git -C "$TMPDIR_CHECK/pypto" rev-parse HEAD)"
SIMPLER_UP="$(git -C "$TMPDIR_CHECK/simpler" rev-parse HEAD)"
PYPTO_LIB_UP="$(git -C "$TMPDIR_CHECK/pypto-lib" rev-parse HEAD)"
PT_HCCL_UP="$(git -C "$TMPDIR_CHECK/pt-hccl" rev-parse HEAD)"

# Toolchain truth from fresh pypto main.
PTOAS_VERSION_UP="$(grep -E '^PTOAS_VERSION=' "$TMPDIR_CHECK/pypto/toolchain/versions.env" | cut -d= -f2)"
PTOAS_AARCH64_UP="$(grep -E '^PTOAS_SHA256_AARCH64=' "$TMPDIR_CHECK/pypto/toolchain/versions.env" | cut -d= -f2)"
PTOAS_X86_64_UP="$(grep -E '^PTOAS_SHA256_X86_64=' "$TMPDIR_CHECK/pypto/toolchain/versions.env" | cut -d= -f2)"
PTO_ISA_PYPTO_UP="$(tr -d '[:space:]' < "$TMPDIR_CHECK/pypto/runtime/pto_isa.pin")"
PTO_ISA_SIMPLER_UP="$(tr -d '[:space:]' < "$TMPDIR_CHECK/simpler/pto_isa.pin")"

info "=== Upstream latest ==="
echo "pypto            ${PYPTO_UP:0:12}"
echo "simpler          ${SIMPLER_UP:0:12}"
echo "pypto-lib        ${PYPTO_LIB_UP:0:12}"
echo "pytorch-hccl     ${PT_HCCL_UP:0:12}"
echo "PTOAS            $PTOAS_VERSION_UP (aarch64 ${PTOAS_AARCH64_UP:0:12}, x86_64 ${PTOAS_X86_64_UP:0:12})"
echo "pto-isa (pypto)  $PTO_ISA_PYPTO_UP"
echo "pto-isa (simpler)$PTO_ISA_SIMPLER_UP"
echo

# ---------------------------------------------------------------------------
# Commit pin checks.
# ---------------------------------------------------------------------------
check_pin() {
  local label="$1" file="$2" upstream="$3"
  local cur
  cur="$(grep -oP "${label}=\K[0-9a-f]{40}" "$file" | head -1 || true)"
  if [[ "$cur" == "$upstream" ]]; then
    ok "  OK   $label in $file ($(basename "$file"))"
  elif [[ -z "$cur" ]]; then
    warn "  SKIP $label in $file — no pinned SHA found (auto-derived / default 'main'?)"
  else
    err "  DRIFT $label in $file: pinned ${cur:0:12}, upstream ${upstream:0:12}"
    DRIFT=1
  fi
}

check_pin PYPTO_COMMIT    "$REPO_ROOT/Dockerfile.hw-native-sys.cann9.0"    "$PYPTO_UP"
check_pin PYPTO_COMMIT    "$REPO_ROOT/Dockerfile.hw-native-sys.sim.ubuntu22.04" "$PYPTO_UP"
check_pin SIMPLER_COMMIT  "$REPO_ROOT/Dockerfile.simpler.cann9.0"          "$SIMPLER_UP"
check_pin SIMPLER_COMMIT  "$REPO_ROOT/Dockerfile.simpler.sim.ubuntu22.04"  "$SIMPLER_UP"
check_pin PYPTO_LIB_COMMIT "$REPO_ROOT/Dockerfile.pypto-lib.cann9.0"       "$PYPTO_LIB_UP"
check_pin PYPTO_LIB_COMMIT "$REPO_ROOT/Dockerfile.pypto-lib.sim.ubuntu22.04" "$PYPTO_LIB_UP"
check_pin PT_HCCL_COMMIT  "$REPO_ROOT/Dockerfile.pytorch-hccl-tests.cann9.0" "$PT_HCCL_UP"

# server image: host-mounted, only PTOAS + pto-isa pinned (handled below).

# ---------------------------------------------------------------------------
# PTOAS version / SHA checks.
# ---------------------------------------------------------------------------
# PTOAS_VERSION values look like "v0.57"; SHA values are 64-hex. Use a pattern
# that captures each shape.
check_ptoa() {
  local label="$1" file="$2" upstream="$3"
  local cur pattern
  if [[ "$label" == "PTOAS_VERSION" ]]; then
    pattern='PTOAS_VERSION=\Kv[0-9.]+'
  else
    pattern="${label}=\K[0-9a-f]{64}"
  fi
  cur="$(grep -oP "$pattern" "$file" | head -1 || true)"
  if [[ "$cur" == "$upstream" ]]; then
    ok "  OK   $label in $(basename "$file")"
  else
    err "  DRIFT $label in $(basename "$file"): pinned ${cur:-<none>}, upstream ${upstream:-<none>}"
    DRIFT=1
  fi
}

for f in Dockerfile.hw-native-sys.cann9.0 Dockerfile.server.cann:9.0; do
  check_ptoa PTOAS_VERSION "$REPO_ROOT/$f" "$PTOAS_VERSION_UP"
  check_ptoa PTOAS_SHA256  "$REPO_ROOT/$f" "$PTOAS_AARCH64_UP"
done
# Sim image installs the x86_64 wheel (SHA256 != tarball SHA): verify the
# wheel digest equals versions.env PTOAS_SHA256_X86_64.
SIM_WHEEL_SHA="$(grep -oP 'PTOAS_WHEEL_SHA256=\K[0-9a-f]{64}' "$REPO_ROOT/Dockerfile.hw-native-sys.sim.ubuntu22.04" | head -1 || true)"
if [[ "$SIM_WHEEL_SHA" == "$PTOAS_X86_64_UP" ]]; then
  ok "  OK   PTOAS_WHEEL_SHA256 (sim) == versions.env x86_64"
else
  err "  DRIFT PTOAS_WHEEL_SHA256 (sim): pinned ${SIM_WHEEL_SHA:0:12}, versions.env x86_64 ${PTOAS_X86_64_UP:0:12}"
  DRIFT=1
fi
# Sim image also hardcodes the version in the wheel filename (ptoas-<ver>-...).
# The filename uses "0.57" without the leading "v"; compare against the
# version with any leading "v" stripped.
SIM_WHEEL_VER="$(grep -oP 'ptoas-\K[0-9.]+(?=-cp310)' "$REPO_ROOT/Dockerfile.hw-native-sys.sim.ubuntu22.04" | head -1 || true)"
if [[ "$SIM_WHEEL_VER" == "${PTOAS_VERSION_UP#v}" ]]; then
  ok "  OK   sim wheel filename version == $PTOAS_VERSION_UP"
else
  err "  DRIFT sim wheel filename version: pinned $SIM_WHEEL_VER, upstream ${PTOAS_VERSION_UP#v}"
  DRIFT=1
fi

# aarch64 images must install the cp310 wheel (not the deprecated cp311 tarball,
# whose SHA is NOT tracked in versions.env). Catch any regression to the tarball.
for f in Dockerfile.hw-native-sys.cann9.0 Dockerfile.server.cann:9.0; do
  if grep -q 'ptoas-bin-aarch64.tar.gz' "$REPO_ROOT/$f"; then
    err "  DRIFT $f still references the deprecated ptoas-bin-aarch64.tar.gz (use the cp310 wheel)"
    DRIFT=1
  else
    ok "  OK   $f installs PTOAS via cp310 wheel (no tarball)"
  fi
done

# ---------------------------------------------------------------------------
# pto-isa checks.
#
# There are TWO independent pto-isa truths:
#   - pypto's  runtime/pto_isa.pin  -> pypto-based images (hw-native-sys,
#     server, pypto-lib). server.cann:9.0 hard-pins this value.
#   - simpler's pto_isa.pin         -> simpler-based images (simpler.cann9.0,
#     simpler.sim), which auto-derive at build time.
# The hw-native-sys / hw-native-sys.sim images auto-derive from the cloned
# pypto's runtime/pto_isa.pin at build time (PTO_ISA_COMMIT empty) -> SKIP.
# ---------------------------------------------------------------------------
check_pin PTO_ISA_COMMIT "$REPO_ROOT/Dockerfile.server.cann:9.0" "$PTO_ISA_PYPTO_UP"
check_pin PTO_ISA_COMMIT "$REPO_ROOT/Dockerfile.simpler.cann9.0" "$PTO_ISA_SIMPLER_UP"
check_pin PTO_ISA_COMMIT "$REPO_ROOT/Dockerfile.simpler.sim.ubuntu22.04" "$PTO_ISA_SIMPLER_UP"

# hw-native-sys / hw-native-sys.sim auto-derive pto-isa from the cloned repo at
# build time (PTO_ISA_COMMIT= empty), so no pin check needed there.

# ---------------------------------------------------------------------------
# README example freshness.
#
# The build examples in README.md quote concrete commit SHAs. Nothing else here
# validates them, so they rot silently every time a pin is bumped - they have
# been found several generations behind while every Dockerfile pin was current.
# Rule: every 40-hex SHA in README.md must also appear in some Dockerfile, i.e.
# it must be a pin this repo currently uses.
# ---------------------------------------------------------------------------
readme_stale=0
while read -r sha; do
  [[ -z "$sha" ]] && continue
  if ! grep -qF "$sha" "$REPO_ROOT"/Dockerfile.* 2>/dev/null; then
    err "  DRIFT README.md quotes ${sha:0:12}, which is not a current pin in any Dockerfile"
    readme_stale=1
    DRIFT=1
  fi
done < <(grep -ohE '[0-9a-f]{40}' "$REPO_ROOT/README.md" 2>/dev/null | sort -u)
if [[ "$readme_stale" -eq 0 ]]; then
  ok "  OK   README.md example SHAs all match current Dockerfile pins"
fi

echo
if [[ "$DRIFT" -eq 0 ]]; then
  ok "=== All Dockerfile pins are current ==="
else
  err "=== DRIFT DETECTED: update the pins above (see dockerfile_skills/SKILL.md) ==="
fi
exit "$DRIFT"
