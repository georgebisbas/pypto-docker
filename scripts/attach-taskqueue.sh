#!/usr/bin/env bash
# attach-taskqueue.sh — join a running container to the shared NPU task queue.
#
# Usage:  scripts/attach-taskqueue.sh <container-name> [queue-volume-path]
#
# The container must already bind-mount the queue volume at the same path as the
# host (default /var/lib/taskqueue) — a bind-mount cannot be added to a live
# container, so recreate it if the volume is missing. Idempotent: creates the
# tool/config symlinks, then verifies the join with `task-submit --list`.
set -euo pipefail

usage() { echo "usage: $0 <container-name> [queue-volume-path=/var/lib/taskqueue]" >&2; exit 2; }
[ $# -ge 1 ] || usage
name="$1"
vol="${2:-/var/lib/taskqueue}"

docker inspect "$name" >/dev/null 2>&1 || { echo "ERROR: no such container: $name" >&2; exit 1; }

docker exec "$name" bash -lc "
  set -e
  if [ ! -x '$vol/bin/task-submit' ]; then
    echo \"ERROR: $vol/bin/task-submit not found inside the container.\" >&2
    echo \"       Is the queue volume bind-mounted at $vol?  Check: docker inspect $name\" >&2
    exit 2
  fi
  ln -sf '$vol/bin/task-submit' /usr/local/bin/task-submit
  ln -sf '$vol/bin/npu-lock'    /usr/local/bin/npu-lock
  ln -sf '$vol/taskqueue.conf'  /etc/taskqueue.conf
"

echo "--- queue state from inside '$name': ---"
docker exec "$name" task-submit --list
echo "--- joined. Run NPU work as:"
echo "      task-submit --device auto --max-time 1800 --timeout 0 --run 'cd /opt/pypto && <cmd> ... \$TASK_DEVICE'"
