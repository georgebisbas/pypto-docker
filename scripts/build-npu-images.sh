#!/usr/bin/env bash
# Build the Ascend 910B (CANN) Docker images for pypto and simpler.
# Intended to run directly on the NPU host (build itself needs no NPU access,
# only GitHub connectivity; the resulting images require Ascend hardware at
# `docker run` time, see the RUN blocks in each Dockerfile).
#
# Usage:
#   ./scripts/build-npu-images.sh [pypto|simpler|all]
#
# Env overrides (only applied if non-empty; otherwise Dockerfile defaults apply):
#   CANN_VERSION      selects base image tag and cann-* paths (both images)
#   INSTALL_PREFIX    install root, default /opt                (both images)
#   PYPTO_COMMIT      pin pypto commit                           (pypto image only)
#   PTO_ISA_COMMIT    pin pto-isa commit                          (both images)
#   PTOAS_VERSION     pin PTOAS release                          (pypto image only)
#   SIMPLER_COMMIT    pin simpler commit                          (simpler image only)
#
# Images:
#   pypto3-hw-native-sys:cann9  <- Dockerfile.hw-native-sys.cann9.0
#   simpler-cann9                <- Dockerfile.simpler.cann9.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLING_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET="${1:-all}"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_BLUE=$'\033[34m'
else
  C_RESET= C_BOLD= C_RED= C_GREEN= C_YELLOW= C_CYAN= C_BLUE=
fi

ok()    { echo "${C_GREEN}$*${C_RESET}"; }
warn()  { echo "${C_YELLOW}$*${C_RESET}"; }
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
command -v npu-smi >/dev/null 2>&1 || warn "npu-smi not found on PATH — fine for build, but check you're on the NPU host if you intend to run these images here"

cd "${TOOLING_DIR}"

build_image() {
  local name="$1" dockerfile="$2" tag="$3"
  shift 3
  local build_args=("$@")

  header "${name} (${tag})"
  echo "dockerfile: ${dockerfile} (stdin build, no build context)"
  ((${#build_args[@]})) && printf 'build-arg:  %s\n' "${build_args[@]}"

  if docker build "${build_args[@]}" -t "${tag}" - < "${dockerfile}"; then
    ok "built ${tag}"
  else
    err "build failed: ${tag}"
    return 1
  fi
}

FAILED=0

if [[ "${TARGET}" == "pypto" || "${TARGET}" == "all" ]]; then
  args=()
  [[ -n "${CANN_VERSION:-}" ]] && args+=(--build-arg "CANN_VERSION=${CANN_VERSION}")
  [[ -n "${INSTALL_PREFIX:-}" ]] && args+=(--build-arg "INSTALL_PREFIX=${INSTALL_PREFIX}")
  [[ -n "${PYPTO_COMMIT:-}" ]] && args+=(--build-arg "PYPTO_COMMIT=${PYPTO_COMMIT}")
  [[ -n "${PTO_ISA_COMMIT:-}" ]] && args+=(--build-arg "PTO_ISA_COMMIT=${PTO_ISA_COMMIT}")
  [[ -n "${PTOAS_VERSION:-}" ]] && args+=(--build-arg "PTOAS_VERSION=${PTOAS_VERSION}")
  build_image "pypto" "Dockerfile.hw-native-sys.cann9.0" "pypto3-hw-native-sys:cann9" "${args[@]}" || FAILED=1
  echo
fi

if [[ "${TARGET}" == "simpler" || "${TARGET}" == "all" ]]; then
  args=()
  [[ -n "${CANN_VERSION:-}" ]] && args+=(--build-arg "CANN_VERSION=${CANN_VERSION}")
  [[ -n "${INSTALL_PREFIX:-}" ]] && args+=(--build-arg "INSTALL_PREFIX=${INSTALL_PREFIX}")
  [[ -n "${SIMPLER_COMMIT:-}" ]] && args+=(--build-arg "SIMPLER_COMMIT=${SIMPLER_COMMIT}")
  [[ -n "${PTO_ISA_COMMIT:-}" ]] && args+=(--build-arg "PTO_ISA_COMMIT=${PTO_ISA_COMMIT}")
  build_image "simpler" "Dockerfile.simpler.cann9.0" "simpler-cann9" "${args[@]}" || FAILED=1
  echo
fi

if [[ "${FAILED}" -ne 0 ]]; then
  echo "${C_RED}${C_BOLD}Done with errors.${C_RESET}"
  exit 1
fi
echo "${C_GREEN}${C_BOLD}Done. NPU image(s) built.${C_RESET}"
echo "Run (single-device, see Dockerfile header for multi-device/HCCL flags):"
echo "  docker run --rm -it --privileged --ipc=host -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro -v /dev:/dev pypto3-hw-native-sys:cann9"
echo "  docker run --rm -it --privileged --ipc=host -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro -v /dev:/dev simpler-cann9"
