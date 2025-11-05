#!/usr/bin/env bash
set -euo pipefail

# -------- 基础环境 --------
PORT="${PORT:-10000}"
unset HOST
export DJANGO_SETTINGS_MODULE="label_studio.core.settings.label_studio"

export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# 可在 Render 的 Environment 覆盖
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

echo "==> Patching imports & settings (safe mode)..."

python - <<'PY'
import inspect, pathlib, re
import label_studio

root = pathlib.Path(inspect.getfile(label_studio)).parent

# 只修补这些内部 app 的 import；不修改模型字符串引用
apps = [
    'core','users','tasks','projects','data_manager','organizations',
    'webhooks','data_export','data_import','ml','ml_models',
    'io_storages','labels_manager'
]

# 1) 仅修补 import 语句（from/import），不动普通字符串
import_rules = []
for app in apps:
    import_rules += [
        (re.compile(r'(\bfrom\s+)'+re.escape(app)+r'(\.)'), r'\1label_studio.'+app+r'\2'),
        (re.compile(r'(\bimport\s+)'+re.escape(app)+r'(\.)'), r'\1label_studio.'+app+r'\2'),
        (re.compile(r'(\bfrom\s+)'+re.escape(app)+r'(\s+import\b)'), r'\1label_studio.'+app+r'\2'),
    ]

def patch_imports(p: pathlib.Path):
    txt = p.read_text(encoding='utf-8', errors='ignore')
    new = txt
    for pat, repl in import_rules:
        new = pat.sub(repl, new)
    if new != txt:
        p.write_text(new, encoding='utf-8')
        print(f"Patched imports in {p}")

for p in root.rglob('*.py'):
    patch_imports(p)

# 2) 只在 settings 文件中修补 INSTALLED_APPS 的裸模块名，以及 REST Framework 的权限字符串
def patch_settings(fpath: pathlib.Path):
    if not fpath.exists():
        return
    s = fpath.read_text(encoding='utf-8')
    orig = s
    # INSTALLED_APPS: 将 'core' 等裸名字替换为 'label_studio.core'
    # 仅替换被引号包裹的独立项，避免误伤 'users.User' 这类模型字符串
    for app in apps:
        s = re.sub(rf"(?P<q>['\"])({app})(?P=q)", rf"\g<q>label_studio.{app}\g<q>", s)
    # REST_FRAMEWORK 里的字符串路径
    s = s.replace("core.api_permissions.HasObjectPermission",
                  "label_studio.core.api_permissions.HasObjectPermission")
    if s != orig:
        fpath.write_text(s, encoding='utf-8')
        print(f"Patched settings in {fpath}")

patch_settings(root / 'core' / 'settings' / 'label_studio.py')
patch_settings(root / 'core' / 'settings' / 'base.py')

# 3) 回修“被误改”的模型字符串（若之前误改过）
#    'label_studio.users.User' -> 'users.User'（Django 要求 'app_label.ModelName'）
model_ref_pat = re.compile(r"([\"'])label_studio\.(\w+)\.([A-Z][A-Za-z0-9_]+)([\"'])")
def revert_model_refs(p: pathlib.Path):
    txt = p.read_text(encoding='utf-8', errors='ignore')
    new = model_ref_pat.sub(lambda m: f"{m.group(1)}{m.group(2)}.{m.group(3)}{m.group(4)}", txt)
    if new != txt:
        p.write_text(new, encoding='utf-8')
        print(f"Repaired model refs in {p}")

for p in root.rglob('*.py'):
    revert_model_refs(p)
PY

echo "==> Running migrations..."
python -m label_studio.manage migrate --noinput || true

echo "==> Ensuring admin user..."
python - <<'PY'
import os, django
os.environ.setdefault("DJANGO_SETTINGS_MODULE","label_studio.core.settings.label_studio")
django.setup()
from django.contrib.auth import get_user_model
User = get_user_model()
email = os.environ.get("LABEL_STUDIO_USERNAME","admin@example.com")
pwd   = os.environ.get("LABEL_STUDIO_PASSWORD","admin123")
u, created = User.objects.get_or_create(email=email, defaults={"is_superuser": True, "is_staff": True})
u.is_superuser = True
u.is_staff = True
u.set_password(pwd)
u.save()
print("Admin ready:", email, "(created)" if created else "(updated)")
PY

echo "==> Starting gunicorn on port ${PORT} ..."
exec gunicorn label_studio.core.wsgi:application \
  --bind 0.0.0.0:${PORT} \
  --workers ${GUNICORN_WORKERS:-2} \
  --threads ${GUNICORN_THREADS:-2} \
  --timeout ${GUNICORN_TIMEOUT:-120} \
  --log-level ${GUNICORN_LOG_LEVEL:-info}
