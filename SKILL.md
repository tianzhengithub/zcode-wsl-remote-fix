---
name: zcode-wsl-remote-fix
description: 诊断与修复 ZCode Desktop 远程(WSL)工作区「此远程设备尚无可用模型」。当用户提到 ZCode 远程/WSL 没有可用模型、远程设备模型列表为空、出现"请先在本机配置模型，保存后会自动同步"横幅、ZCode Agent runtime is not running、model_config_missing、或刚安装/重装 ZCode 后配置 WSL 远程开发时使用——即使没明说"模型"两个字（比如只是说"WSL 里用不了"、"远程连上了但发不出消息"）也应触发。Use whenever ZCode desktop's WSL/SSH remote workspace shows "no available models", cannot send messages, or a freshly connected remote device cannot use any model while the local workspace works fine.
---

# ZCode 远程(WSL)「尚无可用模型」诊断与修复

## 背景：为什么会出这个问题

ZCode Desktop（Windows）连接远程 WSL 时，会在远程 `~/.zcode/` 下安装一个 server 守护进程。远程能否使用模型，取决于 server 启动时调用 `https://zcode.z.ai/api/v1/zcode-plan/billing/balance` 做**套餐可用性检查**——该接口**必须携带 `X-Device-Mid` 请求头**。

deviceMid 来自 `~/.zcode/v2/telemetry-state.json`。桌面端的远程环境同步（provisioning）会推送凭据和模型规则，但截至 3.16.3 **不会同步这个文件**。WSL 端缺失时：

1. 接口返回 HTTP 400 `{"code":3001,"msg":"parameter error"}`（可先 `grep -o 'parameter error' ` 复现）；
2. 所有 `zhipu-account` 账号 provider 被静默标记不可用 → Provider Registry `providerCount:0`；
3. UI 显示「此远程设备尚无可用模型，请先在本机配置模型…」，发送框被 `model_config_missing` 门禁拦截。

该 bug 已上报：zai-org/feedback#1188。凭据、网络、版本都没问题时仍然出现，就是它。

## 症状（满足任意一条即适用本 skill）

- 远程 workspace 横幅「此远程设备尚无可用模型…」，点升级/重配无效，重启后依旧
- 远程发不出消息，本地 workspace 一切正常
- 桌面日志 `C:\Users\<user>\.zcode\v2\logs\<date>.log` 反复出现来自远程 server 路径的 `ZCode Agent runtime is not running`

## 诊断（按顺序，全部只读）

在 Windows 上执行（`<distro>` 换成实际发行版，`wsl -l -v` 可查）：

1. **确认 server 在跑**：`wsl -d <distro> -- ~/.zcode/server/bin/zcode status` → `state` 应为 `ready`。不是 ready 先 `~/.zcode/server/bin/zcode restart`。
2. **检查 deviceMid（本 bug 的判据）**：`wsl -d <distro> -- cat ~/.zcode/v2/telemetry-state.json`。**文件不存在或没有 `deviceMid` 字段 = 确诊**。
3. （可选）对比 Windows 端：`C:\Users\<user>\.zcode\v2\telemetry-state.json` 存在且含 `deviceMid`——这就是要复制的内容。

凭据不用怀疑：`~/.zcode/v2/credentials.json` 的加密密钥由 WSL 端自行派生（`zcode-credential-fallback:<platform>:<homedir>:<username>`），provisioning 时已用 WSL 密钥重加密，能解密就有效。

## 修复

### 方式 A：运行自动化脚本（推荐）

```bash
wsl -d <distro> -- bash <skill目录>/scripts/fix-remote-models.sh
```

脚本幂等，做三件事：从 Windows 侧用户目录复制 `telemetry-state.json`（找不到则生成新 UUID）、重启 server、打印状态。先 `--dry-run` 可预览。脚本在 WSL 内会通过 `/mnt/c/Users/*/` 找 Windows 侧文件。

### 方式 B：手动修复

```bash
# 1. 写入 deviceMid（从 Windows 端复制整个文件即可，同一台机器设备一致）
cp /mnt/c/Users/<user>/.zcode/v2/telemetry-state.json ~/.zcode/v2/telemetry-state.json
# Windows 端也没有时，生成一个新的：
printf '{\n  "deviceMid": "%s",\n  "lastDailyActiveDate": "%s"\n}\n' \
  "$(cat /proc/sys/kernel/random/uuid)" "$(date +%Y-%m-%d)" > ~/.zcode/v2/telemetry-state.json
chmod 600 ~/.zcode/v2/telemetry-state.json

# 2. 重启远程 server
~/.zcode/server/bin/zcode restart
```

### 修复后验证

1. `~/.zcode/server/bin/zcode status` → `state:"ready"`。
2. 回到桌面端**重新打开/切换**远程 workspace（界面会重新检查 provider 视图；横幅若还在，点 × 关掉）。模型选择里应出现 GLM-5.3 / GLM-5.3-Flash。
3. 发一条消息实测。若想看 server 内部确认（providerCount 从 0 变 ≥1），见下方「抓 server 日志」。

## 次要坑：远程 agent 运行时缺失（同一排障中常遇到）

若修复 A 后 headless 直接跑 release 里的 `zcode.cjs` 报「无法定位 CLI ZCode Built-in Provider Config」，是 agent bundle 没同步。桌面端正常远程对话**不受影响**（server spawn 时会注入 `ZCODE_BUILTIN_PROVIDER_CONFIG_FILE`），仅手动 CLI 场景需要：

```bash
mkdir -p ~/.zcode/server/agents
cp -r /mnt/<盘>/ZCode安装目录/resources/glm ~/.zcode/server/agents/glm
mkdir -p ~/.zcode/server/agents/glm/provider
cp /mnt/<盘>/ZCode安装目录/resources/config/provider/zcode-builtin.json ~/.zcode/server/agents/glm/provider/
```

## 抓 server 日志（进阶排障）

server 守护进程以 `stdio:"ignore"` 启动，日志被丢弃。需要时停掉它，前台自启并重定向（注意桌面端检测到 server 消失会自动重启，动作要快）：

```bash
~/.zcode/server/bin/zcode stop
R=~/.zcode/server/releases/$(ls ~/.zcode/server/releases | head -1)/runtime
ZCODE_DATA_BASE_DIR=$HOME ZCODE_SERVER_ROOT=$HOME/.zcode/server NODE_ENV=development \
  nohup $R/node $R/server-cli.js serve --supervisor --server-root $HOME/.zcode/server \
  > /tmp/zcode-server.log 2>&1 &
```

关键日志行：`billing/balance 请求失败/请求完成`（400 parameter error = 本 bug；`hasActiveStartPlan:true` = 已通）、`Provider Registry 已就绪 {"providerCount":N}`。

## 汇报

修复无效或属于新变种时，按 zai-org/feedback 仓库 `[Bug]` 格式提交，附上 `billing/balance` 的请求/响应与 `telemetry-state.json` 两端状态；先搜索 #989、#1060、#1188 是否已覆盖。
