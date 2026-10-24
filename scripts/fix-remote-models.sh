#!/usr/bin/env bash
# fix-remote-models.sh — 修复 ZCode WSL 远程「此远程设备尚无可用模型」
# 根因：远程 ~/.zcode/v2/telemetry-state.json 缺失（无 deviceMid），
#       billing/balance 套餐可用性检查因缺 X-Device-Mid 头被 API 以 400 拒绝。
# 用法：在 WSL 内以普通用户运行
#   bash fix-remote-models.sh [--dry-run]
# 幂等：已修复的机器上重复运行只做检查，不会破坏现有状态。
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

V2_DIR="$HOME/.zcode/v2"
TS_FILE="$V2_DIR/telemetry-state.json"
ZCODE_BIN="$HOME/.zcode/server/bin/zcode"

log() { printf '[zcode-fix] %s\n' "$*"; }

if [[ ! -d "$HOME/.zcode/server" ]]; then
  log "错误：未找到 $HOME/.zcode/server —— 请先在 ZCode 桌面端连接过一次该 WSL 发行版（server 会在首次连接时安装）。"
  exit 1
fi

# ---- 第 1 步：确保 telemetry-state.json 存在且含 deviceMid ----
if [[ -f "$TS_FILE" ]] && grep -q '"deviceMid"' "$TS_FILE" 2>/dev/null; then
  log "OK: deviceMid 已存在（$TS_FILE），跳过写入"
else
  WIN_TS=""
  for u in /mnt/c/Users/*/; do
    candidate="${u}.zcode/v2/telemetry-state.json"
    if [[ -f "$candidate" ]] && grep -q '"deviceMid"' "$candidate" 2>/dev/null; then
      WIN_TS="$candidate"
      break
    fi
  done

  if [[ -n "$WIN_TS" ]]; then
    log "从 Windows 侧复制 deviceMid: $WIN_TS"
    if [[ $DRY_RUN -eq 0 ]]; then
      mkdir -p "$V2_DIR"
      cp "$WIN_TS" "$TS_FILE"
      chmod 600 "$TS_FILE"
    fi
  else
    MID="$(cat /proc/sys/kernel/random/uuid)"
    log "Windows 侧未找到 telemetry-state.json，生成新 deviceMid: $MID"
    if [[ $DRY_RUN -eq 0 ]]; then
      mkdir -p "$V2_DIR"
      printf '{\n  "deviceMid": "%s",\n  "lastDailyActiveDate": "%s"\n}\n' \
        "$MID" "$(date +%Y-%m-%d)" > "$TS_FILE"
      chmod 600 "$TS_FILE"
    fi
  fi
fi

# ---- 第 2 步：重启 server 使配置生效 ----
if [[ $DRY_RUN -eq 1 ]]; then
  log "dry-run：跳过 server 重启"
else
  if [[ -x "$ZCODE_BIN" ]]; then
    log "重启 zcode server ..."
    "$ZCODE_BIN" restart >/dev/null 2>&1 || true
    sleep 3
    "$ZCODE_BIN" status 2>/dev/null | tail -1 || true
  else
    log "警告：未找到 $ZCODE_BIN，请手动重启（在桌面端断开/重连远程，或运行 server-cli restart）"
  fi
fi

log "完成。回到 ZCode 桌面端重新打开远程 workspace；横幅若仍在，点 × 关闭后重试。"
log "验证方法见 SKILL.md「修复后验证」一节。"
