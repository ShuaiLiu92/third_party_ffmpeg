# macOS 平台编译与 AV3A MP4 封装/解封装测试

## 一、构建方法

一条命令完成配置+编译（不安装）：

```bash
./build_macos.sh
# 产物: ../build_macos_av3a/ffmpeg、../build_macos_av3a/ffprobe
```

核心 configure 参数（详见 `build_macos.sh`）：

```bash
configure \
    --disable-everything --disable-doc --disable-debug --disable-ffplay \
    --enable-ffmpeg --enable-ffprobe \
    --enable-demuxer=av3a,mov \
    --enable-muxer=av3a,mp4 \
    --enable-parser=av3a \
    --enable-protocol=file \
    --extra-cflags="-DOHOS_AV3A_DEMUXER"
```

关键点：AV3A 在 MP4 中的封装/解封装代码（movenc.c 写 dca3 box、
mov.c 读 dca3 box、isom_tags.c 的 'av3a' tag、av3a parser 等）全部由
`OHOS_AV3A_DEMUXER` 宏保护。OHOS 产品构建在 BUILD.gn:190 定义该宏，
macOS 构建通过 `--extra-cflags` 传入同名宏即可。av3a 解封装器/封装器/
parser 组件由 configure 从 allformats.c / parsers.c 自动发现注册，
无需改 configure。

## 二、修改点清单（2026-10，分支 darwin_arm64）

### 1. 构建必需（不改无法编译）

| 文件 | 修改 | 原因 |
|---|---|---|
| `ffbuild/libversion.sh`<br>`ffbuild/pkgconfig_generate.sh`<br>`ffbuild/version.sh` | 增加 `+x` 可执行权限 | git 中以 100644 提交，构建时 `/bin/sh` 调用报 Permission denied |
| `libavcodec/version.c` | 静态断言 `AV_CODEC_ID_QOA == 86121` 改为 `86122` | codec_id.h 在音频列表中部（MPEGH_3D_AUDIO 与 SIREN 之间）插入 `AV_CODEC_ID_AVS3DA`，其后所有音频 codec ID 顺移 +1；subtitle/data 列表有独立起始值不受影响 |

### 2. 测试中发现的 bug 修复（movenc.c 的 dca3 box）

`libavformat/movenc.c` `mov_write_dca3_tag()` 两处：

1. **码率字节序错误**：`AV_RB16(extradata + 8)` 改为 `AV_RL16(...)`。
   extradata 是 av3adec.c 以本机（小端）memcpy 写入的 `Av3aFormatContext`
   结构体，AV_RB16 按大端读导致 16 位码率字节交换（128 kbps 被写成
   32768）。同分支 flvenc.c 用本机解引用读取（正确），仅 movenc 读错。
   非分片 MP4 下 mov.c 的 mov_build_index 会用实际数据量重算 bit_rate
   掩盖该错误，但 dca3 box 内存储值错误，影响其他按规范读 dca3 的播放器。
2. **未初始化字节写入**：`avio_write(pb, buffer, sizeof(buffer))` 固定写
   7 字节，改为 `put_bytes_count(&pb_dca3, 1)`（按实际位数 5/6/7 字节）。
   ambisonic（40 bit）与 channel-based（48 bit）布局原先会写入 1~2 字节
   未初始化栈数据，导致 MP4 不可复现。flvenc.c 同函数本来就是按精确字节数
   写的。修复后两次封装逐字节一致。

## 三、AV3A MP4 封装/解封装测试

- 码流：`../conformance_test/` 全部 11 种布局（Mono/Stereo/5.1/5.1.2/
  5.1.4/7.1/7.1.2/7.1.4/FOA/HOA2/HOA3）共 **78 个** .av3a 文件
- 流程：`.av3a --(-c copy)--> .mp4 --(-c copy)--> .rt.av3a`，逐字节比对；
  ffprobe 校验 MP4 流参数与 dca3 box 内容
- 结果：**78/78 封装 OK、解封装 OK、往返码流逐字节一致**
- MP4 中流参数均正确恢复：codec av3a、48 kHz、声道布局（mono/stereo/
  5.1(side)/7.1/带 TSL/TSR/TFL/TFR/TBL/TBR 的自定义布局/ambisonic 1~3）、
  采样格式 s16、帧数与时长（1430 帧、30.507 s）
- 修复后 dca3 box：channel-based 6 字节、ambisonic 5 字节，码率值与源
  码流一致（如 Mono_128000 → 128 kbps、HOA3_896000 → 896 kbps）

测试脚本：`../build_macos_av3a/run_av3a_test.sh`，
结果：`../build_macos_av3a/test_out/results.tsv`。
