import QtQuick 2.15
import net.asivery.ApploadUtils
import "News.js" as News

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"

    signal close
    function unloading() { saveState(); }

    // Scale everything from the Paper Pro's 1620 px portrait width.
    property real u: Math.max(0.35, width / 1620)

    property string lang: "en"
    property var srcIndex: ({ en: 0, zh: 0 })
    property var feeds: ({})            // source key -> { updated, items }
    property var items: []
    property int listPage: 0
    property string listStatus: ""
    property int fontPx: 42
    property bool bilingual: false

    property bool syncing: false
    property string syncStatus: ""

    // Current article: { item, paras, trans, summaryOnly, image } or null.
    property var article: null
    property string articleStatus: ""
    property int articleToken: 0

    readonly property var sources: News.SOURCES[lang]
    readonly property var currentSource: sources[Math.min(srcIndex[lang] || 0, sources.length - 1)]
    readonly property color accent: article ? sourceColor(article.item.source) : currentSource.color
    readonly property bool articleIsEnglish: article !== null && !News.hasCjk(article.item.title + (article.paras[0] || ""))
    readonly property string sansFamily: "Noto Sans SC"
    readonly property string serifFamily: lang === "en" ? "EB Garamond" : "Noto Serif SC"

    function sourceColor(name) {
        var all = News.SOURCES.en.concat(News.SOURCES.zh);
        for (var i = 0; i < all.length; i++) if (all[i].name === name) return all[i].color;
        return "black";
    }

    Component.onCompleted: {
        // The desktop test harness relocates data files via a context property.
        if (typeof rmnewsDataDir !== "undefined") News.dataDir = rmnewsDataDir;
        if (typeof rmnewsDictBase !== "undefined") News.dictBase = rmnewsDictBase;
        News.get(News.dataDir + "debug", function (err) { debugEnabled = !err; });
        News.loadState(function (s) {
            if (stateLoaded) return;
            stateLoaded = true;
            if (s.lang === "en" || s.lang === "zh") lang = s.lang;
            if (s.srcIndex) srcIndex = s.srcIndex;
            if (s.fontPx) fontPx = s.fontPx;
            if (s.bilingual !== undefined) bilingual = s.bilingual;
            showSource();
        });
    }

    // If reading the state file never answers, start with defaults.
    property bool stateLoaded: false
    Timer {
        interval: 1500
        running: !root.stateLoaded
        onTriggered: { root.stateLoaded = true; root.showSource(); }
    }

    function saveState() {
        News.saveState({ lang: lang, srcIndex: srcIndex, fontPx: fontPx, bilingual: bilingual });
    }

    // ------------------------------------------------------------ e-paper

    // AppLoad turns DisplayMethodArea into xochitl's Epaper.ScreenModeItem. Its enum is
    // mapped by index onto [Pen, Mono, Animation, UI, Content], so use these names instead.
    readonly property int modeMono: 1       // fast black & white; interactive feedback
    readonly property int modeUi: 3         // menus, buttons, popups
    readonly property int modeContent: 4    // full quality incl. color; what xochitl uses for documents

    // Gallery 3 leaves faint ghosts after partial updates; clear them now and then.
    property int ghostEvery: 8
    property int turnsSinceClear: 0
    property var framebuffer: null

    function clearGhosting() {
        turnsSinceClear = 0;
        if (framebuffer === null) {
            try {
                // EPFramebuffer lives in com.remarkable, which only exists inside xochitl.
                framebuffer = Qt.createQmlObject(
                    'import QtQuick; import com.remarkable; QtObject { function clear() { EPFramebuffer.scheduleGhostRemoval(); } }',
                    root, "ghost");
            } catch (e) {
                framebuffer = false;
            }
        }
        if (framebuffer) framebuffer.clear();
    }

    // ------------------------------------------------------------ debug bridge
    // Only active when the flag file exists on the tablet: lets a developer run JS inside
    // the app over SSH (write cmd.js, read out.txt).

    readonly property string dataDir: News.dataDir
    property bool debugEnabled: false

    Timer {
        interval: 1500
        repeat: true
        running: root.debugEnabled
        onTriggered: News.get(root.dataDir + "cmd.js", function (err, code) {
            if (err || !code || !code.trim()) return;
            News.put(root.dataDir + "cmd.js", " ");
            var out;
            try {
                out = String(new Function("root", "News", "body", "popup", "Qt", code)(root, News, body, popup, Qt));
            } catch (e) {
                out = "ERROR " + e + "\n" + (e.stack || "");
            }
            News.put(root.dataDir + "out.txt", out);
        })
    }

    // ------------------------------------------------------------ feeds (offline first)

    function setLang(l) {
        if (l === lang) return;
        lang = l;
        saveState();
        showSource();
    }

    function setSource(i) {
        var s = Object.assign({}, srcIndex);
        s[lang] = i;
        srcIndex = s;
        saveState();
        showSource();
    }

    function setFeed(src, data) {
        var f = Object.assign({}, feeds);
        f[src.key] = data;
        feeds = f;
    }

    // Show the selected source from memory or disk; only touches the network on first run.
    function showSource() {
        var src = currentSource;
        listPage = 0;
        if (feeds[src.key]) {
            items = feeds[src.key].items;
            listStatus = "";
            return;
        }
        items = [];
        listStatus = "";
        News.loadFeedCache(src, function (data) {
            if (src !== currentSource) return;
            if (data && data.items.length) {
                setFeed(src, data);
                items = data.items;
            } else {
                listStatus = lang === "zh" ? "本地还没有新闻，正在下载 …" : "Nothing saved yet, downloading …";
                update();
            }
        });
    }

    // Download every source of the current language (feeds, full text, pictures) for offline reading.
    function update() {
        if (syncing) return;
        syncing = true;
        var l = lang;
        var list = sources.slice();
        var cur = currentSource;
        list.sort(function (a, b) { return (a === cur ? -1 : 0) - (b === cur ? -1 : 0); });
        var i = 0;
        function nextSource() {
            if (i >= list.length) {
                syncing = false;
                syncStatus = "";
                clearGhosting();
                return;
            }
            var s = list[i++];
            syncStatus = s.name;
            News.syncSource(s, function (done, total) {
                syncStatus = s.name + " " + done + "/" + total;
            }, function (err, data) {
                if (data) setFeed(s, data);
                if (s === currentSource) {
                    if (data) { items = data.items; listStatus = ""; }
                    else if (!items.length) listStatus = (l === "zh" ? "下载失败：" : "Download failed: ") + err;
                }
                nextSource();
            });
        }
        nextSource();
    }

    readonly property var currentFeed: feeds[currentSource.key] || null

    function dateLine() {
        var d = new Date();
        var s;
        if (lang === "zh") {
            s = (d.getMonth() + 1) + "月" + d.getDate() + "日 星期" + "日一二三四五六"[d.getDay()];
        } else {
            s = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][d.getDay()] + ", " +
                d.getDate() + " " + ["January", "February", "March", "April", "May", "June", "July",
                                     "August", "September", "October", "November", "December"][d.getMonth()];
        }
        if (syncing) return s + (lang === "zh" ? "  ·  正在更新 " : "  ·  Updating ") + syncStatus;
        if (currentFeed) return s + (lang === "zh" ? "  ·  " + News.timeAgo(currentFeed.updated, "zh") + "更新"
                                                    : "  ·  updated " + News.timeAgo(currentFeed.updated, "en"));
        return s;
    }

    readonly property int perPage: Math.max(3, Math.floor(listArea.height / (330 * u)))
    readonly property int listPages: Math.max(1, Math.ceil(items.length / perPage))

    // ------------------------------------------------------------ article

    function openArticle(item) {
        var token = ++articleToken;
        popup.hide();
        article = { item: item, paras: [], trans: [], summaryOnly: false, image: "" };
        articleStatus = lang === "zh" ? "正在打开 …" : "Opening …";
        body.text = "";
        pageIdx = 0;
        News.loadArticleCache(item.id, function (art) {
            if (token !== articleToken) return;
            if (art) return showArticle(item, art);
            // Not downloaded yet (e.g. opened during an update): fetch it now and keep it.
            articleStatus = lang === "zh" ? "正在下载正文 …" : "Downloading article …";
            News.fetchArticle(item, function (err, a) {
                if (token !== articleToken) return;
                if (!a || !a.paras.length) {
                    articleStatus = (lang === "zh" ? "无法加载（离线？）" : "Could not load (offline?)");
                    return;
                }
                var saved = { paras: a.paras, summaryOnly: a.summaryOnly, trans: [] };
                News.saveArticleCache(item.id, saved);
                item.cached = true;
                showArticle(item, saved);
                if (!item.hasImage) News.downloadImage(a.image, item.id, function (ok) {
                    if (!ok || token !== articleToken) return;
                    item.hasImage = true;
                    article.image = News.imageUrl(item.id);
                    renderArticle();
                });
            });
        });
    }

    function showArticle(item, art) {
        article = { item: item, paras: art.paras, trans: art.trans || [], summaryOnly: art.summaryOnly,
                    image: item.hasImage ? News.imageUrl(item.id) : "" };
        articleStatus = "";
        pageIdx = 0;
        renderArticle();
        clearGhosting();
        if (bilingual && articleIsEnglish) translateAll();
    }

    function closeArticle() {
        articleToken++;
        article = null;
        popup.hide();
        body.text = "";
        clearGhosting();
    }

    function renderArticle() {
        if (!article) return;
        var a = article;
        // Text stays pure black (Gallery 3 dithers greys into speckles); color is used for
        // accents and pictures only.
        var col = String(accent);
        var small = "font-family:'Noto Sans SC'; font-weight:500; font-size:" + Math.round(fontPx * 0.68 * u) + "px;";
        var zhStyle = "font-family:'Noto Serif SC'; font-weight:500; font-size:" + Math.round(fontPx * 0.86 * u) +
                      "px; margin-left:" + Math.round(28 * u) + "px; line-height:135%;";
        var h = "<p style=\"font-family:'Noto Sans SC'; font-weight:700; font-size:" + Math.round(fontPx * 0.72 * u) +
                "px; color:" + col + ";\">" + News.escapeHtml(a.item.source.toUpperCase()) + "</p>";
        h += "<h1 style=\"font-family:'" + serifFamily + "'; font-weight:700; font-size:" +
             Math.round(fontPx * 1.45 * u) + "px; line-height:115%;\">" + News.escapeHtml(a.item.title) + "</h1>";
        if (a.item.time)
            h += "<p style=\"" + small + "\">" + News.escapeHtml(News.timeAgo(a.item.time, lang)) + "</p>";
        if (a.image)
            h += "<p><img src=\"" + a.image + "\" width=\"" + Math.floor(bodyArea.width) + "\"></p>";
        if (a.summaryOnly)
            h += "<p style=\"" + small + "\">（原网站未提供全文，以下为摘要）</p>";
        for (var i = 0; i < a.paras.length; i++) {
            h += "<p style=\"line-height:140%; font-weight:500;\">" + News.escapeHtml(a.paras[i]) + "</p>";
            if (bilingual && a.trans[i])
                h += "<p style=\"" + zhStyle + "\">" + News.escapeHtml(a.trans[i]) + "</p>";
        }
        var ratio = pageStarts.length > 1 ? pageStarts[pageIdx] / Math.max(1, body.contentHeight) : 0;
        body.text = h;
        restoreRatio = ratio;
        Qt.callLater(computePages);
    }

    function translateAll() {
        if (!article || !articleIsEnglish) return;
        var a = article;
        var token = articleToken;
        var todo = [];
        for (var i = 0; i < a.paras.length; i++) if (!a.trans[i]) todo.push(i);
        if (!todo.length) { renderArticle(); return; }
        articleStatus = "翻译中 0/" + todo.length;
        var next = 0, done = 0;
        function worker() {
            if (next >= todo.length) return;
            var idx = todo[next++];
            News.translate(a.paras[idx], "en", "zh-CN", function (err, out) {
                if (token !== articleToken) return;
                a.trans[idx] = out || "";
                done++;
                articleStatus = done < todo.length ? "翻译中 " + done + "/" + todo.length : "";
                if (done === todo.length) {
                    // Keep the translation so the bilingual view works offline next time.
                    News.saveArticleCache(a.item.id, { paras: a.paras, summaryOnly: a.summaryOnly, trans: a.trans });
                    renderArticle();
                } else worker();
            });
        }
        for (var w = 0; w < 4; w++) worker();
    }

    function toggleBilingual() {
        bilingual = !bilingual;
        saveState();
        if (bilingual) translateAll(); else renderArticle();
    }

    function setFont(delta) {
        fontPx = Math.max(28, Math.min(72, fontPx + delta));
        saveState();
        renderArticle();
    }

    // ------------------------------------------------------------ pagination

    property var pageStarts: [0]
    property int pageIdx: 0
    property real restoreRatio: 0

    function computePages() {
        var H = bodyArea.height;
        var total = body.contentHeight;
        var starts = [0];
        while (H > 0 && starts.length < 500) {
            var s = starts[starts.length - 1];
            var lim = s + H;
            if (lim >= total) break;
            var r = body.positionToRectangle(body.positionAt(body.width / 2, lim));
            var next = (r.y < lim && r.y + r.height > lim) ? r.y : lim;
            if (next <= s + 1) next = lim;
            starts.push(next);
        }
        pageStarts = starts;
        if (restoreRatio > 0) {
            var target = restoreRatio * total;
            var best = 0;
            for (var i = 0; i < starts.length; i++) if (starts[i] <= target + 1) best = i;
            pageIdx = best;
            restoreRatio = 0;
        }
        pageIdx = Math.min(pageIdx, starts.length - 1);
    }

    function turn(delta) {
        popup.hide();
        var before = article ? pageIdx : listPage;
        if (article) {
            pageIdx = Math.max(0, Math.min(pageStarts.length - 1, pageIdx + delta));
        } else {
            listPage = Math.max(0, Math.min(listPages - 1, listPage + delta));
        }
        if ((article ? pageIdx : listPage) !== before && ++turnsSinceClear >= ghostEvery)
            Qt.callLater(clearGhosting);
    }

    // ------------------------------------------------------------ word lookup

    function isWordChar(c) { return /[A-Za-z'’\-]/.test(c); }

    function wordAt(pos) {
        var from = Math.max(0, pos - 40);
        var t = body.getText(from, Math.min(body.length, pos + 40));
        var i = pos - from;
        if (!isWordChar(t.charAt(i)) && isWordChar(t.charAt(i - 1))) i--;
        if (!isWordChar(t.charAt(i))) return null;
        var a = i, b = i + 1;
        while (a > 0 && isWordChar(t.charAt(a - 1))) a--;
        while (b < t.length && isWordChar(t.charAt(b))) b++;
        while (a < b && /['’\-]/.test(t.charAt(a))) a++;
        while (b > a && /['’\-]/.test(t.charAt(b - 1))) b--;
        if (a >= b) return null;
        return { start: from + a, end: from + b, text: t.slice(a, b) };
    }

    function sentenceAround(a, b) {
        var from = Math.max(0, a - 1200);
        var t = body.getText(from, Math.min(body.length, b + 1200));
        var s = a - from, e = b - from;
        while (s > 0) {
            var c = t.charAt(s - 1);
            if (c === "\u2029" || c === "\n") break;
            if (/[.!?]/.test(c) && /\s/.test(t.charAt(s)) && !/\b(Mr|Mrs|Ms|Dr|St|U\.S|U\.K)$/.test(t.slice(Math.max(0, s - 5), s - 1))) break;
            s--;
        }
        while (e < t.length) {
            var d = t.charAt(e);
            if (d === "\u2029" || d === "\n") break;
            e++;
            if (/[.!?]/.test(d) && (e >= t.length || /[\s"”’']/.test(t.charAt(e)))) {
                while (e < t.length && /["”’']/.test(t.charAt(e))) e++;
                break;
            }
        }
        return t.slice(s, e).trim();
    }

    // ------------------------------------------------------------ layout: masthead

    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: (root.article ? 130 : 210) * u

        DisplayMethodArea { anchors.fill: parent; displayMethod: root.modeContent }

        // Front page: paper name + date on the left, controls on the right.
        Column {
            visible: !root.article
            anchors { left: parent.left; leftMargin: 56 * u; verticalCenter: parent.verticalCenter; verticalCenterOffset: -4 * u }
            spacing: 6 * u
            Text {
                text: root.lang === "zh" ? "今日新闻" : "The Daily Brief"
                font.pixelSize: 76 * root.u
                font.family: root.lang === "zh" ? "Noto Serif SC" : "EB Garamond"
                font.weight: Font.Bold
            }
            Text {
                text: root.dateLine()
                font.pixelSize: 28 * root.u
                font.family: root.sansFamily
                font.weight: Font.Medium
            }
        }

        Row {
            visible: !root.article
            anchors { right: parent.right; rightMargin: 28 * u; verticalCenter: parent.verticalCenter }
            spacing: 26 * u

            // EN | 中文 segmented switch
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 260 * root.u; height: 84 * root.u
                radius: 14 * root.u
                border.width: 3 * root.u
                border.color: "black"
                Row {
                    anchors.fill: parent
                    anchors.margins: 6 * root.u
                    Repeater {
                        model: [["en", "EN"], ["zh", "中文"]]
                        Rectangle {
                            width: parent.width / 2; height: parent.height
                            radius: 9 * root.u
                            color: root.lang === modelData[0] ? "black" : "white"
                            Text {
                                anchors.centerIn: parent
                                text: modelData[1]
                                color: root.lang === modelData[0] ? "white" : "black"
                                font.pixelSize: 32 * root.u
                                font.family: root.sansFamily
                                font.weight: Font.DemiBold
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.setLang(modelData[0]) }
                        }
                    }
                }
            }

            Btn {
                u: root.u
                anchors.verticalCenter: parent.verticalCenter
                text: root.syncing ? (root.lang === "zh" ? "更新中…" : "Updating…") : (root.lang === "zh" ? "更新" : "Update")
                onClicked: root.update()
            }

            IconButton {
                u: root.u
                anchors.verticalCenter: parent.verticalCenter
                kind: "close"
                onClicked: root.close()
            }
        }

        // Article: back on the left, reading controls on the right.
        IconButton {
            visible: root.article !== null
            u: root.u
            anchors { left: parent.left; leftMargin: 28 * u; verticalCenter: parent.verticalCenter }
            kind: "back"
            label: root.lang === "zh" ? "返回" : "Back"
            onClicked: root.closeArticle()
        }

        Row {
            visible: root.article !== null
            anchors { right: parent.right; rightMargin: 36 * u; verticalCenter: parent.verticalCenter }
            spacing: 20 * u
            Btn { u: root.u; text: "A−"; onClicked: root.setFont(-4) }
            Btn { u: root.u; text: "A+"; onClicked: root.setFont(4) }
            Btn {
                u: root.u
                visible: root.articleIsEnglish
                text: "中英对照"
                checked: root.bilingual
                accent: root.accent
                onClicked: root.toggleBilingual()
            }
        }

        // Thick rule in the source's color, newspaper style.
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 8 * u; color: root.accent }
    }

    // ------------------------------------------------------------ layout: front page

    Item {
        id: listView
        visible: !root.article
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: footer.top }

        DisplayMethodArea { anchors.fill: parent; displayMethod: root.modeContent }

        Flow {
            id: chips
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 40 * u; topMargin: 32 * u }
            spacing: 18 * u
            Repeater {
                model: root.sources
                Btn {
                    u: root.u
                    fontPx: 30 * root.u
                    implicitHeight: 76 * root.u
                    text: modelData.name
                    accent: modelData.color
                    checked: index === (root.srcIndex[root.lang] || 0)
                    onClicked: root.setSource(index)
                }
            }
        }

        Item {
            id: listArea
            anchors { top: chips.bottom; topMargin: 20 * u; left: parent.left; right: parent.right; bottom: parent.bottom }

            Text {
                anchors.centerIn: parent
                width: parent.width - 120 * u
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: root.listStatus !== ""
                text: root.listStatus + (root.syncing ? "\n" + root.syncStatus : "")
                font.pixelSize: 38 * u
                font.family: root.sansFamily
            }

            MouseArea {
                anchors.fill: parent
                property real px: 0
                property real py: 0
                onPressed: (mouse) => { px = mouse.x; py = mouse.y; }
                onReleased: (mouse) => {
                    var dx = mouse.x - px;
                    if (Math.abs(dx) > 120 * root.u && Math.abs(dx) > Math.abs(mouse.y - py)) {
                        root.turn(dx < 0 ? 1 : -1);
                        return;
                    }
                    var i = root.listPage * root.perPage + Math.floor(mouse.y / (height / root.perPage));
                    if (i >= 0 && i < root.items.length && i < (root.listPage + 1) * root.perPage)
                        root.openArticle(root.items[i]);
                }
            }

            Column {
                anchors { fill: parent; leftMargin: 56 * u; rightMargin: 56 * u }
                Repeater {
                    model: root.items.slice(root.listPage * root.perPage, (root.listPage + 1) * root.perPage)
                    Item {
                        width: parent.width
                        height: listArea.height / root.perPage

                        Image {
                            id: thumb
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: 330 * root.u
                            height: parent.height - 64 * root.u
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 660
                            asynchronous: true
                            clip: true
                            source: modelData.hasImage ? News.imageUrl(modelData.id) : ""
                            visible: status === Image.Ready
                        }

                        Column {
                            anchors {
                                left: parent.left
                                right: thumb.visible ? thumb.left : parent.right
                                rightMargin: thumb.visible ? 36 * root.u : 0
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 12 * root.u

                            Row {
                                spacing: 16 * root.u
                                Rectangle {
                                    width: tag.implicitWidth + 22 * root.u
                                    height: tag.implicitHeight + 6 * root.u
                                    radius: 6 * root.u
                                    color: root.sourceColor(modelData.source)
                                    Text {
                                        id: tag
                                        anchors.centerIn: parent
                                        text: modelData.source
                                        color: "white"
                                        font.pixelSize: 24 * root.u
                                        font.family: root.sansFamily
                                        font.weight: Font.Bold
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: News.timeAgo(modelData.time, root.lang) + (modelData.cached ? "" : (root.lang === "zh" ? "  · 未下载" : "  · online only"))
                                    font.pixelSize: 24 * root.u
                                    font.family: root.sansFamily
                                    font.weight: Font.Medium
                                }
                            }
                            Text {
                                width: parent.width
                                text: modelData.title
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                font.pixelSize: 44 * root.u
                                font.weight: Font.Bold
                                font.family: root.lang === "en" ? "Noto Sans" : root.sansFamily
                                lineHeight: 1.05
                            }
                            Text {
                                width: parent.width
                                text: modelData.summary
                                visible: text !== ""
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.pixelSize: 32 * root.u
                                font.family: root.serifFamily
                                font.weight: Font.Medium
                            }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2 * root.u; color: "black" }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ layout: article

    Item {
        id: articleView
        visible: root.article !== null
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: footer.top }

        Item {
            id: bodyArea
            anchors { fill: parent; leftMargin: 90 * u; rightMargin: 90 * u; topMargin: 40 * u; bottomMargin: 20 * u }
            onHeightChanged: Qt.callLater(root.computePages)
            onWidthChanged: Qt.callLater(root.computePages)

            Item {
                id: pageClip
                width: parent.width
                height: {
                    var s = root.pageStarts[root.pageIdx] || 0;
                    var e = root.pageIdx + 1 < root.pageStarts.length ? root.pageStarts[root.pageIdx + 1] : body.contentHeight;
                    return Math.min(parent.height, e - s);
                }
                clip: true

                // Full-quality color while reading; fast 1-bit while a word selection is dragged.
                DisplayMethodArea {
                    anchors.fill: parent
                    displayMethod: pager.holding ? root.modeMono : root.modeContent
                }

                TextEdit {
                    id: body
                    width: parent.width
                    y: -(root.pageStarts[root.pageIdx] || 0)
                    readOnly: true
                    selectByMouse: false
                    activeFocusOnPress: false
                    textFormat: TextEdit.RichText
                    wrapMode: TextEdit.Wrap
                    color: "black"
                    selectionColor: "black"
                    selectedTextColor: "white"
                    font.pixelSize: root.fontPx * root.u
                    font.family: root.serifFamily
                    onContentHeightChanged: Qt.callLater(root.computePages)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.articleStatus !== "" && body.text === ""
                text: root.articleStatus
                font.pixelSize: 38 * u
                font.family: root.sansFamily
            }

            MouseArea {
                id: pager
                anchors.fill: parent
                pressAndHoldInterval: 450
                property real px: 0
                property real py: 0
                property bool holding: false
                property bool held: false
                property int anchorA: -1
                property int anchorB: -1

                // Text position under the finger, or -1 when it's in a gap between lines.
                function posAt(mx, my) {
                    var y = my + (root.pageStarts[root.pageIdx] || 0);
                    var p = body.positionAt(mx, y);
                    var r = body.positionToRectangle(p);
                    return (y < r.y - 6 * root.u || y > r.y + r.height + 6 * root.u) ? -1 : p;
                }

                onPressed: (mouse) => { px = mouse.x; py = mouse.y; holding = false; held = false; }

                onPressAndHold: (mouse) => {
                    held = true;
                    if (!root.articleIsEnglish) return;
                    var p = posAt(mouse.x, mouse.y);
                    var w = p < 0 ? null : root.wordAt(p);
                    if (!w) return;
                    holding = true;
                    anchorA = w.start;
                    anchorB = w.end;
                    body.select(w.start, w.end);
                }

                onPositionChanged: (mouse) => {
                    if (!holding) return;
                    var p = posAt(mouse.x, mouse.y);
                    var w = p < 0 ? null : root.wordAt(p);
                    if (!w) return;
                    body.select(Math.min(anchorA, w.start), Math.max(anchorB, w.end));
                }

                onReleased: (mouse) => {
                    if (holding) {
                        holding = false;
                        var a = body.selectionStart, b = body.selectionEnd;
                        popup.show(body.getText(a, b), root.sentenceAround(a, b), body.positionToRectangle(a).y - (root.pageStarts[root.pageIdx] || 0));
                        return;
                    }
                    if (held) return;   // long press on blank space: do nothing
                    var dx = mouse.x - px;
                    if (Math.abs(dx) > 120 * root.u && Math.abs(dx) > Math.abs(mouse.y - py)) {
                        root.turn(dx < 0 ? 1 : -1);
                    } else if (popup.visible) {
                        popup.hide();
                    } else {
                        root.turn(mouse.x < width * 0.3 ? -1 : 1);
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ layout: footer

    Item {
        id: footer
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: 120 * u
        Rectangle { anchors.top: parent.top; width: parent.width; height: 3 * u; color: "black" }
        DisplayMethodArea { anchors.fill: parent; displayMethod: root.modeUi }

        Btn {
            u: root.u
            anchors { left: parent.left; leftMargin: 36 * u; verticalCenter: parent.verticalCenter }
            text: root.lang === "zh" ? "‹ 上一页" : "‹ Prev"
            dim: root.article ? root.pageIdx === 0 : root.listPage === 0
            onClicked: root.turn(-1)
        }
        Text {
            anchors.centerIn: parent
            text: root.article
                  ? (root.articleStatus !== "" && body.text !== "" ? root.articleStatus + "    " : "") +
                    (root.pageIdx + 1) + " / " + root.pageStarts.length
                  : (root.listPage + 1) + " / " + root.listPages
            font.pixelSize: 32 * u
            font.family: root.sansFamily
            font.weight: Font.Medium
        }
        Btn {
            u: root.u
            anchors { right: parent.right; rightMargin: 36 * u; verticalCenter: parent.verticalCenter }
            text: root.lang === "zh" ? "下一页 ›" : "Next ›"
            dim: root.article ? root.pageIdx >= root.pageStarts.length - 1 : root.listPage >= root.listPages - 1
            onClicked: root.turn(1)
        }
    }

    // ------------------------------------------------------------ lookup popup

    Rectangle {
        id: popup
        visible: false
        z: 10
        x: 60 * u
        width: parent.width - 120 * u
        height: popCol.implicitHeight + 70 * u
        color: "white"
        border.width: 4 * u
        border.color: "black"
        radius: 16 * u

        property string query: ""
        property string sentence: ""
        property var entry: null
        property string online: ""
        property string sentenceZh: ""
        property bool busy: false
        property int token: 0
        property real selTop: 0
        // Sit in the half of the screen away from the selection.
        y: selTop > root.height / 2 ? header.height + 30 * u : root.height - footer.height - height - 30 * u
        readonly property bool isPhrase: /\s/.test(query)

        function show(text, sent, selY) {
            text = text.replace(/\u2029/g, " ").trim();
            if (!text) return;
            token++;
            query = text;
            sentence = sent;
            entry = null;
            online = "";
            sentenceZh = "";
            busy = true;
            selTop = header.height + bodyArea.anchors.topMargin + selY;
            visible = true;
            var t = token;
            if (isPhrase) {
                News.translate(text, "en", "zh-CN", function (err, out) {
                    if (t !== popup.token) return;
                    popup.online = out || ("翻译失败：" + err);
                    popup.busy = false;
                });
                return;
            }
            News.lookup(text, function (e) {
                if (t !== popup.token) return;
                popup.entry = e;
                if (e && (e.translation || e.base)) { popup.busy = false; return; }
                News.lookupOnline(text, function (err, out) {
                    if (t !== popup.token) return;
                    popup.online = out || "未找到释义";
                    popup.busy = false;
                });
            });
        }

        function hide() {
            token++;
            visible = false;
            body.deselect();
        }

        function translateSentence() {
            if (!sentence) return;
            var t = token;
            sentenceZh = "翻译中 …";
            News.translate(sentence, "en", "zh-CN", function (err, out) {
                if (t !== popup.token) return;
                popup.sentenceZh = out || ("翻译失败：" + err);
            });
        }

        MouseArea { anchors.fill: parent }   // swallow taps so they don't turn the page

        DisplayMethodArea { anchors.fill: parent; displayMethod: root.modeUi }

        // Colored strip on the left ties the card to the article's source.
        Rectangle {
            x: 4 * u; y: 4 * u
            width: 14 * u; height: parent.height - 8 * u
            radius: 10 * u
            color: root.accent
        }

        Column {
            id: popCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 40 * u; leftMargin: 52 * u }
            spacing: 16 * u

            Row {
                width: parent.width
                spacing: 24 * u
                Text {
                    id: headword
                    width: Math.min(implicitWidth, parent.width - phon.implicitWidth - 24 * root.u)
                    text: popup.isPhrase ? popup.query : (popup.entry && popup.entry.translation ? popup.entry.word : popup.query)
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    font.pixelSize: (popup.isPhrase ? 38 : 54) * root.u
                    font.bold: true
                    font.family: "Noto Sans"
                }
                Text {
                    id: phon
                    anchors.baseline: headword.baseline
                    visible: !popup.isPhrase && popup.entry !== null && popup.entry.phonetic !== ""
                    text: popup.entry ? "/" + popup.entry.phonetic + "/" : ""
                    font.pixelSize: 34 * root.u
                    font.family: "Noto Sans"
                }
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: popup.entry && popup.entry.tags ? popup.entry.tags : ""
                font.pixelSize: 26 * root.u
                font.family: root.sansFamily
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: popup.busy ? "查询中 …"
                      : (popup.entry && popup.entry.translation ? popup.entry.translation : popup.online)
                wrapMode: Text.Wrap
                font.pixelSize: 38 * root.u
                font.family: "Noto Serif SC"
                font.weight: Font.Medium
                lineHeight: 1.15
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: {
                    var b = popup.entry ? popup.entry.base : null;
                    if (!b || !b.translation) return "";
                    return "原形 " + b.word + (b.phonetic ? "  /" + b.phonetic + "/" : "") + "\n" + b.translation;
                }
                wrapMode: Text.Wrap
                font.pixelSize: 34 * root.u
                font.family: "Noto Serif SC"
                font.weight: Font.Medium
                lineHeight: 1.15
            }

            Rectangle { width: parent.width; height: 2 * root.u; color: "black"; visible: popup.sentence !== "" }

            Text {
                width: parent.width
                visible: popup.sentence !== ""
                text: popup.sentence
                wrapMode: Text.Wrap
                maximumLineCount: 6
                elide: Text.ElideRight
                font.pixelSize: 32 * root.u
                font.family: "EB Garamond"
                font.weight: Font.Medium
                font.italic: true
            }

            Text {
                width: parent.width
                visible: popup.sentenceZh !== ""
                text: popup.sentenceZh
                wrapMode: Text.Wrap
                font.pixelSize: 34 * root.u
                font.family: "Noto Serif SC"
                font.weight: Font.Medium
                lineHeight: 1.15
            }

            Row {
                spacing: 24 * root.u
                Btn {
                    u: root.u
                    visible: popup.sentence !== "" && popup.sentenceZh === ""
                    text: "翻译整句"
                    onClicked: popup.translateSentence()
                }
                Btn { u: root.u; text: "关闭"; onClicked: popup.hide() }
            }
        }
    }
}
