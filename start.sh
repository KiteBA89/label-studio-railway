#!/usr/bin/env bash
set -euo pipefail

# 确保运行时具备 pkg_resources 等
python -m pip install -q --upgrade pip setuptools

# Render 注入的端口；本地兜底 8080
PORT="${PORT:-8080}"

# 某些平台会注入 HOST=0.0.0.0；Label Studio把它当外部URL用会报 warning，这里清掉
unset HOST

# 管理员账号（可在环境变量中覆盖）
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}"
export LABEL_STUDIO_USERNAME="${LABEL_STUDIO_USERNAME:-admin}"
export LABEL_STUDIO_PASSWORD="${LABEL_STUDIO_PASSWORD:-admin123}"

# 数据目录（保证存在）
export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# 显式绑定 0.0.0.0:$PORT
label-studio start --host 0.0.0.0 --port "$PORT"
