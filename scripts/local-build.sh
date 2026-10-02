#!/bin/bash
# ============================================================================
# 本地编译脚本（在**你自己的**终端里跑，不是在这个沙箱里）
#
# 用法：
#   cd openwrt-build
#   ./scripts/local-build.sh
#
# 可选环境变量：
#   BUILD_DIR=$HOME/libwrt-build    源码与编译产物的位置（必须在 ext4/xfs/btrfs 上）
#   SRC_COMMIT=<sha>                锁定上游提交（稳定期建议填）
#   JOBS=16                         并行度，默认 nproc
#   USE_PROXY=http://127.0.0.1:7897 编译期走代理下载源码包（国内建议填）
#
# 为什么不能在这个沙箱里跑：
#   1) 沙箱里唯一的大容量可写盘是 E: 盘的 9p 共享，会剥掉文件执行位 —— 编出来的
#      工具跑不起来；2) 真正的 ext4（/）对沙箱只读；3) 没有 root 装不了构建依赖。
#   在你自己的 WSL 终端里这三个限制都不存在。
# ============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$HOME/libwrt-build}"
SRC_REPO="${SRC_REPO:-https://github.com/LiBwrt/LibWrt.git}"
SRC_BRANCH="${SRC_BRANCH:-25.12-nss}"
SRC_COMMIT="${SRC_COMMIT:-}"
JOBS="${JOBS:-$(nproc)}"
NEED_GB=30

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- 0. 前置检查
step "前置检查"

if [ "$(id -u)" = "0" ]; then
  red "不要用 root 编译（OpenWrt 明确禁止）。请用普通用户跑本脚本。"
  exit 1
fi

# 文件系统类型：必须在原生 Linux 文件系统上，否则执行位/符号链接会出问题
BUILD_PARENT="$(dirname "$BUILD_DIR")"
mkdir -p "$BUILD_PARENT" 2>/dev/null || true
FSTYPE="$(df -T "$BUILD_PARENT" 2>/dev/null | awk 'NR==2{print $2}')"
case "$FSTYPE" in
  ext4|xfs|btrfs) grn "文件系统 $FSTYPE ✓" ;;
  "")
    ylw "无法判断 $BUILD_PARENT 的文件系统，继续（若失败请换到 ext4 路径）" ;;
  *)
    red "BUILD_DIR 所在文件系统是 '$FSTYPE'，不是 ext4/xfs/btrfs。"
    red "在 drvfs/9p/ntfs/cifs 这类共享盘上编译会失败（执行位被剥掉）。"
    red "请改用原生路径，例如： BUILD_DIR=\$HOME/libwrt-build $0"
    exit 1 ;;
esac

FREE_GB="$(df -BG --output=avail "$BUILD_PARENT" | tail -1 | tr -dc '0-9')"
if [ "${FREE_GB:-0}" -lt "$NEED_GB" ]; then
  red "可用空间只有 ${FREE_GB}GB，OpenWrt 全量编译需要约 ${NEED_GB}GB。"
  exit 1
fi
grn "可用空间 ${FREE_GB}GB ✓"

MEM_GB="$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo)"
[ "$MEM_GB" -lt 4 ] && { red "内存只有 ${MEM_GB}GB，至少要 4GB。"; exit 1; }
grn "内存 ${MEM_GB}GB ✓ 并行度 JOBS=$JOBS"

# 依赖检查
step "检查构建依赖"
MISSING=()
for t in gcc g++ make patch perl python3 unzip cpio rsync wget curl \
         flex bison gawk gettext autoconf automake libtool zstd bc; do
  command -v "$t" >/dev/null 2>&1 || MISSING+=("$t")
done
for h in /usr/include/zlib.h /usr/include/ncurses.h /usr/include/openssl/ssl.h; do
  [ -f "$h" ] || MISSING+=("$(basename "$h")(头文件)")
done

