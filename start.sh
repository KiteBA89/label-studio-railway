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
import importlib
import label_studio

root = pathlib.Path(inspect.getfile(label_studio)).parent

# 需要处理的内部 app
apps = [
    'core','users','tasks','projects','data_manager','organizations',
    'webhooks','data_export','data_import','ml','ml_models',
    'io_storages','labels_manager'
]

# ---------- 1) 修补 import 路径（仅修补 import 语句） ----------
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

# ---------- 2) 修补 settings：INSTALLED_APPS/权限字符串/移除无效 app ----------
def patch_settings(fpath: pathlib.Path):
    if not fpath.exists():
        return
    s = fpath.read_text(encoding='utf-8')
    orig = s
    # 将 'core' 等裸名字替换为 'label_studio.core'（仅限引号包裹的独立项）
    for app in apps:
        s = re.sub(rf"(?P<q>['\"])({app})(?P=q)", rf"\g<q>label_studio.{app}\g<q>", s)
        s = re.sub(rf"(?P<q>['\"])({app}\.apps\.[A-Za-z0-9_]+Config)(?P=q)",
                   rf"\g<q>label_studio.{app}.apps.\2\g<q>", s)
    # REST_FRAMEWORK 权限路径
    s = s.replace("core.api_permissions.HasObjectPermission",
                  "label_studio.core.api_permissions.HasObjectPermission")
    # 移除可能不存在的 ml_model_providers
    s = re.sub(r"[\"']ml_model_providers[\"'],?\s*", "", s)
    if s != orig:
        fpath.write_text(s, encoding='utf-8')
        print(f"Patched settings in {fpath}")

patch_settings(root / 'core' / 'settings' / 'label_studio.py')
patch_settings(root / 'core' / 'settings' / 'base.py')

# ---------- 3) 回修模型字符串（避免出现 'label_studio.users.User'） ----------
model_ref_pat = re.compile(r"([\"'])label_studio\.(\w+)\.([A-Z][A-Za-z0-9_]+)([\"'])")
def revert_model_refs(p: pathlib.Path):
    txt = p.read_text(encoding='utf-8', errors='ignore')
    new = model_ref_pat.sub(lambda m: f"{m.group(1)}{m.group(2)}.{m.group(3)}{m.group(4)}", txt)
    if new != txt:
        p.write_text(new, encoding='utf-8')
        print(f"Repaired model refs in {p}")

for p in root.rglob('*.py'):
    revert_model_refs(p)

# ---------- 4) 修补 AppConfig.name 与 default_app_config ----------
appconfig_pat = re.compile(r'^\s*class\s+([A-Za-z0-9_]+)\(.*AppConfig.*\):', re.M)
name_pat = re.compile(r'^\s*name\s*=\s*[\'"]([^\'"]+)[\'"]\s*$', re.M)

def fix_app_config(app: str):
    apps_py = root / app / 'apps.py'
    if apps_py.exists():
        s = apps_py.read_text(encoding='utf-8')
        # 找到 AppConfig 子类
        m = appconfig_pat.search(s)
        if m:
            cfg_cls = m.group(1)
            # 修正 name='label_studio.<app>'
            if name_pat.search(s):
                s2 = name_pat.sub(f"name = 'label_studio.{app}'", s)
            else:
                # 没有 name 字段就补上
                s2 = s.replace(m.group(0), m.group(0) + f"\n    name = 'label_studio.{app}'\n")
            if s2 != s:
                apps_py.write_text(s2, encoding='utf-8')
                print(f"Patched AppConfig.name in {apps_py}")
            # 同步 default_app_config
            init_py = root / app / '__init__.py'
            if init_py.exists():
                t = init_py.read_text(encoding='utf-8')
                t2 = re.sub(
                    r"^\s*default_app_config\s*=\s*[\'\"][^\'\"]+[\'\"]\s*$",
                    f"default_app_config = 'label_studio.{app}.apps.{cfg_cls}'",
                    t, flags=re.M
                )
                if t2 != t:
                    init_py.write_text(t2, encoding='utf-8')
                    print(f"Patched default_app_config in {init_py}")

for app in apps:
    fix_app_config(app)
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
