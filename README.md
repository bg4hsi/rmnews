# rmnews — reMarkable Paper Pro 新闻阅读器

在 reMarkable Paper Pro 上看新闻的 [AppLoad](https://github.com/asivery/rm-appload) 应用：中英文新闻源、离线阅读、彩色配图，英文文章长按查词翻译。

*A news reader for the reMarkable Paper Pro, built as an AppLoad app. English summary [below](#english).*

## 功能

- **中英文新闻源**
  - English：BBC World / Tech / Business、Guardian、NPR、Al Jazeera
  - 中文：BBC 中文（自动转简体）、德国之声、纽约时报中文网、爱范儿
- **离线优先**：点「更新」把当前语言所有来源的列表、全文和配图一次下载到设备上，之后阅读不联网。第一次打开时自动下载。超过 14 天的缓存自动清理。
- **长按翻译（英文文章）**
  - 长按单词：离线英汉词典（[ECDICT](https://github.com/skywind3000/ECDICT)，约 11 万词），显示音标、释义、考试标签，变形词同时给出原形（went → go）
  - 长按后拖动：选中短语，在线翻译
  - 「翻译整句」：翻译所在句子
- **中英对照**：英文文章逐段加中文译文，译文会缓存下来离线可看
- **手写笔（Marker）**：笔负责书写，手指负责翻页，两者互不干扰。文章页顶栏可以切换工具：
  - 查词：在单词或短语下面划一道（或圈起来）即可翻译
  - 荧光：划过的文字标黄，高亮锚定在文字上，调字号、开关对照都不会错位
  - 钢笔：自由书写，笔迹跟随所在段落
  - 橡皮：擦掉划过的笔迹和高亮（笔尾橡皮在系统层面和笔尖无法区分，所以做成工具）
  - 批注保存在本地，带批注的文章不会被自动清理
- **生词本**：查过的单词和短语自动收录，附带音标、释义、原句和出处，点一下可回到原文。同时生成 `~/.local/share/rmnews/vocab.tsv`，可直接导入 Anki
- **为 Gallery 3 彩色墨水屏优化**
  - 整页翻页，没有滚动和动画；点左侧往前翻、点右侧往后翻，也可以左右滑动
  - 正文纯黑、字重加粗一级；彩色只用于配图和来源标识
  - 用 xochitl 自带的 Content / UI / Mono 刷新模式分区刷新，每翻几页调用系统接口清一次残影

## 安装

需要：reMarkable Paper Pro（已在固件 3.29.0.153 上测试），已开启开发者模式，并能 SSH 登录。

1. **安装 xovi 和 AppLoad**（AppLoad 0.6.0 起支持 3.29）。参考 [rm-xovi-extensions](https://github.com/asivery/rm-xovi-extensions) 和 [rm-appload](https://github.com/asivery/rm-appload) 的说明，或者用 [vellum](https://github.com/vellum-dev/vellum)：`vellum add xovi appload`。然后在设备上运行一次 `xovi/rebuild_hashtable`。
2. **构建并部署**：在电脑上运行（需要 Python 3，并在 `~/.ssh/config` 里配置一个名为 `remarkable` 的主机，或者设置 `RM_HOST`）：

   ```bash
   ./build.sh deploy
   ```

   第一次运行会下载 ECDICT 并生成离线词典（约 11 MB）。脚本会把应用复制到 `/home/root/xovi/exthome/appload/rmnews/`，然后重启 xochitl。
3. 在侧边栏打开 AppLoad →「新闻 News」。

xovi 是临时挂载的，设备重启后需要重新运行 `/home/root/xovi/start`。推荐安装 [xovi-tripletap](https://github.com/rmitchellscott/xovi-tripletap)，连按三下电源键即可启动。

## 开发

- `app/ui/`：QML 前端，没有后端进程。网络请求和本地文件读写都用 QML 的 `XMLHttpRequest`（xovi 已开启 `QML_XHR_ALLOW_FILE_READ/WRITE`）。
- `tools/mkrcc.py`：纯 Python 的 Qt `.rcc` 打包器，不需要安装 Qt。
- `tools/build_dict.py`：把 ECDICT 的 CSV 切成按前缀加载的 JSON 分片。
- 桌面调试：可以用 PySide6 6.10（与设备相同的 Qt 版本）加载 `app/ui/main.qml`，并给 `net.asivery.ApploadUtils` 提供一个替身模块。
- 桌面运行：`tools/desktop/run.py WORKDIR STEPS_JSON` 用 PySide6 6.10 加载应用并按脚本模拟操作（包括笔事件）和截图。
- 设备调试：在设备上创建 `/home/root/.local/share/rmnews/debug` 后，应用会每 1.5 秒读取同目录下的 `cmd.js` 并执行，结果写入 `out.txt`；`tools/rmjs.sh` 封装了这个流程。**注意不要在应用里调用 `grabToImage`，会让 xochitl 崩溃。**
- 输入：在 xochitl 里，Marker 的事件以非合成鼠标事件（`Qt.MouseEventNotSynthesized`，约 470 Hz）到达应用，手指则是触摸合成的鼠标事件，应用靠这一点区分两者。

## English

rmnews is an [AppLoad](https://github.com/asivery/rm-appload) app for the reMarkable Paper Pro.

- **Sources**: English and Chinese news.
- **Offline first**: "Update" downloads feeds, full articles and pictures, so reading needs no network.
- **Pictures**: shown in color.
- **Long-press lookup** in English articles: offline ECDICT dictionary for single words; online translation for phrases and sentences.
- **Bilingual view**: paragraph-by-paragraph Chinese translation.
- **Marker support**: underline or circle words to translate; highlighter, pen and eraser tools; annotations are anchored to paragraphs and saved locally.
- **Vocabulary list**: every lookup is kept with its sentence and source; exported as `vocab.tsv` for Anki.
- **Tuned for the Gallery 3 color e-ink screen**: paging instead of scrolling, pure-black text, per-region refresh modes, periodic ghost removal.

**Install**: install xovi + AppLoad (0.6.0+ for firmware 3.29), then run `./build.sh deploy` against an SSH host called `remarkable`.

## 许可证 / License

MIT。第三方数据和组件见 [THIRD_PARTY.md](THIRD_PARTY.md)。新闻内容的版权归各自的出版方所有。