if [ ${#MISSING[@]} -gt 0 ]; then
  red "缺少以下依赖：${MISSING[*]}"
  echo
  echo "用下面这条命令装上（Ubuntu/Debian）："
  echo
  cat <<'EOF'
sudo apt update
sudo apt install -y ack antlr3 asciidoc autoconf automake autopoint binutils bison \
  build-essential bzip2 ccache cmake cpio curl device-tree-compiler fastjar flex gawk \
  gettext gcc-multilib g++-multilib git gperf haveged help2man intltool libc6-dev-i386 \
  libelf-dev libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses-dev \
  libreadline-dev libfuse-dev libssl-dev libtool lrzsz genisoimage msmtp nano ninja-build \
  p7zip-full patch pkgconf python3 python3-pip libpython3-dev qemu-utils rsync scons \
  squashfs-tools subversion swig texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev
EOF
  echo
  echo "装完重新运行本脚本即可。"
  exit 1
fi
grn "依赖齐全 ✓"

# 可选：编译期代理（国内下载源码包会用到）
if [ -n "${USE_PROXY:-}" ]; then
  export http_proxy="$USE_PROXY" https_proxy="$USE_PROXY"
  grn "已启用下载代理 $USE_PROXY"
fi

# ---------------------------------------------------------------- 1. 取源码
step "获取上游源码到 $BUILD_DIR"
if [ -d "$BUILD_DIR/.git" ]; then
  ylw "目录已存在，改为更新"
  git -C "$BUILD_DIR" fetch --depth 1 origin "$SRC_BRANCH"
  git -C "$BUILD_DIR" checkout -f FETCH_HEAD
else
  git clone --depth 1 -b "$SRC_BRANCH" --single-branch "$SRC_REPO" "$BUILD_DIR"
fi
if [ -n "$SRC_COMMIT" ]; then
  git -C "$BUILD_DIR" fetch --depth 1 origin "$SRC_COMMIT"
  git -C "$BUILD_DIR" checkout --detach FETCH_HEAD
fi
grn "上游 commit: $(git -C "$BUILD_DIR" rev-parse HEAD)"

test -f "$BUILD_DIR/target/linux/qualcommax/image/ipq60xx.mk" \
  || { red "上游不含 qualcommax 目标，源码不对"; exit 1; }
grep -q 'jdcloud_re-ss-01' "$BUILD_DIR/target/linux/qualcommax/image/ipq60xx.mk" \
  || { red "上游不含 jdcloud_re-ss-01 设备定义"; exit 1; }
grn "设备定义存在 ✓"

# ---------------------------------------------------------------- 2. 应用配置
step "写入配置"
cp "$REPO_DIR/configs/jdcloud_re-ss-01.config" "$BUILD_DIR/.config"
cat "$REPO_DIR/configs/packages.config" >> "$BUILD_DIR/.config"

# 配置卫生检查（和工作流里一致）
BAD="$(grep -nE '^CONFIG_[A-Za-z0-9_-]+=.*#' "$BUILD_DIR/.config" || true)"
[ -n "$BAD" ] && { red "配置里有行内注释，请改成整行注释："; echo "$BAD"; exit 1; }
grn "配置格式检查通过 ✓"

# ---------------------------------------------------------------- 3. feeds
step "添加第三方 feed（按需）"
( cd "$BUILD_DIR" && bash "$REPO_DIR/scripts/diy-1-feeds.sh" )

step "更新并安装 feeds（这一步较慢，会下载不少东西）"
( cd "$BUILD_DIR" && ./scripts/feeds update -a && ./scripts/feeds install -a )

step "编译前自定义"
( cd "$BUILD_DIR" && bash "$REPO_DIR/scripts/diy-2-custom.sh" )

step "展开配置（make defconfig）"
( cd "$BUILD_DIR" && make defconfig )

step "校验包选择是否真的生效"
( cd "$BUILD_DIR" && bash "$REPO_DIR/scripts/check-packages.sh" "$REPO_DIR/configs/packages.config" ) || \
  ylw "有包未生效 —— 请按上面的提示检查包名或 feed（不影响继续编译）"

# ---------------------------------------------------------------- 4. 编译
step "预下载源码包（可用 Ctrl-C 中断后重跑）"
( cd "$BUILD_DIR" && make download -j8 || make download -j1 V=s )

step "开始编译 —— 首次全量大约 1.5–4 小时，建议挂后台："
echo "    cd $BUILD_DIR && nohup make -j$JOBS > build.log 2>&1 &"
echo "    tail -f $BUILD_DIR/build.log"
echo
( cd "$BUILD_DIR" && make -j"$JOBS" || { ylw "并行编译失败，改用单线程重试以获取详细日志"; make -j1 V=s; } )

# ---------------------------------------------------------------- 5. 产物
step "编译完成，产物如下"
OUT="$BUILD_DIR/bin/targets/qualcommax/ipq60xx"
ls -lh "$OUT"/*.bin "$OUT"/*.itb 2>/dev/null || true
echo
grn "要刷的文件："
echo "  $OUT/*-squashfs-sysupgrade.bin      ← 日常升级 / 从 iStoreOS 首次刷入都用它"
echo "  $OUT/*-squashfs-factory.bin        ← uboot web 页面刷写用"
echo
echo "校验："
( cd "$OUT" && sha256sum *.bin 2>/dev/null || true )
echo
ylw "提醒：首次从 iStoreOS 刷入必须用 sysupgrade -n（不保留配置）。详见 docs/04-刷机与回滚.md"
