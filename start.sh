#!/usr/bin/env bash
set -euo pipefail

# -------- 基础环境 --------
PORT="${PORT:-10000}"
unset HOST
export DJANGO_SETTINGS_MODULE="label_studio.core.settings.label_studio"

export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# 管理员（可在 Render 的 Environment 覆盖）
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}"
export LABEL_STUDIO_USERNAME="${LABEL_STUDIO_USERNAME:-admin@example.com}"
export LABEL_STUDIO_PASSWORD="${LABEL_STUDIO_PASSWORD:-admin123}"

# SECRET_KEY（没有就生成一个）
if [[ -z "${SECRET_KEY:-}" ]]; then
  export SECRET_KEY="$(python - <<'PY'
import secrets; print(secrets.token_urlsafe(48))
PY
)"
fi

# -------- 仅修补 import；回修被误改的模型字符串 --------
python - <<'PY'
import inspect, pathlib, re, sys

try:
    import label_studio
except Exception:
    sys.exit(0)

root = pathlib.Path(inspect.getfile(label_studio)).parent

# 需要处理的内部 app
apps = [
    'core','users','tasks','projects','data_manager','organizations',
    'webhooks','data_export','data_import','ml','ml_models',
    'ml_model_providers',
    'io_storages','labels_manager'
]

# 1) 只修补 import 语句（from/import），不动普通字符串
import_rules = []
for app in apps:
    import_rules += [
        (re.compile(rf'\bfrom\s+{app}\.'),   f'from label_studio.{app}.'),
        (re.compile(rf'\bimport\s+{app}\.'), f'import label_studio.{app}.'),
        (re.compile(rf'\bfrom\s+{app}\s+import\b'), f'from label_studio.{app} import'),
    ]

patched = 0
for p in root.rglob('*.py'):
    txt = p.read_text(encoding='utf-8', errors='ignore')
    new = txt
    for pat, repl in import_rules:
        new = pat.sub(repl, new)
    if new != txt:
        p.write_text(new, encoding='utf-8')
        print(f"Patched imports in {p}")
        patched += 1

# 2) 只在 settings 文件中修补 INSTALLED_APPS 的裸模块名
def patch_settings_file(path: pathlib.Path):
    if not path.exists(): 
        return
    s = path.read_text(encoding='utf-8')
    s2 = s
    for app in apps:
        # 将 'core' -> 'label_studio.core'（仅限 settings 文件）
        s2 = s2.replace(f"'{app}'", f"'label_studio.{app}'")
        s2 = s2.replace(f"\"{app}\"", f"\"label_studio.{app}\"")
        s2 = s2.replace(f"'{app}.", f"'label_studio.{app}.")
        s2 = s2.replace(f"\"{app}.", f"\"label_studio.{app}.")
    # 特例：基础设置导入
    s2 = s2.replace('from core.settings.base', 'from label_studio.core.settings.base')
    if s2 != s:
        path.write_text(s2, encoding='utf-8')
        print(f"Patched settings in {path}")

patch_settings_file(root / 'core' / 'settings' / 'label_studio.py')
patch_settings_file(root / 'core' / 'settings' / 'base.py')

# 3) 回修“被误改”的模型字符串：'label_studio.<app>.<Model>' -> '<app>.<Model>'
app_alt = '(?:' + '|'.join(map(re.escape, apps)) + ')'
model_ref_pat = re.compile(r'([\'\"])label_studio\.' + app_alt + r'\.([A-Z][A-Za-z0-9_]+)([\'\"])')

for p in root.rglob('*.py'):
    txt = p.read_text(encoding='utf-8', errors='ignore')
    def _fix(m):
        full = m.group(0)
        quote1, app, model, quote2 = m.group(1), None, None, m.group(3)
        # 重新解析以拿到 app 名
    PY
python - <<'PY'
import inspect, pathlib, re, sys
import label_studio

root = pathlib.Path(inspect.getfile(label_studio)).parent
apps = [
    'core','users','tasks','projects','data_manager','organizations',
    'webhooks','data_export','data_import','ml','ml_models',
    'ml_model_providers',
    'io_storages','labels_manager'
]
app_alt = '(?:' + '|'.join(map(re.escape, apps)) + ')'
model_ref_pat = re.compile(r'([\'\"])label_studio\.(' + app_alt + r')\.([A-Z][A-Za-z0-9_]+)([\'\"])')

for p in root.rglob('*.py'):
    txt = p.read_text(encoding='utf-8', errors='ignore')
    new = model_ref_pat.sub(lambda m: f"{m.group(1)}{m.group(2)}.{m.group(3)}{m.group(4)}", txt)
    if new != txt:
        p.write_text(new, encoding='utf-8')
        print(f"Repaired model refs in {p}")
PY
# -------- 迁移数据库（幂等）--------
python -m label_studio.manage migrate --noinput || true

# -------- 确保管理员账号存在 --------
python - <<'PY'
import os, django
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "label_studio.core.settings.label_studio")
django.setup()
from users.models import User  # 注意：这里用 app_label 导入，以适配 AUTH_USER_MODEL = 'users.User'
email = os.environ.get("LABEL_STUDIO_USERNAME","admin@example.com")
pwd = os.environ.get("LABEL_STUDIO_PASSWORD","admin123")
u, created = User.objects.get_or_create(email=email, defaults={"is_superuser": True, "is_staff": True})
u.is_superuser = True; u.is_staff = True
u.set_password(pwd); u.save()
print("Admin ready:", email, "(created)" if created else "(updated)")
PY

# -------- 启动 Gunicorn --------
exec gunicorn label_studio.core.wsgi:application \
  --bind 0.0.0.0:${PORT} \
  --workers ${GUNICORN_WORKERS:-2} \
  --threads ${GUNICORN_THREADS:-2} \
  --timeout ${GUNICORN_TIMEOUT:-120} \
  --log-level ${GUNICORN_LOG_LEVEL:-info}
