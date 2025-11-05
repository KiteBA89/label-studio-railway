#!/usr/bin/env bash
set -euo pipefail

# 只升级 pip 和 setuptools（不要升级 wheel，避免与 LS 要求冲突）
python -m pip install -q --upgrade pip setuptools

# Render 注入端口；本地兜底 8080
PORT="${PORT:-8080}"

# 清除可能干扰的变量
unset HOST

# 计算 Label Studio 包目录（里面正好有 core/）
LS_DIR="$(python - <<'PY'
import os, label_studio
print(os.path.dirname(label_studio.__file__))
PY
)"

# 指定 Django 的 settings（注意不带 label_studio 前缀）
export DJANGO_SETTINGS_MODULE="core.settings.label_studio"

# 管理员账号（可被 Environment 覆盖）
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}"
export LABEL_STUDIO_USERNAME="${LABEL_STUDIO_USERNAME:-admin}"
export LABEL_STUDIO_PASSWORD="${LABEL_STUDIO_PASSWORD:-admin123}"

# 数据目录（保证存在）
export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# 用 Gunicorn 启动：切换到包目录，再加载 core.wsgi
exec gunicorn --chdir "$LS_DIR" -w 2 -k gthread -b 0.0.0.0:${PORT} core.wsgi:application
