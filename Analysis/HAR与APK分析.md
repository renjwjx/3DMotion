# HAR 与 APK 分析

## HAR 结论

`SpiderProxy-20261012-202930.har` 共 145 个条目，其中关节-肌群页面的主机是 `musclemee.3dbody.com`。离线内容由以下路径组成：

- `static/data/processed_data.json`：70 个动作的中英文名称、分类、动画阶段和主动力/拮抗肌列表。
- `static/action/{id}`：AES-192-CBC 加密、zlib 压缩的 glTF 2.0 骨骼动画模型。
- `static/camera/{id}.json`：初始相机位置和观察目标。
- `static/img/pifuAlphaMap/{id}.png`、`static/img/gugeAlphaMap/{id}.png`：皮肤与骨骼透明蒙版。
- `www.3dbody.com/h/foundation_action/static/ava/jpg/{id}.jpg`：列表缩略图。
- `static/action/obj.fbm/*`：模型引用的公共纹理。

模型的封装逻辑来自网页加载器：文件前 8 字节作为口令，使用兼容 OpenSSL `EVP_BytesToKey(MD5)` 的 AES-192-CBC 解密余下数据，再进行 zlib inflate。解包结果是 glTF 2.0 JSON，几何使用 `KHR_draco_mesh_compression`，动画由 `THREE.AnimationMixer` 播放。

HAR 中的登录、权益和设备请求不是下载静态内容的必要条件，因此下载器不会复制或落盘任何 Authorization、登录表单或设备标识。

## 分类

接口实际返回 8 类 70 条：头颈部 10、面部 6、肩部 8、上肢 18、躯干 4、髋部和骨盆 5、下肢 8、粗大运动 11。截图的“躯干(5)”和“粗大运动(10)”与当前接口不一致；当前清单分别为 4 和 11，新增/迁移条目是 ID 76“脊柱环转”。App 以接口完整数据为准。

## APK 与网页交互

APK 是 Unity/Mono 应用，`Assembly-CSharp.dll` 中可确认 `CameraCtrl`、`CtrlViewWithMouseAtWin`、`CtrlViewWithTouchAtPad`、`ChangeRotateSlider`、`ChangeScaleSlider`、`RotateAround` 等交互入口。当前网页实现使用 Three.js `OrbitControls`，具体映射为左键/单指旋转、滚轮/双指缩放、右键/双指平移。

网页还实现了结构点击选择、双击聚焦、相机复位、镜像、剖切与撤销、肌层显示、主动肌/协同肌/稳定肌/拮抗肌着色、动画播放与阶段进度。macOS App 直接离线承载该查看器，以保留这些操作。
