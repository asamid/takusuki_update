#!/bin/bash
# takusuki_update.sh - Custom Misskey updater with version support
#
# Author: asami (https://takusuki.com)
# License: MIT
#
# Based on: https://github.com/joinmisskey/bash-install
#           Copyright (c) 2021 aqz/tamaina, joinmisskey  
#           MIT License
#
# Modifications:
#   - Interactive version selection
#   - Environment auto-detection
#   - Enhanced user feedback

# カラー付き出力関数
print_step() { tput setaf 6; echo ">>> $1"; tput setaf 7; }
print_section() { echo ""; tput setaf 4; echo "==== $1 ===="; tput setaf 7; }
print_ok() { tput setaf 2; echo "? $1"; tput setaf 7; }
print_fail() { tput setaf 1; echo "? $1"; tput setaf 7; }

# オプション初期化
specified_version=""

# 起動時モード選択
print_section "Misskey Update Mode"
echo "1. 最新版へアップデート"
echo "2. タグから選んでアップデート"
echo "3. master へ強制リセット"
echo ""

read -p "番号で選んでください [1-3]: " mode
case "$mode" in
  1) specified_version="" ;;
  2) specified_version="choose" ;;
  3) specified_version="latest" ;;
  *) echo "無効な選択です"; exit 1 ;;
esac

# タグ選択関数
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

# root権限チェック
print_section "Checking root permissions"
if [ "$(whoami)" != 'root' ]; then
  print_fail "NG. This script must be run as root."
  exit 1
else
  print_ok "OK. Running as root."
fi

# 環境設定を読み込み
print_section "Loading environment settings"
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
    echo "(default settings applied)"
  fi
else
  misskey_user=misskey
  misskey_directory=misskey
  misskey_localhost=localhost
  method=systemd
  echo "(default settings applied)"
fi

echo "method: $method / user: $misskey_user / dir: $misskey_directory / $misskey_localhost:$misskey_port"

# バージョン選択処理開始
if [ "$specified_version" == "choose" ]; then
  select_version
  specified_version="$selected_tag"
fi

if [ "$method" == "systemd" ]; then

print_section "Update process (systemd)"

# Git操作開始
print_step "Fetching and checking out source..."

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

print_step "Stopping systemd service..."
systemctl stop "$host"
print_ok "Service stopped"

print_step "Fixing directory ownership..."
chown -R "$misskey_user":"$misskey_user" "/home/$misskey_user/$misskey_directory"
print_ok "Permission fixed"

# 卓すき仕様でビルド
print_step "Cleaning, patching, installing, building, migrating..."

su "$misskey_user" << MKEOF
set -eu
cd ~/$misskey_directory

echo "Cleaning..."
pnpm run clean

# 5000文字
echo "Modifying MAX_NOTE_TEXT_LENGTH..."
sed -i 's/export const MAX_NOTE_TEXT_LENGTH = 3000;/export const MAX_NOTE_TEXT_LENGTH = 5000;/' packages/backend/src/const.ts || true

# 絵文字ミュートをBlankへ
echo "Download unknown.png into frontend/assets"
wget -q -O /home/misskey/misskey/packages/frontend/assets/unknown.png "https://labo.takusuki.com/unknown.png" || echo "Download failed, continuing..."

echo "Installing dependencies..."
NODE_ENV=production pnpm install --frozen-lockfile

echo "Building Misskey..."
NODE_ENV=production pnpm run build

echo "Running migration..."
pnpm run migrate
MKEOF

print_ok "Build and migration complete"

print_step "Restarting systemd service..."
systemctl restart "$host"
print_ok "Service restarted"

print_ok "Update completed successfully"
fi
