#!/usr/bin/env bash
# queue-smoke.sh — smallest end-to-end check that a containerized job is on the queue.
#
# Run it INSIDE a queue-joined container (see TASK_QUEUE.md), e.g.:
#
#   docker exec <container> task-submit --device auto --max-time 1800 --timeout 0 \
#       --run 'bash /mounted_home/.../pypto-docker/scripts/queue-smoke.sh $TASK_DEVICE'
#
# The queue grants the card, pins it via ASCEND_RT_VISIBLE_DEVICES (logical id in
# TASK_DEVICE), and this script then runs one small a2a3 system test on it.
# Override the pytest target with QUEUE_SMOKE_TARGET='<nodeid ...>'.
set -euo pipefail

DEV="${1:-${TASK_DEVICE:-0}}"

# docker-exec children may not source bash.bashrc; make sure the CANN env exists.
if [ -z "${ASCEND_HOME_PATH:-}" ]; then
    for f in /usr/local/Ascend/ascend-toolkit/set_env.sh \
             /usr/local/Ascend/cann-9.0.0/set_env.sh; do
        if [ -f "$f" ]; then set +u; source "$f"; set -u; break; fi
    done
fi

cd /opt/pypto

echo "== queue smoke =="
echo "TASK_DEVICE=${DEV}  TASK_PHYS_DEVICE=${TASK_PHYS_DEVICE:-unset}  ASCEND_RT_VISIBLE_DEVICES=${ASCEND_RT_VISIBLE_DEVICES:-unset}"

if command -v npu-smi >/dev/null 2>&1; then
    # capture first: piping into `head` under `pipefail` kills npu-smi with SIGPIPE (exit 141)
    npu-smi info > /tmp/queue-smoke-npu.txt || true
    head -5 /tmp/queue-smoke-npu.txt
fi

python -c "import pypto; print('pypto:', pypto.__file__)"

TARGET="${QUEUE_SMOKE_TARGET:-tests/st/runtime/ops/test_vector_misc.py::TestVectorMisc::test_tile_muls[16x16]}"
pytest "$TARGET" -v --platform=a2a3 --device "$DEV"
