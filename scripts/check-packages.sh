#!/bin/bash
# ============================================================================
# 校验：你在 configs/packages.config 里点名要的包，是否真的进了最终 .config
#
# 为什么需要这个：OpenWrt 的 `make defconfig` 对**不存在的包名会静默丢弃**。
# 你可能以为编了 openclash，结果固件里根本没有，刷完才发现。
# 本脚本把"请求了但现在没开"的包全部列出来。
#
# 执行时机：make defconfig 之后（工作流里已调用）
# 工作目录：openwrt/（源码树根）
#
# 严格模式：STRICT=1 bash scripts/check-packages.sh   → 有缺失就退出码 1
# ============================================================================
set -uo pipefail

REQ_FILE="${1:-../configs/packages.config}"
FINAL=".config"
[ -f "$FINAL" ] || { echo "错误：找不到 $FINAL"; exit 1; }
[ -f "$REQ_FILE" ] || { echo "错误：找不到请求清单 $REQ_FILE"; exit 1; }

MISSING=()
OK=()
# 只检查 =y 的请求（=m 的不进固件，不校验）
while read -r pkg; do
  [ -z "$pkg" ] && continue
  # 匹配时容忍设置项后面可能跟的行内注释或空白（虽然配置卫生检查会拦住这种写法，
  # 但这里不因为写法问题产生误报）
  if grep -qE "^CONFIG_PACKAGE_${pkg}=y([[:space:]]|#|$)" "$FINAL"; then
    OK+=("$pkg")
  else
    # 找出它现在的实际状态，方便定位
    state="$(grep -E "^# CONFIG_PACKAGE_${pkg} is not set([[:space:]]|$)|^CONFIG_PACKAGE_${pkg}=[ym]([[:space:]]|#|$)" "$FINAL" | head -1)"
    if [ -n "$state" ]; then
      MISSING+=("$pkg   ← 存在但未启用（依赖缺失或你把它关了）：${state}")
    else
      MISSING+=("$pkg   ← 该包在本次 feed 集合里根本不存在（包名错 / feed 没加）")
    fi
  fi
done < <(grep -oE '^CONFIG_PACKAGE_[A-Za-z0-9_.+-]+=y' "$REQ_FILE" | sed 's/^CONFIG_PACKAGE_//; s/=y$//' | sort -u)

echo "=== 包选择校验 ==="
echo "请求编译: $((${#OK[@]} + ${#MISSING[@]})) 个 | 生效: ${#OK[@]} 个 | 有问题: ${#MISSING[@]} 个"
echo
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "--- 下面这些没生效，请检查包名或 feed ---"
  for m in "${MISSING[@]}"; do echo "  ✗ $m"; done
  echo
  echo "提示：包名可去 immortalwrt/luci（applications/themes）或 immortalwrt/packages"
  echo "      （net/utils 等子目录）的 openwrt-25.12 分支核对。"
  echo "      若是第三方包，确认 scripts/diy-1-feeds.sh 里加了对应 feed。"
  if [ "${STRICT:-0}" = "1" ]; then
    echo
    echo "STRICT=1：校验失败，中止编译。"
    exit 1
  fi
  # 在工作流里输出 annotation，方便在 Actions 页面一眼看到
  [ -n "${GITHUB_ACTIONS:-}" ] && for m in "${MISSING[@]}"; do
    echo "::warning title=包未生效::${m%% *}"
  done
else
  echo "✅ 所有请求的包都已生效"
fi

echo
echo "=== 最终固件里的 LuCI 应用清单 ==="
# 过滤掉 luci-app-xxx_INCLUDE_yyy 这类子选项，只留真正的应用包
grep -oE '^CONFIG_PACKAGE_luci-app-[A-Za-z0-9_.+-]+=y' "$FINAL" \
  | sed 's/^CONFIG_PACKAGE_//; s/=y$//' | grep -vE '_[A-Z]' | sort | sed 's/^/  /'
exit 0
