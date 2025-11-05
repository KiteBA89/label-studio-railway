#!/usr/bin/env bash
set -euo pipefail

# Render 会注入 $PORT；没有就回退 10000
export PORT="${PORT:-10000}"

# 数据目录（可自定义）
export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# 可选：首用户创建开关（先允许自助注册更省事）
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-false}"

# 必需：SECRET_KEY（稳定起见，建议在 Render 的环境变量里固定一个值）
if [[ -z "${SECRET_KEY:-}" ]]; then
  export SECRET_KEY="$(python - <<'PY'
import secrets; print(secrets.token_urlsafe(48))
PY
)"
fi

# 迁移（失败不致命，继续跑）
python -m label_studio.manage migrate --noinput || true

# 关键：用官方启动器，它会正确设置 sys.path（短名 app 才能正常 import）
# 等价于：label-studio start --host 0.0.0.0 --port $PORT
exec python -m label_studio.server --host 0.0.0.0 --port "$PORT"
