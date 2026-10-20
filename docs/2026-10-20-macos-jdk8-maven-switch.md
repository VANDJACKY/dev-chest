# macOS 多版本 JDK 共存与切换指南（含 Maven 安装）

> 适用场景：macOS（Apple Silicon / Intel）上已有一个新版 JDK（如 17/21），需要再安装 JDK 8 等老版本跑遗留项目，**不改变系统全局默认 Java**，只在特定终端会话中按需切换。
>
> 整理自 2026-10 在本机（macOS 15 + Apple Silicon，默认 JDK 21）安装 Zulu JDK 8 的实操过程。

---

## 1. 原理速览

- macOS 有一个系统级的 JDK 注册机制：放在 `/Library/Java/JavaVirtualMachines/` 下的 JDK 会被自动识别，可通过 `/usr/libexec/java_home` 查询和选择版本。
- **切换某个终端会话的 Java 版本，只需要在该会话里设置 `JAVA_HOME` 并把 `$JAVA_HOME/bin` 放到 `PATH` 最前**，不影响其他终端、IDE 和系统默认。
- Homebrew 的 cask 安装方式最省事，但安装 pkg 到系统目录时需要输入一次 macOS 登录密码（必须在自己的终端交互输入，不能在自动化脚本里完成）。

## 2. 安装第二个 JDK（以 Apple Silicon 装 JDK 8 为例）

Apple Silicon 上 JDK 8 推荐使用 **Azul Zulu**（有原生 aarch64 构建）；Temurin/Oracle 官方 8 没有 macOS arm64 版本。

```bash
# 确认 cask 存在（会显示最新版本号）
brew info --cask zulu@8

# 安装（会提示输入登录密码 —— 这步必须自己来，没有 TTY 的环境会卡住）
brew install --cask zulu@8
```

安装位置：`/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home`

### 验证与查看已注册的 JDK

```bash
# 列出本机所有 JDK
/usr/libexec/java_home -V

# 按版本号取路径（8 要写成 1.8）
/usr/libexec/java_home -v 1.8

# 直接验证二进制
/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home/bin/java -version
```

### 备选：不想用 brew / 输密码时（绿色解压版，装到用户目录）

从 Azul 官网下载 `.tar.gz`（如 `zulu8.x.x.x-ca-jdk8.0.xxx-macosx_aarch64.tar.gz`），解压到用户目录即可使用：

```bash
mkdir -p ~/jdks && cd ~/jdks
tar xzf ~/Downloads/zulu8.*-macosx_aarch64.tar.gz
# JDK 路径 = 解压目录（里面的 Contents/Home 或根目录，视包结构而定）
./zulu8.xxx/Contents/Home/bin/java -version
```

这种方式系统 `java_home` 工具不认识它，切换脚本需改用显式路径。

## 3. 一键切换脚本 `usejdk`

### 3.1 脚本内容

保存为 `~/bin/usejdk.zsh`：

```zsh
#!/bin/zsh
# usejdk - 在当前 shell 会话中一键切换 JDK 版本（不改全局默认，不影响其他终端/IDE）
# 用法:
#   usejdk          列出本机所有可用 JDK
#   usejdk 8        切换到 JDK 1.8（当前会话生效）
#   usejdk 17 / usejdk 21  同上
#   usejdk -r       恢复为系统默认 JDK

usejdk() {
  local ver="$1"

  if [[ -z "$ver" ]]; then
    echo "本机可用 JDK："
    /usr/libexec/java_home -V 2>&1
    echo
    echo "当前 JAVA_HOME: ${JAVA_HOME:-<未设置，使用系统默认>}"
    echo "当前 java 版本: $(java -version 2>&1 | head -1)"
    return 0
  fi

  if [[ "$ver" == "-r" ]]; then
    unset JAVA_HOME
    if [[ -n "$_USEJDK_OLD_PATH" ]]; then
      export PATH="$_USEJDK_OLD_PATH"
      unset _USEJDK_OLD_PATH
    fi
    echo "已恢复系统默认 JDK：$(java -version 2>&1 | head -1)"
    return 0
  fi

  # 版本号归一化：8 -> 1.8，其余按大版本
  [[ "$ver" == "8" ]] && ver="1.8"

  local home
  home=$(/usr/libexec/java_home -v "$ver" 2>/dev/null)
  if [[ -z "$home" ]]; then
    echo "未找到 JDK $ver，可用版本如下：" >&2
    /usr/libexec/java_home -V 2>&1
    return 1
  fi

  [[ -z "$_USEJDK_OLD_PATH" ]] && _USEJDK_OLD_PATH="$PATH"
  export JAVA_HOME="$home"
  # 新 JDK 的 bin 放到 PATH 最前，java/javac 即指向该版本
  export PATH="$JAVA_HOME/bin:$PATH"
  echo "已切换到: $JAVA_HOME"
  java -version 2>&1
}
```

