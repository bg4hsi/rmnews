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

    // Pen tools in articles. The Marker reaches us as plain (non-synthesized) mouse events,
    // fingers as touch-synthesized ones, so the pen can write while fingers keep turning pages.
    property string tool: "lookup"      // "lookup" | "highlight" | "pen" | "erase"
    readonly property string activeTool: tool === "lookup" && !articleIsEnglish ? "highlight" : tool
    property var notes: ({ hl: [], ink: [] })
    readonly property color highlightColor: "#FFD600"
    readonly property color inkColor: "#0D47A1"

    property bool showVocab: false
    property var vocabList: []
    property int vocabPage: 0

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
        News.loadVocab(function (v) { vocabList = v.slice(); });
        News.loadState(function (s) {
            if (stateLoaded) return;
            stateLoaded = true;
            if (s.lang === "en" || s.lang === "zh") lang = s.lang;
            if (s.srcIndex) srcIndex = s.srcIndex;
            if (s.fontPx) fontPx = s.fontPx;
            if (s.bilingual !== undefined) bilingual = s.bilingual;
            if (s.tool) tool = s.tool;
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
        News.saveState({ lang: lang, srcIndex: srcIndex, fontPx: fontPx, bilingual: bilingual, tool: tool });
    }

    // ------------------------------------------------------------ e-paper

    // AppLoad turns DisplayMethodArea into xochitl's Epaper.ScreenModeItem. Its enum is
    // mapped by index onto [Pen, Mono, Animation, UI, Content], so use these names instead.
    readonly property int modeMono: 1       // fast black & white; interactive feedback
    // Used while writing. Pen mode is faster still, but xochitl stops refreshing Pen areas while
    // a palm rests on the glass; Animation (what xochitl uses for scrolling) keeps up.
    readonly property int modeAnimation: 2
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

    // Input trace for on-device debugging (read it with tools/rmjs.sh 'return root.trace.join("\\n")').
    property var trace: []
    function dlog(msg) {
        if (!debugEnabled) return;
        trace.push((Date.now() % 100000) + " " + msg);
        if (trace.length > 300) trace.shift();
    }

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
        tool = "lookup";        // articles open for reading; writing tools are picked explicitly
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
        var token = articleToken;
        News.loadNotes(item.id, function (n) {
            if (token !== articleToken) return;
            notes = n;
            article = { item: item, paras: art.paras, trans: art.trans || [], summaryOnly: art.summaryOnly,
                        image: item.hasImage ? News.imageUrl(item.id) : "" };
            articleStatus = "";
            pageIdx = 0;
            renderArticle();
            clearGhosting();
            if (bilingual && articleIsEnglish) translateAll();
        });
    }

    function closeArticle() {
        if (pendingHl.length) flushHighlights();
        inkSession = false;
        clearSegs();
        articleToken++;
        article = null;
        popup.hide();
        body.text = "";
        notes = { hl: [], ink: [] };
        inkPaths = [];
        clearGhosting();
    }

    function renderArticle() {
        if (!article) return;
        if (pendingHl.length) {
            notes = { hl: mergeHighlights(notes.hl.concat(pendingHl)), ink: notes.ink };
            pendingHl = [];
        }
        clearSegs("highlight");
        inkSession = false;
        writeBox = Qt.rect(0, 0, 0, 0);
        var a = article;
        // Text stays pure black (Gallery 3 dithers greys into speckles); color is used for
        // accents and pictures only.
        var col = String(accent);
        var small = "font-family:'Noto Sans SC'; font-weight:500; font-size:" + Math.round(fontPx * 0.68 * u) + "px;";
        var zhStyle = "font-family:'Noto Serif SC'; font-weight:500; font-size:" + Math.round(fontPx * 0.86 * u) +
                      "px; margin-left:" + Math.round(28 * u) + "px; line-height:135%;";
        // Every <p>/<h1> becomes one text block; keys[] records what each block holds so
        // highlights and ink can be anchored to "paragraph 7" instead of pixel positions.
        var keys = [];
        var h = "<p style=\"font-family:'Noto Sans SC'; font-weight:700; font-size:" + Math.round(fontPx * 0.72 * u) +
                "px; color:" + col + ";\">" + News.escapeHtml(a.item.source.toUpperCase()) + "</p>";
        keys.push("b0");
        h += "<h1 style=\"font-family:'" + serifFamily + "'; font-weight:700; font-size:" +
             Math.round(fontPx * 1.45 * u) + "px; line-height:115%;\">" + markup(a.item.title, "b", 1) + "</h1>";
        keys.push("b1");
        if (a.item.time) {
            h += "<p style=\"" + small + "\">" + News.escapeHtml(News.timeAgo(a.item.time, lang)) + "</p>";
            keys.push("b2");
        }
        if (a.image) {
            h += "<p><img src=\"" + a.image + "\" width=\"" + Math.floor(bodyArea.width) + "\"></p>";
            keys.push("b3");
        }
        if (a.summaryOnly) {
            h += "<p style=\"" + small + "\">（原网站未提供全文，以下为摘要）</p>";
            keys.push("b4");
        }
        for (var i = 0; i < a.paras.length; i++) {
            h += "<p style=\"line-height:140%; font-weight:500;\">" + markup(a.paras[i], "p", i) + "</p>";
            keys.push("p" + i);
            if (bilingual && a.trans[i]) {
                h += "<p style=\"" + zhStyle + "\">" + markup(a.trans[i], "t", i) + "</p>";
                keys.push("t" + i);
            }
        }
        var ratio = pageStarts.length > 1 ? pageStarts[pageIdx] / Math.max(1, body.contentHeight) : 0;
        body.text = h;
        blockKeys = keys;
        var plain = body.getText(0, body.length);
        var starts = [0];
        for (var c = 0; c < plain.length; c++) if (plain.charAt(c) === "\u2029") starts.push(c + 1);
        blockStarts = starts;
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

    // ------------------------------------------------------------ annotations

    property var blockKeys: []      // per text block: "p3" paragraph 3, "t3" its translation, "b1" title, ...
    property var blockStarts: []    // document position where each block begins
    property var inkPaths: []       // ink strokes resolved to document coordinates: [{ src, w, pts }]

    // On Gallery 3 every repaint in Content mode is a slow color flash, and so is switching an
    // area back from Pen to Content. Once the reader starts writing on a page we therefore stay
    // in Pen mode, keep freshly drawn segments on screen as they are and only fold pending
    // highlights into the text when the page is repainted anyway (turn, close, font, bilingual).
    property bool inkSession: false
    property var pendingHl: []

    // Animation mode is black & white, so it only covers where the pen has been on this page
    // (document coordinates, padded); the rest of the page, pictures included, stays in color.
    property rect writeBox: Qt.rect(0, 0, 0, 0)
    function growWriteBox(x, y) {
        var pad = 140 * u;
        var b = writeBox;
        var x0 = x - pad, y0 = y - pad, x1 = x + pad, y1 = y + pad;
        if (b.width > 0) {
            x0 = Math.min(x0, b.x); y0 = Math.min(y0, b.y);
            x1 = Math.max(x1, b.x + b.width); y1 = Math.max(y1, b.y + b.height);
        }
        writeBox = Qt.rect(x0, y0, x1 - x0, y1 - y0);
    }

    // Palm rejection. Touches (palm or finger) are ignored on the page while the Marker is
    // down, hovering, or was used within the last 1.5 s. With a writing tool selected a touch
    // can only swipe pages (a resting palm lands like a tap); footer buttons ignore touches
    // while the pen is near.
    property double lastPenAt: 0
    property double lastTouchAt: 0
    readonly property bool writingTool: article !== null && activeTool !== "lookup"
    function notePen() { lastPenAt = Date.now(); }
    function penNear() { return pager.penDown || Date.now() - lastPenAt < 1500; }

    function clearSegs(kind) {
        for (var j = freshSegs.count - 1; j >= 0; j--)
            if (!kind || freshSegs.get(j).g === kind) freshSegs.remove(j);
    }

    function markup(text, k, i) {
        var rs = notes.hl.filter(function (x) { return x.k === k && x.i === i; })
                         .sort(function (x, y) { return x.s - y.s; });
        var out = "", at = 0;
        rs.forEach(function (x) {
            var s = Math.max(at, x.s), e = Math.min(text.length, x.e);
            if (e <= s) return;
            out += News.escapeHtml(text.slice(at, s)) + "<span style=\"background-color:" + highlightColor + ";\">" +
                   News.escapeHtml(text.slice(s, e)) + "</span>";
            at = e;
        });
        return out + News.escapeHtml(text.slice(at));
    }

    function blockAt(pos) {
        var b = 0;
        while (b + 1 < blockStarts.length && blockStarts[b + 1] <= pos) b++;
        return b;
    }

    function blockTop(k, i) {
        var b = blockKeys.indexOf(k + i);
        return b < 0 ? null : body.positionToRectangle(blockStarts[b]).y;
    }

    function setNotes(n) {
        notes = n;
        if (article) News.saveNotes(article.item.id, n);
    }

    function layoutInk() {
        var out = [];
        notes.ink.forEach(function (st, idx) {
            var top = blockTop(st.k, st.i);
            if (top === null) return;   // e.g. drawn on a translation that is hidden now
            out.push({ src: idx, w: st.w, pts: st.pts.map(function (p) { return Qt.point(p[0], top + p[1]); }) });
        });
        inkPaths = out;
        clearSegs("pen");
        clearSegs("erase");
    }

    // Text range a pen stroke points at: an underline (or strike-through) marks the words
    // on that line, a loop marks the words inside it. null when the stroke misses the text.
    function strokeRange(pts) {
        var minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
        pts.forEach(function (p) {
            minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x);
            minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y);
        });
        var lineH = fontPx * u * 1.4;
        var loop = maxY - minY > 0.8 * lineH;
        var ys = pts.map(function (p) { return p.y; }).sort(function (a, b) { return a - b; });
        var yC = loop ? (minY + maxY) / 2 : ys[Math.floor(ys.length / 2)];
        var midX = (minX + maxX) / 2;
        var r = body.positionToRectangle(body.positionAt(midX, yC));
        var yLine;
        if (yC >= r.y + 0.2 * r.height && yC <= r.y + r.height) {
            yLine = r.y + r.height / 2;     // through the words, or touching their bottoms
        } else {
            // In the leading between two lines: an underline belongs to the line above.
            var r2 = body.positionToRectangle(body.positionAt(midX, yC - 0.5 * lineH));
            yLine = r2.y + r2.height / 2;
        }
        var pad = loop ? 0.15 * lineH : 0;
        var a = body.positionAt(minX + pad, yLine), b = body.positionAt(maxX - pad, yLine);
        if (b <= a) return null;
        // Snap to whole words; a word the stroke only grazes (less than half covered) is left out.
        var wa = wordAt(a), wb = wordAt(Math.max(a, b - 1));
        if (wa && wa.start < a) a = (a - wa.start) > (wa.end - a) ? wa.end : wa.start;
        if (wb && wb.end > b) b = (wb.end - b) > (b - wb.start) ? wb.start : wb.end;
        var t = body.getText(a, b);
        while (a < b && /[\s\u2029]/.test(t.charAt(0))) { a++; t = t.slice(1); }
        while (b > a && /[\s\u2029]/.test(t.charAt(t.length - 1))) { b--; t = t.slice(0, -1); }
        return b > a ? { start: a, end: b } : null;
    }

    function mergeHighlights(list) {
        var groups = {};
        list.forEach(function (x) { (groups[x.k + x.i] = groups[x.k + x.i] || []).push(x); });
        var out = [];
        Object.keys(groups).forEach(function (key) {
            var g = groups[key].sort(function (x, y) { return x.s - y.s; });
            var cur = Object.assign({}, g[0]);
            for (var j = 1; j < g.length; j++) {
                if (g[j].s <= cur.e) cur.e = Math.max(cur.e, g[j].e);
                else { out.push(cur); cur = Object.assign({}, g[j]); }
            }
            out.push(cur);
        });
        return out;
    }

    function addHighlight(rg) {
        var hl = [];
        for (var b = blockAt(rg.start); b <= blockAt(rg.end - 1); b++) {
            var start = blockStarts[b];
            var end = b + 1 < blockStarts.length ? blockStarts[b + 1] - 1 : body.length;
            var s = Math.max(rg.start, start) - start, e = Math.min(rg.end, end) - start;
            if (e > s) hl.push({ k: blockKeys[b].charAt(0), i: +blockKeys[b].slice(1), s: s, e: e });
        }
        pendingHl = pendingHl.concat(hl);
        // Saved right away; drawn into the text at the next repaint (see inkSession).
        if (article) News.saveNotes(article.item.id, { hl: mergeHighlights(notes.hl.concat(pendingHl)), ink: notes.ink });
    }

    // Highlights drawn since the last repaint become part of the text (renderArticle merges them).
    function flushHighlights() {
        if (pendingHl.length && article) renderArticle();
        else clearSegs("highlight");
    }

    // The stroke stays on screen exactly as drawn (its live segments); it only joins
    // inkPaths at the next layout, so lifting the pen causes no repaint.
    function addInk(pts) {
        var b = blockAt(body.positionAt(pts[0].x, pts[0].y));
        var top = body.positionToRectangle(blockStarts[b]).y;
        var stroke = { k: blockKeys[b].charAt(0), i: +blockKeys[b].slice(1), w: 4,
                       pts: pts.map(function (p) { return [Math.round(p.x), Math.round(p.y - top)]; }) };
        setNotes({ hl: notes.hl, ink: notes.ink.concat([stroke]) });
    }

    // Remove ink strokes and highlights the eraser stroke passes over.
    function eraseAlong(pts) {
        flushHighlights();
        layoutInk();
        var R = 30 * u;
        var step = Math.max(1, Math.floor(pts.length / 80));
        var gone = {};
        inkPaths.forEach(function (path) {
            for (var j = 0; j < path.pts.length && !gone[path.src]; j += 2) {
                for (var k = 0; k < pts.length; k += step) {
                    var dx = path.pts[j].x - pts[k].x, dy = path.pts[j].y - pts[k].y;
                    if (dx * dx + dy * dy < R * R) { gone[path.src] = true; break; }
                }
            }
        });
        var hits = [];
        for (var k = 0; k < pts.length; k += step) {
            var p = body.positionAt(pts[k].x, pts[k].y);
            var r = body.positionToRectangle(p);
            if (pts[k].y < r.y - R || pts[k].y > r.y + r.height + R) continue;
            var b = blockAt(p);
            hits.push({ key: blockKeys[b], off: p - blockStarts[b] });
        }
        var hl = notes.hl.filter(function (x) {
            return !hits.some(function (h) { return h.key === x.k + x.i && h.off >= x.s - 1 && h.off <= x.e + 1; });
        });
        var ink = notes.ink.filter(function (st, idx) { return !gone[idx]; });
        var hlChanged = hl.length !== notes.hl.length;
        setNotes({ hl: hl, ink: ink });
        if (hlChanged) renderArticle(); else layoutInk();
    }

    function penStroke(pts) {
        if (!article || !body.text) return;
        if (activeTool !== "lookup") inkSession = true;
        switch (activeTool) {
        case "lookup":
            var rg = strokeRange(pts);
            if (!rg) { clearSegs("lookup"); return; }
            body.select(rg.start, rg.end);
            popup.show(body.getText(rg.start, rg.end), sentenceAround(rg.start, rg.end),
                       body.positionToRectangle(rg.start).y - (pageStarts[pageIdx] || 0));
            break;
        case "highlight":
            var hr = strokeRange(pts);
            if (hr) addHighlight(hr); else clearSegs("highlight");
            break;
        case "pen":
            addInk(pts);
            break;
        case "erase":
            eraseAlong(pts);
            break;
        }
    }

    function setTool(t) {
        tool = t;
        saveState();
    }

    // ------------------------------------------------------------ vocabulary page

    function openVocab() {
        News.loadVocab(function (v) { vocabList = v.slice(); vocabPage = 0; showVocab = true; });
    }

    function closeVocab() {
        showVocab = false;
        clearGhosting();
    }

    function deleteVocab(word) {
        News.removeVocab(word);
        vocabList = News.vocab.slice();
        vocabPage = Math.min(vocabPage, vocabPages - 1);
    }

    readonly property int vocabPerPage: Math.max(3, Math.floor(vocabArea.height / (330 * u)))
    readonly property int vocabPages: Math.max(1, Math.ceil(vocabList.length / vocabPerPage))

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
        layoutInk();
    }

    function turn(delta) {
        popup.hide();
        if (article && (pendingHl.length || inkSession)) {
            // The new page repaints in full anyway: fold in highlights, back to Content mode.
            // Highlights don't change the layout, so stay on the page being turned from.
            flushHighlights();
            restoreRatio = 0;
            inkSession = false;
            writeBox = Qt.rect(0, 0, 0, 0);
        }
        var cur = function () { return article ? pageIdx : showVocab ? vocabPage : listPage; };
        var before = cur();
        if (article) {
            pageIdx = Math.max(0, Math.min(pageStarts.length - 1, pageIdx + delta));
        } else if (showVocab) {
            vocabPage = Math.max(0, Math.min(vocabPages - 1, vocabPage + delta));
        } else {
            listPage = Math.max(0, Math.min(listPages - 1, listPage + delta));
        }
        if (cur() !== before && ++turnsSinceClear >= ghostEvery)
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
        height: (root.article || root.showVocab ? 130 : 210) * u

        DisplayMethodArea { anchors.fill: parent; displayMethod: root.modeContent }

        // Front page: paper name + date on the left, controls on the right.
        Column {
            visible: !root.article && !root.showVocab
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
            visible: !root.article && !root.showVocab
            anchors { right: parent.right; rightMargin: 28 * u; verticalCenter: parent.verticalCenter }
            spacing: 22 * u

            Seg {
                u: root.u
                anchors.verticalCenter: parent.verticalCenter
                segWidth: 124 * root.u
                options: [["en", "EN"], ["zh", "中文"]]
                value: root.lang
                onPicked: (v) => root.setLang(v)
            }

            Btn {
                u: root.u
                anchors.verticalCenter: parent.verticalCenter
                text: (root.lang === "zh" ? "生词本" : "Words") + (root.vocabList.length ? " " + root.vocabList.length : "")
                onClicked: root.openVocab()
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

        // Article / vocabulary: back on the left, controls on the right.
        IconButton {
            visible: root.article !== null || root.showVocab
            u: root.u
            anchors { left: parent.left; leftMargin: 28 * u; verticalCenter: parent.verticalCenter }
            kind: "back"
            label: root.lang === "zh" ? "返回" : "Back"
            onClicked: root.article ? root.closeArticle() : root.closeVocab()
        }

        Text {
            visible: root.showVocab && !root.article
            anchors.centerIn: parent
            text: (root.lang === "zh" ? "生词本 · " + root.vocabList.length + " 个" : "Words · " + root.vocabList.length)
            font.pixelSize: 44 * root.u
            font.family: root.lang === "zh" ? "Noto Serif SC" : "EB Garamond"
            font.weight: Font.Bold
        }

        Row {
            visible: root.article !== null
            anchors { right: parent.right; rightMargin: 28 * u; verticalCenter: parent.verticalCenter }
            spacing: 16 * u

            // What the Marker does on the page; fingers always turn pages.
            Seg {
                u: root.u
                anchors.verticalCenter: parent.verticalCenter
                segWidth: 112 * root.u
                accent: root.accent
                options: root.articleIsEnglish
                         ? [["lookup", "查词"], ["highlight", "荧光"], ["pen", "钢笔"], ["erase", "橡皮"]]
                         : [["highlight", "荧光"], ["pen", "钢笔"], ["erase", "橡皮"]]
                value: root.activeTool
                onPicked: (v) => root.setTool(v)
            }

            Btn { u: root.u; text: "A−"; onClicked: root.setFont(-4) }
            Btn { u: root.u; text: "A+"; onClicked: root.setFont(4) }
            Btn {
                u: root.u
                visible: root.articleIsEnglish
                text: "对照"
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
        visible: !root.article && !root.showVocab
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

                // Full quality (color) while reading, fast black & white while a word selection
                // is dragged. Writing gets its own Animation-mode area below.
                DisplayMethodArea {
                    anchors.fill: parent
                    displayMethod: pager.holding || touchArea.holding ? root.modeMono : root.modeContent
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

                // Where the pen writes: Animation mode keeps ink live even with a palm on the glass
                // (Pen mode stalls then), but it is monochrome, so it stays as small as possible.
                DisplayMethodArea {
                    visible: (pager.penDown || root.inkSession) && root.writeBox.width > 0
                    x: root.writeBox.x
                    y: root.writeBox.y - (root.pageStarts[root.pageIdx] || 0)
                    width: root.writeBox.width
                    height: root.writeBox.height
                    displayMethod: root.modeAnimation
                }

                // Handwritten ink, plus the stroke currently being drawn; scrolls with the text.
                Item {
                    id: inkLayer
                    y: body.y
                    width: parent.width
                    height: body.contentHeight

                    Repeater {
                        model: root.inkPaths
                        InkStroke {
                            anchors.fill: parent
                            pts: modelData.pts
                            color: root.inkColor
                            lineWidth: modelData.w * root.u
                        }
                    }

                    // Strokes drawn since the last layout, one segment per pen sample; each keeps the
                    // style of the tool it was drawn with.
                    Repeater {
                        model: ListModel { id: freshSegs }
                        Rectangle {
                            readonly property real dx: x1 - x0
                            readonly property real dy: y1 - y0
                            x: x0 - w / 2
                            y: y0 - w / 2
                            width: Math.sqrt(dx * dx + dy * dy) + w
                            height: w
                            radius: w / 2
                            antialiasing: true
                            color: c
                            opacity: o
                            transform: Rotation { origin.x: w / 2; origin.y: w / 2; angle: Math.atan2(dy, dx) * 180 / Math.PI }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.articleStatus !== "" && body.text === ""
                text: root.articleStatus
                font.pixelSize: 38 * u
                font.family: root.sansFamily
            }

            // Fingers/palm and the Marker are separate pointing devices in Qt, so each gets its own
            // area: a palm resting on the glass must never hold the input the pen needs.
            MouseArea {
                id: touchArea
                anchors.fill: parent
                pressAndHoldInterval: 450
                property real px: 0
                property real py: 0
                property bool holding: false    // long-press word selection in progress
                property bool held: false
                property bool swipeOnly: false  // a writing tool is active: taps are palms
                property int anchorA: -1
                property int anchorB: -1

                onPressed: (mouse) => {
                    root.dlog("touch press src=" + mouse.source + " " + Math.round(mouse.x) + "," + Math.round(mouse.y) + " penNear=" + root.penNear());
                    if (root.penNear()) {
                        mouse.accepted = false;     // palm while writing
                        return;
                    }
                    root.lastTouchAt = Date.now();
                    swipeOnly = root.writingTool;
                    px = mouse.x; py = mouse.y; holding = false; held = false;
                }

                onPressAndHold: (mouse) => {
                    held = true;
                    if (swipeOnly || root.penNear() || !root.articleIsEnglish) return;
                    var p = pager.posAt(mouse.x, mouse.y);
                    var w = p < 0 ? null : root.wordAt(p);
                    if (!w) return;
                    holding = true;
                    anchorA = w.start;
                    anchorB = w.end;
                    body.select(w.start, w.end);
                }

                onPositionChanged: (mouse) => {
                    if (!holding) return;
                    var p = pager.posAt(mouse.x, mouse.y);
                    var w = p < 0 ? null : root.wordAt(p);
                    if (w) body.select(Math.min(anchorA, w.start), Math.max(anchorB, w.end));
                }

                onCanceled: root.dlog("touch canceled")

                onReleased: (mouse) => {
                    root.dlog("touch release src=" + mouse.source);
                    root.lastTouchAt = Date.now();
                    if (holding) {
                        holding = false;
                        var a = body.selectionStart, b = body.selectionEnd;
                        popup.show(body.getText(a, b), root.sentenceAround(a, b), body.positionToRectangle(a).y - (root.pageStarts[root.pageIdx] || 0));
                        return;
                    }
                    if (root.penNear()) return;     // a palm that rested while the pen wrote
                    var dx = mouse.x - px;
                    var swipe = Math.abs(dx) > 120 * root.u && Math.abs(dx) > Math.abs(mouse.y - py);
                    if (swipe) {
                        root.turn(dx < 0 ? 1 : -1);
                    } else if (swipeOnly || held) {
                        return;                     // palm landing / long press on blank space
                    } else if (popup.visible) {
                        popup.hide();
                    } else {
                        root.turn(mouse.x < width * 0.3 ? -1 : 1);
                    }
                }
            }

            MouseArea {
                id: pager
                anchors.fill: parent
                pressAndHoldInterval: 450
                property real px: 0
                property real py: 0
                property bool holding: false    // pen long-press word selection (lookup tool)
                property bool held: false
                property bool penDown: false    // the Marker is on the glass
                property real penTravel: 0
                property var stroke: []         // document coordinates of the current pen stroke
                property int anchorA: -1
                property int anchorB: -1

                function docY(my) { return my + (root.pageStarts[root.pageIdx] || 0); }

                // Text position under the pointer, or -1 when it's in a gap between lines.
                function posAt(mx, my) {
                    var y = docY(my);
                    var p = body.positionAt(mx, y);
                    var r = body.positionToRectangle(p);
                    return (y < r.y - 6 * root.u || y > r.y + r.height + 6 * root.u) ? -1 : p;
                }

                onPressed: (mouse) => {
                    root.dlog("pen-area press src=" + mouse.source + " btn=" + mouse.button + " " + Math.round(mouse.x) + "," + Math.round(mouse.y) + " touchPressed=" + touchArea.pressed);
                    if (mouse.source !== Qt.MouseEventNotSynthesized) {
                        mouse.accepted = false;     // touches go to touchArea below
                        return;
                    }
                    root.notePen();
                    px = mouse.x; py = mouse.y; holding = false; held = false;
                    penDown = true;
                    stroke = [{ x: mouse.x, y: docY(mouse.y) }];
                    penTravel = 0;
                    root.growWriteBox(mouse.x, docY(mouse.y));
                }

                onPressAndHold: (mouse) => {
                    held = true;
                    if (root.activeTool !== "lookup" || penTravel > 12 * root.u || !root.articleIsEnglish) return;
                    var p = posAt(mouse.x, mouse.y);
                    var w = p < 0 ? null : root.wordAt(p);
                    if (!w) return;
                    holding = true;
                    anchorA = w.start;
                    anchorB = w.end;
                    body.select(w.start, w.end);
                }

                onPositionChanged: (mouse) => {
                    root.notePen();
                    if (holding) {
                        var p = posAt(mouse.x, mouse.y);
                        var w = p < 0 ? null : root.wordAt(p);
                        if (w) body.select(Math.min(anchorA, w.start), Math.max(anchorB, w.end));
                        return;
                    }
                    if (!penDown) return;
                    var last = stroke[stroke.length - 1];
                    var x = mouse.x, y = docY(mouse.y);
                    var d = Math.sqrt((x - last.x) * (x - last.x) + (y - last.y) * (y - last.y));
                    if (d >= 3 * root.u) {
                        stroke.push({ x: x, y: y });
                        penTravel += d;
                        root.growWriteBox(x, y);
                        var t = root.activeTool;
                        freshSegs.append({ x0: last.x, y0: last.y, x1: x, y1: y, g: t,
                                           w: (t === "highlight" ? 30 : t === "erase" ? 36 : 4) * root.u,
                                           c: t === "highlight" ? "#FFD600" : t === "erase" ? "#9E9E9E"
                                              : t === "pen" ? String(root.inkColor) : "#000000",
                                           o: t === "highlight" ? 0.5 : 1 });
                    }
                }

                onCanceled: { root.dlog("pen canceled"); penDown = false; root.clearSegs(root.activeTool); }

                onReleased: (mouse) => {
                    root.dlog("pen release travel=" + Math.round(penTravel) + " pts=" + stroke.length);
                    penDown = false;
                    root.notePen();
                    if (holding) {
                        holding = false;
                        var a = body.selectionStart, b = body.selectionEnd;
                        popup.show(body.getText(a, b), root.sentenceAround(a, b), body.positionToRectangle(a).y - (root.pageStarts[root.pageIdx] || 0));
                        return;
                    }
                    if (penTravel > 12 * root.u) {
                        if (root.activeTool === "lookup") popup.hide();
                        root.penStroke(stroke);
                        return;
                    }
                    root.clearSegs(root.activeTool);    // a dot, not a stroke
                    if (held) return;
                    if (popup.visible) popup.hide();
                    else root.turn(mouse.x < width * 0.3 ? -1 : 1);
                }
            }
        }
    }

    // ------------------------------------------------------------ layout: vocabulary

    Item {
        id: vocabView
        visible: root.showVocab && !root.article
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: footer.top }

        DisplayMethodArea { anchors.fill: parent; displayMethod: root.modeContent }

        Item {
            id: vocabArea
            anchors { fill: parent; leftMargin: 56 * u; rightMargin: 56 * u; topMargin: 16 * u }

            Text {
                anchors.centerIn: parent
                width: parent.width - 80 * u
                visible: root.vocabList.length === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.lang === "zh"
                      ? "还没有生词。\n在英文文章里用笔在单词下面划一道，或者用手指长按单词，查过的词会自动收进这里。"
                      : "No words yet.\nUnderline a word with the Marker (or long-press it) in an English article."
                font.pixelSize: 36 * u
                font.family: root.sansFamily
                lineHeight: 1.3
            }

            Column {
                anchors.fill: parent
                Repeater {
                    model: root.vocabList.slice(root.vocabPage * root.vocabPerPage, (root.vocabPage + 1) * root.vocabPerPage)
                    Item {
                        width: parent.width
                        height: vocabArea.height / root.vocabPerPage

                        MouseArea {
                            anchors.fill: parent
                            onClicked: if (modelData.article) root.openArticle(modelData.article)
                        }

                        Column {
                            anchors { left: parent.left; right: del.left; rightMargin: 30 * root.u; verticalCenter: parent.verticalCenter }
                            spacing: 8 * root.u
                            Row {
                                spacing: 22 * root.u
                                Text {
                                    text: modelData.word
                                    font.pixelSize: 50 * root.u
                                    font.family: "Noto Sans"
                                    font.weight: Font.Bold
                                }
                                Text {
                                    anchors.baseline: parent.children[0].baseline
                                    text: modelData.phonetic ? "/" + modelData.phonetic + "/" : ""
                                    font.pixelSize: 30 * root.u
                                    font.family: "Noto Sans"
                                }
                            }
                            Text {
                                width: parent.width
                                text: modelData.meaning || ""
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.pixelSize: 32 * root.u
                                font.family: "Noto Serif SC"
                                font.weight: Font.Medium
                            }
                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: modelData.sentence || ""
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.pixelSize: 30 * root.u
                                font.family: "EB Garamond"
                                font.weight: Font.Medium
                                font.italic: true
                            }
                            Row {
                                spacing: 14 * root.u
                                Rectangle {
                                    visible: !!modelData.article
                                    width: srcTag.implicitWidth + 20 * root.u
                                    height: srcTag.implicitHeight + 6 * root.u
                                    radius: 6 * root.u
                                    color: modelData.article ? root.sourceColor(modelData.article.source) : "black"
                                    Text {
                                        id: srcTag
                                        anchors.centerIn: parent
                                        text: modelData.article ? modelData.article.source : ""
                                        color: "white"
                                        font.pixelSize: 22 * root.u
                                        font.family: root.sansFamily
                                        font.weight: Font.Bold
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: News.timeAgo(modelData.added, root.lang) + (modelData.count > 1 ? (root.lang === "zh" ? " · 查过 " + modelData.count + " 次" : " · looked up " + modelData.count + "×") : "")
                                    font.pixelSize: 24 * root.u
                                    font.family: root.sansFamily
                                    font.weight: Font.Medium
                                }
                            }
                        }

                        Btn {
                            id: del
                            u: root.u
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            fontPx: 28 * root.u
                            implicitHeight: 72 * root.u
                            text: root.lang === "zh" ? "删除" : "Delete"
                            onClicked: root.deleteVocab(modelData.word)
                        }

                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2 * root.u; color: "black" }
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
            dim: root.article ? root.pageIdx === 0 : root.showVocab ? root.vocabPage === 0 : root.listPage === 0
            onClicked: if (byPen || !root.penNear()) root.turn(-1)
        }
        Text {
            anchors.centerIn: parent
            text: root.article
                  ? (root.articleStatus !== "" && body.text !== "" ? root.articleStatus + "    " : "") +
                    (root.pageIdx + 1) + " / " + root.pageStarts.length
                  : root.showVocab ? (root.vocabPage + 1) + " / " + root.vocabPages
                  : (root.listPage + 1) + " / " + root.listPages
            font.pixelSize: 32 * u
            font.family: root.sansFamily
            font.weight: Font.Medium
        }
        Btn {
            u: root.u
            anchors { right: parent.right; rightMargin: 36 * u; verticalCenter: parent.verticalCenter }
            text: root.lang === "zh" ? "下一页 ›" : "Next ›"
            dim: root.article ? root.pageIdx >= root.pageStarts.length - 1
                 : root.showVocab ? root.vocabPage >= root.vocabPages - 1 : root.listPage >= root.listPages - 1
            onClicked: if (byPen || !root.penNear()) root.turn(1)
        }
    }

    // The Marker reports a few hover moves as it approaches the glass: treat that as "pen near"
    // so a palm landing first is already ignored. NoButton lets every press pass through.
    MouseArea {
        anchors.fill: parent
        z: 100
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onPositionChanged: (mouse) => {
            // Qt Quick also emits hover moves while a finger drags; those are not the pen.
            if (mouse.source !== Qt.MouseEventNotSynthesized) return;
            if (touchArea.pressed || Date.now() - root.lastTouchAt < 500) return;
            if (Date.now() - root.lastPenAt > 1000) root.dlog("pen hover " + Math.round(mouse.x) + "," + Math.round(mouse.y));
            root.notePen();
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
        property bool saved: false
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
            saved = false;
            busy = true;
            selTop = header.height + bodyArea.anchors.topMargin + selY;
            visible = true;
            var t = token;
            if (isPhrase) {
                News.translate(text, "en", "zh-CN", function (err, out) {
                    if (t !== popup.token) return;
                    popup.online = out || ("翻译失败：" + err);
                    popup.busy = false;
                    if (out) popup.remember();
                });
                return;
            }
            News.lookup(text, function (e) {
                if (t !== popup.token) return;
                popup.entry = e;
                if (e && (e.translation || e.base)) { popup.busy = false; popup.remember(); return; }
                News.lookupOnline(text, function (err, out) {
                    if (t !== popup.token) return;
                    popup.online = out || "未找到释义";
                    popup.busy = false;
                    if (out) popup.remember();
                });
            });
        }

        // Every lookup goes into the vocabulary list (with its sentence and article).
        function remember() {
            var e = entry;
            var word = isPhrase ? query : (e && e.translation ? e.word : query);
            var meaning = e && e.translation ? e.translation : online;
            if (e && e.base && e.base.translation)
                meaning = (meaning ? meaning + "\n" : "") + "原形 " + e.base.word + "：" + e.base.translation.split("\n")[0];
            var it = root.article ? root.article.item : null;
            News.addVocab({
                word: word,
                phonetic: !isPhrase && e ? (e.phonetic || (e.base ? e.base.phonetic : "")) : "",
                meaning: meaning,
                sentence: sentence,
                article: it ? { id: it.id, title: it.title, source: it.source, link: it.link, time: it.time,
                                hasImage: it.hasImage, cached: it.cached } : null
            });
            root.vocabList = News.vocab.slice();
            saved = true;
        }

        function toggleSaved() {
            if (saved) {
                News.removeVocab(isPhrase ? query : (entry && entry.translation ? entry.word : query));
                root.vocabList = News.vocab.slice();
                saved = false;
            } else {
                remember();
            }
        }

        function hide() {
            token++;
            visible = false;
            body.deselect();
            root.clearSegs("lookup");
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
                Btn {
                    u: root.u
                    visible: !popup.busy
                    text: popup.saved ? "★ 生词本" : "☆ 生词本"
                    checked: popup.saved
                    accent: root.accent
                    onClicked: popup.toggleSaved()
                }
                Btn { u: root.u; text: "关闭"; onClicked: popup.hide() }
            }
        }
    }
}
