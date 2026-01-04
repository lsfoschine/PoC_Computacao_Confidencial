#!/usr/bin/env bash
set -euo pipefail

export UV_CACHE_DIR="${UV_CACHE_DIR:-.uv-cache}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-.uv-python}"

OUT=""
if [[ "${1:-}" == "--out" ]]; then
  OUT="$2"
  shift 2
fi

TMPDIR_ENV="$(mktemp -d)"
export TMPDIR_ENV
trap 'rm -rf "$TMPDIR_ENV"' EXIT

capture_cmd() {
  local name="$1"
  shift
  local bin="$1"
  if command -v "$bin" >/dev/null 2>&1; then
    "$@" >"${TMPDIR_ENV}/${name}" 2>&1 || true
  else
    echo "not_found" >"${TMPDIR_ENV}/${name}"
  fi
}

capture_file() {
  local name="$1"
  local path="$2"
  if [[ -f "$path" ]]; then
    cat "$path" >"${TMPDIR_ENV}/${name}" 2>&1 || true
  else
    echo "not_found" >"${TMPDIR_ENV}/${name}"
  fi
}

capture_cmd uname "uname" "-a"
capture_file cmdline "/proc/cmdline"

capture_cmd lscpu "lscpu"
capture_cmd lscpu_extended "lscpu" "-e"

if [[ -f "/proc/cpuinfo" ]]; then
  awk -F: '/model name|flags|microcode/ {print}' /proc/cpuinfo >"${TMPDIR_ENV}/cpuinfo_relevant" || true
else
  echo "not_found" >"${TMPDIR_ENV}/cpuinfo_relevant"
fi

capture_cmd microcode_dmesg "dmesg"
if [[ -f "${TMPDIR_ENV}/microcode_dmesg" ]]; then
  grep -i microcode "${TMPDIR_ENV}/microcode_dmesg" >"${TMPDIR_ENV}/microcode_dmesg_filtered" || echo "not_found" >"${TMPDIR_ENV}/microcode_dmesg_filtered"
else
  echo "not_found" >"${TMPDIR_ENV}/microcode_dmesg_filtered"
fi

capture_file microcode_sysfs "/sys/devices/system/cpu/microcode/version"

capture_file governor_cpu0 "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"

capture_file turbo_intel_no_turbo "/sys/devices/system/cpu/intel_pstate/no_turbo"

capture_file cpufreq_boost "/sys/devices/system/cpu/cpufreq/boost"

capture_cmd cpupower_frequency_info "cpupower" "frequency-info"

capture_cmd numactl_hardware "numactl" "--hardware"

capture_cmd taskset_self "taskset" "-pc" "$$"

capture_cmd free_h "free" "-h"
capture_cmd meminfo "cat" "/proc/meminfo"

capture_cmd lsblk "lsblk" "-o" "NAME,TYPE,SIZE,ROTA,TRAN,MODEL"
capture_cmd df_h "df" "-h"
capture_cmd df_workdir "df" "-P" "."
capture_cmd blockdev_rota "cat" "/sys/block/*/queue/rotational"

capture_cmd confidential_dmesg "dmesg"
if [[ -f "${TMPDIR_ENV}/confidential_dmesg" ]]; then
  grep -E -i "sev|snp|tdx|confidential|cc" "${TMPDIR_ENV}/confidential_dmesg" >"${TMPDIR_ENV}/confidential_dmesg_filtered" || echo "not_found" >"${TMPDIR_ENV}/confidential_dmesg_filtered"
else
  echo "not_found" >"${TMPDIR_ENV}/confidential_dmesg_filtered"
fi

capture_cmd uv_version "uv" "--version"

uv run python - <<'PY' >"${TMPDIR_ENV}/env.json"
import json
import os
import platform
import socket
from datetime import datetime, timezone
from pathlib import Path

tmpdir = Path(os.environ["TMPDIR_ENV"])

