# 关节-肌群解析 App

这是一个支持 macOS、iPhone 和 iPad 的离线模型浏览器。它按原页面的 8 个分类展示 70 个动作，使用设备回环地址加载已经打包进 App 的模型、动画、肌群阶段数据、相机参数、蒙版和贴图。运行时不需要访问原服务器。

## 构建

```bash
cd 3DBodyMac
python3 Scripts/download_assets.py
zsh Scripts/build_app.sh
open "dist/关节-肌群解析.app"
```

成品位于 `dist/关节-肌群解析.app`。下载脚本支持断点式重复执行：已存在的文件会被校验并保留；加 `--force` 可重新下载。

也可以直接打开 `Body3DMac.xcodeproj`，Scheme `Body3DMac` 同时支持：

- macOS 14 及以上
- iPhone（iOS 17 及以上）
- iPad（iPadOS 17 及以上）

命令行构建 iPhone/iPad 模拟器版本：

```bash
xcodebuild \
  -project Body3DMac.xcodeproj \
  -scheme Body3DMac \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData-iOS \
  CODE_SIGNING_ALLOWED=NO build
```

真机运行时请在 Xcode 中选择自己的开发团队签名。

## 操作

- 左键拖动：旋转
- 滚轮或触控板双指滚动：缩放
- 右键拖动或两指平移：移动视角
- 单击结构：选择并显示名称
- 双击结构：聚焦
- 页面工具栏：播放/暂停、阶段进度、复位、镜像、剖切、撤销、肌层与着色等

下载器不会保存 HAR 里的 Authorization、手机号登录参数或设备标识，只访问 `foundation_action_new/static/` 和公开缩略图路径。

## 验证结果

- 离线资源：8 类、70 个动作、376 个文件、70,408,176 字节；70 个模型均已完成 AES 解密和 zlib/glTF 结构校验。
- macOS Debug 构建通过。
- iPhone 17 Pro（iOS 26.5）模拟器构建、安装、启动并加载 3D 模型通过。
- iPad Pro 13-inch (M5)（iOS 26.5）模拟器构建、安装、启动并加载 3D 模型通过。

模拟器运行截图位于 `Validation/`。
