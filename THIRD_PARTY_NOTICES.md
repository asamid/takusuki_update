# Third-party notices

このrepositoryは単一ライセンスではありません。rootのMITライセンスはTakusuki updaterと
Takusuki独自helperに適用し、以下のthird-party由来部分には各ライセンスが適用されます。

## Misskey

- Project: [misskey-dev/misskey](https://github.com/misskey-dev/misskey)
- License: AGPL-3.0-only
- License text: [`LICENSES/AGPL-3.0-only.txt`](LICENSES/AGPL-3.0-only.txt)
- Applicable files:
  - `bundle/takusuki-update3-bundle/misskey-patches/001-max-note-text-length.patch`
  - `bundle/takusuki-update3-bundle/misskey-patches/010-exp003-federation-chart-blocked-host.patch`

これらはMisskey sourceへ適用する差分であり、patchのbyte列はLive Staging検証済みbundleから
変更せず取り込んでいます。

## joinmisskey/bash-install

- Project: [joinmisskey/bash-install](https://github.com/joinmisskey/bash-install)
- License: MIT
- Copyright: Copyright (c) 2021 aqz/tamaina, joinmisskey

Takusuki updaterは同projectの運用フローから影響・着想を受けています。MIT noticeはroot
[`LICENSE`](LICENSE)に保持しています。

## unknown.png

`bundle/takusuki-update3-bundle/assets/unknown.png`とlegacy copyは既存repository履歴に存在し、
bundle内のfileはそのbyte-identical copyです。しかし、履歴だけでは作者・権利保有・再配布条件を
確定できません。

- License: **UNKNOWN / clarification required**
- GitHub Releaseや第三者による再配布前に権利関係を確認してください。
