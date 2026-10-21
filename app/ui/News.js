.pragma library
.import "T2S.js" as T2S

// ---------------------------------------------------------------- sources

// Colors are saturated on purpose: Gallery 3 mutes everything, pastel tones turn to grey.
var SOURCES = {
    en: [
        { key: "bbc-world", name: "BBC World",    color: "#C62828", url: "https://feeds.bbci.co.uk/news/world/rss.xml" },
        { key: "bbc-tech",  name: "BBC Tech",     color: "#6A1B9A", url: "https://feeds.bbci.co.uk/news/technology/rss.xml" },
        { key: "bbc-biz",   name: "BBC Business", color: "#2E7D32", url: "https://feeds.bbci.co.uk/news/business/rss.xml" },
        { key: "guardian",  name: "Guardian",     color: "#0D47A1", url: "https://www.theguardian.com/world/rss" },
        { key: "npr",       name: "NPR",          color: "#1E88E5", url: "https://feeds.npr.org/1001/rss.xml" },
        { key: "aljazeera", name: "Al Jazeera",   color: "#EF6C00", url: "https://www.aljazeera.com/xml/rss/all.xml" }
    ],
    zh: [
        // This feed's titles come in traditional script even on the "simp" URL.
        { key: "bbc-zh",    name: "BBC 中文",     color: "#C62828", url: "https://feeds.bbci.co.uk/zhongwen/simp/rss.xml", t2s: true },
        { key: "dw-zh",     name: "德国之声",     color: "#0277BD", url: "https://rss.dw.com/rdf/rss-chi-all" },
        { key: "nyt-zh",    name: "纽约时报中文", color: "#212121", url: "https://cn.nytimes.com/rss/" },
        { key: "ifanr",     name: "爱范儿",       color: "#D81B60", url: "https://www.ifanr.com/feed" }
    ]
};

var MAX_ITEMS = 30;          // per source and update
var dataDir = "file:///home/root/.local/share/rmnews/";

// ---------------------------------------------------------------- http

function request(method, url, body, cb) {
    var xhr = new XMLHttpRequest();
    var done = false;
    function finish(err, text) {
        if (done) return;
        done = true;
        cb(err, text);
    }
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        // file:// reads report status 0 on success.
        if ((xhr.status >= 200 && xhr.status < 300) || (xhr.status === 0 && xhr.responseText))
            finish(null, xhr.responseText);
        else
            finish("HTTP " + xhr.status, null);
    };
    try {
        xhr.open(method, url);
        if (body !== null)
            xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded;charset=UTF-8");
        xhr.send(body);
    } catch (e) {
        finish(String(e), null);
    }
    return xhr;
}

function get(url, cb) { return request("GET", url, null, cb); }

// ---------------------------------------------------------------- text helpers

var ENTITIES = {
    amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " ", ndash: "–", mdash: "—",
    lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”", hellip: "…", middot: "·", bull: "•",
    copy: "©", reg: "®", trade: "™", eacute: "é", egrave: "è", aacute: "á", oacute: "ó",
    iacute: "í", uacute: "ú", ntilde: "ñ", ccedil: "ç", uuml: "ü", ouml: "ö", auml: "ä",
    laquo: "«", raquo: "»", times: "×", euro: "€", pound: "£", deg: "°", shy: ""
};

function decodeEntities(s) {
    return s.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g, function (m, e) {
        if (e[0] === "#") {
            var code = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
            return isNaN(code) ? m : String.fromCodePoint(code);
        }
        return ENTITIES.hasOwnProperty(e) ? ENTITIES[e] : m;
    });
}

function stripTags(s) {
    return decodeEntities(s.replace(/<br\s*\/?>/gi, " ").replace(/<[^>]+>/g, ""))
        .replace(/\s+/g, " ").trim();
}

function unCdata(s) {
    var m = /^\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*$/.exec(s);
    return m ? m[1] : s;
}

