# PyCharm 远程 SSH / 解释器 配置清理手册（独立复用 Runbook）

> 用途：当**项目目录改名/移动**、出现**重复的 SSH 连接（如 `ssh password (2)`）**、或**远程解释器缓存指向旧路径**导致连不上/全量扫描等 IDE 缓存 bug 时，彻底清空 PyCharm 缓存的 SSH 连接、Deployment 服务器与远程解释器，然后干净地重加一次。
>
> 本手册既给「**手动 GUI**」做法（最安全，推荐日常使用），也给「**脚本直接改配置文件**」做法（适合缓存已乱、GUI 删不干净时）。

---

## 0. 先搞懂三类配置分别存在哪（关键）

PyCharm 的远程开发由三块拼成，**改名/重复问题常常只在其中一块**：

| 配置 | 在哪 | 存什么 | 文件 |
|---|---|---|---|
| **SSH Configuration** | 全局（IDE 级，跨项目共享） | 连接本身：host / 端口 / 用户 / 认证 | `…/options/sshConfigs.xml` |
| **Deployment 服务器 (SFTP/WebServer)** | 全局 `webServers.xml` + 项目 `.idea/webServers.xml`/`deployment.xml` | 引用某个 SSH Configuration（`sshConfigId`），配映射路径 | 上述文件 |
| **远程 Python 解释器 (SSH SDK)** | 全局 `jdk.table.xml` | 解释器定义，内含 `ASSOCIATED_PROJECT_PATH`（**改名后会变旧**）、关联的 webServer id | `…/options/jdk.table.xml` |

- **重复的 `ssh password (N)`** 一般是全局 `webServers.xml` 里有多条 `webServer` 指向同一个 `sshConfigId`。
- **改名后的缓存 bug** 一般是 `jdk.table.xml` 里那个 SSH 解释器的 `ASSOCIATED_PROJECT_PATH` 仍指向旧目录名。
- 同一台主机只应保留**一条** SSH Configuration；多余引用会造成悬空（重开变空/连不上）。

### 配置目录位置（先确定你的 IDE 与版本）
- **macOS**：`~/Library/Application Support/JetBrains/<PyCharm版本>/options/`
  例：`~/Library/Application Support/JetBrains/PyCharm2026.1/options/`
  （可能同时存在多个版本目录，以**当前实际使用**的那个为准。）
- **Windows**：`%APPDATA%\JetBrains\<PyCharm版本>\options\`
- **Linux**：`~/.config/JetBrains/<PyCharm版本>/options/`

下文用变量表示，执行前先设好：
```bash
IDE="PyCharm2026.1"                       # 改成你的版本目录名
O="$HOME/Library/Application Support/JetBrains/$IDE/options"   # macOS 配置目录
```

---

## 1. 前置铁律：先彻底退出 PyCharm

> **PyCharm 运行时会把配置留在内存，退出时回写覆盖磁盘。** 不退出就改文件 = 白改。

```bash
# macOS：确认没有残留进程
pgrep -fl -i 'MacOS/pycharm' && echo "仍在运行，请先 Cmd+Q 完全退出！" || echo "✓ 已退出"
```
- 用 **Cmd+Q（或文件▸退出）** 关闭**所有** PyCharm 窗口；只关窗口不算。
- 上一步 `pgrep` 无输出后再继续。

---

## 2. 体检：先看清现状再动手（只读）

```bash
echo "== SSH 连接 ==" && cat "$O/sshConfigs.xml"
echo "== Deployment/SFTP 服务器(找重复) ==" && cat "$O/webServers.xml"
echo "== 解释器名(找指向旧目录的 SSH 那条) ==" && grep -n '<name value=' "$O/jdk.table.xml"
echo "== SSH 解释器的失效项目路径 ==" && grep -n 'ASSOCIATED_PROJECT_PATH' "$O/jdk.table.xml"
# 项目级(每个工程各自一份；改名后通常这里也有旧引用)
echo "== 容器根项目 ==" && cat <项目路径>/.idea/misc.xml ; cat <项目路径>/.idea/webServers.xml ; cat <项目路径>/.idea/deployment.xml
```
判断要点：
- `webServers.xml` 是否有多条 `webServer`（尤其名字带 `(2)`/`(3)`）；
- `jdk.table.xml` 里 SSH 解释器的 `ASSOCIATED_PROJECT_PATH` 是否是**已改名/已不存在**的旧目录；
- 各 `.idea/misc.xml` 的 `project-jdk-name="SSH (…)"`：大容器根项目**不应**绑定远程解释器（会整根扫描/更新）。

---

## 3. 方案 A：手动 GUI 清理（最安全，推荐）

在 PyCharm **开着**时操作（无需退出），逐项删：
1. **删多余的 Deployment/SFTP 服务器**：Settings ▸ Build, Execution, Deployment ▸ Deployment；左侧服务器列表选中重复项（如 `…password (2)`）▸ 减号删除（改名场景建议全删，稍后重加）。
2. **删 SSH 连接**：Settings ▸ Tools ▸ SSH Configurations；选中连接 ▸ 减号删除（改名后建议全删重加，只保留一条）。
3. **删远程解释器**：Settings ▸ Project ▸ Python Interpreter ▸ 齿轮 ▸ Show All ▸ 选中 SSH 解释器 ▸ 减号；多项目各自处理。
4. **大容器根项目**：把解释器设为 None/本地（不绑远程，避免整根扫描）。
5. 删完重启 PyCharm，按第 5 节重加。

> GUI 若删了仍复现（配置回写/悬空引用顽固），改用第 4 节脚本清底。

---

## 4. 方案 B：脚本直接清空配置文件（缓存顽固时）

> 务必先完成第 1 节（**PyCharm 完全退出**）。逐文件先备份。

### 4.1 备份
```bash
cp "$O/sshConfigs.xml" "$O/sshConfigs.xml.bak-$(date +%Y%m%d)"
cp "$O/webServers.xml" "$O/webServers.xml.bak-$(date +%Y%m%d)"
cp "$O/jdk.table.xml"  "$O/jdk.table.xml.bak-$(date +%Y%m%d)"
```

### 4.2 清空 SSH 连接（把整个 `sshConfigs.xml` 写成）
```xml
<application>
  <component name="SshConfigs">
    <configs />
  </component>
