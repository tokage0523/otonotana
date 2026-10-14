# 音の棚 — iPhone用音楽プレーヤー

SwiftUI / AVAudioPlayer、iOS 17以降向けの初版です。GitHubのmacOS環境でiPhone向けReleaseビルドとPC・Swift両方の歌詞形式チェックが成功し、未署名IPAを生成しました。iPhone実機での導入・再生確認はまだ実施していません。IPAはAltStore Classicなどで署名してからインストールします。

最新のビルド・検証状況: https://github.com/tokage0523/otonotana/actions/runs/38522143276

## 現在の実装

- 「ファイル」から複数の曲を取り込み、アプリ内にコピーしてオフラインで再生
- m4a（AAC / ALAC）、MP3、WAV、AIFF、CAF。暗号化された曲には非対応
- 元ファイルを再圧縮せず、そのまま保存
- 曲一覧、曲名検索、削除、再生・一時停止、前後の曲、シーク、順番再生
- バックグラウンド再生とロック画面の再生操作
- 電話などの割り込みとイヤホン切断への対応
- PCの編集画面で歌詞ごとの開始時刻を手入力・再生位置から設定し、UTF-8 LRCに保存
- iPhoneでは選択した曲にLRCを読み込み、歌詞タップで指定時刻から再生
- 現在の歌詞の強調表示と自動スクロール

取り込み時に音楽ファイル内の曲名・アーティスト・アルバム・ジャケットを読み込みます。情報がない場合はファイル名と仮のジャケットを使用します。プレイリスト、シャッフル、リピート、FLACは今回の実装には含めていません。同じ曲を再度取り込むと別の曲として保存します。元の音楽ファイルは変更しません。アプリを削除すると取り込んだコピーも削除されます。

## 0.2版のプレイヤー画面

- ライブラリの下部は小さなミニプレーヤー。タップするとジャケット中心の再生画面が開きます。
- 再生画面の左下の吹き出しアイコンでジャケットと歌詞を切り替えます。
- 歌詞の「自動スクロール ON / OFF」を切り替えられます。OFFでは再生位置の強調表示のみ更新し、スクロール位置は動かしません。ONに戻すと現在の行に戻ります。設定は次回起動時も保持します。
- 右上の「…」から、写真または画像ファイルを使ってジャケットを設定、LRCの読み込み、曲名・アーティスト・アルバムの編集ができます。
- 背景は「ジャケットに合わせる」「ミッドナイト」「ペーパー」の3種類から選択できます。ジャケット下の歌詞プレビューもON / OFFを選べます。
- お気に入りと絞り込み、曲一覧、AirPlay出力先選択を追加しています。
- ジャケットは曲ごとに保存します。取り込んだ画像は表示用に最大1200pxのJPEGへ変換しますが、元画像や音楽は変更しません。
- 以前の曲と歌詞を読み込める互換性を維持しています。更新は同じAppleアカウントでIPAを上書き導入し、既存アプリを削除しないでください。署名ツール側の挙動もあるため、元の音楽とLRCは別途保管してください。

`Design/directions.html` はコードで作成した見た目の草案です。実際のSwiftUI画面のスクリーンショットではありません。シミュレーターのUIテストでは架空のサンプル音源・歌詞・ジャケットを使用し、本番Release版にはサンプルの生成処理を含めません。

## PCで歌詞に時刻を付ける

1. `PCEditor/index.html` をEdgeやChromeで開く。PCEditorフォルダー内の3ファイルは同じ場所に置く。
2. 音楽ファイルを選び、歌詞を1行ずつ貼り付けて「歌詞の行を追加」を押す。
3. 曲を再生し、各行の歌い始めに「選択行に今の時刻 → 次の行」を押す。Ctrl＋Enterも使える。
4. 秒数欄に直接入力、または±0.1秒で調整する。「ここから再生」で確認できる。
5. 「LRCを保存」で時刻付き歌詞を保存する。未設定の行がある場合は保存を止める。
6. 編集途中で終わる場合は「下書きを保存」。次回はJSONファイルを読み込んで続ける。

音楽・歌詞は外部へ送信しません。ブラウザ内にも下書きを自動保存しますが、ブラウザの保存データを消すと失われるため、下書きファイルの保存を推奨します。音楽自体は下書きに含まれず、再開時に同じファイルを選び直します。ブラウザによってALACの再生ができない場合があります。その場合は秒数の手入力を使えます。再生位置がずれるのを防ぐため、PCとiPhoneでは同じ音楽ファイルを使用してください。

## iPhoneで歌詞から再生する

1. PCから音楽ファイルとLRCをiPhoneの「ファイル」で開ける場所へ転送する。
2. アプリの＋から音楽を取り込み、その曲を選ぶ。
3. 曲をタップして再生画面を開き、左下の吹き出しアイコンで歌詞に切り替える。右上の書類＋アイコン、または中央の「LRCを読み込む」から対応する歌詞を選ぶ。再生画面右上の「…」からも読み込める。
4. 歌詞の行をタップすると、その時刻から再生する。一時停止中でも再生を開始する。

読み込んだ歌詞はその曲に保存され、次回も利用できます。LRCは `[00:12.345]歌詞` の形式です。空の歌詞行は間奏として表示します。時刻は各行の開始位置です。音楽ファイルへ歌詞を埋め込む必要はありません。

## Windowsから無料で導入する候補

