#!/usr/bin/env bash
set -euo pipefail

# Render 会注入 $PORT；若没有就回退 10000
export PORT="${PORT:-10000}"

# 数据目录（可自定义）
export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# 一些云端功能会读取 HOST 环境变量，但它要求是 URL。
# Render 通常会把 HOST=0.0.0.0 之类的值传进来，这会触发告警；我们干脆去掉它。
unset HOST || true

# SECRET_KEY 建议放到 Render 的环境变量面板里固定；如果没配，这里临时生成一个。
if [[ -z "${SECRET_KEY:-}" ]]; then
  export SECRET_KEY="$(python - <<'PY'
import secrets; print(secrets.token_urlsafe(48))
PY
)"
fi

# 关键：不要再调用 manage.py / migrate 之类的命令！
# 直接用官方启动器（它会正确设置 sys.path，让 core/users 等短名可被 import）
# 等价于终端命令：label-studio start --host 0.0.0.0 --port $PORT
exec python -m label_studio.server --host 0.0.0.0 --port "$PORT"
