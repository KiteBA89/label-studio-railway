#!/usr/bin/env bash
set -euo pipefail

# ---------------- 基础设置 ----------------
PORT="${PORT:-10000}"
unset HOST  # 避免非 http(s) 的 HOST 触发 warning
export DJANGO_SETTINGS_MODULE="label_studio.core.settings.label_studio"

# 管理员（可在 Render Environment 覆盖）
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}"
export LABEL_STUDIO_USERNAME="${LABEL_STUDIO_USERNAME:-admin@example.com}"   # 必须像邮箱
export LABEL_STUDIO_PASSWORD="${LABEL_STUDIO_PASSWORD:-admin123}"

# 数据目录
export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# SECRET_KEY：若未提供则临时生成（建议在 Environment 固定一个）
if [[ -z "${SECRET_KEY:-}" ]]; then
  export SECRET_KEY="$(python - <<'PY'
import secrets; print(secrets.token_urlsafe(48))
PY
)"
fi

# ---------------- 启动前修补（全量扫描）----------------
# 1) 修补 import 里的 core.*
# 2) 修补字符串里的 'core.' / "core."
# 3) 修补 INSTALLED_APPS 等场景的裸 app 名（'core','users',...）为 'label_studio.<app>'
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
# 字符串里的 'core.' / "core."
string_dot_patterns = [
    (re.compile(r'([\'\"])core\.'), r'\1label_studio.core.'),
]
# 裸 app 名（仅限 Label Studio 内部 app；避免误伤第三方）
apps = [
    'core','users','tasks','projects','data_manager','organizations',
    'webhooks','data_export','data_import','ml','ml_models',
    'io_storages','labels_manager'
]
string_bare_patterns = []
for app in apps:
    string_bare_patterns += [
        (re.compile(rf"([\'\"])({app})([\'\"])"), rf"\1label_studio.\2\3"),
    ]

patched = 0
for p in root.rglob('*.py'):
    text = p.read_text(encoding='utf-8', errors='ignore')
    new = text
    for pat, repl in import_patterns:
        new = pat.sub(repl, new)
    for pat, repl in string_dot_patterns:
        new = pat.sub(repl, new)
    for pat, repl in string_bare_patterns:
        # 仅替换完全等于 'app' 或 "app" 的情况
        new = pat.sub(repl, new)
    if new != text:
        p.write_text(new, encoding='utf-8')
        print(f'Patched in {p}')
        patched += 1

# 兜底修补历史文件：settings/label_studio.py 的错误写法
p = root / 'core' / 'settings' / 'label_studio.py'
if p.exists():
    s = p.read_text(encoding='utf-8')
    s2 = s.replace('from core.settings.base', 'from label_studio.core.settings.base')
    s2 = s2.replace("'core.", "'label_studio.core.").replace('"core.', '"label_studio.core.')
    for app in apps:
        s2 = s2.replace(f"'{app}'", f"'label_studio.{app}'").replace(f'"{app}"', f'"label_studio.{app}"')
    if s2 != s:
        p.write_text(s2, encoding='utf-8')
        print(f'Patched in {p}')
PY

# ---------------- 迁移数据库（幂等） ----------------
python -m label_studio.manage migrate --noinput || true

# ---------------- 确保管理员存在 ----------------
python - <<'PY'
import os, django
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "label_studio.core.settings.label_studio")
django.setup()
from users.models import User

email = os.environ.get("LABEL_STUDIO_USERNAME","admin@example.com")
pwd = os.environ.get("LABEL_STUDIO_PASSWORD","admin123")
u, created = User.objects.get_or_create(email=email, defaults={"is_superuser": True, "is_staff": True})
u.is_superuser = True; u.is_staff = True
u.set_password(pwd); u.save()
print("Admin ready:", email, "(created)" if created else "(updated)")
PY

# ---------------- 使用 Gunicorn 启动 ----------------
exec gunicorn label_studio.core.wsgi:application \
  --bind 0.0.0.0:${PORT} \
  --workers ${GUNICORN_WORKERS:-2} \
  --threads ${GUNICORN_THREADS:-2} \
  --timeout ${GUNICORN_TIMEOUT:-120} \
  --log-level ${GUNICORN_LOG_LEVEL:-info}
