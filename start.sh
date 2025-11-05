#!/usr/bin/env bash
set -euo pipefail

# Default admin credentials (can be overridden by Railway Variables)
export LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK=${LABEL_STUDIO_DISABLE_SIGNUP_WITHOUT_LINK:-true}
export LABEL_STUDIO_USERNAME=${LABEL_STUDIO_USERNAME:-admin}
export LABEL_STUDIO_PASSWORD=${LABEL_STUDIO_PASSWORD:-admin123}

# Start Label Studio on Railway's PORT (fallback 8080)
export PORT=${PORT:-8080}
label-studio start --host 0.0.0.0 --port "${PORT}"
