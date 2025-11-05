#!/usr/bin/env bash
set -euo pipefail

# 只升级 pip 和 setuptools（不要升级 wheel，避免与 LS 要求冲突）
python -m pip install -q --upgrade pip setuptools

# Render 注入端口；本地兜底 8080
PORT="${PORT:-8080}"

# 清除可能干扰的变量
unset HOST

# 计算 Label Studio 的包目录（里面正好有 core/）
LS_DIR="$(python - <<'PY'
import os, label_studio
print(os.path.dirname(label_studio.__file__))
PY
)"

# 切到包目录，并显式指定 settings
cd "$LS_DIR"
export DJANGO_SETTINGS_MODULE="core.settings.label_studio"

# 做数据库迁移（幂等）
python -m label_studio.manage migrate --noinput

# 用 Gunicorn 明确绑定 0.0.0.0:$PORT 到 WSGI 入口
exec gunicorn -w 2 -k gthread -b 0.0.0.0:${PORT} core.wsgi:application
