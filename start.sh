#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# 1) 基础环境
# -----------------------------
# Render 注入的端口变量：$PORT（必须用它来监听）
: "${PORT:?PORT is required}"

# 有些平台会注入 HOST=0.0.0.0，Label Studio 会打印 warning，这里直接干掉
unset HOST

# 数据与媒体目录（持久化建议改用 PostgreSQL；此目录仍可用来放缓存/临时文件）
export LABEL_STUDIO_DATA_DIR="${LABEL_STUDIO_DATA_DIR:-/opt/render/.local/share/label-studio}"
mkdir -p "$LABEL_STUDIO_DATA_DIR"

# 可选：从环境注入安全密钥（强烈建议在 Render Environment 里设置 SECRET_KEY）
export SECRET_KEY="${SECRET_KEY:-}"

# -----------------------------
# 2) 读取并规范管理员账号
# -----------------------------
# 从环境读取账号/密码；没有就给默认
ADMIN_EMAIL="${LABEL_STUDIO_USERNAME:-admin@example.com}"
# 若传入的是“admin”这种无 @ 的值，自动补成邮箱
case "$ADMIN_EMAIL" in
  *"@"*) ;; 
  *) ADMIN_EMAIL="${ADMIN_EMAIL}@example.com" ;;
esac
ADMIN_PASSWORD="${LABEL_STUDIO_PASSWORD:-admin123}"

# 禁用无邀请注册（可用环境变量覆盖）
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK="${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}"

# -----------------------------
# 3) 数据库迁移
# -----------------------------
python -m label_studio.manage migrate --noinput

# -----------------------------
# 4) 确保管理员存在（邮箱登录）
# -----------------------------
python - <<PY
import os, django
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "core.settings.label_studio")
django.setup()
from users.models import User

email = "${ADMIN_EMAIL}"
pwd = "${ADMIN_PASSWORD}"

u, created = User.objects.get_or_create(email=email, defaults={"is_superuser": True, "is_staff": True})
u.is_superuser = True
u.is_staff = True
u.set_password(pwd)
u.save()
print("Admin ready:", email, "(created)" if created else "(updated)")
PY

# -----------------------------
# 5) 以 Gunicorn 启动（生产模式）
# -----------------------------
# * 绑定 Render 的 $PORT
# * 2 个 worker + 4 线程；可按机器规格调整
# * timeout 120 防止长任务提前被杀
exec gunicorn label_studio.core.wsgi:application \
  --bind 0.0.0.0:"$PORT" \
  --workers 2 \
  --threads 4 \
  --timeout 120
