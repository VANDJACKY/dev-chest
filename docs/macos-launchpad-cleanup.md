# macOS 启动台残留图标清理与重置

适用：卸载软件后启动台（Launchpad）残留删不掉的图标；定期系统维护。
系统：macOS 15.x 验证通过（Sequoia）。命令默认在「终端」以普通用户执行，需提权时加 `sudo`。

## 0. 快速版（90% 的残留图标都是空壳注册）

```bash
# 1. 找出 LaunchServices 里注册的可疑路径（把 epic 换成残留软件关键词）
LSR=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
"$LSR" -dump | grep -iE "path:.*epic"

# 2. 确认路径指向的是残留/空壳 bundle 后注销它
"$LSR" -u "/完整/路径/xxx.app"

# 3. 重启 Dock 刷新启动台
pkill Dock
```

## 1. 排查（只读，安全）

```bash
# 定位启动台数据库（路径中的随机串因机器而异，用变量自动获取）
DB=$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
ls -lh "$DB"

# 查启动台数据库里的残留条目（item_id/bundleid/分类）
sqlite3 "$DB" "select item_id, title, bundleid, category_id from apps where title like '%epic%' or title like '%unreal%'"

# 查 LaunchServices 注册表里的所有相关路径（重点看非 /Applications 的路径，如 /Users/Shared、更新暂存目录）
"$LSR" -dump | grep -iE "path:.*(epic|unreal)" | sort -u

# 全盘搜残留 bundle（Spotlight）
mdfind "kMDItemDisplayName == 'Epic*'c"

# 逐个确认嫌疑 bundle 是不是空壳：Contents/MacOS 为空 = 不可执行 = 残留
ls -la "xxx.app/Contents/MacOS" "xxx.app/Contents/_CodeSignature"
du -sh "xxx.app"

# 盘点用户目录残留（把关键词换成目标软件）
cd ~ && find Library -maxdepth 3 \( -iname "*epic*" -o -iname "*unreal*" \) 2>/dev/null
du -sh "Library/Application Support/Epic" 2>/dev/null

# 常见残留位置清单
ls -d \
  "Library/Application Support/<软件名>" \
  "Library/Preferences/com.<厂商>.<软件>.plist" \
  "Library/Caches/com.<厂商>.<软件>" \
  "Library/Logs/<软件名>" \
  "Library/HTTPStorages/com.<厂商>.<软件>" \
  "Library/Saved Application State/com.<厂商>.<软件>.savedState" \
  "Library/Containers/com.<厂商>.<软件>" \
  "Library/Group Containers/group/com.<厂商>.*" \
  "Library/LaunchAgents/*<软件>*" \
  "Library/Services/*<软件>*.app" \
  "/Users/Shared/<厂商目录>" 2>/dev/null
```

## 2. 清理（写操作，先核实再删）

> ⚠️ 删除前先确认目录里是缓存/配置而不是你的作品（如项目、文档）。
> 卸载残留的大头通常在 `~/Library/Application Support/<厂商>`，动辄几百 MB 缓存。

```bash
# 注销空壳（必须在删除 bundle 之前执行）
"$LSR" -u "/完整/路径/xxx.app"

# 删除共享目录残留（可能需要 sudo）
sudo rm -rf "/Users/Shared/<厂商目录>"

# 删除用户目录残留（按排查结果逐项列全再删）
cd ~
rm -rf "Library/Application Support/<厂商>" \
       "Library/Preferences/com.<厂商>.*.plist" \
       "Library/Logs/<软件名>" \
       "Library/HTTPStorages/com.<厂商>.<软件>"* \
       "Library/Saved Application State/com.<厂商>.<软件>.savedState" \
       "Library/Services/<残留>.app"

# 复查是否清干净
find Library -maxdepth 4 \( -iname "*epic*" -o -iname "*unreal*" \) 2>/dev/null
```

## 3. 重置启动台（方案 B，核弹级）

> ⚠️ 会丢失全部自定义分组和布局，恢复默认。仅在精准清理无效、残留图标仍显示时使用。
> Sequoia 上启动台数据由 Dock 进程渲染，数据库没有 icons 表，需清 apps/categories/groups/items/image_cache。

```bash
DB=$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db

# 1. 备份（放在不会被启动台索引的位置）
mkdir -p ~/launchpad-backup
cp "$DB" ~/launchpad-backup/db.$(date +%Y%m%d-%H%M%S)

# 2. 看表结构（不同系统版本表名可能不同，先看再删）
sqlite3 "$DB" ".tables"

# 3. 清空并压缩
sqlite3 "$DB" "DELETE FROM apps; DELETE FROM categories; DELETE FROM groups; DELETE FROM items; DELETE FROM image_cache; VACUUM;"

# 4. 重启 Dock（沙盒下 pkill 可能被拦，可改用 killall；实在不行注销重登）
pkill Dock || killall Dock

# 5. 验证：等待数秒后检查已按 LaunchServices 重建，且残留为 0
sleep 5
sqlite3 "$DB" "select count(*) from apps"
sqlite3 "$DB" "select count(*) from apps where bundleid like '%epic%'"
```

回滚（如需）：Dock 运行时直接覆盖 db 再 `killall Dock` 即可。

```bash
cp ~/launchpad-backup/db.<时间戳> "$DB" && killall Dock
```

## 4. 附：dmg 安装包归档习惯（可选）

下载目录的 dmg 定期按类别移动到软件库；完全重名的用新日期文件覆盖旧文件，不同版本并存保留：

```bash
# 只列出下载目录的 dmg（按时间排序），逐个归类
find ~/Downloads -maxdepth 1 -name "*.dmg" -print0 | xargs -0 ls -lT

# 移动
mv ~/Downloads/xxx.dmg /路径/SOFTWARE/<分类>/

# 同名覆盖（新替旧）
mv -f ~/Downloads/xxx.dmg "/路径/SOFTWARE/<分类>/xxx.dmg"
```

## 注意事项

- `lsregister -u` 只对 LaunchServices 生效，不删文件；文件残留要单独 `rm`。
- 删除 `/Users/Shared`、系统目录需要 `sudo`；删除前务必用 `du -sh` / `ls` 确认内容。
- `pkill Dock` 会导致 Dock 闪断重建，不影响数据；若被沙盒拦截报 `Operation not permitted`，Dock 通常也会自行重建，可用 `ps -p $(pgrep -x Dock) -o lstart` 验证是否新进程。
- 启动台只显示 LaunchServices 注册过的 app；注册路径指向空壳/已删目录时就是「长按删不掉」的成因。
