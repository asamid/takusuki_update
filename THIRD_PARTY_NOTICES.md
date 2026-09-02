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
  - `bundle/takusuki-update3-bundle/misskey-patches/020-gallery-file-limit-256.patch`

これらはMisskey sourceへ適用する差分です。020を含むcandidateのbyte列は、機能検証と
deterministic rebuild後、2026-09-03の運用者waiverによりGit release sourceとして固定しました。
この判断はStaging isolation FAILをPASSへ変更するものではありません。

## joinmisskey/bash-install

- Project: [joinmisskey/bash-install](https://github.com/joinmisskey/bash-install)
- License: MIT
- Copyright: Copyright (c) 2021 aqz/tamaina, joinmisskey

Takusuki updaterは同projectの運用フローから影響・着想を受けています。MIT noticeはroot
[`LICENSE`](LICENSE)に保持しています。

## Takusuki original asset

- Files:
  - `bundle/takusuki-update3-bundle/assets/unknown.png`
  - `legacy/assets/unknown.png`
- Copyright: Copyright (c) 2025-2026 asami
- License: MIT

`unknown.png`はasamiが制作したTakusuki original assetです。authorshipはcopyright holder本人により
2026-08-16に確認されました。root [`LICENSE`](LICENSE)のMIT条件を適用します。
