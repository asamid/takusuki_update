# takusuki_update.sh

Custom Misskey updater script with interactive version selection and build automation.  
Designed for `systemd`-based Misskey installations (non-Docker).

## Features

- Interactive update mode selection
- Tag list preview and checkout
- Automatic environment loading from `.misskey.env`
- Directory permission fix, clean build, DB migration
- MAX_NOTE_TEXT_LENGTH patching (default: 5000)

## Usage

Run the script as root:

```bash
sudo bash takusuki_update.sh

---
### takusuki_update.sh とは？

Misskey サーバー向けのカスタムアップデートスクリプトです。  
`systemd` で Misskey を運用している環境を対象としています（Docker には非対応）。

このスクリプトは以下のような機能を備えています：

- 対話式でアップデート方法を選択可能
- Git タグ一覧からバージョンを選択してアップデート
- `.misskey.env` ファイルから環境変数を自動読み込み
- 所有権修正、クリーンビルド、DBマイグレーションを自動実行
- `MAX_NOTE_TEXT_LENGTH` を 5000 に自動拡張

---

### 使用方法

```bash
sudo bash takusuki_update.sh
