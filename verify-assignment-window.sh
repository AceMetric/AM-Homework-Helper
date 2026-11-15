#!/bin/zsh
# Explicit opt-in lane: opens a native window and sends real synthetic clicks.
set -euo pipefail
cd "${0:A:h}"
if [[ "${AM_UI_FOREGROUND:-0}" != 1 ]]; then
  print -u2 -- '设置 AM_UI_FOREGROUND=1 后才打开可见验收窗口。'
  exit 2
fi
AM_UI_TEST=AssignmentWorkspaceUsage AM_UI_COMPILE_ONLY=1 zsh verify-hybrid-ui.sh
args=()
if [[ "${AM_UI_HOLD_REVIEW:-0}" == 1 ]]; then args=(--keep-open); fi
python3 Tools/run-assignment-window.py "${args[@]}"
