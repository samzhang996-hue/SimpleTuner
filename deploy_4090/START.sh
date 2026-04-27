#!/usr/bin/env bash
# ============================================================
# 4090 云端训练一键启动脚本
# 用法：bash START.sh
# ============================================================
set -Eeuo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${HOME}/simpletuner_workspace"
REPO_DIR="${WORKSPACE}/SimpleTuner"

echo "========================================"
echo " SimpleTuner 4090 一键部署启动"
echo " 部署包目录: ${DEPLOY_DIR}"
echo " 工作目录:   ${WORKSPACE}"
echo "========================================"

# ── 1. 系统依赖 ──────────────────────────────────────────────
echo ""
echo "[1/7] 安装系统依赖..."
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -q
  apt-get install -y -q git git-lfs ffmpeg build-essential rsync curl
  git lfs install || true
fi

# ── 2. 克隆 SimpleTuner ──────────────────────────────────────
echo ""
echo "[2/7] 获取 SimpleTuner 源码..."
mkdir -p "${WORKSPACE}"
if [[ ! -d "${REPO_DIR}/.git" ]]; then
  git clone https://github.com/bghira/SimpleTuner.git "${REPO_DIR}"
else
  echo "  已存在，跳过克隆"
fi

# ── 3. Python 环境 ───────────────────────────────────────────
echo ""
echo "[3/7] 创建 Python 虚拟环境并安装依赖..."
cd "${REPO_DIR}"

pick_python() {
  for c in python3.13 python3.12 python3; do
    if command -v "${c}" >/dev/null 2>&1; then
      if "${c}" -c "import sys; raise SystemExit(0 if (3,12)<=sys.version_info<(3,14) else 1)" 2>/dev/null; then
        command -v "${c}"; return 0
      fi
    fi
  done
  return 1
}

PYTHON_BIN="$(pick_python || true)"
USE_UV_FOR_VENV=0
if [[ -z "${PYTHON_BIN}" ]]; then
  echo "  未找到 Python 3.12/3.13，通过 uv 安装..."
  pip install -q --user uv 2>/dev/null || python3 -m pip install -q --user uv
  export PATH="${HOME}/.local/bin:${PATH}"
  uv python install 3.12
  USE_UV_FOR_VENV=1
else
  "${PYTHON_BIN}" -c "
import sys
if sys.version_info < (3, 12) or sys.version_info >= (3, 14):
    raise SystemExit(f'Python 3.12 or 3.13 required, got {sys.version}')
print(sys.version)
"
fi

cd "${REPO_DIR}"

echo "[venv] 创建虚拟环境..."
if [[ "${USE_UV_FOR_VENV}" == "1" ]]; then
  uv venv --python 3.12 --seed .venv
  source .venv/bin/activate
  uv pip install -U pip setuptools wheel
  uv pip install -e '.[cuda]'
else
  "${PYTHON_BIN}" -m venv .venv
  source .venv/bin/activate
  python -m pip install -q -U pip setuptools wheel
  python -m pip install -e '.[cuda]'
fi

# ── 4. 移除已知冲突包 ────────────────────────────────────────
echo ""
echo "[4/7] 移除冲突包（deepspeed / torchao）..."
pip uninstall -y deepspeed torchao 2>/dev/null || true

# ── 5. 同步配置和数据集 ──────────────────────────────────────
echo ""
echo "[5/7] 同步配置和训练数据..."
mkdir -p "${REPO_DIR}/config" "${REPO_DIR}/dataset/client_face" "${REPO_DIR}/output" "${REPO_DIR}/cache"

cp -f "${DEPLOY_DIR}/config/config.json"           "${REPO_DIR}/config/"
cp -f "${DEPLOY_DIR}/config/multidatabackend.json" "${REPO_DIR}/config/"

rsync -a --exclude='._*' --exclude='.DS_Store' \
  "${DEPLOY_DIR}/dataset/client_face/" \
  "${REPO_DIR}/dataset/client_face/"

# 清理 Mac 产生的垃圾文件
find "${REPO_DIR}/dataset/client_face" -name '._*' -delete 2>/dev/null || true

# ── 6. 验证 GPU ──────────────────────────────────────────────
echo ""
echo "[6/7] 验证 CUDA / GPU..."
python - <<'PY'
import torch
print(f"  torch:     {torch.__version__}")
print(f"  CUDA 可用: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"  GPU:       {torch.cuda.get_device_name(0)}")
else:
    raise SystemExit("ERROR: CUDA 不可用，请检查驱动和 torch 版本")
PY

# ── 7. 登录 HuggingFace 并开始训练 ──────────────────────────
echo ""
echo "[7/7] 准备训练..."
echo ""
echo "  ⚠️  接下来需要输入 HuggingFace Token（用于下载 FLUX.1-dev）"
echo "      获取地址: https://huggingface.co/settings/tokens"
echo "      如果使用 SDXL 方案（config.json 里已配置），可直接回车跳过"
echo ""
huggingface-cli login --add-to-git-credential || true

echo ""
echo "========================================"
echo " 环境就绪，开始训练！"
echo "========================================"
cd "${REPO_DIR}"
export HF_HUB_DISABLE_XET=1
export HF_HUB_ENABLE_HF_TRANSFER=1

python -m simpletuner.cli train 2>&1 | tee "${WORKSPACE}/train_$(date +%Y%m%d_%H%M%S).log"

echo ""
echo "训练完成！输出文件在: ${REPO_DIR}/output/face_lora/"
