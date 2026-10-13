#!/bin/bash
# macOS 平台编译 third_party_ffmpeg（含 AV3A / Audio Vivid 封装与解封装支持）
#
# 用法: ./build_macos.sh [源码目录] [输出目录]
#   源码目录默认: 脚本同级目录
#   输出目录默认: ../build_macos_av3a
#
# 产物: <输出目录>/ffmpeg、<输出目录>/ffprobe（不执行 make install）
#
# 已对仓库做过的两处修改（已提交则无需重复操作，未提交时脚本自动处理）:
#   1. ffbuild/{libversion,pkgconfig_generate,version}.sh 加可执行权限
#      （git 中以 100644 提交，构建时 /bin/sh 调用会 Permission denied）
#   2. libavcodec/version.c 静态断言 AV_CODEC_ID_QOA 86121 -> 86122
#      （codec_id.h 在音频列表中部插入 AV_CODEC_ID_AVS3DA，其后 ID 顺移 +1）
#
# 说明: AV3A 在 MP4 中的封装/解封装代码（movenc.c 的 dca3 box 写入、
# mov.c 的 dca3 解析、isom_tags.c 的 'av3a' tag 等）均由 OHOS_AV3A_DEMUXER
# 宏保护，OHOS 产品构建在 BUILD.gn 中定义该宏；本脚本通过 --extra-cflags
# 传入同名宏在 macOS 上启用同样的代码路径。

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SRC_DIR=${1:-$SCRIPT_DIR}
OUT_DIR=${2:-$SCRIPT_DIR/../build_macos_av3a}

SRC_DIR=$(cd "$SRC_DIR" && pwd)
mkdir -p "$OUT_DIR"
OUT_DIR=$(cd "$OUT_DIR" && pwd)

# 修改点 1: 构建脚本可执行权限
chmod +x "$SRC_DIR/ffbuild/libversion.sh" \
         "$SRC_DIR/ffbuild/pkgconfig_generate.sh" \
         "$SRC_DIR/ffbuild/version.sh"

cd "$OUT_DIR"

# --disable-everything 后按需启用，编译快、体积小
# 需要全功能时去掉 --disable-everything 与各 --enable-* 即可，
# OHOS_AV3A_DEMUXER 宏必须保留
"$SRC_DIR/configure" \
    --disable-everything \
    --disable-doc \
    --disable-debug \
    --disable-ffplay \
    --enable-ffmpeg \
    --enable-ffprobe \
    --enable-demuxer=av3a,mov \
    --enable-muxer=av3a,mp4 \
    --enable-parser=av3a \
    --enable-protocol=file \
    --extra-cflags="-DOHOS_AV3A_DEMUXER"

make -j"$(sysctl -n hw.ncpu)"

echo
echo "构建完成: $OUT_DIR/ffmpeg"
