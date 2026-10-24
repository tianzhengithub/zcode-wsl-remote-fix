# zcode-wsl-remote-fix

修复 ZCode Desktop 远程(WSL)工作区「此远程设备尚无可用模型」的 ZCode skill。

## 这是什么问题

ZCode Desktop（Windows）连接 WSL 远程后，远程端 server 缺少 `~/.zcode/v2/telemetry-state.json`（deviceMid 设备 ID）。server 检查套餐可用性时调用的 `https://zcode.z.ai/api/v1/zcode-plan/billing/balance` 接口必需 `X-Device-Mid` 请求头，缺失时返回 HTTP 400 `{"code":3001,"msg":"parameter error"}`，导致所有账号模型被静默标记为不可用——界面显示「此远程设备尚无可用模型，请先在本机配置模型，保存后会自动同步…」。

- 官方 issue：https://github.com/zai-org/feedback/issues/1188
- 影响：ZCode Desktop 3.16.3（后续版本是否修复以官方为准）
- 凭据、网络、账号均正常，仅远程设备缺 deviceMid

## 安装 skill（每台新电脑）

把本仓库克隆到 ZCode 的个人技能目录（Windows）：

```powershell
git clone https://github.com/tianzhengithub/zcode-wsl-remote-fix.git "$env:USERPROFILE\.agents\skills\zcode-wsl-remote-fix"
```

重启 ZCode 后，当你遇到该问题时 agent 会自动按 skill 处理；也可以直接对 agent 说「用 zcode-wsl-remote-fix 修复 WSL 远程模型」。

## 直接修复（不装 skill 也行）

在 WSL 内运行一条命令（幂等，已修复则只做检查）：

```powershell
wsl -d <发行版名> -- bash "/mnt/c/Users/<你的用户名>/.agents/skills/zcode-wsl-remote-fix/scripts/fix-remote-models.sh"
```

或者手动三步：

```bash
cp /mnt/c/Users/<你>/.zcode/v2/telemetry-state.json ~/.zcode/v2/telemetry-state.json
chmod 600 ~/.zcode/v2/telemetry-state.json
~/.zcode/server/bin/zcode restart
```

（Windows 端没有该文件时用 `cat /proc/sys/kernel/random/uuid` 生成一个 deviceMid 即可，格式见 `scripts/fix-remote-models.sh`。）

## 修复后

回到 ZCode 桌面端重新打开远程 workspace；模型选择里应出现 GLM-5.3 / GLM-5.3-Flash。详细诊断流程、抓 server 日志方法见 [SKILL.md](SKILL.md)。
