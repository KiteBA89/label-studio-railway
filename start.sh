#!/usr/bin/env bash
set -euo pipefail

python -m pip install -q --upgrade pip setuptools

PORT="${PORT:-8080}"

unset HOST
# 关键：显式指定 Django 的 settings 模块为 Label Studio 的全路径
export DJANGO_SETTINGS_MODULE="label_studio.core.settings.label_studio"

# 管理员账号（可被 Environment 覆盖）
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}"
export LABEL_STUDIO_USERNAME="${LABEL_STUDIO_USERNAME:-admin}"
export LABEL_STUDIO_PASSWORD="${LABEL_STUDIO_PASSWORD:-admin123}"

export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# 用 gunicorn 显式绑定 0.0.0.0:$PORT
exec gunicorn -w 2 -k gthread -b 0.0.0.0:${PORT} label_studio.core.wsgi:application
