#!/bin/bash
# takusuki_update.sh - Custom Misskey updater with version support
#
# Author: asami (https://takusuki.com)
# License: MIT
#
# This script was originally inspired by:
#   https://github.com/joinmisskey/bash-install
#   Copyright (c) 2022 syuilo and contributors
#   Licensed under the MIT License
#
# Substantial modifications have been made to support:
#   - interactive version selection
#   - environment auto-detection
#   - enhanced user feedback during update process

# 補助関数（カラー表示）
print_step() { tput setaf 6; echo ">>> $1"; tput setaf 7; }
print_section() { echo ""; tput setaf 4; echo "==== $1 ===="; tput setaf 7; }
print_ok() { tput setaf 2; echo "? $1"; tput setaf 7; }
print_fail() { tput setaf 1; echo "? $1"; tput setaf 7; }

# オプション初期化
specified_version=""

# 起動時にモードを選択
print_section "Misskey Update Mode"
echo "1. 通常の最新版アップデート"
echo "2. タグ一覧から選んでアップデート"
echo "3. master へ強制リセット"
echo ""

read -p "番号で選んでください [1-3]: " mode
case "$mode" in
  1) specified_version="" ;;
  2) specified_version="choose" ;;
  3) specified_version="latest" ;;
  *) echo "無効な選択です"; exit 1 ;;
esac

# ユーザーがタグ一覧から選択する関数
select_version() {
  echo "Fetching available tags..."
  tag_list=$(su "$misskey_user" -c "cd ~/$misskey_directory && git fetch --tags > /dev/null && git tag --sort=-creatordate")
  mapfile -t tags <<< "$tag_list"

  echo ""
  echo "Available Tags:"
  for i in "${!tags[@]}"; do
    printf "  [%2d] %s\n" "$i" "${tags[$i]}"
  done

  echo ""
  while true; do
    read -p "Select tag number (0-${#tags[@]}): " index
    if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 0 && index < ${#tags[@]} )); then
      selected_tag="${tags[$index]}"
      echo "Selected tag: $selected_tag"
      break
    else
      echo "Invalid selection. Try again."
    fi
  done
}

# rootチェック
print_section "Check: root user"
if [ "$(whoami)" != 'root' ]; then
  print_fail "NG. This script must be run as root."
  exit 1
else
  print_ok "OK. I am root user."
fi

# 環境読み込み
print_section "Import environment and detect method"
if [ -f "/root/.misskey.env" ]; then
  . "/root/.misskey.env"
  if [ -f "/home/$misskey_user/.misskey.env" ]; then
    . "/home/$misskey_user/.misskey.env"
    method=systemd
  elif [ -f "/home/$misskey_user/.misskey-docker.env" ]; then
    . "/home/$misskey_user/.misskey-docker.env"
  else
    misskey_user=misskey
    misskey_directory=misskey
    misskey_localhost=localhost
    method=systemd
    echo "use default"
  fi
else
  misskey_user=misskey
  misskey_directory=misskey
  misskey_localhost=localhost
  method=systemd
  echo "use default"
fi

echo "method: $method / user: $misskey_user / dir: $misskey_directory / $misskey_localhost:$misskey_port"

# バージョン選択処理
if [ "$specified_version" == "choose" ]; then
  select_version
  specified_version="$selected_tag"
fi

if [ "$method" == "systemd" ]; then

print_section "Update process (systemd)"

#region Git操作
print_step "Running git checkout / pull / tag update..."

su "$misskey_user" << MKEOF
set -eu
cd ~/$misskey_directory
git fetch --all --tags
git reset --hard

if [ "$specified_version" != "" ] && [ "$specified_version" != "latest" ]; then
  echo "Checking out version: $specified_version"
  git checkout "tags/$specified_version" -b "update-$specified_version"
else
  echo "Pulling latest changes"
  git checkout master
  git pull
fi

git submodule update --init
MKEOF

print_ok "Git update complete"
#endregion

print_step "Stopping systemd service..."
systemctl stop "$host"
print_ok "Service stopped"

print_step "Fixing directory ownership..."
chown -R "$misskey_user":"$misskey_user" "/home/$misskey_user/$misskey_directory"
print_ok "Permission fixed"

#region Build & Migration
print_step "Running clean, patch, install, build, and migrate..."

su "$misskey_user" << MKEOF
set -eu
cd ~/$misskey_directory

echo "Process: clean"
pnpm run clean

echo "Modify MAX_NOTE_TEXT_LENGTH"
sed -i 's/export const MAX_NOTE_TEXT_LENGTH = 3000;/export const MAX_NOTE_TEXT_LENGTH = 5000;/' packages/backend/src/const.ts || true

echo "Installing dependencies"
NODE_ENV=production pnpm install --frozen-lockfile

echo "Building Misskey"
NODE_ENV=production pnpm run build

echo "Running migration"
pnpm run migrate
MKEOF

print_ok "Build and migration complete"
#endregion

print_step "Restarting systemd service..."
systemctl restart "$host"
print_ok "Service restarted"

print_section "Misskey update finished successfully!"
fi
