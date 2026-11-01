# 安装与维护指南

本文以 macOS 为例（Linux 基本相同），设备是 reMarkable Paper Pro。

| 组件 | 测试过的版本 |
|---|---|
| 固件 | 3.29.0.153、3.29.1.0 |
| [xovi + qt-resource-rebuilder](https://github.com/asivery/rm-xovi-extensions) | pre-v20-08092026 |
| [AppLoad](https://github.com/asivery/rm-appload) | v0.6.0（从这个版本开始支持 3.29） |
| [xovi-tripletap](https://github.com/rmitchellscott/xovi-tripletap)（可选） | v1.1.1 |

> **风险说明**：xovi 会把扩展注入系统界面进程 xochitl，属于非官方修改。它是临时挂载的，重启设备就会回到原厂状态，系统分区不会被改动；xovi-tripletap 例外，它会往系统分区写入一个服务。操作前请备份重要笔记。

---

## 1. 准备：开发者模式和 SSH

### 1.1 开启开发者模式

设备上打开「设置 → 通用 → 软件 → 高级 → 开发者模式」。开启时设备会**恢复出厂设置**，请先确认笔记都已同步到云端。

### 1.2 找到 root 密码

用 USB-C 线连接电脑后，设备的地址是 `10.11.99.1`。root 密码在「设置 → 通用 → 关于 → 版权与许可」页面，在「GPLv3 合规」那段文字的最底部。

输入密码时请注意：

- 密码区分大小写，容易混淆的字符有 `l`/`I`/`1`、`0`/`O`、`Z`/`2`、`S`/`5`。
- 先把电脑输入法切到英文，中文输入法可能会改动你输入的字符。

### 1.3 配置免密登录

在电脑上依次运行：

```bash
ssh-keygen -t ed25519 -f ~/.ssh/remarkable -N ""
```

```bash
ssh-copy-id -i ~/.ssh/remarkable.pub root@10.11.99.1
```

运行第二条时，看到 `root@10.11.99.1's password:` 提示后再输入密码。最后一行显示 `Number of key(s) added: 1` 就表示成功了。

然后在 `~/.ssh/config` 里加一个名为 `remarkable` 的主机，本项目的脚本默认都用这个名字：

```bash
printf '\nHost remarkable\n  HostName 10.11.99.1\n  User root\n  IdentityFile ~/.ssh/remarkable\n' >> ~/.ssh/config
```

用 `ssh remarkable` 测试一下，能直接登录、不再要求输入密码就说明配置好了。

> 在 macOS 上，如果某个终端程序报 `No route to host`，但其他终端能连上，通常是那个程序没有「本地网络」权限。可以在「系统设置 → 隐私与安全性 → 本地网络」里打开，或者换用系统自带的「终端」App。

---

## 2. 安装 xovi 和 AppLoad

可以用 [vellum](https://github.com/vellum-dev/vellum) 安装：`vellum add xovi appload`。下面是手动安装的步骤。

### 2.1 下载并复制到设备

```bash
curl -LO https://github.com/asivery/rm-xovi-extensions/releases/download/pre-v20-08092026/xovi-aarch64.tar.gz
```

```bash
curl -LO https://github.com/asivery/rm-appload/releases/download/v0.6.0/appload-aarch64.tar.gz
```

```bash
scp xovi-aarch64.tar.gz appload-aarch64.tar.gz remarkable:/tmp/
```

### 2.2 在设备上解压

```bash
ssh remarkable 'tar xzf /tmp/xovi-aarch64.tar.gz -C /home/root && mkdir -p /tmp/al && tar xzf /tmp/appload-aarch64.tar.gz -C /tmp/al && cp /tmp/al/appload.so /home/root/xovi/extensions.d/ && mkdir -p /home/root/shims /home/root/xovi/exthome/appload && cp /tmp/al/shims/* /home/root/shims/'
```

### 2.3 生成哈希表并启动

xovi 修改界面时需要一份和当前固件对应的哈希表。下面这条命令运行时屏幕会重启一次，出现锁屏的话请解锁：

```bash
ssh remarkable 'echo | /home/root/xovi/rebuild_hashtable'
```

看到 `Hashtable rebuilt.` 后启动 xovi：

```bash
ssh remarkable /home/root/xovi/start
```

大约 10 秒后，侧边栏会出现 AppLoad 入口。

---

## 3. 安装 rmnews

需要 Python 3，不需要安装 Qt。

```bash
git clone https://github.com/bg4hsi/rmnews.git
```

```bash
cd rmnews && ./build.sh deploy
```

`build.sh deploy` 会做这些事：

1. 用纯 Python 把 `app/ui/` 打包成 `resources.rcc`。
2. 第一次运行时，下载 [ECDICT](https://github.com/skywind3000/ECDICT)（约 63 MB），生成约 11 MB 的离线词典分片，放在 `build/dict/`。
3. 把应用复制到设备的 `/home/root/xovi/exthome/appload/rmnews/`。如果设备上还没有词典，会一并上传。
4. 安装缓存清理脚本 `/home/root/xovi/scripts/pre-start/rmnews-cleanup.sh`，xovi 每次启动时会删除 14 天前的旧文章，有批注的文章会保留。
5. 重启 xochitl，让新版本生效。

完成后在侧边栏打开 AppLoad →「新闻 News」。第一次打开会自动下载当前语言所有来源的新闻，大约需要 1～2 分钟。

如果 SSH 主机不叫 `remarkable`，可以这样指定：`RM_HOST=root@10.11.99.1 ./build.sh deploy`。

---

## 4. 重启后自动恢复（推荐：xovi-tripletap）

xovi 是临时挂载的，**设备重启后 AppLoad 入口会消失**，但所有文件都还在。恢复方式有两种：

- **手动恢复**：运行 `ssh remarkable /home/root/xovi/start`。
- **连按三下电源键**：安装 [xovi-tripletap](https://github.com/rmitchellscott/xovi-tripletap) 后，在设备上连按三下电源键（2 秒内按完）即可启动 xovi，不需要电脑。

安装 xovi-tripletap 前，建议先读一遍它的 `install.sh`、`enable.sh` 和 `main.sh`。在 Paper Pro 上，它会把根分区重新挂载为可写，并往 `/etc/systemd/system/` 写入一个服务。

```bash
curl -LO https://raw.githubusercontent.com/rmitchellscott/xovi-tripletap/v1.1.1/install.sh
```

```bash
scp install.sh remarkable:/tmp/tripletap-install.sh && ssh remarkable 'bash /tmp/tripletap-install.sh'
```

安装时 `/etc` 的 overlay 会被卸载，xovi 当前的挂载配置也随之失效，所以装完后再运行一次 `ssh remarkable /home/root/xovi/start`。

如果按三下触发不了，可以把间隔放宽：修改 `/home/root/xovi-tripletap/config` 里的 `TIME_THRESHOLD=3`，然后运行 `systemctl restart xovi-tripletap`。

---

## 5. 固件更新之后

固件更新会替换系统分区，带来两个影响：

- xovi-tripletap 服务被清除
- xovi 的哈希表和新版 xochitl 对不上

**`/home/root` 下的内容都不受影响**，包括 xovi、AppLoad、rmnews、已下载的新闻、批注和生词本。

### 5.1 一键恢复

设备连着 USB 并且已唤醒时，在本仓库目录里运行：

```bash
tools/after-update.sh
```

这个脚本依次执行：

1. 重建哈希表
2. 重新启用 xovi-tripletap（如果装过）
3. 启动 xovi
4. 检查 AppLoad 是否加载成功、xochitl 是否稳定

最后显示 `OK` 就表示恢复成功了。

### 5.2 手动恢复

```bash
ssh remarkable 'echo | /home/root/xovi/rebuild_hashtable'
```

```bash
ssh remarkable /home/root/xovi-tripletap/enable.sh
```

```bash
ssh remarkable /home/root/xovi/start
```

### 5.3 大版本更新（比如 3.29 → 3.30）

先到 [rm-appload](https://github.com/asivery/rm-appload/releases) 和 [rm-xovi-extensions](https://github.com/asivery/rm-xovi-extensions/releases) 确认已经支持新固件，再更新设备。如果已经更新了但还没有支持，就先别启动 xovi，用原厂系统等新版本发布。小版本更新（比如 3.29.0 → 3.29.1）一般可以直接按 5.1 恢复。

---

## 6. 常见问题

**重启后找不到应用**
连按三下电源键，或者运行 `ssh remarkable /home/root/xovi/start`。

**固件更新后找不到应用**
见第 5 节。

**`ssh: connect to host 10.11.99.1 ... timed out`**
设备休眠时 USB 网络会断开。按一下电源键唤醒设备，确认 USB 线插紧后再试。

**xovi 启动后界面反复重启，或者卡住**
直接重启设备（长按电源键），就会回到原厂系统。然后检查 AppLoad 是否支持当前固件。

**新闻加载失败**
应用需要能访问 BBC、Guardian 等境外网站。设备通过 Wi-Fi 上网，请确认网络能访问这些站点。

**数据位置**

| 路径 | 内容 |
|---|---|
| `/home/root/xovi/exthome/appload/rmnews/` | 应用和离线词典 |
| `/home/root/.local/share/rmnews/state.json` | 设置（语言、来源、字号等） |
| `/home/root/.local/share/rmnews/cache/` | 新闻列表、正文、配图、批注 |
| `/home/root/.local/share/rmnews/vocab.json` / `vocab.tsv` | 生词本；`vocab.tsv` 可以导入 Anki，用 `scp remarkable:/home/root/.local/share/rmnews/vocab.tsv .` 取到电脑上 |

**卸载**

```bash
ssh remarkable 'rm -rf /home/root/xovi/exthome/appload/rmnews /home/root/.local/share/rmnews /home/root/xovi/scripts/pre-start/rmnews-cleanup.sh'
```

如果要连 xovi-tripletap 一起卸载，再运行 `ssh remarkable /home/root/xovi-tripletap/uninstall.sh`。xovi 本身只要不启动，重启设备后就不会生效。

---

## 7. 开发者调试

- **在桌面上跑**：`tools/desktop/run.py WORKDIR STEPS_JSON` 用 PySide6 6.10.3（和设备上的 Qt 版本相同）加载应用，按脚本模拟手指、笔和悬停事件并截图。加上 `QT_QUICK_BACKEND=software` 就和 xochitl 一样走软件渲染。
- **在设备上调试**：先运行 `ssh remarkable touch /home/root/.local/share/rmnews/debug`，再重新打开应用，就可以用 `tools/rmjs.sh 'return root.items.length'` 在运行中的应用里执行 JavaScript。`root.trace` 里记录了最近的输入事件。调试完删掉这个标记文件。
- **已知限制**
  - 在 xochitl 里调用 `grabToImage` 会导致 xochitl 崩溃（日志里是 `Layers are not supported`）。
  - QtQuick.Shapes 画的路径在 xochitl 的软件渲染下显示不出来，所以笔迹用旋转的矩形拼成。
  - Marker 的笔尾橡皮和笔尖在应用层面无法区分。
  - 手掌压在屏幕上时，xochitl 不会刷新 Pen 模式的区域，所以书写时用 Animation 模式。
