# takusuki_update.sh

A custom update script for Misskey, featuring interactive version selection and automated build/migration.  
Intended for `systemd`-based Misskey environments (non-Docker).

---

## Features

- Interactive mode selection on startup
- Git tag listing and version selection
- Auto-detection of environment via `.misskey.env`
- Ownership fix, clean build, and database migration
- Automatic patching of `MAX_NOTE_TEXT_LENGTH` to 5000

---

## Usage

Run the script as root:

```bash
sudo bash takusuki_update.sh
```

You will be prompted with the following options:

1. Standard update (pull from master)  
2. Select version from Git tags  
3. Hard reset to master  

---

## Requirements

- Misskey installed under a local Linux user (not Docker)
- `pnpm`, `git`, and `systemctl` available
- Environment defined in `/root/.misskey.env` and/or `/home/<user>/.misskey.env`
- Misskey service controllable via `systemctl`

---

## License

This project is licensed under the [MIT License](./LICENSE).

---

## Acknowledgements

Parts of this script were inspired by and adapted from  
[bash-install](https://github.com/joinmisskey/bash-install),  
Copyright (c) 2021 aqz/tamaina, joinmisskey  
Licensed under the MIT License.

---

## 🇯🇵 日本語版 README

### takusuki_update.sh とは？

Misskey サーバー向けのカスタムアップデートスクリプトです。  
`systemd` を使用して Misskey を運用している環境に対応しており、Docker には非対応です。

このスクリプトには以下の機能があります：

- 起動時に対話形式でアップデートモードを選択可能
- Git タグの一覧からバージョンを選び、チェックアウトして更新
- `.misskey.env` から自動で環境変数を読み込み
- 所有権の修正、クリーンビルド、DBマイグレーションを自動実行
- `MAX_NOTE_TEXT_LENGTH` を 5000 に自動変更

---

### 使用方法

```bash
sudo bash takusuki_update.sh
```

起動後に以下の選択肢が表示されます：

1. 通常の最新版アップデート（master を pull）  
2. Git タグ一覧から選んで指定バージョンへ更新  
3. master へ強制リセット  

---

### 必要条件

- Misskey が一般ユーザーでインストールされていること（Docker ではない）
- `pnpm`, `git`, `systemctl` が使用可能であること
- `/root/.misskey.env` または `/home/<ユーザー名>/.misskey.env` に必要な設定が記述されていること
- Misskey サービスを `systemctl` で制御できること

---

### ライセンス

このスクリプトは [MIT ライセンス](./LICENSE) のもとで公開されています。

---

### 謝辞

本スクリプトは [joinmisskey/bash-install](https://github.com/joinmisskey/bash-install) にインスパイアされて開発されました。  
原作への敬意を表しつつ、対話モードやタグ選択機能など多数の改良を施しています。

作者: [asami](https://takusuki.com)
