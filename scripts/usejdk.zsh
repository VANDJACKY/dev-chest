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
