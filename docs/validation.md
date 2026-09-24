# 検証記録

検証日: 2026-09-13(ドラム合成は 2026-09-24 に再検証)。macOS / Apple Silicon、SuperCollider 3.14.1、Node.js 24.14.0、Python 3を使用。以下は実行結果の記録です。追加Quarkや作品の音源を必要としない経路を確認しました。

## 配布

- インストーラーの6テストが通過: dry-run、バックアップと同一内容の再実行、生成物の除外、symlink拒否、実行権限の修復、更新失敗時の復元。
- 3 skillのfrontmatter、内部リンク、Python / JavaScript / shell構文、公開用パス検査が通過。

## 作曲と共通実行

- WAV checker / process runnerの11テストが通過。PCM24の既知値、無音、floatのNaN/Infinity、full-scale、破損WAV、使用中UDP、終了コード、timeout、正常終了後の子プロセス片付けを検証。
- macOSの終了時EPERMを再現し、稼働中のプロセスがない場合だけ終了済みと判断する修正後、11テストを20回連続で通過。稼働中のグループに対する権限エラーは保持する。
- 標準SCのNRT例: stereo / 48 kHz / PCM24、144,064 frames（3.001333秒）、peak −16.982 dBFS、RMS −32.358 dBFS、非有限値・full-scale sampleともに0。
- 別担当者がskill単体をコピーし、リポジトリ外の空白を含むパスから実行して同じ結果を確認。非公開toolkitや他skillへの依存なし。
- 1秒timeoutの実SC実行がexit 124で終了。無関係なsentinel processは生存し、使用UDPは再bind可能、所有するSC processの残存なし。
- 既存WAVの上書きを拒否してhashを保持。空白を含む出力パスは成功し、shell展開に使われる文字を含むパスは出力前に拒否。

## ドラム合成

- 2026-09-24: クラップ、クローズド／オープンハット、クラッシュを差し替え、乾いたリムを追加。いずれもワンショットを1音ずつ試聴したgood / bad評価と、測定値(`references/sound-design.md`)に基づく。キックとスネアは変更なし。
- 同日、エフェクト処理のチャンネルストリップ(`assets/fx.scd`)を追加。トランジェント整形、サチュレーション、コンプレッサー、コーラス、ディレイとリバーブのセンドを持ち、音色ごとのプリセットは試聴で承認されたもの。リムは試聴者の希望で処理なし。
- 6音色のgallery、同seedの再レンダー、sidechain例、garageループ例(処理なし・エフェクト処理あり)を標準SC 3.14.1でNRT実行。
- Gallery: 48 kHz / 24-bit PCM / stereo、18.001333秒。最終ブロック64 framesを含む長さ。
- 6音色すべてに音があり、クリップしたsampleは0。全体peak −16.216 dBFS。キック比のpeakはスネア −0.9、クラップ −2.0、クローズドハット −11.9、オープンハット −10.9、クラッシュ −9.0 dB。
- 同seedの2つのWAVのSHA-256が一致: `f1a2e27e32223a8722b3be77735b198c2f62de23e28972f97d7eb5fc9f7488a1`。
- Garage: 132 BPM・8小節ちょうどの698,182 frames、peak −1.0 dBFS、クリップ0。ループの継ぎ目の段差0.00206(通常のsample間変化の99.9パーセンタイル0.199)。6音色すべてに音があり、同seedのPCMが一致。seed 1の出力は、試聴で承認されたループとバイト単位で一致(SHA-256 `8367c322943f9fef6bbfce4a60174519b648a583946298145527f5d1d765ffb3`)。
- Garage(`fx`引数でエフェクト処理あり): 698,182 frames、peak −1.0 dBFS、クリップ0。継ぎ目の段差0.00364(99.9パーセンタイル0.198)。同seedのPCMが一致。seed 1の出力は、試聴で承認された処理済みループとバイト単位で一致(SHA-256 `d82062e4a9ee716a6a3fb687f698535efe534eff97d5c966e532911cc9c5a160`)。
- Sidechain: 997 Hzのキャリア成分が約34.192 dB減衰し、回復後の差は約+0.034 dB。専用bus、実行順序、attack/release処理を含む音声出力で確認。
- SIGINT / SIGTERM、NRT子プロセス実行中の終了、使用UDPの解放、無関係なプロセスの保持を確認。稼働中プロセスへのEPERMは明示的な失敗として保持。

## WebUI

- `npm test` 4/4通過。schema生成、入力検証、presetのパス逸脱、Host/Origin検査、実HTTP/WebSocket/OSC転送、再接続、バッチ記録の書き込み失敗を検証。
- `npm audit --omit=dev`: 0 vulnerabilities。検証時点のlockfileとscoped `qs` overrideを含む。
- `npm run test:integration`: 標準SC 3.14.1で逐次NRT、WAV/JSONの完了順序、現在ジョブ完了後の停止、使用中ポートの所有者保持、実行中NRT子プロセスの終了処理が通過。
- 44.1 kHz / 24-bit / stereoの短い3ファイルは2.001270秒で、固定seedのPCM SHA-256が一致: `8d2c861857eb0a0ccfca87902313ff69305dd21af9b7a46412f4cd230200a794`。peak 0.149003、RMS 0.019783。
- 停止テストは5件中1件のWAV/JSONを完了し、後続をスキップ。120秒のNRTを実行中にsupervisorを停止するテストでも、所有プロセスと使用ポートの解放を確認。
- ブラウザ1280×900 / 390×844で、copy/resetの分離、1件の実レンダー、reload後の状態、再接続を確認。page errorと横方向のoverflowは0。最終画面の完了状態と音声無効状態も確認。
- Audible RT previewおよびオーディオ機器への出力は未検証。

## 検証の限界

NRTの数値検査は、音楽的な試聴評価、実機オーディオ出力、Bluetooth機器、多チャンネル配線や会場校正の証明ではありません。CIは配布・構文・インストーラー・WebUIの単体／transport検証を実行し、SCを使う実レンダーはこのローカル検証と区別します。
