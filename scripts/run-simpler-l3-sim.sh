#!/usr/bin/env bash
# Run simpler L3 example STs on a2a3sim (mirrors simpler CI st-sim-a2a3 flags).
#
# Usage (inside simpler-hw-native-sys:sim container):
#   run-simpler-l3-sim.sh [distributed|all|allreduce]

set -euo pipefail

SIMPLER_DIR="${SIMPLER_DIR:-/opt/simpler}"
SCOPE="${1:-distributed}"

cd "${SIMPLER_DIR}"

PYTEST_COMMON=(
  pytest
  --platform a2a3sim
  --device 0-15
  -v
  --pto-session-timeout 600
  --clone-protocol https
  --require-pto-isa
)

case "${SCOPE}" in
  allreduce)
    TARGETS=(examples/workers/l3/allreduce)
    ;;
  distributed)
    TARGETS=(
      examples/workers/l3/allreduce
      examples/workers/l3/domain_rank_map
      examples/workers/l3/dual_domain_overlap
      examples/workers/l3/ffn_tp_parallel
      examples/workers/l3/ep_dispatch_combine
      examples/workers/l3/child_memory
      examples/workers/l3/l3_l2_message_queue
      examples/workers/l3/l3_l2_orch_comm_stream
      examples/workers/l3/per_task_runtime_env
    )
    ;;
  all)
    TARGETS=(examples/workers/l3)
    ;;
  *)
    echo "Usage: $0 [distributed|all|allreduce]" >&2
    exit 2
    ;;
esac

echo "==> simpler L3 sim: scope=${SCOPE} dir=${SIMPLER_DIR}"
exec "${PYTEST_COMMON[@]}" "${TARGETS[@]}"