function escapeHtml(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function hasCjk(s) { return /[一-鿿]/.test(s); }

// ---------------------------------------------------------------- feeds

function tag(block, name) {
    var re = new RegExp("<" + name + "(?:\\s[^>]*)?>([\\s\\S]*?)</" + name + ">", "i");
    var m = re.exec(block);
    return m ? unCdata(m[1]) : "";
}

function parseFeed(xml) {
    var items = [];
    var re = /<(item|entry)(?:\s[^>]*)?>([\s\S]*?)<\/\1>/gi;
    var m;
    while ((m = re.exec(xml)) !== null) {
        var b = m[2];
        var link = tag(b, "link").trim();
        if (!link) {
            var lm = /<link[^>]*href="([^"]+)"/i.exec(b);
            if (lm) link = lm[1];
        }
        link = decodeEntities(link.trim());
        var summary = tag(b, "description") || tag(b, "summary") || tag(b, "content:encoded");
        var content = tag(b, "content:encoded");
        var date = tag(b, "pubDate") || tag(b, "dc:date") || tag(b, "updated") || tag(b, "published");
        items.push({
            id: hashId(link),
            image: feedImage(b),
            title: stripTags(tag(b, "title")),
            link: link,
            summary: stripTags(summary).replace(/#?欢迎关注[\s\S]*$/, "").trim(),
            content: content,
            date: date.trim(),
            time: parseDate(date.trim())
        });
    }
    return items;
}

function hashId(s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
        h ^= s.charCodeAt(i);
        h = (h * 16777619) >>> 0;
    }
    return ("0000000" + h.toString(16)).slice(-8);
}

// Largest picture an RSS item advertises, if any.
function feedImage(b) {
    var best = "", bestW = -1, m;
    var re = /<(?:media:content|media:thumbnail|enclosure)\b([^>]*)>/gi;
    while ((m = re.exec(b)) !== null) {
        var u = /url="([^"]+)"/i.exec(m[1]);
        if (!u || /type="(?!image)/i.test(m[1])) continue;
        var w = /width="(\d+)"/i.exec(m[1]);
        var wv = w ? +w[1] : 0;
        if (wv > bestW) { best = decodeEntities(u[1]); bestW = wv; }
    }
    if (!best) {
        var img = /<img[^>]*src="([^"]+)"/i.exec(unCdata(b));
        if (img) best = decodeEntities(img[1]);
    }
    // BBC serves 240px thumbnails in RSS; the same path exists at 800px.
    return best.replace(/(ichef\.bbci\.co\.uk\/(?:ace\/)?(?:standard|ws)\/)240\//, "$1800/");
}

var MONTHS = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };

function parseDate(s) {
    if (!s) return 0;
    var t = Date.parse(s);
    if (!isNaN(t)) return t;
    // RFC 822: "Tue, 20 Oct 2026 10:00:00 GMT" / "+0800"
    var m = /(\d{1,2})\s+([A-Za-z]{3})\w*\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Z]{1,4})?/.exec(s);
    if (!m) return 0;
    var utc = Date.UTC(+m[3], MONTHS[m[2].toLowerCase()] || 0, +m[1], +m[4], +m[5], +(m[6] || 0));
    var tz = m[7] || "GMT";
    if (/^[+-]\d{4}$/.test(tz)) {
        var mins = (+tz.slice(1, 3)) * 60 + (+tz.slice(3, 5));
        utc -= (tz[0] === "+" ? 1 : -1) * mins * 60000;
    }
    return utc;
}

function timeAgo(t, lang) {
    if (!t) return "";
    var d = (Date.now() - t) / 60000;
    if (d < 1) d = 1;
    if (lang === "zh") {
        if (d < 60) return Math.round(d) + " 分钟前";
        if (d < 1440) return Math.round(d / 60) + " 小时前";
        return Math.round(d / 1440) + " 天前";
    }
    if (d < 60) return Math.round(d) + "m ago";
    if (d < 1440) return Math.round(d / 60) + "h ago";
    return Math.round(d / 1440) + "d ago";
}

