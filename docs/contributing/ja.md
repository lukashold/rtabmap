# KANTURA への参加

KANTURA は RTAB-Map の独立したフォークです。開発とプルリクエストの対象は [`lukashold/rtabmap:kantura/main`](https://github.com/lukashold/rtabmap/tree/kantura/main) です。全体の手順は[英語の参加ガイド](../../CONTRIBUTING.md)を参照してください。

## 最初の一歩

[ワークスペースの説明](../../tools/scan-workspace/README.md)、[機能比較](../KANTURA-FEATURES.md)、[検証記録](../../tools/scan-workspace/VALIDATION.md)を確認してください。報告する前に[既存の Issue](https://github.com/lukashold/rtabmap/issues)を検索します。再現可能な不具合、小さな操作性の改善、翻訳、実機テストなどが役立ちます。

ブラウザー版の開発にはリポジトリ全体、Node.js 24、pnpm 11.25.0 が必要です。`kantura/main` から作業用ブランチを作成し、`tools/scan-workspace` で実行します。

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm start
```

`http://localhost:4173` を開きます。Corepack、Docker、サーバー保存の設定はメインガイドにあります。形状計算、アーカイブ、保存処理の変更には意味のある検証を行ってください。文章だけの修正では言語と表示を確認します。実行した確認と、まだ実行できていない確認を区別して報告してください。

## 翻訳と使い方の説明

日本語パックは `tools/scan-workspace/locales/ja.json` にあります。ネイティブガイドの `app/ios/RTABMapApp/MeasurementGuide.json` と動画台本の `tools/scan-workspace/public/videos/scripts.json` との整合性も確認してください。キー、シーン ID、アイコン ID、単位、置換用の記号を維持します。字幕とナレーションの内容をそろえ、文字が切れる場合はスクリーンショットを添付してください。

動画は合成アニメーションで、実際に撮影したスキャンではありません。この表示を残してください。RoomPlan は屋内用で、門や屋外の物体には LiDAR スキャンを使います。別々の部屋は自動で位置合わせされません。基準寸法との照合はスキャン全体の精度保証ではなく、搬入の推定も実経路の全衝突を確認するものではありません。

## iPhone での検証

iOS のビルドと署名には Mac、対応する Xcode、ネイティブ依存関係が必要です。[インストールと公開のガイド](../APP-STORE-RELEASE.md)を参照してください。`app/ios/Tests/run-scan-tracking-tests.sh` と `run-measurement-guide-tests.sh` は、実機での撮影の代わりにはなりません。

報告にはリビジョン、端末、iOS バージョン、モード、再現手順、期待した結果と実際の結果を記載します。巻尺と比較した場合は両方の値、測定方法、単位を記録し、合成データか実データかを明示してください。変更に応じて部屋、門、中断、保存と再読み込み、写真、書き出しを確認します。私的な室内、人、住所、キー、アカウント情報を許可なく公開しないでください。

## プルリクエストとライセンス

フォークと `kantura/main` に基づく作業ブランチを作り、対象を絞った変更を **`lukashold/rtabmap:kantura/main`** に提案します。問題、変更後の動作、検証、制限を説明してください。一般的な RTAB-Map の修正は上流へ別途提案できます。KANTURA の画面やワークスペースはこのフォークで扱います。建設的にやり取りしてください。

著作権表示と [BSD 3-Clause ライセンス](../../LICENSE)を保持してください。ネイティブ依存関係には独自の条件があります。[公開監査](../APP-STORE-RELEASE.md#native-abhängigkeiten-und-lizenzen)を確認し、新しい依存関係のバージョン、ライセンス、目的を記載してください。秘密情報、署名証明書、配布権のない素材を追加しないでください。リポジトリやテストの成功だけで App Store 公開の準備が完了したことにはなりません。
