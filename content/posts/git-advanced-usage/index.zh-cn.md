---
title: "Git高级用法"
subtitle: ""
date: 2023-06-27T00:01:52+08:00
lastmod: 2023-06-27T00:01:52+08:00
draft: false
author: "Bard"
authorLink: "www.bardblog.cn"
description: "介绍git的一些不太常见的高级用法"
license: ""
images: []

tags: ["git","linux"]
categories: ["technology"]

featuredImage: ""
featuredImagePreview: ""

hiddenFromHomePage: false
hiddenFromSearch: false
twemoji: false
lightgallery: true
ruby: true
fraction: true
fontawesome: true
linkToMarkdown: true
rssFullText: true

toc:
  enable: true
  auto: true
code:
  copy: true
  maxShownLines: 50
math:
  enable: false
  # ...
mapbox:
  # ...
share:
  enable: true
  # ...
comment:
  enable: true
  # ...
---

## Git 子模块

### 概念
>Git 子模块允许你将另一个 Git 仓库作为主仓库的子目录引入。每个子模块都是一个独立的 Git 项目，具有自己的提交、拉取和推送操作。主仓库以子模块的形式包含多个子仓库。

### 示例
我们通过一个示例来了解如何使用 Git 子模块。

1. 创建一个名为 "gitSubmodules" 的文件夹，并将其初始化为 Git 仓库：
   ```shell
   mkdir gitSubmodules
   cd gitSubmodules
   git init
   ```

2. 添加一个远程 origin，并将仓库推送到 GitHub：
   ```shell
   git remote add origin git@github.com:你的用户名/gitSubmodules.git
   echo "关于 gitSubmodules" >> README.md
   git add .
   git commit -m "初始化 gitSubmodules"
   git push --set-upstream origin main
   ```

   在这里，将 "你的用户名" 替换为你的 GitHub 用户名。

3. 现在，让我们将两个子仓库添加到 "gitSubmodules" 仓库中：
   ```shell
   git submodule add git@github.com:你的用户名/submodule1.git
   git submodule add git@github.com:你的用户名/submodule2.git
   ```

   执行这些命令后，"gitSubmodules" 仓库将添加子模块 "submodule1" 和 "submodule2"。此命令会将子模块的远程仓库克隆到 "gitSubmodules" 仓库的根目录中。

   默认情况下，每个子模块将被放置在与子仓库同名的目录中。

4. 如果你执行 `git status` 命令，你将看到仓库中现在有一个名为 ".gitmodules" 的文件，以及两个名为 "submodule1" 和 "submodule2" 的目录。

   ".gitmodules" 文件存储了子模块的本地目录路径与远程仓库 URL 之间的映射关系。

5. 提交并推送更改到主仓库：
   ```shell
   git add .
   git commit -m "添加 submodule1 和 submodule2 子模块"
   git push
   ```

   这将把子模块的信息一并推送到远程仓库。

6. 如果有人克隆了 "gitSubmodules" 仓库，他们最初会得到子模块的空目录。为了将子模块填充为其相应的内容，他们需要运行以下命令：
   ```shell
   git submodule init
   git submodule update
   ```

   运行这些命令后，子模块的远程文件将与本地仓库同步，包括每个子模块的提交信息。

### 使用场景
Git 子模块在需要在主项目中引入其他项目时非常有用,每个项目可以拥有自己独立的仓库和版本控制历史，确保对主项目和子模块的修改互不干扰。







