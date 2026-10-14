# AV3A <-> MP4 往返转换测试（linux_amd64）

本文档记录在 Ubuntu 24.04 上将该工程编译为可执行文件（仅编译，不安装）的步骤，
以及使用 `conformance_test` 目录中的 AVS3-P3（Audio Vivid / AV3A）符合性测试序列
执行 av3a -> MP4、MP4 -> av3a 往返转换测试的过程与结果。

## 1. 编译环境

| 项目 | 值 |
| ---- | -- |
| 操作系统 | Ubuntu 24.04.5 LTS (x86_64) |
| 编译器 | gcc 13.3.0 (Ubuntu 13.3.0-6ubuntu2~24.04.1) |
| 汇编器 | yasm 1.3.0（x86 汇编优化已启用） |
| 构建方式 | 源码树内 `./configure && make -j16`，不执行 `make install` |

## 2. 编译步骤

```bash
./configure \
    --disable-avdevice --disable-postproc --disable-network \
    --disable-dwt --disable-faan --disable-pixelutils --disable-bsfs \
    --disable-encoders --disable-decoders --disable-hwaccels --disable-muxers --disable-demuxers \
    --disable-parsers --disable-protocols --disable-devices --disable-filters \
    --disable-doc --disable-debug --disable-iconv --disable-stripping \
    --disable-vaapi --disable-vdpau --disable-zlib --disable-xlib --disable-cuvid --disable-cuda \
    --disable-libxcb --disable-libxcb_shm --disable-libxcb_shape --disable-libxcb_xfixes \
    --disable-sdl2 --disable-bzlib --disable-lzma --disable-vulkan \
    --enable-demuxer=mp3,aac,ape,flac,ogg,wav,mov,mpegts,amr,amrnb,amrwb,matroska,flv,mpegps,asf,asf_o,srt,h264,webvtt,av3a,avi,mpegvideo,ac3,gsm,gsm_ms,amv,smjpeg,thp,xa,adx,dtk,afc,psxstr,dts,caf,aiff,au \
    --enable-muxer=mp4,h264,ipod,amr,mpegts,mp3,wav,flac,av3a,adts,ogg,flv \
    --enable-parser=h263,h264,hevc,mpeg4video,vp8,vp9,mpegvideo,mjpeg \
    --enable-parser=mpegaudio,aac,aac_latm,av3a,amr,opus,ac3,gsm,gsm_ms,ilbc,cook,dca,dvaudio \
    --enable-decoder=h263,h264,mpeg2video,mpeg4,vp8,vp9,wmv3,msvideo1,mjpeg,cinepak,mpeg1video,dvvideo,rawvideo \
    --enable-decoder=mp2,mp3,mp3float,aac,aac_latm,ape,flac,vorbis,opus,amrnb,amrwb,ac3,gsm_ms,wmav1,wmav2,wmapro,adpcm_mtaf,adpcm_ima_wav,adpcm_ms,adpcm_ima_qt,adpcm_ima_dk3,adpcm_ima_dk4,adpcm_ima_ws,adpcm_ima_smjpeg,adpcm_ima_dat4,adpcm_ima_amv,adpcm_ima_apc,adpcm_ima_iss,adpcm_ima_oki,adpcm_ima_rad,adpcm_adx,adpcm_afc,adpcm_aica,adpcm_ct,adpcm_dtk,adpcm_g722,adpcm_g726,adpcm_g726le,adpcm_psx,adpcm_sbpro_2,adpcm_sbpro_3,adpcm_sbpro_4,adpcm_thp,adpcm_thp_le,adpcm_xa,adpcm_yamaha,gsm,alac,pcm_dvd,pcm_bluray,ilbc,twinvq,dvaudio,cook \
    --enable-decoder=png,bmp \
    --enable-encoder=aac,aac_latm,opus,flac \
    --enable-encoder=mpeg4,h263 \
    --enable-bsf=h264_mp4toannexb,extract_extradata \
    --enable-protocol=file \
    --enable-filter=crop,transpose,vflip,hflip \
    --extra-cflags=-DOHOS_AV3A_DEMUXER

make -j16
```

编译产物：源码树根目录下的 `ffmpeg`、`ffprobe` 可执行文件。

> 注：首次编译时系统未安装 nasm/yasm，曾使用 `--disable-x86asm` 完成构建；
> 安装 yasm 1.3.0 后按上述命令重新 configure 并编译，x86 汇编优化生效
> （`HAVE_X86ASM=1`），重新执行全部测试结果一致。

## 3. 构建过程中发现并修复的问题

### 3.1 ffbuild/pkgconfig_generate.sh 缺少可执行权限

仓库中该脚本的 git 模式为 `100644`（不可执行），导致 `make` 在生成 `*.pc`
文件时报 `Permission denied`。

