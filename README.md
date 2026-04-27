# SimpleTuner M4 32GB 人脸 LoRA 训练指南

> 设备：Apple M4 32GB  
> 目标：训练客户专属人脸 LoRA，用于 AI 带货视频生成

---

## 目录结构

```
SimpleTuner_M4_32GB/
├── config.env              ← 核心训练参数
├── multidatabackend.json   ← 数据集配置
├── extract_frames.sh       ← 从视频抽帧
├── auto_caption.sh         ← 自动生成触发词文件
├── train.sh                ← 启动训练
├── dataset/
│   ├── client_face/        ← 放客户照片（20~50张）
│   └── regularization/     ← 放正则化图片（可选）
├── output/
│   └── face_lora/          ← 训练结果输出
└── cache/                  ← 训练缓存（自动生成）
```

---

## Step 1：安装 SimpleTuner

```bash
# 克隆仓库
git clone https://github.com/bghira/SimpleTuner.git
cd SimpleTuner

# 创建虚拟环境（Python 3.11）
python3.11 -m venv venv
source venv/bin/activate

# 安装依赖（M4 Metal 加速版）
pip install torch torchvision torchaudio
pip install -r requirements.txt
```

---

## Step 2：准备数据集

### 方式A：直接放图片
```bash
mkdir -p dataset/client_face

# 把20~50张客户照片放进去
# 文件格式：JPG / PNG
# 分辨率：建议 512px 以上
```

### 方式B：从视频抽帧（推荐）
```bash
# 先安装 ffmpeg
brew install ffmpeg

# 运行抽帧脚本
bash extract_frames.sh ./客户提供的视频.mp4

# 然后进目录手动删除模糊/遮脸的帧，保留20~50张
```

### 生成 Caption 文件
```bash
bash auto_caption.sh

# 每张图会自动生成同名的 .txt 文件
# 内容：ohwx person
# 触发词 ohwx person 在生成图片时会召唤这个人的脸
```

---

## Step 3：配置参数

编辑 `config.env`，只需要改这几个地方：

```bash
# 1. 选择模型（Flux 效果好但慢，SDXL 快）
MODEL_TYPE="flux"  # 或 "sdxl"

# 2. HuggingFace Token（只有 Flux 需要）
HUGGING_FACE_HUB_TOKEN="hf_你的token"

# 3. 训练步数（根据数据量调整）
# 图片数量 × 10 ≤ MAX_TRAIN_STEPS ≤ 图片数量 × 50
# 30张图片 → 推荐 800~1500步
MAX_TRAIN_STEPS=1200
```

---

## Step 4：启动训练

```bash
# 确保在 SimpleTuner 根目录，且复制配置文件
cp /path/to/SimpleTuner_M4_32GB/config.env ./config.env
cp /path/to/SimpleTuner_M4_32GB/multidatabackend.json ./multidatabackend.json

# 启动
bash /path/to/SimpleTuner_M4_32GB/train.sh
```

---

## 训练中查看效果

每 200 步会自动生成验证图片，位置：
```
./output/face_lora/validation/
```

**判断标准：**
- 步数 200~400：可能还不像
- 步数 600~800：开始有明显相似度
- 步数 1000~1200：效果最佳区间
- 步数过多（>2000）：开始过拟合，表情变僵硬

---

## 训练完成后

LoRA 文件位置：`./output/face_lora/pytorch_lora_weights.safetensors`

**在 ComfyUI 中使用：**
1. 把 `.safetensors` 文件放入 `ComfyUI/models/loras/`
2. 在工作流中添加 `Load LoRA` 节点
3. 触发词写 `ohwx person`
4. strength 建议从 0.8 开始调试

---

## M4 32GB 性能参考

| 模型 | 训练时间 | 出图速度 | 推荐场景 |
|------|---------|---------|---------|
| Flux.1-dev LoRA | 2~3小时 | 20~30秒/张 | 最高质量接单 |
| SDXL LoRA | 45~70分钟 | 8~15秒/张 | 快速出方案 |

---

## 常见问题

**Q：训练时 MPS 报错？**
```bash
export PYTORCH_ENABLE_MPS_FALLBACK=1
# 加在 train.sh 里已经有了，不用手动
```

**Q：内存不够？**
```bash
# 降低 batch size
TRAIN_BATCH_SIZE=1
GRADIENT_ACCUMULATION_STEPS=4  # 等效 batch 不变
```

**Q：人脸相似度不够高？**
- 增加数据集质量（删掉模糊、侧脸、遮挡图片）
- 增加训练步数（+300步再看效果）
- 提高 LoRA rank：`LORA_RANK=32`

---

*最后更新：2026-04-13*
