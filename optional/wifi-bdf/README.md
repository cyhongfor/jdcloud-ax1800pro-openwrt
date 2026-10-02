# 可选的 WiFi 校准修复件（BDF）

## 这是什么

`board-2.bin` —— ath11k 的**板级校准数据（BDF）**，来自上游
[openwrt/firmware_qca-wireless](https://github.com/openwrt/firmware_qca-wireless)
仓库的 `board-jdcloud_re-ss-01.ipq6018`，即**你这台机器的专属文件**。

- 大小：65 640 字节
- SHA256：`64cedd60a69ff8bf4d8566d2d9ced132b343f7ed18ed82d9959427db533f6b6a`
- 容器内条目名：`bus=ahb,qmi-chip-id=0,qmi-board-id=?,variant=JDC-RE-SS-01`
  （与设备树里 `qcom,ath11k-calibration-variant = "JDC-RE-SS-01"` 精确匹配）

## 为什么要备这个东西

LibWrt 的 `ath11k-firmware` 包用的是 fork
[laipeng668/ath11k-firmware-ddwrt](https://github.com/laipeng668/ath11k-firmware-ddwrt)，
它的 `IPQ6018/hw1.0/board-2.bin` 里**只有一个通用条目**：

```
bus=ahb,qmi-chip-id=0,qmi-board-id=255
```

没有 `variant=JDC-RE-SS-01`。所以 ath11k 会匹配不到专属变体、**回退到通用校准数据**。
WiFi 通常仍然能起来能用，但射频参数不是原厂调校值。

详细证据链见 `../../docs/05-实机核查报告.md` 第四节"风险 3"。

## 怎么启用（默认不启用）

工作流里已有"可选：注入本仓库 files/ 覆盖层"这一步，只要 `files/` 非空就会被复制进源码树。
所以在仓库根目录执行：

```bash
mkdir -p files/lib/firmware/IPQ6018/hw1.0
cp optional/wifi-bdf/board-2.bin files/lib/firmware/IPQ6018/board-2.bin
cp optional/wifi-bdf/board-2.bin files/lib/firmware/IPQ6018/hw1.0/board-2.bin
```

两个路径都放一份，是因为本仓库的 ath11k-firmware 包把固件**平铺**装到
`/lib/firmware/IPQ6018/`，而上游 ath11k 驱动传统上找 `/lib/firmware/IPQ6018/hw1.0/`，
两条都覆盖可以避免路径不确定带来的反复。

`files/` 里的内容在生成 rootfs 时最后写入，**会覆盖包安装的同名文件**，所以能生效。

## 什么时候该启用

**建议先不启用，直接编一版刷上，然后看 dmesg：**

```sh
dmesg | grep -iE 'ath11k.*(board|bdf|variant|cal)' | head -20
```

- 如果无线正常、测速与原厂相当 → 不用管，通用 BDF 够用。
- 如果出现找不到变体 / 回退的提示，且信号或速率明显不如原厂 → 启用本修复件重编。

## 为什么不直接默认启用

两点考虑：

1. 这是**未经实机验证的优化**。我没有在你这台机器上刷过 LibWrt，
   无法保证上游 BDF 与 LibWrt 那份 QSDK 派生固件（`q6_fw`/`m3_fw`）一定匹配；
   万一不匹配，反而可能导致无线起不来。**先跑通用版、出问题再换**，是风险最低的顺序。
2. `files/` 覆盖层一旦启用，就意味着固件内置了内容，
   与你选的"固件不内置任何配置"原则有轻微冲突（虽然 BDF 是固件数据不是配置）。

## 数据来源与许可

本文件是 OpenWrt 官方固件仓库分发的内容（`firmware_qca-wireless`）。
它是 QCA 的闭源校准数据，OpenWrt 以"随固件分发"的方式提供；
放进你自己的私有仓库使用没有问题，但**不要公开再分发**。
