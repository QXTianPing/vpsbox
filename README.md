# VPSBox

VPS 初始化、系统优化与 sing-box 节点管理脚本。

## VPS 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/QXTianPing/vpsbox/main/vpsbox.sh)
```

## 管理命令

安装完成后，可随时输入以下命令打开管理面板：

```bash
vpsbox
```

## 主界面

输入 `vpsbox` 打开管理面板：

```text
========================================
 VPSBox
========================================
 提示：输入 vpsbox 打开管理面板
----------------------------------------
 sing-box：已安装 / 未安装
 sing-box 状态：运行中 / 未运行
 sing-box 版本：1.x.x
 当前节点：已创建 / 未创建
 节点地址：example.com:49880
----------------------------------------
 IPv4 DNS：
 nameserver 1.1.1.1
 nameserver 8.8.8.8
----------------------------------------
 1) 节点管理
 2) sing-box 管理
 3) 系统优化
 4) 一键自检
 5) 查看三网回程
----------------------------------------
 8) 更新 vpsbox 脚本
 9) 卸载 VPSBox
 0) 退出
========================================
请输入选项:
```

## 子菜单

```text
节点管理
1) 创建/重建 SS 2022 节点
2) 查看节点链接
3) 删除当前节点
0) 返回主菜单

sing-box 管理
1) 启动 sing-box 服务
2) 停止 sing-box 服务
3) 重启 sing-box 服务
4) 更新 sing-box
0) 返回主菜单

系统优化
1) 系统更新
2) 一键开启 BBR + fq
3) 安装 Fail2ban
4) 限制 systemd 日志大小
5) 修改系统 IPv4 DNS
6) 启用系统 IPv4 优先
7) 修改 SSH 端口
8) SSH 基础加固
9) 查看 SSH 当前生效配置
10) 开启 NTP 时间同步
0) 返回主菜单
```

## 功能

- 自动检查并安装 sing-box
- 创建/重建 SS 2022 节点
- 校验节点域名/IP 格式
- 随机端口
- 随机强密码
- 固定加密：2022-blake3-aes-128-gcm
- 查看节点链接
- 删除当前节点
- 启动、停止、重启 sing-box
- 一键自检，包含系统优化状态和端口安全组建议
- 三网回程检测
- 系统更新
- 一键开启 BBR + fq
- 安装 Fail2ban
- 开启 NTP 时间同步，使用 chrony 自动校准系统时间并设置开机自启
- 限制 systemd 日志大小
- 修改系统 IPv4 DNS
- 启用系统 IPv4 优先，IPv4 不可用时 IPv6 仍可兜底
- 修改 SSH 端口为 23333，并同步 Fail2ban sshd 端口
- SSH 基础加固，启用低风险 SSH 配置项
- 查看 SSH 当前生效配置
- 更新 sing-box
- 更新 vpsbox 脚本
- 打开管理面板时自动检查并更新 vpsbox
- 卸载 VPSBox
- 可单独确认删除 sing-box 和所有节点配置