def read_file(name: str):
    path = tmpdir / name
    if not path.exists():
        return {"status": "not_found"}
    content = path.read_text(errors="replace").strip()
    if content == "not_found" or not content:
        return {"status": "not_found"}
    return {"status": "ok", "raw": content}

def parse_df_device(df_raw: str | None):
    if not df_raw:
        return None
    lines = [line for line in df_raw.splitlines() if line.strip()]
    if len(lines) < 2:
        return None
    parts = lines[1].split()
    if not parts:
        return None
    return parts[0]

def normalize_device(device: str | None):
    if not device:
        return None
    if device.startswith("/dev/"):
        device = device[5:]
    if device.startswith("mapper/"):
        device = device[len("mapper/"):]
    return device

def filter_lsblk(raw: str | None, device: str | None):
    if not raw or not device:
        return None
    lines = [line for line in raw.splitlines() if line.strip()]
    header = lines[0] if lines else None
    matches = []
    for line in lines[1:]:
        first = line.split()[0]
        if first == device or first.startswith(device):
            matches.append(line)
    if not matches:
        return None
    return "\n".join([header] + matches) if header else "\n".join(matches)

sev_paths = [
    "/dev/sev-guest",
    "/sys/firmware/sev",
    "/sys/firmware/sev-guest",
]

tdx_paths = [
    "/dev/tdx-guest",
    "/sys/firmware/tdx",
]

def path_status(paths):
    results = []
    for p in paths:
        results.append({"path": p, "exists": Path(p).exists()})
    return results

payload = {
    "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "hostname": socket.gethostname(),
    "platform": platform.platform(),
    "kernel": platform.release(),
    "machine": platform.machine(),
    "processor": platform.processor(),
    "python_version": platform.python_version(),
    "uv_version": read_file("uv_version"),
    "kernel_cmdline": read_file("cmdline"),
    "cpu": {
        "lscpu": read_file("lscpu"),
        "lscpu_extended": read_file("lscpu_extended"),
        "cpuinfo_relevant": read_file("cpuinfo_relevant"),
    },
    "microcode": {
        "dmesg": read_file("microcode_dmesg_filtered"),
        "sysfs": read_file("microcode_sysfs"),
    },
    "frequency": {
        "governor_cpu0": read_file("governor_cpu0"),
        "turbo_intel_no_turbo": read_file("turbo_intel_no_turbo"),
        "cpufreq_boost": read_file("cpufreq_boost"),
        "cpupower_frequency_info": read_file("cpupower_frequency_info"),
    },
    "numa": {
        "numactl_hardware": read_file("numactl_hardware"),
    },
    "memory": {
        "free_h": read_file("free_h"),
        "meminfo": read_file("meminfo"),
    },
    "storage": {
        "lsblk": read_file("lsblk"),
        "df_h": read_file("df_h"),
        "df_workdir": read_file("df_workdir"),
        "blockdev_rotational": read_file("blockdev_rota"),
        "workdir": os.getcwd(),
        "workdir_device": None,
        "workdir_lsblk": None,
    },
    "pinning": {
        "taskset": read_file("taskset_self"),
    },
    "kernel_info": {
        "uname": read_file("uname"),
    },
    "confidential": {
        "dmesg": read_file("confidential_dmesg_filtered"),
        "sev_paths": path_status(sev_paths),
        "tdx_paths": path_status(tdx_paths),
    },
}

df_workdir = payload["storage"]["df_workdir"]
df_raw = df_workdir.get("raw") if isinstance(df_workdir, dict) else None
device = parse_df_device(df_raw)
normalized = normalize_device(device)
payload["storage"]["workdir_device"] = device
lsblk_raw = payload["storage"]["lsblk"].get("raw") if isinstance(payload["storage"]["lsblk"], dict) else None
payload["storage"]["workdir_lsblk"] = filter_lsblk(lsblk_raw, normalized)

print(json.dumps(payload, ensure_ascii=True, indent=2))
PY

if [[ -n "$OUT" ]]; then
  cat "${TMPDIR_ENV}/env.json" >"$OUT"
else
  cat "${TMPDIR_ENV}/env.json"
fi