修复：`chmod +x ffbuild/pkgconfig_generate.sh`，并将模式以 `100755` 记录到 git。

### 3.2 libavcodec/version.c 静态断言失败

本 fork 在 codec id 列表中（`MPEGH_3D_AUDIO` 与 `SIREN` 之间）插入了
`AV_CODEC_ID_AVS3DA`，使后续 id 整体后移一位（`QOA` 由 86121 变为 86122）。
上游 n7.1.1 的 `static_assert` 不匹配 fork 的枚举布局，编译报错
`Don't insert new codec ids in the middle of a list`。
OHOS 的 gn 构建（BUILD.gn）未编译 `libavcodec/version.c`，因此该问题此前未暴露。

修复：将断言更新为 fork 的实际布局，并显式加入对 `AV_CODEC_ID_AVS3DA == 86108`
的检查，防止后续误插。

### 3.3 链接错误：ff_aom_uninit_film_grain_params 未定义

`libavcodec/h2645_sei.c` 的 `ff_h2645_sei_reset()` 无条件调用
`ff_aom_uninit_film_grain_params()`（上游 n7.1.1 同样如此），而
`aom_film_grain.o` 仅在 `CONFIG_HEVC_SEI` 下编译（libavcodec/Makefile）。
当构建不含 HEVC 相关组件时链接失败。OHOS 构建通过 BUILD.gn 显式加入
`aom_film_grain.c` 规避。

修复：configure 增加 `--enable-parser=hevc`（`hevc_parser_select` 含
`hevc_sei`），使 `aom_film_grain.o` 参与编译，无需改动源码。

### 3.4 OHOS_AV3A_DEMUXER 宏

AVS3DA 在 MP4（`mov.c`/`movenc.c`/`isom_tags.c`）、FLV、MPEG-TS 中的特殊处理
由宏 `OHOS_AV3A_DEMUXER` 保护，该宏原仅在 OHOS 构建（BUILD.gn cflags）中定义。
Linux 构建通过 `--extra-cflags=-DOHOS_AV3A_DEMUXER` 启用，否则
`movenc` 找不到 av3a 的 codec tag（`could not find tag for codec avs3da`），
`mov` 解复用器也无法识别 `av3a` 采样项，av3a <-> MP4 转换不可用。

## 4. 测试方法

测试素材：`FFmpeg/conformance_test/` 下 11 种声道布局共 78 个
`AVS3P3_Conformance_Test_Sequence_01_48kHz_16bits_*.av3a` 序列
（Mono 11、Stereo 10、5.1 12、5.1.2 4、5.1.4 6、7.1 8、7.1.2 5、7.1.4 5、
FOA 4、HOA2 7、HOA3 6）。

对每个序列执行：

```bash
# av3a -> MP4
ffmpeg -y -v error -i <seq>.av3a -c copy <seq>.mp4
# MP4 -> av3a
ffmpeg -y -v error -i <seq>.mp4  -c copy <seq>_back.av3a
# 字节级一致性校验
cmp <seq>.av3a <seq>_back.av3a
```

判定标准：两步转换均以 0 退出，且 `_back.av3a` 与原始 `.av3a` 字节完全一致
（说明 AV3A 帧在 MP4 容器中无失真存取，av3a 解封装按帧边界切分正确）。

## 5. 测试结果

| 声道布局 | 序列数 | av3a->MP4 | MP4->av3a | 字节一致 |
| -------- | ------ | --------- | --------- | -------- |
| Mono     | 11 | 11/11 | 11/11 | 11/11 |
| Stereo   | 10 | 10/10 | 10/10 | 10/10 |
| 5.1      | 12 | 12/12 | 12/12 | 12/12 |
| 5.1.2    | 4  | 4/4   | 4/4   | 4/4   |
| 5.1.4    | 6  | 6/6   | 6/6   | 6/6   |
| 7.1      | 8  | 8/8   | 8/8   | 8/8   |
| 7.1.2    | 5  | 5/5   | 5/5   | 5/5   |
| 7.1.4    | 5  | 5/5   | 5/5   | 5/5   |
| FOA      | 4  | 4/4   | 4/4   | 4/4   |
| HOA2     | 7  | 7/7   | 7/7   | 7/7   |
| HOA3     | 6  | 6/6   | 6/6   | 6/6   |
| **合计** | **78** | **78/78** | **78/78** | **78/78** |

补充验证：

- MP4 中为单路音频流：`codec_name=av3a`、`codec_tag=av3a`、48 kHz、
  声道数与布局一致（如 5.1 -> 6 声道、5.1.4/7.1.2 -> 10 声道）。
- MP4 内写有自定义 `dca3` box（AV3A 参数信息），可由本工程 `mov` 解复用器读回，
  保证 extradata 完整往返。
- 每序列 1430 个 AV3A 帧（1024 samples/帧，时长约 30.5 s）。
