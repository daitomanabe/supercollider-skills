# SuperCollider Skills

SuperColliderで作曲、ドラム合成、WebUIによる試聴・書き出しを行うための、Codex / Claude Code向けskill集です。個別プロジェクトやサンプル音源に依存せず、標準UGenで動かせる例と検証用スクリプトを含みます。

| Skill | 担当 |
| --- | --- |
| [sc-composition-toolkit](skills/sc-composition-toolkit/SKILL.md) | 作曲、SynthDef、Pattern、RT/NRT、音声検証、任意の既存toolkitとの連携 |
| [sc-drum-synthesis](skills/sc-drum-synthesis/SKILL.md) | キック・スネア・クラップ・リム・ハットなどの音色設計、ビート、sidechain、継ぎ目のないループ、エフェクト処理、テンポ同期のSE(ダウンリフター、インパクト、ライザー)と808・シンセベース、ディレイタイムのザップ、スタッター、リファレンス比較 |
| [sc-webui-preview-render](skills/sc-webui-preview-render/SKILL.md) | パラメータ定義を共有するブラウザUI、OSC、プレビュー、バッチレンダー |

必要なskillだけを読み、詳しい手順はリンク先のreferencesへ進む構成です。既存の3つのskill名を維持しています。

## インストール

Python 3.10以降が必要です。

```sh
git clone https://github.com/daitomanabe/supercollider-skills.git
cd supercollider-skills
python3 scripts/install.py                    # Codexへの変更予定を確認
python3 scripts/install.py --apply            # 3 skillをインストール
python3 scripts/install.py --target claude --apply
```

`--skill sc-drum-synthesis`のように対象を限定できます。Codexは`$CODEX_HOME/skills`（未指定時は`~/.codex/skills`）、Claude Codeは`~/.claude/skills`へコピーします。`--destination /path/to/skills`で変更できます。更新前の既存フォルダはskillsフォルダ外にバックアップし、内容一致を確認します。`.system`や無関係なskillは変更しません。既存のskill管理システムを使う場合は、`skills/`からその管理元へ取り込み、通常の手順で対象だけを配布してください。

インストール後は新しいセッションで、たとえば次のように呼び出します。

```text
$sc-composition-toolkit 8小節の生成アンビエントを作り、WAVで書き出して検証して
$sc-drum-synthesis 標準UGenでキックとハットを作り、短いNRT比較をして
$sc-webui-preview-render 試聴パラメータと書き出し設定を分けたWebUIを作って
```

## 実行環境

- SuperColliderの`sclang`と`scsynth`。付属音源例は追加Quark / sc3-plugins不要。
- Python 3.10以降。WebUIテンプレートはNode.js 22以降とnpm。
- 実行方法と依存関係の指定は各skillの説明を参照してください。

NRTはオフラインでWAVを作成し、オーディオ機器を開きません。RTプレビューは使用する機器のサンプルレートと出力設定を確認してから起動します。共有マシン上の他のSuperColliderプロセスを停止しません。

## 検証と開発

```sh
python3 scripts/validate.py
python3 -m unittest discover -s tests -v
```

上記は構成・リンク・構文・インストーラーの検証です。DSPやレンダーの変更時は、該当skillの短い実レンダーと音声検証も実行します。今回の実行結果と範囲は[検証記録](docs/validation.md)を参照してください。

このリポジトリは公開配布元です。既存の作曲toolkit本体、第三者のSynthDef集、音源、作品固有のデータは同梱しません。作曲skillは単体で利用でき、既存toolkitを持つ場合の連携方法も説明しています。[整理方針](docs/organization.md)に公開範囲と変更点を記録しています。

MIT License — Copyright (c) 2026 Daito Manabe