</application>
```

### 4.3 清空 Deployment/SFTP 服务器（含重复，把 `webServers.xml` 写成）
```xml
<application>
  <component name="WebServers">
    <option name="servers" />
  </component>
</application>
```

### 4.4 删除指定名字的 SSH 解释器（保留其它解释器）
```bash
IDE="$IDE" python3 - <<'PY'
import os, re
IDE = os.environ["IDE"]
p = os.path.expanduser(f"~/Library/Application Support/JetBrains/{IDE}/options/jdk.table.xml")
s = open(p).read()
# 删除 name 里含 "SSH (sftp://…/PaddleNLP/…)" 的那一整块 <jdk>
pat = re.compile(r'[ \t]*<jdk version="2">\s*<name value="SSH \([^"]*?PaddleNLP[^"]*\)".*?</jdk>\n?', re.S)
s2, n = pat.subn('', s)
print("将删除块数 =", n, "（期望 1；不为 1 请勿写入，先核对 name）")
if n == 1:
    open(p, 'w').write(s2)
PY
```
要点：
- `<name value="SSH …">` 要与你机器上实际名字匹配；不确定先 `grep '<name value=' "$O/jdk.table.xml"` 照抄。
- 只删目标块，**别动其它解释器**（如本地 conda）；用非贪婪 `.*?</jdk>` 只吃一块。
- 删成功后其它 `<jdk>`（如 play/spider）应原样保留。

### 4.5 清最近主机建议（可选）
```bash
# 若 <list/> 已空可跳过；有内容就删文件让 IDE 重建
mv "$O/sshRecentConnections.v2.xml"  "$O/sshRecentConnections.v2.xml.bak-$(date +%Y%m%d)" 2>/dev/null || true
mv "$O/sshRecentConnectionsHost.xml" "$O/sshRecentConnectionsHost.xml.bak-$(date +%Y%m%d)" 2>/dev/null || true
```

### 4.6 解绑大容器根项目的远程解释器（推荐）
把容器根 `.idea/misc.xml` 的 `project-jdk-name="SSH (…)"` 去掉（保留 `project-jdk-type`）：
```bash
sed -i '' -E 's/ project-jdk-name="[^"]*"//' <项目路径>/.idea/misc.xml
```

---

## 5. 重加（打开 PyCharm 后，一次干净的）
1. **SSH 连接**：Settings ▸ Tools ▸ SSH Configurations ▸ `+`：Host `192.168.10.20`、Port `22`、User `root`、认证方式按需 → Test Connection → OK。**只加这一条。**
2. **子项目远程解释器**：用**独立窗口打开改名后的子项目目录** ▸ Settings ▸ Python Interpreter ▸ `+` ▸ On SSH ▸ 选第 1 步连接 ▸ 填解释器路径 `/www/anaconda3/envs/PaddleNLP/bin/python` → 等解析完成。
3. **Deployment**：子项目 Settings ▸ … ▸ Deployment ▸ `+` 引用同一条 SSH 连接；`Mappings` 的**远程路径**填改名后的服务器目录（**别带尾部空格**）。生产/预览分离时各自配 `-dev` 目录与对应端口。
4. **大容器根项目保持不绑**远程解释器（None/本地），避免整根扫描。

---

## 6. 验证
```bash
echo "sshConfig 条数=$(grep -c '<sshConfig ' "$O/sshConfigs.xml")"    # 清底后 0；重加后应为 1
echo "webServer 条数=$(grep -c '<webServer ' "$O/webServers.xml")"    # 清底后 0；按需要
echo "残留 SSH 解释器=$(grep -c 'SSH (sftp' "$O/jdk.table.xml")"       # 清底后应为 0
grep -n 'ASSOCIATED_PROJECT_PATH' "$O/jdk.table.xml"                  # 不应再出现旧目录名
```
GUI 侧：SSH 列表**只有一条**、无 `(2)`；子项目解释器正常解析、不再整根扫描；Deployment 映射指向新目录且能上传。

---

## 7. 回滚（万一删错）
从同日备份还原（**先退出 PyCharm** 再覆盖回）：
```bash
D=20261113   # 改成你的备份日期后缀
cp "$O/sshConfigs.xml.bak-$D" "$O/sshConfigs.xml"
cp "$O/webServers.xml.bak-$D"  "$O/webServers.xml"
cp "$O/jdk.table.xml.bak-$D"   "$O/jdk.table.xml"
# misc.xml 同理从其 .bak 还原
```

---

## 8. 一键脚本（改名场景串起来直接用）
```bash
set -e
IDE="PyCharm2026.1"                                            # ← 改成你的版本
O="$HOME/Library/Application Support/JetBrains/$IDE/options"
PROJ_IDE="/Volumes/macDevelop/tgsxx-proj/Tgsxx-PaddlePaddle/.idea"   # ← 容器根 .idea
DSTAMP="$(date +%Y%m%d)"

