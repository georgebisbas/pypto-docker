#!/usr/bin/env bash
# Build the Ascend 910B (CANN) Docker images for pypto, simpler, and pto-kernels.
# Intended to run directly on the NPU host (build itself needs no NPU access,
# only GitHub connectivity; the resulting images require Ascend hardware at
# `docker run` time, see the RUN blocks in each Dockerfile).
#
# Usage:
#   ./scripts/build-npu-images.sh [--a5] [pypto|simpler|pto-kernels|all]
#
# --a5  Build A5 (Ascend 950) images with the URMA provider instead of the
#       default a2a3/910B ones. Implies CANN_VERSION=9.3.0-beta.1, CANN_SOC=950
#       and BUILD_TARGETS=build_package_a5, and tags the images
#       pypto3-hw-native-sys:a5 / simpler-a5. Only a 950 base image ships the A5
#       AICore codegen (dav-c310) and HcclChannelAcquireWithConfig, which the
#       URMA provider needs; 9.3.0-beta.1 rather than 9.2.0 because simpler's A5
#       CCU registration needs hcomm's HCOMM_CCU_RES_TYPE_CASC_CNT, which first
#       appears on the 9.3.0 line (hcomm 2b5d32c30, in no release tag up to and
#       including v9.2.0). pto-kernels has no A5 variant and is skipped. Run the
#       tests with --platform a5; these images do NOT build a2a3. Any env
#       override below still wins over the --a5 defaults.
#
# Env overrides (only applied if non-empty; otherwise Dockerfile defaults apply):
#   CANN_VERSION      selects base image tag and cann-* paths (defaults:
#                     pypto/simpler 9.0.0, pto-kernels 9.2.0-beta.1)
#   CANN_SOC          base image silicon: 910b (a2a3) or 950 (A5)  (pypto/simpler)
#   BUILD_TARGETS     runtime build.targets list                   (pypto/simpler)
#   INSTALL_PREFIX    install root, default /opt                (both images)
#   PYPTO_COMMIT      pin pypto commit                           (pypto image only)
#   PTO_ISA_COMMIT    pin pto-isa commit                          (both images)
#   PTOAS_VERSION     pin PTOAS release                          (pypto image only)
#   SIMPLER_COMMIT    pin simpler commit                          (simpler image only)
#   PTO_KERNELS_COMMIT pin pto-kernels commit                     (pto-kernels image only)
#
# Images:
#   pypto3-hw-native-sys:cann9  <- Dockerfile.hw-native-sys.cann9.0
#   simpler-cann9                <- Dockerfile.simpler.cann9.0
#   pto-kernels:cann9            <- Dockerfile.pto-kernels.cann9.0  (sim + NPU)
# With --a5:
#   pypto3-hw-native-sys:a5     <- Dockerfile.hw-native-sys.cann9.0
#   simpler-a5                   <- Dockerfile.simpler.cann9.0

set -euo pipefail

# BuildKit is required for the Dockerfiles' --mount=type=cache pip/apt caches.
export DOCKER_BUILDKIT=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLING_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
A5=0
while [[ $# -gt 0 && "${1}" == -* ]]; do
  case "${1}" in
    --a5) A5=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--a5] [pypto|simpler|pto-kernels|all]"
      exit 0
      ;;
    *)
      echo "Usage: $0 [--a5] [pypto|simpler|pto-kernels|all]" >&2
      exit 2
      ;;
  esac
done
TARGET="${1:-all}"

# A5 defaults — env overrides still win (:= only assigns when unset/empty).
if [[ "${A5}" -eq 1 ]]; then
  : "${CANN_VERSION:=9.3.0-beta.1}"
  : "${CANN_SOC:=950}"
  : "${BUILD_TARGETS:=build_package_a5}"
  PYPTO_TAG="pypto3-hw-native-sys:a5"
  SIMPLER_TAG="simpler-a5"
else
  PYPTO_TAG="pypto3-hw-native-sys:cann9"
  SIMPLER_TAG="simpler-cann9"
