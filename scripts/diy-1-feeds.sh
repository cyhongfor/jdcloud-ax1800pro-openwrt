#!/bin/bash
# ============================================================================
# diy-1：添加第三方 feed
#
# 执行时机：**在 `./scripts/feeds update -a` 之前**（工作流里已按此顺序调用）
# 工作目录：openwrt/（源码树根），可直接读到已合并的 .config
#
# 设计：按需加源。只有在 .config 里真的选了某个第三方包时，才把它对应的 feed 加进来。
#       这样能避免多个 feed 之间的同名包冲突（passwall / helloworld / kenzok8 之间
#       经常同时提供 shadowsocks-libev、xray-core 一类包，全加进来会打架）。
#
# 强制全部添加：ADD_ALL_FEEDS=1 bash scripts/diy-1-feeds.sh
# ============================================================================
set -euo pipefail

FEEDS_FILE="feeds.conf.default"
[ -f "$FEEDS_FILE" ] || { echo "错误：当前目录不是 OpenWrt 源码树根（找不到 $FEEDS_FILE）"; exit 1; }

# 请求清单：默认读仓库里的 configs/packages.config（相对本脚本运行目录 openwrt/）
# ★ 为什么读它而不是读 .config：
#   本脚本在 `feeds update/install` **之前**运行，此时 .config 还不该存在
#   （存在也会被 scripts/feeds 的 refresh_config() 用 oldconfig 静默重建，
#    导致 feed 里的包符号被丢弃）。所以"你要哪些包"一律以请求清单为准。
REQ_FILE="${1:-${REQ_FILE:-../configs/packages.config}}"
[ -f "$REQ_FILE" ] || { echo "错误：找不到请求清单 $REQ_FILE"; exit 1; }

FORCE_ALL="${ADD_ALL_FEEDS:-0}"
ADDED=()

# 判断请求清单里是否要了某个包
want() {
  [ "$FORCE_ALL" = "1" ] && return 0
  grep -qE "^CONFIG_PACKAGE_$1=y" "$REQ_FILE" 2>/dev/null
}

# 幂等添加 feed（已存在则跳过）
add_feed() {
  local line="$1" name
  name="$(echo "$line" | awk '{print $2}')"
  if grep -qE "^[[:space:]]*src-git[[:space:]]+${name}[[:space:]]" "$FEEDS_FILE"; then
    echo "  [跳过] feed 已存在: $name"
    return
  fi
  echo "  [添加] $line"
  echo "$line" >> "$FEEDS_FILE"
  ADDED+=("$name")
}

echo "=== 按请求清单添加第三方 feed ==="
echo "    清单文件: $REQ_FILE（其中 $(grep -cE '^CONFIG_PACKAGE_[A-Za-z0-9_.+-]+=y' "$REQ_FILE") 个包）"

# ---------------------------------------------------------------- 代理插件
# OpenClash（你现在用的就是这个）—— 分支已实测存在：core/dev/master/package
if want luci-app-openclash; then
  add_feed "src-git openclash https://github.com/vernesong/OpenClash.git;dev"
fi

# PassWall（推荐替代方案，nftables 版）
if want luci-app-passwall; then
  add_feed "src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall.git;main"
  add_feed "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main"
fi

# SSR Plus（你现在用的是 ssrplus）
# 注意：helloworld 与 passwall 会提供同名包，两个都选会冲突，建议二选一
if want luci-app-ssr-plus; then
  add_feed "src-git helloworld https://github.com/fw876/helloworld.git;master"
fi

# ---------------------------------------------------------------- 工具类
if want luci-app-lucky; then
  add_feed "src-git lucky https://github.com/gdy666/luci-app-lucky.git;main"
fi

if want luci-app-serverchan; then
  add_feed "src-git serverchan https://github.com/tty228/luci-app-serverchan.git;master"
fi

if want luci-app-pushbot; then
  add_feed "src-git pushbot https://github.com/zzsj0928/luci-app-pushbot.git;master"
fi

# ---------------------------------------------------------------- 主题
# argon 主题本体与它的配置界面都在 immortalwrt/luci 里：
#   themes/luci-theme-argon、applications/luci-app-argon-config（均已核实存在）
# 所以**不需要**加 jerrykuku 的第三方源 —— 加了反而会出现两个同名包
# luci-app-argon-config 而互相冲突。这里刻意留空。

# aurora 主题与配置界面都不在 immortalwrt feeds 里，需要 eamonxg 的两个仓库
if want luci-theme-aurora || want luci-app-aurora-config; then
  add_feed "src-git aurora https://github.com/eamonxg/luci-theme-aurora.git;main"
  add_feed "src-git aurora_config https://github.com/eamonxg/luci-app-aurora-config.git;main"
fi

# ---------------------------------------------------------------- 按需强制加源
if [ "$FORCE_ALL" = "1" ]; then
  echo "  [强制模式] 已添加全部已知 feed"
fi

echo
if [ ${#ADDED[@]} -eq 0 ]; then
  echo "结果：没有需要额外添加的 feed（你的 .config 只用了上游自带包）"
else
  echo "结果：新增 ${#ADDED[@]} 个 feed -> ${ADDED[*]}"
fi
echo
echo "=== 当前 feeds.conf.default ==="
cat "$FEEDS_FILE"
