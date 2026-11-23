#!/bin/zsh
# 给项目作者的一键发布助手。只会发布当前这个独立开源 Demo。
set -euo pipefail
cd "${0:A:h}"

if ! command -v gh >/dev/null 2>&1; then
  echo '请先在 Mac 终端运行：brew install gh'
  echo '安装后重新双击 Publish-to-GitHub.command。'
  read -r '?按回车结束…' || true
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo '请先在浏览器登录自己的 GitHub：'
  gh auth login
fi
if [[ ! -d .git ]]; then
  git init -b main
fi
if ! git config user.name >/dev/null || ! git config user.email >/dev/null; then
  echo 'Git 还缺少提交者信息，可先运行：'
  echo 'git config --global user.name "你的用户名"'
  echo 'git config --global user.email "GitHub 公开提交邮箱"'
  read -r '?按回车结束…' || true
  exit 1
fi

git add App AIShutterDemo.xcodeproj Tests backend docs Examples .github README.md LICENSE .gitignore project.yml create_xcodeproj.py Publish-to-GitHub.command
if ! git diff --cached --quiet; then
  git commit -m 'feat: let AI choose the shutter moment'
fi

REPO='Elisekaiu/AI-Takes-the-Photo'
if gh repo view "$REPO" >/dev/null 2>&1; then
  echo "仓库已存在，准备更新 $REPO"
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "https://github.com/$REPO.git"
  fi
  git push -u origin main
else
  echo "正在为 $REPO 建立独立的公开仓库…"
  gh repo create "$REPO" --public --source=. --remote=origin --push \
    --description 'SwiftUI 相机：让 AI 自己决定什么时候按下 iPhone 快门，边聊边拍。'
fi

echo
printf '发布成功：https://github.com/%s\n' "$REPO"
read -r '?按回车关闭…' || true
