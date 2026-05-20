# Opus 模拟器 ARM64 支持修复

## 问题

在 Apple Silicon Mac（M 系列芯片）上运行 iOS 模拟器时，编译报错：

```
Error (Xcode): Framework 'opus' not found
```

## 原因

`opus_flutter_ios` 插件提供的 `opus.xcframework` 仅包含两个架构 slice：

| Slice | 架构 | 用途 |
|---|---|---|
| `ios-arm64` | arm64 | 真机 |
| `ios-x86_64-simulator` | x86_64 | Intel Mac 模拟器 |

缺少 `ios-arm64-simulator`（Apple Silicon 模拟器），导致 Xcode 在 arm64 模拟器上找不到匹配的 opus 库。

## 修复方案

从 opus 1.3.1 源码编译 arm64 模拟器版本，通过 `lipo` 合并为通用模拟器二进制（arm64 + x86_64），替换原有 xcframework。

### 修改内容

**文件路径**: `app/ios/.symlinks/plugins/opus_flutter_ios/ios/opus.xcframework`

修复前：
```
ios-arm64/                  → arm64（真机）
ios-x86_64-simulator/       → x86_64（Intel 模拟器）
```

修复后：
```
ios-arm64/                  → arm64（真机，未改动）
ios-arm64_x86_64-simulator/ → arm64 + x86_64（通用模拟器）
```

### 修复步骤

```bash
# 1. 下载 opus 1.3.1 源码
cd /tmp
curl -sL https://downloads.xiph.org/releases/opus/opus-1.3.1.tar.gz -o opus-1.3.1.tar.gz
tar xzf opus-1.3.1.tar.gz

# 2. 编译 arm64 iOS 模拟器版本
cd opus-1.3.1
./configure \
  --host=aarch64-apple-darwin \
  --target=arm64-apple-ios14.0-simulator \
  --enable-static --disable-shared \
  CFLAGS="-arch arm64 -isysroot $(xcrun --sdk iphonesimulator --show-sdk-path) -mios-simulator-version-min=14.0 -O2" \
  LDFLAGS="-arch arm64 -isysroot $(xcrun --sdk iphonesimulator --show-sdk-path) -mios-simulator-version-min=14.0"
make -j$(sysctl -n hw.ncpu)

# 3. 创建 arm64-sim framework
SIM_FW=/tmp/opus-build/opus.framework
mkdir -p "$SIM_FW/Headers" "$SIM_FW/Modules"

# 复制头文件（从现有真机 framework）
OPUS_XCFW=app/ios/.symlinks/plugins/opus_flutter_ios/ios/opus.xcframework
cp -R "$OPUS_XCFW/ios-arm64/opus.framework/Headers/" "$SIM_FW/Headers/"
cp "$OPUS_XCFW/ios-arm64/opus.framework/Modules/module.modulemap" "$SIM_FW/Modules/"

# 从静态库创建动态库
xcrun --sdk iphonesimulator clang++ \
  -arch arm64 -mios-simulator-version-min=14.0 \
  -dynamiclib -o "$SIM_FW/opus" \
  /tmp/opus-1.3.1/.libs/libopus.a \
  -isysroot $(xcrun --sdk iphonesimulator --show-sdk-path) \
  -install_name @rpath/opus.framework/opus

# 4. 合并为通用模拟器 framework（arm64 + x86_64）
UNI_FW=/tmp/opus-build/opus-sim.framework
cp -R "$OPUS_XCFW/ios-x86_64-simulator/opus.framework" "$UNI_FW"

lipo -create \
  "$OPUS_XCFW/ios-x86_64-simulator/opus.framework/opus" \
  "$SIM_FW/opus" \
  -output "$UNI_FW/opus"

# 5. 创建新 xcframework
xcodebuild -create-xcframework \
  -framework "$OPUS_XCFW/ios-arm64/opus.framework" \
  -framework "$UNI_FW" \
  -output /tmp/opus-new.xcframework

# 6. 替换原 xcframework
rm -rf "$OPUS_XCFW"
cp -R /tmp/opus-new.xcframework "$OPUS_XCFW"

# 7. 重新运行 pod install 生成正确的构建脚本
cd app/ios && pod install
```

## 影响范围

| 平台 | 影响 |
|---|---|
| iOS 真机 (arm64) | 无影响，slice 未改动 |
| iOS 模拟器 (arm64) | 新增支持 |
| iOS 模拟器 (x86_64) | 无影响，二进制未改动 |

## 注意事项

1. **`flutter clean` 后需重新 `pod install`**：xcframework 位于 `.symlinks/plugins/` 目录，`pod install` 会读取它生成构建脚本。clean 不会删除该文件，但如果重新 `flutter pub get` 触发了插件更新，可能覆盖修复。

2. **`opus_flutter_ios` 插件升级时**：如果升级 `opus_flutter` 包版本，新版本可能覆盖 xcframework。升级后需检查是否包含 arm64-sim 支持，若无则需重新执行修复步骤。

3. **模拟器功能限制**：Opus 编解码在模拟器上可正常工作，但 WebRTC 语音通话建议在真机上测试（模拟器无真实麦克风输入）。

## 相关信息

- opus 源码版本: 1.3.1（与原 xcframework 中的版本一致）
- 编译日期: 2026-04-14
- 编译环境: macOS 26.3.1, Xcode 26.4, Apple Silicon (arm64)
