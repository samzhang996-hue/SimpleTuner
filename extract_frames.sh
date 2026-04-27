#!/bin/bash
# ============================================================
# 自动抽帧脚本：从客户视频提取高质量人脸帧
# 用法：bash extract_frames.sh ./客户视频.mp4
# 需要：brew install ffmpeg
# ============================================================

VIDEO=$1
OUTPUT_DIR="./dataset/client_face"
FRAME_RATE=1   # 每秒抽1帧，5分钟视频约300张

mkdir -p "$OUTPUT_DIR"

echo "📹 开始从视频抽帧..."
echo "   来源: $VIDEO"
echo "   输出: $OUTPUT_DIR"
echo ""

# 抽帧（每秒1帧，高质量JPEG）
ffmpeg -i "$VIDEO" \
  -vf "fps=$FRAME_RATE,scale=1024:1024:force_original_aspect_ratio=decrease,pad=1024:1024:(ow-iw)/2:(oh-ih)/2" \
  -q:v 2 \
  "$OUTPUT_DIR/frame_%04d.jpg"

FRAME_COUNT=$(ls "$OUTPUT_DIR"/*.jpg 2>/dev/null | wc -l)
echo ""
echo "✅ 抽帧完成！共 $FRAME_COUNT 张图片"
echo ""
echo "📌 下一步："
echo "   1. 打开 $OUTPUT_DIR 目录"
echo "   2. 手动删除模糊/遮脸/侧脸过大的图片"
echo "   3. 保留 20~50 张最清晰的人脸图"
echo "   4. 为每张图创建同名 .txt 文件，写上触发词"
echo "      例：frame_0001.txt 内容→ ohwx person, standing, looking at camera"
