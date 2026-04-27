#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE="${WORKSPACE:-/workspace/diniu-training}"
SIMPLETUNER_REPO_URL="${SIMPLETUNER_REPO_URL:-https://github.com/bghira/SimpleTuner.git}"
SIMPLETUNER_PLATFORM_EXTRA="${SIMPLETUNER_PLATFORM_EXTRA:-cuda}"
INSTALL_APT="${INSTALL_APT:-1}"
USE_UV_PYTHON="${USE_UV_PYTHON:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${LOCAL_REPO}/pyproject.toml" && -d "${LOCAL_REPO}/simpletuner" ]]; then
  REPO_DIR="${SIMPLETUNER_DIR:-${LOCAL_REPO}}"
else
  REPO_DIR="${SIMPLETUNER_DIR:-${WORKSPACE}/SimpleTuner}"
fi

run_privileged() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

pick_python() {
  for candidate in python3.13 python3.12 python3; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      if "${candidate}" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if (3, 12) <= sys.version_info < (3, 14) else 1)
PY
      then
        command -v "${candidate}"
        return 0
      fi
    fi
  done
  return 1
}

echo "== SimpleTuner 4090 bootstrap =="
echo "Workspace: ${WORKSPACE}"
echo "Repo dir:  ${REPO_DIR}"

mkdir -p \
  "${WORKSPACE}/hf_cache" \
  "${WORKSPACE}/pip_cache" \
  "${WORKSPACE}/datasets/person_lora/train_images" \
  "${WORKSPACE}/outputs" \
  "${WORKSPACE}/models" \
  "${WORKSPACE}/logs" \
  "${WORKSPACE}/cache"

export HF_HOME="${WORKSPACE}/hf_cache"
export HF_HUB_CACHE="${WORKSPACE}/hf_cache/hub"
export PIP_CACHE_DIR="${WORKSPACE}/pip_cache"

cat >"${WORKSPACE}/env.sh" <<EOF
export WORKSPACE="${WORKSPACE}"
export HF_HOME="${HF_HOME}"
export HF_HUB_CACHE="${HF_HUB_CACHE}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR}"
export SIMPLETUNER_DIR="${REPO_DIR}"
EOF

if [[ "${INSTALL_APT}" == "1" ]] && command -v apt-get >/dev/null 2>&1; then
  echo "== Installing system packages =="
  run_privileged apt-get update
  run_privileged apt-get install -y \
    ca-certificates \
    curl \
    git \
    git-lfs \
    ffmpeg \
    build-essential \
    python3-pip \
    python3-venv \
    rsync

  if ! run_privileged apt-get install -y nvidia-cuda-toolkit; then
    echo "WARN: nvidia-cuda-toolkit install failed or is unavailable in this image."
    echo "WARN: Continue if the image already includes CUDA compiler/runtime support."
  fi
fi

git lfs install || true

if [[ ! -d "${REPO_DIR}/.git" ]]; then
  echo "== Cloning SimpleTuner =="
  mkdir -p "$(dirname "${REPO_DIR}")"
  git clone "${SIMPLETUNER_REPO_URL}" "${REPO_DIR}"
else
  echo "== Using existing SimpleTuner checkout =="
fi

PYTHON_BIN="$(pick_python || true)"
USE_UV_FOR_VENV=0

if [[ -z "${PYTHON_BIN}" ]]; then
  if [[ "${USE_UV_PYTHON}" != "1" ]]; then
    echo "ERROR: Python 3.12 or 3.13 is required."
    exit 1
  fi

  echo "== Python 3.12/3.13 not found; installing uv-managed Python 3.12 =="
  if ! command -v uv >/dev/null 2>&1; then
    if ! python3 -m pip install --user --break-system-packages uv; then
      python3 -m pip install --user uv
    fi
    export PATH="${HOME}/.local/bin:${PATH}"
  fi
  uv python install 3.12
  USE_UV_FOR_VENV=1
else
  "${PYTHON_BIN}" - <<'PY'
import sys
if sys.version_info < (3, 12) or sys.version_info >= (3, 14):
    raise SystemExit(f"Python 3.12 or 3.13 required, got {sys.version}")
print(sys.version)
PY
fi

cd "${REPO_DIR}"

echo "== Creating virtual environment =="
if [[ "${USE_UV_FOR_VENV}" == "1" ]]; then
  uv venv --python 3.12 .venv
else
  "${PYTHON_BIN}" -m venv .venv
fi
source .venv/bin/activate

echo "== Installing SimpleTuner with ${SIMPLETUNER_PLATFORM_EXTRA} extra =="
python -m pip install -U pip setuptools wheel
if [[ "${SIMPLETUNER_PLATFORM_EXTRA}" == "cuda13" ]]; then
  python -m pip install -e '.[cuda13]' --extra-index-url https://download.pytorch.org/whl/cu130
else
  python -m pip install -e '.[cuda]'
fi

mkdir -p "${REPO_DIR}/dataset" "${REPO_DIR}/config"
if [[ ! -e "${REPO_DIR}/dataset/person_lora" ]]; then
  ln -s "${WORKSPACE}/datasets/person_lora" "${REPO_DIR}/dataset/person_lora"
fi
if [[ ! -e "${REPO_DIR}/output" ]]; then
  ln -s "${WORKSPACE}/outputs" "${REPO_DIR}/output"
fi
if [[ ! -e "${REPO_DIR}/cache" ]]; then
  ln -s "${WORKSPACE}/cache" "${REPO_DIR}/cache"
fi

echo "== Verifying CUDA =="
python - <<'PY'
import torch
print("torch:", torch.__version__)
print("cuda_available:", torch.cuda.is_available())
if not torch.cuda.is_available():
    raise SystemExit("CUDA is not available to PyTorch.")
print("gpu:", torch.cuda.get_device_name(0))
print("capability:", torch.cuda.get_device_capability(0))
PY

echo "== Verifying simpletuner CLI =="
simpletuner --help >/dev/null

echo ""
echo "Bootstrap complete."
echo "Next time on this machine:"
echo "  source ${WORKSPACE}/env.sh"
echo "  source ${REPO_DIR}/.venv/bin/activate"
echo ""
echo "Training data path:"
echo "  ${WORKSPACE}/datasets/person_lora/train_images"
echo ""
echo "SimpleTuner repo:"
echo "  ${REPO_DIR}"
