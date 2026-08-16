# GitHub publication audit — v4.0.0

Audit date: 2026-08-16

## Verified artifacts

- Updater SHA-256: `a121db5ab1ef3d834f8cf3f49909318b3a6736eb3e0dc608acca7a6c71a9aa5f`
- Bundle SHA-256: `be3c5a0846bd36313b5292193a8c947e6913f0d4c3ee150d34e609b3f5d0e7de`
- Repository updater is byte-identical to the Live Staging artifact.
- `scripts/build-bundle.sh` produces a byte-identical ZIP from repository source.
- Bundle manifest inventory、individual SHA-256/size、ZIP CRC、path/type checks: PASS

## Secret audit

**PASS**

commit予定fileをprivate-key header、GitHub/AWS token形式、Bearer/Authorization値、
`DATABASE_URL`実値、password/secret/token関連語、environment file名、高entropy候補で検査した。

reviewした語彙一致:

- `process.env.EXP003_DATABASE_URL`: integration test用の環境変数名だけで値なし
- `db.pass` / `PGPASSWORD`: runtimeでtrusted Misskey configから子processへ渡すcodeで実値なし
- `.misskey.env` / `/root/.misskey.env`: runtime探索pathだけでfile内容なし
- SECURITY/README/verification script内のsecurity用語と検出pattern: documentation/codeのみ
- 64桁hex値: SHA-256 digestのみ

次の禁止物は存在しない。

- `.env`、`.misskey.env`、実環境`default.yml`
- DB dump、PostgreSQL backup、runtime log
- SSH/private key
- GitHub/Cloudflare/SMTP credential、API token、cookie、session value
- `~/.config/gh/hosts.yml`またはCodex credential

## Operational metadata audit

exact updater内に次の値が存在する。

- Production IPv4 denylist literal: `192.168.100.29`
- Production IPv6 denylist literal: `2400:4051:b900:7400:250:56ff:fe22:664c`
- trusted configuration候補path: `/root/.misskey.env`

IP literalはcredentialではなく、Production endpointをbundle/health targetに指定した場合に
拒否する安全制御である。public sourceからinternal addressingが判明する点は認識済みだが、
Live Staging検証済みexact updater SHAを維持するため変更していない。Staging IP、DB password、
token、internal hostname、実環境config/log/backupは含まれない。

## License audit

結果は[`license-audit.md`](license-audit.md)を参照。updater/helperはMIT、Misskey-derived
patchはAGPL-3.0-only。`unknown.png`は権利根拠を確定できないため
`UNKNOWN / clarification required`として公開時に明示している。
