# Security policy

## Reporting a vulnerability

security issue、credential、再現用secretをpublic Issueへ投稿しないでください。GitHubの
private security advisoryを優先して利用してください。存在しない連絡用email addressは
案内していません。

次の情報をIssue、PR、logへ貼らないでください。

- `.env`、`.misskey.env`、実環境`default.yml`
- database/Redis password、connection URL、dump、backup
- API token、GitHub/Cloudflare/SMTP credential、cookie、session secret
- SSH/private key
- private LAN構成やProduction credential

## Artifact verification

updaterはrootで動作するため、実行前に配布sidecarでSHA-256を確認してください。bundleは
updater自身もSHA、ZIP構造、manifest、各fileのhash/sizeを検証し、検証失敗時はservice停止前に
fail-closedします。

security advisoryへ添付する場合も、credentialを除去した最小限の再現情報だけを使用してください。
