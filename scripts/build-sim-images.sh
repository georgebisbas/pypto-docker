#!/usr/bin/env bash
# Build the local, NPU-free simulation Docker images for pypto and simpler
# (a2a3sim / a5sim only — no Ascend hardware required).
#
# Usage:
#   ./scripts/build-sim-images.sh [pypto|simpler|all]
#
# Env overrides (only applied if non-empty; otherwise Dockerfile defaults apply):
#   PYPTO_COMMIT      pin pypto commit   (pypto image only)
#   PTO_ISA_COMMIT    pin pto-isa commit (both images)
#   SIMPLER_COMMIT    pin simpler commit (simpler image only)
#
# Images:
#   pypto3-hw-native-sys:sim   <- Dockerfile.hw-native-sys.sim.ubuntu22.04
#   simpler-hw-native-sys:sim  <- Dockerfile.simpler.sim.ubuntu22.04

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLING_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET="${1:-all}"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'; C_CYAN=$'\033[36m'; C_BLUE=$'\033[34m'
else
  C_RESET= C_BOLD= C_RED= C_GREEN= C_CYAN= C_BLUE=
fi

ok()    { echo "${C_GREEN}$*${C_RESET}"; }
err()   { echo "${C_RED}ERROR:${C_RESET} $*" >&2; }
header(){ echo "${C_BOLD}${C_BLUE}=== $* ===${C_RESET}"; }

case "${TARGET}" in
  pypto|simpler|all) ;;
  *)
    echo "Usage: $0 [pypto|simpler|all]" >&2
    exit 2
    ;;
esac

command -v docker >/dev/null 2>&1 || { err "docker not found on PATH"; exit 1; }

# Build context is pypto-tooling itself: Dockerfile.simpler.sim.ubuntu22.04
# COPYs scripts/run-simpler-l3-sim.sh from here.
cd "${TOOLING_DIR}"

build_image() {
  local name="$1" dockerfile="$2" tag="$3"
  shift 3
  local build_args=("$@")

  header "${name} (${tag})"
  echo "dockerfile: ${dockerfile}"
  echo "context:    ${TOOLING_DIR}"
  ((${#build_args[@]})) && printf 'build-arg:  %s\n' "${build_args[@]}"

  if docker build "${build_args[@]}" -t "${tag}" -f "${dockerfile}" .; then
    ok "built ${tag}"
  else
    err "build failed: ${tag}"
    return 1
  fi
}

FAILED=0

if [[ "${TARGET}" == "pypto" || "${TARGET}" == "all" ]]; then
  args=()
  [[ -n "${PYPTO_COMMIT:-}" ]] && args+=(--build-arg "PYPTO_COMMIT=${PYPTO_COMMIT}")
  [[ -n "${PTO_ISA_COMMIT:-}" ]] && args+=(--build-arg "PTO_ISA_COMMIT=${PTO_ISA_COMMIT}")
  build_image "pypto" "Dockerfile.hw-native-sys.sim.ubuntu22.04" "pypto3-hw-native-sys:sim" "${args[@]}" || FAILED=1
  echo
fi

if [[ "${TARGET}" == "simpler" || "${TARGET}" == "all" ]]; then
  args=()
  [[ -n "${SIMPLER_COMMIT:-}" ]] && args+=(--build-arg "SIMPLER_COMMIT=${SIMPLER_COMMIT}")
  [[ -n "${PTO_ISA_COMMIT:-}" ]] && args+=(--build-arg "PTO_ISA_COMMIT=${PTO_ISA_COMMIT}")
  build_image "simpler" "Dockerfile.simpler.sim.ubuntu22.04" "simpler-hw-native-sys:sim" "${args[@]}" || FAILED=1
  echo
fi

if [[ "${FAILED}" -ne 0 ]]; then
  echo "${C_RED}${C_BOLD}Done with errors.${C_RESET}"
  exit 1
fi
echo "${C_GREEN}${C_BOLD}Done. Sim image(s) built.${C_RESET}"
echo "Run e.g.: docker run --rm -it pypto3-hw-native-sys:sim"
echo "          docker run --rm -it --shm-size=4g simpler-hw-native-sys:sim"
