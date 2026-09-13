# 整理方針

SuperCollider専用の3 skillを、既存の呼び出し名を変えずに公開用パッケージへ整理しました。作曲全般、ドラム設計、WebUIの責務を分け、長いコード例や特定環境の手順を必要時に読むreferencesへ移しました。

入口となる`SKILL.md`の総文字数は32,296から8,707へ、約73%短縮しました。必要な具体例は実行可能なファイルに移し、詳細資料は関連する用途から参照します。

| Skill | 整理前の文字数 | 整理後の文字数 |
| --- | ---: | ---: |
| sc-composition-toolkit | 10,640 | 2,866 |
| sc-drum-synthesis | 14,400 | 3,067 |
| sc-webui-preview-render | 7,256 | 2,774 |

- `sc-composition-toolkit`: ローカルの固定配置と非公開toolkitを前提にした入口を、単体で使えるSC制作手順へ変更。既存toolkitのAPIは任意連携として保持。
- `sc-drum-synthesis`: 音色設計の意図を保ちつつ、実行例と説明を分離。特定のハット設計や機器で得た注意点を、SC全体の制約として扱わない。
- `sc-webui-preview-render`: 配布時に欠ける生成先ディレクトリ、ポート判定、NRTの完了判定、JSON保存、入力検証、プロセス管理を見直す。

`autechre-fm`は特定エンジンの移植、`als-remix-enhance`はAbletonのリミックス、`magenta-realtime-sequencer`は別エンジンとの統合が主目的なので、この配布には含めていません。汎用的な空間AV skillや作品固有のRoomデータも対象外です。

Claude側に存在する旧`supercollider-process-hygiene`のうち、外側のタイムアウト、所有プロセスだけの終了、NRT音声の内容検査という要点は作曲skillに含めています。この公開パッケージは旧skillや個人用hookの存在を前提にしません。既存のhookや旧skillの設定はインストーラーでは変更しません。

同梱コードは本skill集の標準UGen例とWebUIテンプレートです。既存toolkitの`external/`、収集コード、音源、顧客資料、第三者ライセンスの異なるコードは取り込んでいません。外部ドキュメントへのリンクは参照資料であり、同梱物のライセンスを変更するものではありません。

今後の公開版の編集元はこのリポジトリです。別のskill catalogへ取り込む場合は、公開版のGit revisionを記録し、対象skillを検証して配布します。過去のtoolkitに付属するskillインストーラーは古い内容を上書きし得るため、この配布版と同時運用する際は使う配布元を一つに決めてください。