function fetchFeed(src, cb) {
    get(src.url, function (err, text) {
        if (err) return cb(err, []);
        var items = parseFeed(text);
        for (var i = 0; i < items.length; i++) {
            items[i].source = src.name;
            if (src.t2s) {
                items[i].title = T2S.convert(items[i].title);
                items[i].summary = T2S.convert(items[i].summary);
            }
            // BBC Chinese links point at the traditional-script page by default.
            if (items[i].link.indexOf("/zhongwen/") >= 0)
                items[i].link = items[i].link.replace("/trad", "/simp");
        }
        cb(null, items);
    });
}

// ---------------------------------------------------------------- article extraction

var JUNK = [
    /^(Your support helps|This article first appeared|Sign up|Subscribe|Advertisement|Follow us|Read more|Related:|Share this|NPR does not offer|To view this video)/i,
    /^(We use cookies|我们利用cookies|通过在此处点击|自20\d\d年|免费下载|点击查看本文英文版|翻译：|#?欢迎关注|本文原以英文撰写|DW中文有)/,
    /^(©|Copyright)/i
];

function isJunk(t) {
    for (var i = 0; i < JUNK.length; i++)
        if (JUNK[i].test(t)) return true;
    return false;
}

function findArticleBody(obj) {
    if (!obj || typeof obj !== "object") return "";
    if (Array.isArray(obj)) {
        for (var i = 0; i < obj.length; i++) {
            var r = findArticleBody(obj[i]);
            if (r) return r;
        }
        return "";
    }
    if (typeof obj.articleBody === "string") return obj.articleBody;
    if (obj["@graph"]) return findArticleBody(obj["@graph"]);
    return "";
}

function paragraphsFrom(html, minLen) {
    var out = [];
    var re = /<p\b([^>]*)>([\s\S]*?)<\/p>/gi;
    var m;
    while ((m = re.exec(html)) !== null) {
        // Skip "related story" teasers: promo/headline-styled paragraphs or a lone link.
        if (/class="[^"]*(promo|headline|teaser|related|caption|byline)/i.test(m[1])) continue;
        if (/^\s*<a\b[^>]*>(?:(?!<\/a>)[\s\S])*<\/a>\s*$/i.test(m[2])) continue;
        var t = stripTags(m[2]);
        var cjk = hasCjk(t);
        if ((t.length >= minLen || (cjk && t.length >= 12)) && !isJunk(t))
            out.push(t);
    }
    return out;
}

function ogImage(html) {
    var m = /<meta[^>]+property="og:image"[^>]+content="([^"]+)"/i.exec(html) ||
            /<meta[^>]+content="([^"]+)"[^>]+property="og:image"/i.exec(html);
    return m ? decodeEntities(m[1]) : "";
}

function extractArticle(html) {
    // 1. JSON-LD articleBody (clean, used by many publishers).
    var ld = /<script[^>]*application\/ld\+json[^>]*>([\s\S]*?)<\/script>/gi;
    var m;
    while ((m = ld.exec(html)) !== null) {
        try {
            var body = findArticleBody(JSON.parse(m[1]));
            if (body && body.length > 400) {
                var ps = decodeEntities(body).split(/\n+/).map(function (s) { return s.trim(); })
                    .filter(function (s) { return s.length > 0 && !isJunk(s); });
                if (ps.length > 1) return ps;
            }
        } catch (e) { }
    }
    // 2. <p> tags inside <article>/<main>.
    var h = html.replace(/<(script|style|noscript|figure|figcaption|nav|footer|header|aside|form|svg|button)\b[\s\S]*?<\/\1>/gi, "");
    var scope = /<article\b[\s\S]*<\/article>/i.exec(h) || /<main\b[\s\S]*<\/main>/i.exec(h);
    var ps2 = paragraphsFrom(scope ? scope[0] : h, 25);
    if (scope && ps2.join("").length < 300)
        ps2 = paragraphsFrom(h, 25);
    // 3. Sites that put body text in <div class="...paragraph...">.
    if (ps2.join("").length < 300) {
        var re = /<div[^>]*class="[^"]*paragraph[^"]*"[^>]*>([\s\S]*?)<\/div>/gi;
        var alt = [];
        while ((m = re.exec(h)) !== null) {
            var t = stripTags(m[1]);
            if (t.length >= 12 && !isJunk(t)) alt.push(t);
        }
        if (alt.join("").length > ps2.join("").length) ps2 = alt;
    }
    return ps2;
}

