# 参与 KANTURA 开发

KANTURA 是 RTAB-Map 的独立分支。开发和拉取请求以 [`lukashold/rtabmap:kantura/main`](https://github.com/lukashold/rtabmap/tree/kantura/main) 为目标。[英文主指南](../../CONTRIBUTING.md)介绍完整流程。

## 开始开发

先阅读[工作区说明](../../tools/scan-workspace/README.md)、[功能比较](../KANTURA-FEATURES.md)和[验证记录](../../tools/scan-workspace/VALIDATION.md)，并搜索[本分支的问题列表](https://github.com/lukashold/rtabmap/issues)。可以从可复现的缺陷、界面小改进、翻译或真机测试开始。

浏览器开发需要完整仓库、Node.js 24 和 pnpm 11.25.0。从 `kantura/main` 创建自己的分支，在 `tools/scan-workspace` 中运行：

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm start
```

打开 `http://localhost:4173`。Corepack、Docker 和服务器存储的设置见主指南。修改几何或数据保存逻辑时，应提供相关测试；仅修改文字时，检查相应语言和布局即可。请说明实际运行过的检查和仍未验证的部分。

## 翻译和教程

网页文字位于工作区的 `src/i18n.js` 和 `src/experience-i18n.js`；原生教程位于 `app/ios/RTABMapApp/MeasurementGuide.json`。视频使用 `tools/scan-workspace/public/videos/scripts.json`。保留键名、场景 ID、单位和占位符；字幕与旁白应同步修改。文字被截断时请附上截图。

解释视频是合成动画，不是真实扫描。请保留这一说明，以及测量和搬运估算的能力限制。

## 真机测试

iOS 开发需要 Mac、兼容的 Xcode、原生依赖和自己的签名，步骤见[安装指南](../APP-STORE-RELEASE.md)。Swift 脚本 `app/ios/Tests/run-scan-tracking-tests.sh` 和 `run-measurement-guide-tests.sh` 不能替代 iPhone 上的实际采集。

报告中请注明代码版本、设备、iOS 版本、扫描模式、复现步骤、预期与实际结果。用卷尺比较测量值，并给出两组数值和单位。明确标记合成数据。根据改动测试房间、大门、中断、保存与重开、照片和导出。未经相应授权，不要公开私人室内场景、人物或账户凭据。

## 提交拉取请求

创建自己的 fork，从 `kantura/main` 建立分支，完成范围明确的修改并验证，然后向 **`lukashold/rtabmap:kantura/main`** 提交 PR。解释问题、最终行为和限制。通用 RTAB-Map 修复可以另行提交原项目；KANTURA 品牌界面和浏览器改动先提交此分支。请尊重其他参与者，围绕可观察的问题开展讨论。

## 许可要求

项目代码使用 [BSD 3-Clause](../../LICENSE)。保留版权和第三方声明，只提交有权分发的内容。原生依赖需要单独审查：启用 `WITH_ORB_OCTREE` 的实现使用 GPLv3，OpenCV 启用了 Nonfree，还需核查实际使用的 SuiteSparse/g2o 组件，以及静态 LASzip 2.0.1/libLAS。新增依赖应说明准确版本、许可和用途。[发布审查记录](../APP-STORE-RELEASE.md#native-abhängigkeiten-und-lizenzen)不代表已经完成 App Store 分发许可审核。
