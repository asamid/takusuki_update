# takusuki_update

Misskey のカスタムアップデートスクリプトと、[takusuki.com](https://takusuki.com) における独自の改変内容（AGPL v3 準拠）を含むリポジトリです。

---

## 🔧 主な改変内容

### 1. 投稿文字数制限の緩和
Misskeyの投稿最大文字数をデフォルトの 3000 文字から 5000 文字に拡張しています。

- 対象ファイル: `packages/backend/src/const.ts`
- 差分パッチ: `patches/maxnote5000.patch`

適用方法：

```bash
cd ~/misskey
patch -p1 < /path/to/patches/maxnote5000.patch
```

---

### 2. 画像の差し替え（unknown.png）

未登録のカスタム絵文字などが表示される際のデフォルト画像 `unknown.png` を差し替えています。

- 差し替えファイル: `assets/unknown.png`
- 配置先: `packages/frontend/assets/unknown.png`

適用方法：

```bash
cp /path/to/assets/unknown.png ~/misskey/packages/frontend/assets/unknown.png
```

---

## 🛠 takusuki_update.sh とは？

Misskey サーバー向けのカスタムアップデートスクリプトです。  
`systemd` によって Misskey を運用している環境に対応しており、**Docker 環境には非対応**です。

このスクリプトは以下の処理を自動で行います：

- 起動時に対話形式でアップデートモードを選択
- Git タグの一覧からバージョン選択とチェックアウト
- `.misskey.env` を自動読み込み（環境変数設定）
- 所有権の修正、クリーンビルド、DBマイグレーションの実行
- `MAX_NOTE_TEXT_LENGTH` の 5000 文字化処理

---

## ▶ 使用方法

```bash
sudo bash takusuki_update.sh
```

起動後、以下の選択肢が表示されます：

1. 最新版にアップデート（`master` を pull）  
2. Git タグ一覧からバージョンを選んでアップデート  
3. `master` へ強制リセット  

---

## ✅ 必要条件

- Misskey を通常ユーザーでインストールしていること（※ Docker は非対応）
- 以下のコマンドが使用可能であること：`pnpm`, `git`, `systemctl`
- `/root/.misskey.env` または `/home/<ユーザー名>/.misskey.env` に必要な設定が記述されていること
- Misskey サービスを `systemctl` で制御可能な構成であること

---

## 📜 ライセンス

このリポジトリは [MIT ライセンス](./LICENSE) のもとで公開されています。

---

## 🙏 謝辞

このスクリプトは [joinmisskey/bash-install](https://github.com/joinmisskey/bash-install) にインスパイアされて作成されました。  
原作への敬意を表しつつ、対話モードやタグ選択機能、文字数制限改変など多数の改良を加えています。

作者: [asami](https://takusuki.com/@asami)
