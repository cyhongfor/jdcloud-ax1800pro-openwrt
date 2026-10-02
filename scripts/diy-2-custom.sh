#!/bin/bash
# ============================================================================
# diy-2：编译前自定义
#
# 执行时机：**在 `./scripts/feeds install -a` 之后、`make defconfig` 之前**
# 工作目录：openwrt/（源码树根）
#
# 原则：你选择了"不内置任何配置"（network / wifi / 密码 / 证书都不编进固件），
#       所以这里**只做构建期调整**，不写任何 uci 默认值、不放密钥。
#       刷完机默认地址是 192.168.1.1，无 root 密码。
# ============================================================================
set -euo pipefail

echo "=== 构建期自定义检查 ==="

# ---------------------------------------------------------------- 1. 冲突保护
# turboacc 的 SFE/flow-offload 与 NSS 硬件卸载功能重复，同时启用会互相打架
if grep -qE '^CONFIG_PACKAGE_luci-app-turboacc=y' .config; then
  echo "  [警告] 检测到 luci-app-turboacc=y：它与 NSS 卸载重复，正在改为不编译"
  # 用 .* 吃掉可能的行尾内容，避免因行内注释导致替换失败
  sed -i 's|^CONFIG_PACKAGE_luci-app-turboacc=y.*|# CONFIG_PACKAGE_luci-app-turboacc is not set|' .config
fi

# 代理插件互斥提醒（不自动改，只提示，避免误删你的选择）
_proxy=0
for p in luci-app-openclash luci-app-passwall luci-app-ssr-plus; do
  grep -qE "^CONFIG_PACKAGE_${p}=y" .config && _proxy=$((_proxy+1))
done
if [ "$_proxy" -gt 1 ]; then
  echo "  [警告] 同时选了 $_proxy 个代理插件，它们会争抢 TUN/透明代理与 DNS，强烈建议只留一个"
  grep -E '^CONFIG_PACKAGE_luci-app-(openclash|passwall|ssr-plus)=y' .config | sed 's/^/         /'
fi

# ---------------------------------------------------------------- 2. 无线校准数据
# 本机型的无线 BDF 由 DEVICE_PACKAGES 里的 ipq-wifi-jdcloud_re-ss-01 提供，确认它存在
if ! grep -q 'ipq-wifi-jdcloud_re-ss-01' target/linux/qualcommax/image/ipq60xx.mk; then
  echo "  [警告] 上游 device 定义里没有 ipq-wifi-jdcloud_re-ss-01，无线校准数据可能缺失"
fi

# ---------------------------------------------------------------- 3. 内核/固件相关
# NSS 固件 11.4 与 12.x 互斥，这里做一次一致性检查
_v114=$(grep -c '^CONFIG_NSS_FIRMWARE_VERSION_11_4=y' .config || true)
_v12x=$(grep -cE '^CONFIG_NSS_FIRMWARE_VERSION_12_[0-9]+=y' .config || true)
echo "  NSS 固件版本：11.4=$(( _v114 )) / 12.x=$(( _v12x ))"
if [ "$_v114" -gt 0 ] && [ "$_v12x" -gt 0 ]; then
  echo "  [警告] 11.4 与 12.x 同时被选中，这会导致编译失败，请只留一个"
fi

# ---------------------------------------------------------------- 4. 可选：默认主题
# 如果你想让固件刷完默认就是某个主题，把下面注释打开（这不是"配置"，是构建期默认值）
# sed -i 's/^CONFIG_PACKAGE_luci-theme-argon=y/# CONFIG_PACKAGE_luci-theme-argon is not set/' .config
# sed -i 's/^CONFIG_PACKAGE_luci-theme-aurora=y/# CONFIG_PACKAGE_luci-theme-aurora is not set/' .config
# echo 'CONFIG_PACKAGE_luci-theme-argon=y' >> .config

# ---------------------------------------------------------------- 5. 编译加速
# ccache 大小上限（GitHub Actions 缓存上限 10GB）
if [ -x /usr/bin/ccache ] || command -v ccache >/dev/null 2>&1; then
  ccache --max-size=5G 2>/dev/null || true
  ccache -z 2>/dev/null || true
  echo "  ccache 已配置（上限 5G，统计已清零）"
fi

# ---------------------------------------------------------------- 6. 输出摘要
# 注意：脚本开头是 `set -euo pipefail`，而下面这些只是"打印给人看"的管道。
# 如果 .config 里一条都没匹配到（比如配置又被 oldconfig 丢了），
# grep 会返回 1，配合 pipefail 会把整个构建打断 —— 一个纯展示动作不该有这种权力。
# 所以统一加 `|| true`，真正的配置校验交给 check-packages.sh 去做。
echo
echo "=== 将要编进固件的 LuCI 应用 ==="
grep -oE '^CONFIG_PACKAGE_luci-app-[A-Za-z0-9_.+-]+=y' .config 2>/dev/null \
  | sed 's/^CONFIG_PACKAGE_//; s/=y$//' | grep -vE '_[A-Z]' | sort | sed 's/^/  /' || true
_count=$(grep -cE '^CONFIG_PACKAGE_luci-app-[A-Za-z0-9_.+-]+=y' .config 2>/dev/null || echo 0)
[ "${_count:-0}" -eq 0 ] && echo "  ⚠️ 一个都没匹配到 —— 说明 .config 可能被重建过，请看下一步的包校验"
echo
echo "=== 已选语言包 ==="
grep -oE '^CONFIG_PACKAGE_luci-i18n-[A-Za-z0-9_.+-]+=y' .config 2>/dev/null \
  | sed 's/^CONFIG_PACKAGE_//; s/=y$//' | sort | sed 's/^/  /' || true
echo
echo "=== NSS 固件版本（应有一个 =y）==="
grep -E '^CONFIG_NSS_FIRMWARE_VERSION_[0-9_]+=y' .config 2>/dev/null | sed 's/^/  /' || echo "  ⚠️ 没有！"
echo
echo "diy-2 完成（未写入任何网络/密码类默认配置）"
