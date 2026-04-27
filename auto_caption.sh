#!/bin/bash
# ============================================================
# 批量生成 caption（触发词）文件
# 用法：bash auto_caption.sh
# ============================================================

DATASET_DIR="./dataset/client_face"
TRIGGER_WORD="ohwx person"

echo "📝 自动生成 caption 文件..."

for img in "$DATASET_DIR"/*.jpg "$DATASET_DIR"/*.png; do
  [ -f "$img" ] || continue
  base="${img%.*}"
  txt_file="${base}.txt"
  
  if [ ! -f "$txt_file" ]; then
    echo "${TRIGGER_WORD}" > "$txt_file"
    echo "   生成: $(basename $txt_file)"
  fi
done

echo "✅ Caption 生成完成"
echo ""
echo "💡 提示：可以手动给部分图片添加更详细的描述"
echo "   例：ohwx person, smiling, looking at camera, warehouse background"