pgrep -fl -i 'MacOS/pycharm' && { echo "请先彻底退出 PyCharm"; exit 1; }

for f in sshConfigs.xml webServers.xml jdk.table.xml; do cp "$O/$f" "$O/$f.bak-$DSTAMP"; done
cp "$PROJ_IDE/misc.xml" "$PROJ_IDE/misc.xml.bak-$DSTAMP"

printf '<application>\n  <component name="SshConfigs">\n    <configs />\n  </component>\n</application>\n' > "$O/sshConfigs.xml"
printf '<application>\n  <component name="WebServers">\n    <option name="servers" />\n  </component>\n</application>\n' > "$O/webServers.xml"

IDE="$IDE" python3 - <<'PY'
import os, re
IDE = os.environ["IDE"]
p = os.path.expanduser(f"~/Library/Application Support/JetBrains/{IDE}/options/jdk.table.xml")
s = open(p).read()
pat = re.compile(r'[ \t]*<jdk version="2">\s*<name value="SSH \([^"]*?PaddleNLP[^"]*\)".*?</jdk>\n?', re.S)
s2, n = pat.subn('', s)
assert n == 1, f"预期删除 1 块，实际 {n}（未写入）"
open(p, 'w').write(s2); print("已删除 SSH 解释器块 =", n)
PY

sed -i '' -E 's/ project-jdk-name="[^"]*"//' "$PROJ_IDE/misc.xml"
for f in sshRecentConnections.v2.xml sshRecentConnectionsHost.xml; do
  [ -f "$O/$f" ] && mv "$O/$f" "$O/$f.bak-$DSTAMP"
done

echo "清理完成。打开 PyCharm 按第 5 节重加：一条 SSH + 子项目解释器 + Deployment。"
```

---

## 9. 常见坑速记
- **不退出 PyCharm 就改文件** → 退出时被内存回写覆盖，等于没改。
- **同一主机多条 / `ssh password (N)`** → 只留一条；多余引用会悬空、重开变空。
- **改名后解释器 `ASSOCIATED_PROJECT_PATH` 指旧目录** → 删该解释器块重加。
- **Deployment 远程路径尾部空格** → 上传目标变成 `名字␣`，SFTP 报错/传错地方。
- **大容器根项目绑远程解释器** → 整根扫描（含非 Python 文件）；解释器只给具体子项目配。
- **想删一个 `<jdk>` 却误伤其它解释器** → 用非贪婪 `.*?</jdk>` 精确匹配目标 `name`，删前先 `grep '<name value='` 核对。
- **多个 IDE 版本目录** → 只清当前实际使用的那个；其余按需另清。