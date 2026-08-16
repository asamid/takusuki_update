# License audit — Takusuki Update3 v4.0.0

Audit date: 2026-08-16

| Path | License | Basis |
|---|---|---|
| `takusuki_update3.sh` | MIT | Takusuki updater code; root `LICENSE` |
| `scripts/*` | MIT | Takusuki original build/verification helpers; root `LICENSE` |
| `legacy/takusuki_update2.sh` | MIT | Existing notice; joinmisskey/bash-install MIT notice retained |
| `bundle/**/001-max-note-text-length.patch` | AGPL-3.0-only | Misskey-derived source patch |
| `bundle/**/010-exp003-federation-chart-blocked-host.patch` | AGPL-3.0-only | Misskey-derived source patch |
| `legacy/patches/maxnote5000.patch` | AGPL-3.0-only | Legacy Misskey-derived source patch |
| `bundle/**/assets/unknown.png` | UNKNOWN / clarification required | Existing history does not establish authorship or redistribution terms |
| `legacy/assets/unknown.png` | UNKNOWN / clarification required | Same byte-identical asset and unresolved provenance |
| `LICENSES/AGPL-3.0-only.txt` | AGPL-3.0-only license text | GNU Affero GPL v3 official text |
| Documentation | MIT | Takusuki project documentation; root `LICENSE` |

## License boundary result

**PASS with disclosed UNKNOWN asset status.** Repository全体をMIT-onlyとは表現していません。
Misskey由来patchにはAGPL-3.0-onlyを明示し、joinmisskey/bash-installのMIT noticeを保持しました。

`unknown.png`はSHA-256
`ac918e92451687bac2c17a139eb2528fd450c2b4dfcc169caae7442d88889c0f`のexact assetですが、
repository historyから権利保有者やlicenseを確定できません。確認完了まではUNKNOWNです。

## Operational metadata

検証済みupdaterにはProduction endpointを誤指定した場合に拒否するためのprivate IPv4/IPv6
denylist literalが含まれます。これはcredentialではなく安全制御ですが、public sourceから
内部addressingが判明します。exact Staging-verified artifactのSHAを維持するため変更していません。
