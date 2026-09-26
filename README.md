# openwrt-Cqcfe-Campus-network

> 🌐 面向 OpenWrt 的校园网自动登录 LuCI 插件
> 🏫 默认适配重庆财经（CQCFE）校园网门户，兼容 `dr.com / eportal` 体系
> 📦 提供源码与可直接安装的 `ipk` 发行包
> 🧭 支持 Web 管理页面、掉线自动重登、工作日静默、节假日识别

> ✅ 适用于 `dr.com / eportal` 体系的校园网认证环境

## ✨ 项目作用

本项目把校园网门户的网页登录逻辑（`GET + JSONP`）移植为 OpenWrt 上的常驻守护进程 + LuCI 管理插件，让路由器在校园网掉线时能自动重新认证，无需人工打开浏览器登录。

它解决的问题是：

- 🔌 **掉线自动重登**：路由器长时间运行时会因会话过期、Portal 踢下线等原因掉网，本插件能自动检测并重新登录
- 🌙 **断网时段不再空转**：校园网在凌晨维护时段无法上网，避免插件在此期间反复无效认证
- 🏖️ **节假日智能判断**：仅在**工作日**执行静默策略，节假日 / 休息日不静默，全天保持检测
- ⚡ **低资源占用**：面向 128MB 内存 / 小容量存储的路由器做了缓存与原子写入优化

适用范围：

- `dr.com` 校园网系统
- `eportal` 风格门户认证系统
- 典型接口路径包含 `/eportal/portal/login`、`/eportal/portal/online_list`
- 需要 `program_index`、`page_index`、`wlan_user_ip`、`wlan_user_mac` 等参数的认证环境

## 🧠 工作原理

插件不是“盲目定时登录”，而是「先检测外网 → 再判断门户登录态 → 最后才在确实掉线时发起登录」：

1. 每 `5` 秒执行一次 `ping cn.bing.com`
2. 若 `ping` 成功，则认为外网正常，不做任何登录动作
3. 若 `ping` 失败，调用 `/eportal/portal/online_list` 查询门户在线状态
4. 若门户状态为未登录，调用 `/eportal/portal/login` 发起登录
5. 登录后用在线状态接口复核，确认成功才记录
6. 判定为**工作日**的静默时段（默认 `00:00-05:00`）内直接跳过全部检测；节假日、休息日不静默
7. 连续失败按退避间隔重试（1→5s、2→15s、3→30s、4→60s、5→120s、≥6 封顶 `backoff_max`），达到失败上限后进入冷却

### 认证体系特征

- 登录接口为 `GET + JSONP`
- 登录入口通常是 `/eportal/portal/login`
- 在线状态查询接口通常是 `/eportal/portal/online_list`
- 默认网关：`http://login.cqcfe.com:801`（重庆财经）
- 登录关键参数：`user_account`、`user_password`、`wlan_user_ip`、`wlan_user_ipv6`、`wlan_user_mac`、`program_index`、`page_index`、`login_method`、`terminal_type`、`lang`、`jsVersion`

### 自动识别终端身份

为适配旁路、中继、无线 STA 等场景，插件会自动识别用于认证的终端接口：

- 优先读取路由器 `wan` 侧实际接口，同时兼顾 `phy1-sta0`、`phy1-ap0`
- 终端 IPv4 只取 `10.*` 网段地址，拿不到则留空
- MAC 地址取已识别接口的 MAC，拿不到则留空

## 📂 仓库结构

```text
openwrt-Cqcfe-Campus-network/
├─ README.md
├─ LICENSE
├─ .gitattributes
├─ package/
│  └─ luci-app-campus-portal/
│     ├─ Makefile
│     ├─ README.md
│     └─ root/
└─ releases/
   ├─ README.md
   └─ v1.0.0/
      ├─ luci-app-campus-portal_1.0.0-1_all.ipk
      └─ luci-app-campus-portal_1.0.0-1_all.ipk.sha256
```

## 🚀 使用方法

### 方式一：直接安装发行版（推荐）

把 [releases/v1.0.0](./releases/v1.0.0) 里的 `ipk` 上传到路由器，然后执行：

```sh
opkg install luci-app-campus-portal_1.0.0-1_all.ipk
/etc/init.d/campus_portal enable
/etc/init.d/campus_portal start
```

安装前可先校验哈希：

```sh
sha256sum luci-app-campus-portal_1.0.0-1_all.ipk
```

LuCI 菜单位置：

```text
服务 -> 校园网自动登录
```

### 方式二：放入 OpenWrt SDK / 源码树重新编译

把 [package/luci-app-campus-portal](./package/luci-app-campus-portal) 放入 OpenWrt 源码树的 `package/` 目录后执行：

```sh
./scripts/feeds update -a
./scripts/feeds install -a
make package/luci-app-campus-portal/compile V=s
```

## ⚙️ 配置项

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `gateway` | `http://login.cqcfe.com:801` | 认证网关（默认重庆财经） |
| `account_prefix` | `,0,` | 登录时拼接到账号前的固定前缀 |
| `silent_enabled` | `1` | 是否启用工作日静默时段 |
| `silent_start` | `00:00` | 静默时段开始时间 |
| `silent_end` | `05:00` | 静默时段结束时间 |
| `silent_sleep` | `60` | 静默时段内的休眠间隔（秒） |
| `holiday_enabled` | `1` | 是否启用在线节假日识别 |
| `holiday_api` | `https://timor.tech/api/holiday/info` | 节假日查询接口 |
| `holiday_list` | 空 | 手动节假日列表（逗号分隔，支持 `YYYY-MM-DD` 或 `MM-DD`） |
| `workday_list` | 空 | 手动补班日列表（逗号分隔） |
| `max_retry` | `10` | 连续失败上限，达到后进入冷却 |
| `retry_cooldown` | `1800` | 达到失败上限后的冷却时间（秒） |
| `backoff_max` | `300` | 渐进退避的间隔上限（秒） |

静默时段仅在判定当天为**工作日**时生效，判定优先级为：手动补班日列表 > 手动节假日列表 > 在线接口 > 周六/周日兜底。时段归属以「时段所属日期」为准（例如周二凌晨 `00:00-05:00` 属于周二；周五晚 12 点后属于周六，休息日不静默）。

## 🖥️ LuCI 页面功能

- 📶 当前登录状态
- 🧪 最后一次联网检查
- 🕒 最后动作与说明
- 🧭 自动识别接口与终端 IPv4 / MAC
- 📝 最近 5 次成功登录记录
- 📄 最近日志
- 👤 账号 / 🔑 密码输入与保存

## 🙏 致谢与开源项目

本项目为独立开发的全新项目，在实现过程中参考了以下同类开源项目，在此一并致谢：

1. **LoginCqcfe** —— 重庆财经校园网登录客户端（`Vue 3 + Tauri`）
   - 仓库：https://github.com/yichen9247/LoginCqcfe
   - 登录接口参数与认证流程的思路参考自该项目

2. **openwrt-sjzpt-Campus-network-tools** —— OpenWrt 校园网自动认证工具（LuCI 插件框架）
   - 仓库：https://github.com/xnxiang666/openwrt-sjzpt-Campus-network-tools
   - OpenWrt 打包方式与 LuCI 页面的实现思路参考自该项目

## 📮 联系方式

如有急事，可发送邮件至：**jasmeafwjd@gmail.com**

## 📜 许可

本项目按 `MIT` 许可整理发布，详见 [LICENSE](./LICENSE)。
