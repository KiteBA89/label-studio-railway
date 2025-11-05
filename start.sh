#!/usr/bin/env bash
set -euo pipefail

# =============== 基础设置 ===============
# Render 会提供要监听的端口到 $PORT；默认兜底 10000
PORT="${PORT:-10000}"

# 避免 Label Studio 读取到没有 http(s) 前缀的 HOST 报告 warning
unset HOST

# 管理员账号（可被 Render 环境变量覆盖）
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}"
export LABEL_STUDIO_USERNAME="${LABEL_STUDIO_USERNAME:-admin@example.com}"  # 必须像邮箱
export LABEL_STUDIO_PASSWORD="${LABEL_STUDIO_PASSWORD:-admin123}"

# 数据目录（持久化）
export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# SECRET_KEY 若未提供则临时生成一串随机值（建议在环境变量里长期固定）
if [[ -z "${SECRET_KEY:-}" ]]; then
  export SECRET_KEY="$(python - <<'PY'
import secrets; print(secrets.token_urlsafe(48))
PY
)"
fi

# =============== 兼容修补 ===============
# 修补 1.14.0 包中 settings 的错误 import（幂等，已修补则不改）
python - <<'PY'
import inspect, pathlib, sys
try:
    import label_studio
except Exception:
    sys.exit(0)

p = pathlib.Path(inspect.getfile(label_studio)).parent / "core" / "settings" / "label_studio.py"
if p.exists():
    s = p.read_text(encoding="utf-8")
    s2 = s.replace("from core.settings.base", "from label_studio.core.settings.base")
    if s2 != s:
        p.write_text(s2, encoding="utf-8")
        print(f"Patched import in {p}")
    else:
        print("No patch needed")
PY

# =============== 以 Gunicorn 启动（规避 manage.py） ===============
exec gunicorn label_studio.core.wsgi:application \
  --bind 0.0.0.0:${PORT} \
  --workers ${GUNICORN_WORKERS:-2} \
  --threads ${GUNICORN_THREADS:-2} \
  --timeout ${GUNICORN_TIMEOUT:-120} \
  --log-level ${GUNICORN_LOG_LEVEL:-info}
