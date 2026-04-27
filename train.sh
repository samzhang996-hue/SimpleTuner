#!/bin/bash
# ============================================================
# 启动训练（M4 32GB 专用）
# 用法：bash train.sh
# ============================================================

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PYTORCH_ENABLE_MPS_FALLBACK=1

# 激活虚拟环境
source "$(dirname "$0")/venv/bin/activate"

echo "🚀 开始 LoRA 训练（M4 32GB 模式）..."
echo "   Python: $(python --version)"
echo "   预计时间：Flux约2~3小时 / SDXL约45~70分钟"
echo "   训练中可在 ./output/face_lora 查看中间结果"
echo ""

# 检查数据集是否有照片
PHOTO_COUNT=$(ls ./dataset/client_face/*.jpg ./dataset/client_face/*.png 2>/dev/null | wc -l | tr -d ' ')
if [ "$PHOTO_COUNT" -lt 10 ]; then
  echo "❌ 照片数量不足！当前 $PHOTO_COUNT 张，至少需要 15 张"
  echo "   请把照片放入 ./dataset/client_face/ 目录"
  exit 1
fi
echo "✅ 检测到 $PHOTO_COUNT 张照片，开始训练..."
echo ""

# 读取 config.env 中的 token 并导出
export HUGGING_FACE_HUB_TOKEN=$(grep HUGGING_FACE_HUB_TOKEN config.env | cut -d'"' -f2)

python st_cli.py train --env config
