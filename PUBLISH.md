# 发到你自己的 GitHub

已整理成独立仓库，名字建议就叫 **AI-Takes-the-Photo**。

等 Mac 打开后，解压本项目。在 Mac 终端安装一次 GitHub CLI：

```bash
brew install gh
gh auth login
```

接着双击文件夹里的 **`Publish-to-GitHub.command`**。它会把这个独立 Demo 发布到 `Elisekaiu/AI-Takes-the-Photo`，不会改动你现有的 Lumae 或其他 GitHub 仓库。

也可以自己新建一个空的 Public 仓库，然后用 `git init`、`git add .`、`git commit` 和 `git push` 上传。

仓库设为 Public 之后，大家就可以 clone 下来用 Xcode 打开 `AIShutterDemo.xcodeproj`。记得不要提交自己服务器的 `.env`。
