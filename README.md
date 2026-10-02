# JDCloud RE-SS-01 (AX1800 Pro) OpenWrt 自编译

本仓库**只存放编译所需的最小内容**：GitHub Actions 工作流 + 设备/插件配置 + 辅助脚本。
编译说明、刷机步骤、设备实测记录等文档**不进仓库**，只保留在本地。

## 仓库内容

| 路径 | 作用 |
|---|---|
| `.github/workflows/build.yml` | 云编译工作流（21 步，含配置校验与失败诊断） |
| `configs/jdcloud_re-ss-01.config` | 设备 + NSS + 内核基础配置 |
| `configs/packages.config` | 插件选择清单（43 个包，全部逐个核实过上游） |
| `scripts/diy-1-feeds.sh` | 按**请求清单**添加第三方 feed（须在 `feeds update` 之前运行） |
| `scripts/diy-2-custom.sh` | 编译前自定义与冲突保护（在 `feeds install` 之后运行） |
| `scripts/check-packages.sh` | 校验请求的包是否真的进了最终 `.config` |
| `scripts/local-build.sh` | 在本机编译（可选路径） |
| `optional/wifi-bdf/` | 本机型无线校准数据（默认不启用，见该目录说明） |

## 使用

- **手动触发**：Actions 页面 → `Build OpenWrt for JDCloud RE-SS-01` → Run workflow
- **自动触发**：推送到 `main`（且改动 `configs/**`、`scripts/**` 或工作流本身时）

两个可选输入：

- `source_commit`：填 SHA 锁定上游提交，保证构建可复现（稳定期建议填）
- `publish_packages`：把整套 `.apk` 打包发到 Release，方便以后按需安装

产物在 **Releases** 里：`*-squashfs-sysupgrade.bin` 用于刷机，`*-squashfs-factory.bin` 用于 uboot 恢复页。

## 一个必须遵守的顺序（踩过坑）

`.config` 必须在 `feeds update/install` **之后**才写入源码树。

原因：`scripts/feeds` 里的 `refresh_config()` 只要发现 `.config` 已存在，就会静默执行
`make oldconfig`（输出重定向到 `/dev/null`）。若此时 feed 里的包尚未安装，
Kconfig 不认识那些包符号，`CONFIG_PACKAGE_*` 会被**整批丢弃**，
最终编出一个几乎没有插件的固件，且日志里看不到任何异常。

## 上游

- 源码：[LiBwrt/LibWrt](https://github.com/LiBwrt/LibWrt) 分支 `25.12-nss`
- 内核 6.12，含 NSS 硬件卸载（NAT/PPPoE/桥接/2.4G+5G 无线）