### 3.2 安装并挂载到 zsh

```bash
mkdir -p ~/bin
# （把上面脚本内容写入 ~/bin/usejdk.zsh 后）
cp ~/.zshrc ~/.zshrc.bak.$(date +%Y%m%d)          # 先备份
echo '[ -f ~/bin/usejdk.zsh ] && source ~/bin/usejdk.zsh' >> ~/.zshrc
source ~/.zshrc
```

### 3.3 使用

```bash
usejdk        # 列出所有可用 JDK + 当前生效版本
usejdk 8      # 当前终端切到 JDK 8（跑老项目用）
usejdk 21     # 切回 21
usejdk -r     # 恢复系统默认（unset JAVA_HOME + 还原 PATH）
```

> 注意：只在**当前 shell 会话**生效。关闭终端窗口/标签后自动回到系统默认，天然隔离。

## 4. 安装 Maven

```bash
brew install maven
mvn -v
```

要点：

- Homebrew 装 Maven 会附带下载一个最新版 openjdk 作为依赖，**不用管它** —— Maven 启动脚本优先使用当前已设置的 `JAVA_HOME`。
- 因此正确姿势是：**先 `usejdk 8`，再跑 `mvn`**。此时 `mvn -v` 输出的 `Java version:` 应显示 zulu-8 的路径。
- 验证 Maven 实际使用的 JDK：

  ```bash
  usejdk 8
  mvn -v | grep -i java        # Java version: 1.8.0_xxx, vendor: Azul Systems...
  ```

## 5. 常见坑（本次实操踩过）

| 现象 | 原因 | 解决 |
|---|---|---|
| `brew install --cask xxx` 长时间无输出/被取消 | cask 安装 pkg 需要**交互式输入登录密码**，非交互终端（脚本、AI 会话）拿不到 TTY 会卡住 | 在自己的终端窗口手动执行；下载慢可提前配好代理，包会缓存在 `~/Library/Caches/Homebrew/downloads/`，重跑不重复下载 |
| 切换命令里 `echo ===` 报 `zsh:1: == not found` | zsh 会把词首 `=` 做命令路径展开（`=cmd` 语法） | 分隔符加引号，如 `echo "---"` |
| 老项目 `-source 1.7` 编译失败 | JDK 20+ 已移除 source 7 支持；JDK 17 只支持到 7 且伴随大量弃用警告 | 老项目一律 `usejdk 8` 后再构建；或给 IDE/Maven 单独指定 JDK 8 |
| 设了 `JAVA_HOME` 但 `java -version` 没变 | `PATH` 里 `/usr/bin` 在前，系统的 `java` 分发器不看 `JAVA_HOME` | 确保 `$JAVA_HOME/bin` 插到 `PATH` 最前（脚本已处理） |
| IDE 终端里版本和外面不一致 | IDE 自带终端可能继承 IDE 进程的 JDK 环境 | 在 IDE 终端里显式执行 `usejdk 8`，或在 IDE 设置里单独指定项目 JDK |

## 6. 快速回滚

```bash
# 卸载某个 cask JDK
brew uninstall --cask zulu@8

# 移除切换脚本挂载
# 编辑 ~/.zshrc 删除 "[ -f ~/bin/usejdk.zsh ] ..." 那一行（或直接恢复备份）
cp ~/.zshrc.bak.YYYYMMDD ~/.zshrc
rm ~/bin/usejdk.zsh
```
