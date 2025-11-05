#!/usr/bin/env bash
set -euo pipefail

# 只升级 pip 与 setuptools（不要升级 wheel，避免与 LS 要求冲突）
python -m pip install -q --upgrade pip setuptools

# Render 注入的端口；本地兜底 8080
PORT="${PORT:-8080}"

# 清除可能干扰的变量
unset HOST
export DJANGO_SETTINGS_MODULE="label_studio.core.settings.label_studio"

# 管理员账号（可被 Environment 覆盖）
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}"
export LABEL_STUDIO_USERNAME="${LABEL_STUDIO_USERNAME:-admin}"
export LABEL_STUDIO_PASSWORD="${LABEL_STUDIO_PASSWORD:-admin123}"

# 数据目录（保证存在）
export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# 用 Gunicorn 明确绑定 0.0.0.0:$PORT 到 Label Studio 的 WSGI 入口
exec gunicorn -w 2 -k gthread -b 0.0.0.0:${PORT} label_studio.core.wsgi:application
