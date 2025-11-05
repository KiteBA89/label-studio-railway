#!/usr/bin/env bash
set -euo pipefail

# ---------------- 基础设置 ----------------
PORT="${PORT:-10000}"
unset HOST  # 避免非 http(s) 的 HOST 触发 warning

# 显式指定 Django settings（更稳）
export DJANGO_SETTINGS_MODULE="label_studio.core.settings.label_studio"

# 管理员账号（可被 Render Environment 覆盖）
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}"
export LABEL_STUDIO_USERNAME="${LABEL_STUDIO_USERNAME:-admin@example.com}"
export LABEL_STUDIO_PASSWORD="${LABEL_STUDIO_PASSWORD:-admin123}"

# 数据目录（持久化）
export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# SECRET_KEY：若未提供则临时生成（推荐在 Environment 中固定一个）
if [[ -z "${SECRET_KEY:-}" ]]; then
  export SECRET_KEY="$(python - <<'PY'
import secrets; print(secrets.token_urlsafe(48))
PY
)"
fi

# ---------------- 启动前修补（全量扫描）----------------
# 1) 修补 import 语句里的 core.*
# 2) 也修补所有 Python 源码里以字符串写的 "core.*" / 'core.*'
python - <<'PY'
import inspect, pathlib, re, sys
try:
    import label_studio
except Exception:
    sys.exit(0)

root = pathlib.Path(inspect.getfile(label_studio)).parent

# 代码层面的 import 替换
import_patterns = [
    (re.compile(r'\bfrom\s+core\.'), 'from label_studio.core.'),
    (re.compile(r'\bimport\s+core\.'), 'import label_studio.core.'),
    (re.compile(r'\bfrom\s+core\s+import\b'), 'from label_studio.core import'),
]

# 字符串里的 'core.' / "core." 替换（比如 DRF 的设置项里）
string_patterns = [
    (re.compile(r'([\'\"])core\.'), r'\1label_studio.core.'),
]

for p in root.rglob('*.py'):
    text = p.read_text(encoding='utf-8', errors='ignore')
    new = text
    for pat, repl in import_patterns:
        new = pat.sub(repl, new)
    for pat, repl in string_patterns:
        new = pat.sub(repl, new)
    if new != text:
        p.write_text(new, encoding='utf-8')
        print(f'Patched imports/strings in {p}')

# 兜底修补历史文件：settings/label_studio.py 的错误写法
p = root / 'core' / 'settings' / 'label_studio.py'
if p.exists():
    s = p.read_text(encoding='utf-8')
    s2 = s.replace('from core.settings.base', 'from label_studio.core.settings.base')
    s2 = s2.replace("'core.", "'label_studio.core.")
    s2 = s2.replace('"core.', '"label_studio.core.')
    if s2 != s:
        p.write_text(s2, encoding='utf-8')
        print(f'Patched import in {p}')
PY

# ---------------- 使用 Gunicorn 启动 ----------------
exec gunicorn label_studio.core.wsgi:application \
  --bind 0.0.0.0:${PORT} \
  --workers ${GUNICORN_WORKERS:-2} \
  --threads ${GUNICORN_THREADS:-2} \
  --timeout ${GUNICORN_TIMEOUT:-120} \
  --log-level ${GUNICORN_LOG_LEVEL:-info}