// Drop trailing "related story" links: short lines without closing punctuation.
function trimTail(ps) {
    while (ps.length > 3) {
        var last = ps[ps.length - 1];
        if (last.length < 140 && !/[.!?"”’'):;。！？」』）…]$/.test(last)) ps.pop();
        else break;
    }
    return ps;
}

// cb(err, { paras, summaryOnly, image })
function fetchArticle(item, cb) {
    var fromFeed = item.content ? paragraphsFrom(item.content, 1) : [];
    get(item.link, function (err, html) {
        var ps = err ? [] : extractArticle(html);
        if (fromFeed.join("").length > ps.join("").length) ps = fromFeed;
        ps = trimTail(ps);
        var summaryOnly = ps.join("").length < 200;
        if (summaryOnly) ps = item.summary ? [item.summary] : [];
        var og = err ? "" : ogImage(html);
        // RSS pictures are signed/sized for us; og:image is the fallback.
        cb(err && !ps.length ? err : null, { paras: ps, summaryOnly: summaryOnly, image: item.image || og });
    });
}

// ---------------------------------------------------------------- offline cache
// cache/feed-<source key>.json   { updated, items: [...] }   (items carry hasImage)
// cache/art-<id>.json            { paras, summaryOnly, trans }
// cache/img-<id>.jpg

function cacheUrl(name) { return dataDir + "cache/" + name; }
function imageUrl(id) { return cacheUrl("img-" + id + ".jpg"); }

function readJson(url, cb) {
    get(url, function (err, text) {
        var v = null;
        if (!err) { try { v = JSON.parse(text); } catch (e) { } }
        cb(v);
    });
}

function loadFeedCache(src, cb) { readJson(cacheUrl("feed-" + src.key + ".json"), cb); }
function saveFeedCache(src, data) { put(cacheUrl("feed-" + src.key + ".json"), JSON.stringify(data)); }
function loadArticleCache(id, cb) { readJson(cacheUrl("art-" + id + ".json"), cb); }
function saveArticleCache(id, art) { put(cacheUrl("art-" + id + ".json"), JSON.stringify(art)); }

// Download a JPEG/PNG/GIF into the cache (the tablet's Qt has no WebP decoder).
function downloadImage(url, id, cb) {
    if (!url || /\.webp(\?|$)/i.test(url)) return cb(false);
    var xhr = new XMLHttpRequest();
    xhr.responseType = "arraybuffer";
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        var type = xhr.getResponseHeader("Content-Type") || "";
        var buf = xhr.response;
        if (xhr.status !== 200 || !buf || buf.byteLength < 500 || /webp|avif/i.test(type)) return cb(false);
        try {
            var w = new XMLHttpRequest();
            w.open("PUT", imageUrl(id));
            w.send(buf);
            cb(true);
        } catch (e) { cb(false); }
    };
    try { xhr.open("GET", url); xhr.send(); } catch (e) { cb(false); }
}

// Fetch one source's feed plus every article and picture not yet cached.
// progress(done, total); cb(err, data)
function syncSource(src, progress, cb) {
    loadFeedCache(src, function (old) {
        var known = {};
        if (old) old.items.forEach(function (it) { if (it.cached) known[it.id] = it; });
        fetchFeed(src, function (err, items) {
            if (err || !items.length) return cb(err || "empty", old);
            items = items.slice(0, MAX_ITEMS);
            var todo = [];
            items.forEach(function (it) {
                var k = known[it.id];
                if (k) { it.cached = true; it.hasImage = k.hasImage; delete it.content; }
                else todo.push(it);
            });
            var next = 0, done = 0;
            function finish() {
                var data = { updated: Date.now(), items: items };
                saveFeedCache(src, data);
                cb(null, data);
            }
            function worker() {
                if (next >= todo.length) return;
                var it = todo[next++];
                fetchArticle(it, function (e, art) {
                    delete it.content;
                    if (!e && art.paras.length) {
                        saveArticleCache(it.id, { paras: art.paras, summaryOnly: art.summaryOnly, trans: [] });
                        it.cached = true;
                    }
                    downloadImage(art ? art.image : "", it.id, function (ok) {
                        it.hasImage = ok;
                        done++;
                        progress(done, todo.length);
                        if (done === todo.length) finish(); else worker();
                    });
                });
            }
            if (!todo.length) return finish();
            for (var w = 0; w < 4; w++) worker();
        });
    });
}

// ---------------------------------------------------------------- translation

function translate(text, sl, tl, cb) {
    var url = "https://translate.googleapis.com/translate_a/single?client=gtx&dt=t&sl=" + sl + "&tl=" + tl;
    request("POST", url, "q=" + encodeURIComponent(text), function (err, body) {
        if (!err) {
            try {
                var j = JSON.parse(body);
                var out = "";
                for (var i = 0; i < j[0].length; i++)
                    if (j[0][i][0]) out += j[0][i][0];
                if (out) return cb(null, out);
            } catch (e) { }
        }
        // Fallback: MyMemory (no key, 500 chars per request).
        var mm = "https://api.mymemory.translated.net/get?langpair=" + sl + "|" + (tl === "zh-CN" ? "zh-CN" : tl) +
                 "&q=" + encodeURIComponent(text.slice(0, 480));
        get(mm, function (err2, body2) {
            if (err2) return cb(err || err2, null);
            try { cb(null, decodeEntities(JSON.parse(body2).responseData.translatedText)); }
            catch (e2) { cb("翻译失败", null); }
        });
    });
}

// Online dictionary lookup for words the offline dictionary doesn't have.
function lookupOnline(word, cb) {
    var url = "https://translate.googleapis.com/translate_a/single?client=gtx&dt=t&dt=bd&sl=en&tl=zh-CN&q=" +
              encodeURIComponent(word);
    get(url, function (err, body) {
        if (err) return cb(err, null);
        try {
            var j = JSON.parse(body);
            var lines = [];
            if (j[1]) for (var i = 0; i < j[1].length; i++)
                lines.push(j[1][i][0] + ". " + j[1][i][1].slice(0, 6).join(", "));
            if (!lines.length && j[0] && j[0][0]) lines.push(j[0][0][0]);
            cb(null, lines.join("\n"));
        } catch (e) { cb("查询失败", null); }
    });
}

// ---------------------------------------------------------------- offline dictionary

var dictBase = "file:///home/root/xovi/exthome/appload/rmnews/dict/";
var shards = {};

function shardKey(w) {
    var k = w.toLowerCase().slice(0, 2);
    return /^[a-z]{1,2}$/.test(k) ? k : "_";
}

function loadShard(key, cb) {
    if (shards.hasOwnProperty(key)) return cb(shards[key]);
    get(dictBase + key + ".json", function (err, text) {
        var d = {};
        if (!err) { try { d = JSON.parse(text); } catch (e) { } }
        shards[key] = d;
        cb(d);
    });
}

function rawEntry(word, cb) {
    loadShard(shardKey(word), function (d) {
        var e = d[word] || d[word.toLowerCase()] ||
                (word.length > 1 ? d[word[0].toUpperCase() + word.slice(1).toLowerCase()] : null);
        cb(e ? { word: d[word] ? word : (d[word.toLowerCase()] ? word.toLowerCase() : word),
                 phonetic: e[0] || "", translation: e[1] || "", lemma: e[2] || "", tags: e[3] || "" } : null);
    });
}

// Candidate base forms for words missing from the dictionary.
function guesses(w) {
    var g = [];
    var rules = [[/ies$/, "y"], [/es$/, ""], [/s$/, ""], [/ied$/, "y"], [/ed$/, ""], [/ed$/, "e"],
                 [/ing$/, ""], [/ing$/, "e"], [/([a-z])\1ing$/, "$1"], [/([a-z])\1ed$/, "$1"],
                 [/ier$/, "y"], [/iest$/, "y"], [/er$/, ""], [/est$/, ""], [/'s$/, ""], [/s'$/, ""]];
    for (var i = 0; i < rules.length; i++)
        if (rules[i][0].test(w)) g.push(w.replace(rules[i][0], rules[i][1]));
    return g;
}

// cb({word, phonetic, translation, tags, base: {...} | null} | null)
function lookup(word, cb) {
    word = word.replace(/[’‘]/g, "'").replace(/^'+|'+$/g, "");
    rawEntry(word, function (e) {
        if (e && e.translation) {
            if (e.lemma && e.lemma !== e.word)
                return rawEntry(e.lemma, function (b) { e.base = b; cb(e); });
            return cb(e);
        }
        if (e && e.lemma)
            return rawEntry(e.lemma, function (b) { cb(b ? { word: word, phonetic: "", translation: "",
                                                              tags: "", base: b } : null); });
        var gs = guesses(word.toLowerCase());
        (function tryNext(i) {
            if (i >= gs.length) return cb(null);
            rawEntry(gs[i], function (b) {
                if (b && b.translation) cb({ word: word, phonetic: "", translation: "", tags: "", base: b });
                else tryNext(i + 1);
            });
        })(0);
    });
}

// ---------------------------------------------------------------- annotations
// cache/note-<id>.json  { hl: [{ k, i, s, e }], ink: [{ k, i, w, pts: [[x, dy], ...] }] }
// k/i name the block an annotation belongs to ("p" = paragraph i, "t" = its translation,
// "b" = other block i), so marks follow their paragraph when the layout changes.

function loadNotes(id, cb) {
    readJson(cacheUrl("note-" + id + ".json"), function (v) { cb(v || { hl: [], ink: [] }); });
}

function saveNotes(id, notes) { put(cacheUrl("note-" + id + ".json"), JSON.stringify(notes)); }

// ---------------------------------------------------------------- vocabulary
// vocab.json is the list (newest first); vocab.tsv is rewritten alongside for Anki import.

var vocab = null;

function loadVocab(cb) {
    if (vocab) return cb(vocab);
    readJson(dataDir + "vocab.json", function (v) {
        vocab = v || [];
        cb(vocab);
    });
}

function vocabIndex(word) {
    if (!vocab) return -1;
    var w = word.toLowerCase();
    for (var i = 0; i < vocab.length; i++) if (vocab[i].word.toLowerCase() === w) return i;
    return -1;
}

function inVocab(word) { return vocabIndex(word) >= 0; }

// entry: { word, phonetic, meaning, sentence, article: { id, title, source, link, time, hasImage } }
function addVocab(entry) {
    var i = vocabIndex(entry.word);
    if (i >= 0) {
        var old = vocab.splice(i, 1)[0];
        entry.count = (old.count || 1) + 1;
        if (!entry.sentence) entry.sentence = old.sentence;
    } else {
        entry.count = 1;
    }
    entry.added = Date.now();
    vocab.unshift(entry);
    saveVocab();
}

function removeVocab(word) {
    var i = vocabIndex(word);
    if (i >= 0) { vocab.splice(i, 1); saveVocab(); }
}

function saveVocab() {
    put(dataDir + "vocab.json", JSON.stringify(vocab));
    var clean = function (s) { return (s || "").replace(/\t/g, " ").replace(/\n/g, "<br>"); };
    var lines = vocab.map(function (v) {
        return [v.word, v.phonetic ? "/" + v.phonetic + "/" : "", clean(v.meaning), clean(v.sentence),
                v.article ? clean(v.article.source + " · " + v.article.title) : ""].join("\t");
    });
    put(dataDir + "vocab.tsv", lines.join("\n") + "\n");
}

// ---------------------------------------------------------------- persistence

function loadState(cb) {
    get(dataDir + "state.json", function (err, text) {
        var s = {};
        if (!err) { try { s = JSON.parse(text); } catch (e) { } }
        cb(s);
    });
}

function put(url, text) {
    try {
        var xhr = new XMLHttpRequest();
        xhr.open("PUT", url);
        xhr.send(text);
    } catch (e) { }
}

function saveState(s) { put(dataDir + "state.json", JSON.stringify(s)); }
