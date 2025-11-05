#!/usr/bin/env bash
set -euo pipefail

# 基础依赖（不升级 wheel，避免与 LS 要求冲突）
python -m pip install -q --upgrade pip setuptools

# Render 会注入 $PORT；本地兜底 8080
PORT="${PORT:-8080}"

# 某些平台会注入 HOST=0.0.0.0；Label Studio 会把它当外部 URL 用，这里清掉
unset HOST

# 管理员账号（也可在 Environment 中覆盖）
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}"
export LABEL_STUDIO_USERNAME="${LABEL_STUDIO_USERNAME:-admin}"
export LABEL_STUDIO_PASSWORD="${LABEL_STUDIO_PASSWORD:-admin123}"

# 数据目录（保证存在）
export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# 先做一次迁移（幂等）
python -m label_studio.manage migrate --noinput || true

# 用 Gunicorn 明确绑定端口（WSGI 模块）
exec gunicorn -w 2 -k gthread -b 0.0.0.0:${PORT} label_studio.core.wsgi:application
