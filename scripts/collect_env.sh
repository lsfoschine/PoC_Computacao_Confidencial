#!/usr/bin/env bash
set -euo pipefail

export UV_CACHE_DIR="${UV_CACHE_DIR:-.uv-cache}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-.uv-python}"

printf "== System ==\n"
uname -a

printf "\n== CPU ==\n"
if command -v lscpu >/dev/null 2>&1; then
  lscpu
else
  sysctl -a 2>/dev/null | rg -i 'machdep.cpu|hw.memsize' || true
fi

printf "\n== RAM ==\n"
if command -v free >/dev/null 2>&1; then
  free -h
else
  vm_stat 2>/dev/null || true
fi

printf "\n== Python ==\n"
python --version

printf "\n== UV ==\n"
uv --version

printf "\n== Python packages ==\n"
uv run python - <<'PY'
import platform

print(f"python: {platform.python_version()}")
try:
    import numpy
    print(f"numpy: {numpy.__version__}")
except Exception as exc:
    print(f"numpy: not available ({exc})")
try:
    import torch
    print(f"torch: {torch.__version__}")
    print(f"torch_cuda: {torch.cuda.is_available()}")
except Exception as exc:
    print(f"torch: not available ({exc})")
try:
    import sentence_transformers
    print(f"sentence-transformers: {sentence_transformers.__version__}")
except Exception as exc:
    print(f"sentence-transformers: not available ({exc})")
PY
