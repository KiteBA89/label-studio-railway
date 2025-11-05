#!/usr/bin/env bash
set -euo pipefail

# 保证运行时有 pkg_resources 等
python -m pip install -q --upgrade pip setuptools wheel

# Render 会注入 $PORT；本地时用 8080 兜底
PORT="${PORT:-8080}"

# 有的平台会把 HOST=0.0.0.0 注入到环境，LS 会把它当“外部访问 URL”用，导致告警；直接清掉
unset HOST

# 管理员账号（也可在 Render 的 Environment 里覆盖）
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}"
export LABEL_STUDIO_USERNAME="${LABEL_STUDIO_USERNAME:-admin}"
export LABEL_STUDIO_PASSWORD="${LABEL_STUDIO_PASSWORD:-admin123}"

# 数据目录（确保存在）
export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# 启动（显式绑定 0.0.0.0:$PORT）
label-studio start --host 0.0.0.0 --port "$PORT"
