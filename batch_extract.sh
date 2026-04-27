#!/bin/bash
# ============================================================
# 批量抽帧脚本：支持多个视频同时处理
# 用法：把所有视频放入 dataset/ 目录，然后运行 bash batch_extract.sh
# ============================================================

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

VIDEO_DIR="./dataset"
OUTPUT_DIR="./dataset/client_face"
FRAME_RATE=3  # 每秒抽3帧（15秒视频=45张）

mkdir -p "$OUTPUT_DIR"

# 找所有视频文件
VIDEOS=$(find "$VIDEO_DIR" -maxdepth 1 -type f \( -name "*.mp4" -o -name "*.mov" -o -name "*.MP4" -o -name "*.MOV" -o -name "*.m4v" \))

if [ -z "$VIDEOS" ]; then
  echo "❌ dataset/ 目录下没有找到视频文件"
  echo "   支持格式：mp4 / mov / m4v"
  exit 1
fi

echo "🎬 找到以下视频："
echo "$VIDEOS" | while read f; do
  DURATION=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null)
  DURATION_INT=${DURATION%.*}
  echo "   $(basename $f) → 时长约 ${DURATION_INT}秒，预计抽 $((DURATION_INT * FRAME_RATE)) 张"
done
echo ""

FRAME_NUM=1
echo "$VIDEOS" | while read VIDEO; do
  BASENAME=$(basename "$VIDEO" | sed 's/\.[^.]*$//')
  echo "▶ 处理：$(basename $VIDEO)"

  # 抽帧，文件名带视频来源前缀
  ffmpeg -i "$VIDEO" \
    -vf "fps=$FRAME_RATE,scale=1024:1024:force_original_aspect_ratio=decrease,pad=1024:1024:(ow-iw)/2:(oh-ih)/2" \
    -q:v 2 \
    "${OUTPUT_DIR}/${BASENAME}_%04d.jpg" \
    -y 2>/dev/null

  COUNT=$(ls "${OUTPUT_DIR}/${BASENAME}_"*.jpg 2>/dev/null | wc -l | tr -d ' ')
  echo "   ✅ 抽取 $COUNT 张"
done

echo ""
TOTAL=$(ls "$OUTPUT_DIR"/*.jpg 2>/dev/null | wc -l | tr -d ' ')
echo "================================================"
echo "✅ 全部完成！共抽取：$TOTAL 张图片"
echo "   位置：$OUTPUT_DIR"
echo ""
echo "📌 下一步："
echo "   1. 打开 Finder 查看图片（已自动打开）"
echo "   2. 删掉模糊、遮脸、极度侧脸的图"
echo "   3. 保留 20~50 张清晰人脸图"
echo "   4. 运行：bash auto_caption.sh"
echo "   5. 运行：bash train.sh"
echo "================================================"

# 打开 Finder
open "$OUTPUT_DIR"