fi

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
  pypto|simpler|pto-kernels|all) ;;
  *)
    echo "Usage: $0 [pypto|simpler|pto-kernels|all]" >&2
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
  [[ -n "${CANN_SOC:-}" ]] && args+=(--build-arg "CANN_SOC=${CANN_SOC}")
  [[ -n "${BUILD_TARGETS:-}" ]] && args+=(--build-arg "BUILD_TARGETS=${BUILD_TARGETS}")
  build_image "pypto" "Dockerfile.hw-native-sys.cann9.0" "${PYPTO_TAG}" "${args[@]}" || FAILED=1
  echo
fi

if [[ "${TARGET}" == "simpler" || "${TARGET}" == "all" ]]; then
  args=()
  [[ -n "${CANN_VERSION:-}" ]] && args+=(--build-arg "CANN_VERSION=${CANN_VERSION}")
  [[ -n "${INSTALL_PREFIX:-}" ]] && args+=(--build-arg "INSTALL_PREFIX=${INSTALL_PREFIX}")
  [[ -n "${SIMPLER_COMMIT:-}" ]] && args+=(--build-arg "SIMPLER_COMMIT=${SIMPLER_COMMIT}")
  [[ -n "${PTO_ISA_COMMIT:-}" ]] && args+=(--build-arg "PTO_ISA_COMMIT=${PTO_ISA_COMMIT}")
  [[ -n "${CANN_SOC:-}" ]] && args+=(--build-arg "CANN_SOC=${CANN_SOC}")
  [[ -n "${BUILD_TARGETS:-}" ]] && args+=(--build-arg "BUILD_TARGETS=${BUILD_TARGETS}")
  build_image "simpler" "Dockerfile.simpler.cann9.0" "${SIMPLER_TAG}" "${args[@]}" || FAILED=1
  echo
fi

if [[ "${TARGET}" == "pto-kernels" && "${A5}" -eq 1 ]]; then
  err "pto-kernels has no A5 variant (its base image is 910b-only) — drop --a5"
  exit 2
fi

if [[ "${TARGET}" == "pto-kernels" || ( "${TARGET}" == "all" && "${A5}" -eq 0 ) ]]; then
  args=()
  [[ -n "${CANN_VERSION:-}" ]] && args+=(--build-arg "CANN_VERSION=${CANN_VERSION}")
  [[ -n "${INSTALL_PREFIX:-}" ]] && args+=(--build-arg "INSTALL_PREFIX=${INSTALL_PREFIX}")
  [[ -n "${PTO_KERNELS_COMMIT:-}" ]] && args+=(--build-arg "PTO_KERNELS_COMMIT=${PTO_KERNELS_COMMIT}")
  build_image "pto-kernels" "Dockerfile.pto-kernels.cann9.0" "pto-kernels:cann9" "${args[@]}" || FAILED=1
  echo
fi

if [[ "${FAILED}" -ne 0 ]]; then
  echo "${C_RED}${C_BOLD}Done with errors.${C_RESET}"
  exit 1
fi
echo "${C_GREEN}${C_BOLD}Done. NPU image(s) built.${C_RESET}"
RUN_FLAGS="--rm -it --privileged --ipc=host -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro -v /dev:/dev"
if [[ "${A5}" -eq 1 ]]; then
  echo "Run (A5; add --pid=host --cap-add=SYS_PTRACE --security-opt seccomp=unconfined for multi-device URMA/HCCL):"
  echo "  docker run ${RUN_FLAGS} ${PYPTO_TAG}"
  echo "  docker run ${RUN_FLAGS} ${SIMPLER_TAG}"
  echo "Inside, gate on silicon before touching a card, then run with --platform a5, e.g.:"
  echo "  .claude/skills/onboard-arch-precheck/check.sh a5"
  echo "  python -m pytest tests/st/a5/tensormap_and_ringbuffer/urma_multi_jetty --platform a5 --device 0,1 --require-pto-isa -v"
else
  echo "Run (single-device, see Dockerfile header for multi-device/HCCL flags):"
  echo "  docker run ${RUN_FLAGS} ${PYPTO_TAG}"
  echo "  docker run ${RUN_FLAGS} ${SIMPLER_TAG}"
  echo "  docker run --rm pto-kernels:cann9 bash -lc 'cd /opt/pto-kernels/.skills/testing-pto-kernels/reference/static_single_core/a2a3 && ./run_sim.sh msprof --kernel add'  # sim, no NPU"
fi
