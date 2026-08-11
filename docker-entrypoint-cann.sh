#!/usr/bin/env bash
set -euo pipefail

workspace_root=${WORKSPACE_ROOT:-/workspace/hw-native-sys/pypto}
installed_simpler_root=${SIMPLER_ROOT:-/workspace/hw-native-sys/simpler}
workspace_runtime_dir="${workspace_root}/runtime"

if [[ -d "${installed_simpler_root}/src" ]]; then
    if [[ -L "${workspace_runtime_dir}" ]]; then
        :
    elif [[ -d "${workspace_runtime_dir}" && ! -d "${workspace_runtime_dir}/src" ]]; then
        rm -rf "${workspace_runtime_dir}"
        ln -s "${installed_simpler_root}" "${workspace_runtime_dir}"
    elif [[ ! -e "${workspace_runtime_dir}" ]]; then
        ln -s "${installed_simpler_root}" "${workspace_runtime_dir}"
    fi
fi

exec "$@"