クラウドビルドとIPAの生成は成功しました。AltStore Classicによる署名・導入、およびiPhone 15 Pro / iOS 26.6.1での動作は未検証です。

1. GitHubに公開リポジトリを用意し、このM4APlayerフォルダーの**中身**をルートに配置する。`.github/workflows/build-ios.yml` も含める。音楽や歌詞、Appleアカウントの情報はアップロード不要。
2. mainブランチへのコード追加・更新でビルドが開始する。Actions → Build iPhone app → Run workflowから手動でも実行できる。公開リポジトリの標準macOSランナーは無料。非公開リポジトリでは実行をスキップする設定で、ストアへの配信は行わない。
3. ビルドに成功したら成果物 `M4APlayer-unsigned` をダウンロードし、ZIP内のIPAを取り出す。未署名なのでそのままではiPhoneで起動できない。
4. AltStoreの公式Windows手順に従ってAltServerとAltStore Classicを導入する。
5. USBでiPhoneをPCに接続し、Windowsの通知領域にあるAltServerのアイコンをShiftキーを押しながらクリックする。「Sideload .ipa…」からIPAを選び、自分の無料Apple Accountで署名して導入する。iCloudへの転送は不要。AltStore Classic内の「My Apps → ＋」からIPAを選ぶ方法も使える。
6. 無料署名は7日で期限切れになるので、期限前にAltServerを使って更新する。更新は通常アプリを削除せずに行える。アプリ削除は取り込んだ曲・歌詞も消すため避ける。

公開リポジトリを使う場合はアプリのソースが公開されます。非公開リポジトリの無料実行枠や課金設定は別条件なので、費用ゼロを保証するものではありません。このプロジェクトから外部への公開・課金サービスの登録は行っていません。

- GitHubの無料標準ランナー: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- AltStore ClassicのWindows導入: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
- 7日ごとの更新: https://faq.altstore.io/altstore-classic/your-altstore

## ビルドに必要なもの

Mac（手元・借用・クラウドのいずれか）、XcodeとiOS SDK、XcodeGen。実機へのインストールにはAppleの署名設定が必要です。WindowsだけでXcodeのビルドは実行できません。

1. Macへこのフォルダーをコピーする。
2. XcodeGenをインストールし、このフォルダーで `xcodegen generate` を実行する。
3. 生成された `M4APlayer.xcodeproj` をXcodeで開く。
4. Signing & Capabilitiesで自分のTeamを選択し、Bundle Identifierを自分固有の値に変更する。
5. 自分のiPhoneを接続し、必要に応じてDeveloper Modeを有効にする。
6. iPhoneを実行先に選んでRunする。

無料Apple AccountのPersonal Teamは個人の実機テスト用です。署名に有効期限があり、継続利用には再インストールなどが必要です。有料メンバーシップでも署名の更新は必要です。クラウドMacを使う場合も実機への導入方法は別途選定してください。

Macのシミュレーターでのビルド確認例（署名不要）:

```sh
xcodebuild -project M4APlayer.xcodeproj -scheme M4APlayer -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## 実機で確認すること

- AACとALACのm4aを取り込み、元ファイルと取り込んだファイルのハッシュが一致すること
- 再生、一時停止、シーク、前後の曲、最後の曲での停止
- アプリ再起動後も一覧と曲が残ること
- 画面ロック後の継続再生とロック画面操作
- 電話などの割り込み、イヤホン切断時の一時停止
- 壊れた曲や未対応形式を取り込んだ際のエラー表示
- 再生中の曲の削除と、検索中の曲の削除
- PCで作った日本語LRCの読み込み、再起動後の保存、別の曲に歌詞が混ざらないこと
- 再生中・一時停止中の歌詞タップが指定秒数から再生を開始すること
- 歌詞の自動スクロール、間奏行、曲の長さを超えた時刻のエラー表示
- 自動スクロールOFFで手動の閲覧位置が保持されること、ONへ戻すと現在行に戻ること
- 写真・画像ファイルによるジャケットの設定、別の曲への切り替え、アプリ再起動後の表示
- 旧版の曲・歌詞を引き継いだ更新、曲の情報とお気に入りの保存

デザインの参考: [Apple Musicの再生画面](https://support.apple.com/ja-jp/guide/iphone/iph676daac9b/ios)、[Spotifyの歌詞画面・プレビュー](https://support.spotify.com/us/article/lyrics/)、[Dopplerの曲情報編集](https://apps.apple.com/us/app/doppler-mp3-flac-player/id1468459747)、[foobar2000のiOS画面](https://www.foobar2000.org/screenshots-ios)。スクロールの切り替えは本アプリの用途に合わせて追加しています。

PC側の形式チェックは `node PCEditor/lyrics-core.test.cjs`。iPhone側のパーサーのチェックはGitHubのmacOSビルド時に実行します。実機上の動作を確認するテストの代わりにはなりません。

## 公式資料

- 日本の代替マーケットプレイス: https://developer.apple.com/jp/support/app-distribution-in-japan/
- 個人の実機テスト: https://developer.apple.com/help/account/basics/about-your-developer-account
- ファイルの取り込み: https://developer.apple.com/documentation/swiftui/view/fileimporter(isPresented:allowedContentTypes:onCompletion:)
- オーディオセッション: https://developer.apple.com/documentation/avfaudio/avaudiosession
- ロック画面の情報: https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter
