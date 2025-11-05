#!/usr/bin/env bash
set -euo pipefail

# ---------------- 基础设置 ----------------
PORT="${PORT:-10000}"
unset HOST
export DJANGO_SETTINGS_MODULE="label_studio.core.settings.label_studio"

# 管理员（可用 Render Environment 覆盖）
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}"
export LABEL_STUDIO_USERNAME="${LABEL_STUDIO_USERNAME:-admin@example.com}"
export LABEL_STUDIO_PASSWORD="${LABEL_STUDIO_PASSWORD:-admin123}"

# 数据目录
export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# SECRET_KEY
if [[ -z "${SECRET_KEY:-}" ]]; then
  export SECRET_KEY="$(python - <<'PY'
import secrets; print(secrets.token_urlsafe(48))
PY
)"
fi

# ---------------- 启动前修补（全量扫描）----------------
python - <<'PY'
import inspect, pathlib, re, sys
try:
    import label_studio
except Exception:
    sys.exit(0)

root = pathlib.Path(inspect.getfile(label_studio)).parent

# 需要统一加前缀的内部 app 名
apps = [
    'core','users','tasks','projects','data_manager','organizations',
    'webhooks','data_export','data_import','ml','ml_models',
    'ml_model_providers',  # ✅ 新增这一项
    'io_storages','labels_manager'
]

# 生成 import 修补规则：from <app>.xxx / import <app>.xxx / from <app> import ...
import_patterns = []
for app in apps:
    import_patterns += [
        (re.compile(rf'\bfrom\s+{app}\.'), f'from label_studio.{app}.'),
        (re.compile(rf'\bimport\s+{app}\.'), f'import label_studio.{app}.'),
        (re.compile(rf'\bfrom\s+{app}\s+import\b'), f'from label_studio.{app} import'),
    ]

# 生成字符串修补：'<app>.' / "<app>."
string_dot_patterns = []
for app in apps:
    string_dot_patterns += [
        (re.compile(rf'([\'\"])({app})\.'), r'\1label_studio.\2.'),
    ]

# 生成字符串修补：裸 '<app>' / "<app>"
string_bare_patterns = []
for app in apps:
    string_bare_patterns += [
        (re.compile(rf'([\'\"])({app})([\'\"])'), r'\1label_studio.\2\3'),
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
        new = pat.sub(repl, new)
    if new != text:
        p.write_text(new, encoding='utf-8')
        print(f'Patched in {p}')
        patched += 1

# 兜底：settings/label_studio.py 常见错误写法
p = root / 'core' / 'settings' / 'label_studio.py'
if p.exists():
    s = p.read_text(encoding='utf-8')
    s2 = s
    s2 = s2.replace('from core.settings.base', 'from label_studio.core.settings.base')
    for app in apps:
        s2 = s2.replace(f"'{app}.", f"'label_studio.{app}.")
        s2 = s2.replace(f'"{app}.', f'"label_studio.{app}.')
        s2 = s2.replace(f"'{app}'", f"'label_studio.{app}'")
        s2 = s2.replace(f'"{app}"', f'"label_studio.{app}"')
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
