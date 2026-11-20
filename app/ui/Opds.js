.pragma library
.import "News.js" as News

// OPDS 1.x (Atom) catalogs: browse, search, and download books into the reMarkable library.
//
// Books land in xochitl's own document folder as ordinary EPUB/PDF documents inside an "OPDS"
// folder, so they open in the system reader. xochitl reads that folder when it starts, so a new
// book shows up in the library after xochitl restarts (triple-tap the power button with
// xovi-tripletap, or reboot).
//
// data/opds.json  { catalogs: [{ name, url, user, pass }], folder: "<uuid>", books: { <entry id>: { uuid, title, at } } }

var DEFAULT_CATALOGS = [
    { name: "Project Gutenberg", url: "https://www.gutenberg.org/ebooks.opds/", builtin: true },
    { name: "Unglue.it", url: "https://unglue.it/api/opds/", builtin: true }
];

var libraryDir = "file:///home/root/.local/share/remarkable/xochitl/";

var state = null;

function stateUrl() { return News.dataDir + "opds.json"; }

function load(cb) {
    if (state) return cb(state);
    News.readJson(stateUrl(), function (v) {
        state = v || {};
        if (!state.catalogs) state.catalogs = [];
        if (!state.books) state.books = {};
        cb(state);
    });
}

function save() { News.put(stateUrl(), JSON.stringify(state)); }

function catalogs() { return DEFAULT_CATALOGS.concat(state ? state.catalogs : []); }

function addCatalog(url, user, pass) {
    url = url.trim();
    if (!/^https?:\/\//i.test(url)) url = "http://" + url;
    var c = { name: url.replace(/^https?:\/\//i, "").replace(/\/.*$/, ""), url: url, user: user || "", pass: pass || "" };
    state.catalogs.push(c);
    save();
    return c;
}

// Change a user catalog's address or login. A new address gets its name from the feed again.
function updateCatalog(c, url, user, pass) {
    url = url.trim();
    if (!/^https?:\/\//i.test(url)) url = "http://" + url;
    if (url !== c.url) {
        c.name = url.replace(/^https?:\/\//i, "").replace(/\/.*$/, "");
        c.named = false;
    }
    c.url = url;
    c.user = user || "";
    c.pass = pass || "";
    save();
    return c;
}

function removeCatalog(c) {
    var i = state.catalogs.indexOf(c);
    if (i >= 0) { state.catalogs.splice(i, 1); save(); }
}

// Give a user catalog the title its feed announces, the first time it loads.
function nameCatalog(c, title) {
    if (!c || c.builtin || !title || c.named) return;
    c.name = title;
    c.named = true;
    save();
}

function isDownloaded(entry) { return !!(state && entry && state.books[entry.id]); }

// ---------------------------------------------------------------- http

function authHeader(cat) {
    return cat && cat.user ? "Basic " + Qt.btoa(cat.user + ":" + (cat.pass || "")) : "";
}

// cb(err, text). Catalogs on a home network (Calibre) often need HTTP basic auth.
function fetchText(url, cat, cb) {
    var xhr = new XMLHttpRequest();
    var done = false;
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE || done) return;
        done = true;
        if (xhr.status >= 200 && xhr.status < 300) cb(null, xhr.responseText);
        else cb(xhr.status === 401 ? "401" : "HTTP " + xhr.status, null);
    };
    try {
        xhr.open("GET", url);
        var a = authHeader(cat);
        if (a) xhr.setRequestHeader("Authorization", a);
        xhr.setRequestHeader("Accept", "application/atom+xml, application/xml;q=0.9, */*;q=0.5");
        xhr.send();
    } catch (e) {
        done = true;
        cb(String(e), null);
    }
}

// ---------------------------------------------------------------- urls

function resolve(base, href) {
    href = News.decodeEntities((href || "").trim());
    if (!href) return "";
    if (/^[a-z][a-z0-9+.\-]*:/i.test(href)) return href;
    var m = /^([a-z][a-z0-9+.\-]*:)\/\/([^\/?#]*)([^?#]*)/i.exec(base);
    if (!m) return href;
    if (href.indexOf("//") === 0) return m[1] + href;
    if (href[0] === "/") return m[1] + "//" + m[2] + href;
    if (href[0] === "?") return m[1] + "//" + m[2] + m[3] + href;
    var dir = m[3].replace(/[^\/]*$/, "") || "/";
    var parts = (dir + href).split("/");
    var out = [];
    for (var i = 0; i < parts.length; i++) {
        if (parts[i] === "..") { if (out.length > 1) out.pop(); }
        else if (parts[i] !== "." || i === parts.length - 1) out.push(parts[i] === "." ? "" : parts[i]);
    }
    return m[1] + "//" + m[2] + out.join("/");
}

// ---------------------------------------------------------------- parsing

function attrs(tag) {
    var a = {}, m;
    var re = /([\w:\-]+)\s*=\s*("([^"]*)"|'([^']*)')/g;
    while ((m = re.exec(tag)) !== null)
        a[m[1].toLowerCase()] = m[3] !== undefined ? m[3] : m[4];
    return a;
}

function links(block) {
    var out = [], m;
    var re = /<link\b([^>]*?)\/?>/gi;
    while ((m = re.exec(block)) !== null) out.push(attrs(m[1]));
    return out;
}

// Atom carries HTML summaries escaped (&lt;p&gt;…): unescape, then strip the tags.
function text(block, name) {
    var raw = News.tag(block, name);
    if (/&lt;/.test(raw)) raw = News.decodeEntities(raw);
    return News.stripTags(raw);
}

var ACQ = "http://opds-spec.org/acquisition";

function isFeedType(t) { return /atom\+xml|opds-catalog/i.test(t || ""); }

function formatOf(type) {
    if (/epub/i.test(type)) return "EPUB";
    if (/pdf/i.test(type)) return "PDF";
    return "";
}

function parseEntry(b, base) {
    var e = {
        id: "",
        title: text(b, "title"),
        author: "",
        summary: "",
        nav: "",
        files: [],          // [{ format, type, url }] best first
        cover: "",
        thumb: ""
    };
    var authors = [], m;
    var re = /<author\b[^>]*>([\s\S]*?)<\/author>/gi;
    while ((m = re.exec(b)) !== null) {
        var n = text(m[1], "name");
        if (n) authors.push(n);
    }
    e.author = authors.join(", ");
    e.summary = text(b, "summary") || text(b, "content");
    var ls = links(b);
    for (var i = 0; i < ls.length; i++) {
        var l = ls[i], rel = l.rel || "", type = l.type || "", href = resolve(base, l.href);
        if (!href) continue;
        if (/opds-spec\.org\/image\/thumbnail/.test(rel)) e.thumb = href;
        else if (/opds-spec\.org\/image$|opds-spec\.org\/cover/.test(rel)) e.cover = href;
        else if (rel.indexOf(ACQ) === 0) {
            // Only what can be fetched directly: no buy / borrow / subscribe.
            if (/\/(buy|borrow|subscribe)$/.test(rel)) continue;
            var f = formatOf(type);
            if (f) e.files.push({ format: f, type: type, url: href, rel: rel });
        } else if (isFeedType(type) && !/alternate|related/.test(rel) && !e.nav) {
            e.nav = href;
        }
    }
    // EPUB first (reflows on the tablet), and among Gutenberg's EPUBs the one with images.
    e.files.sort(function (a, b) {
        var s = function (x) {
            return (x.format === "EPUB" ? 0 : 10) + (/noimages|images=false/i.test(x.url) ? 1 : 0) +
                   (/\/sample$/.test(x.rel) ? 5 : 0);
        };
        return s(a) - s(b);
    });
    // One button per format.
    var seen = {};
    e.files = e.files.filter(function (f) { if (seen[f.format]) return false; seen[f.format] = true; return true; });
    var idText = text(b, "id");
    e.id = News.hashId(idText || e.title + "|" + (e.files.length ? e.files[0].url : e.nav));
    if (!e.thumb) e.thumb = e.cover;
    return e;
}

// { title, entries, next, search, searchType }
function parseFeed(xml, base) {
    var head = xml.replace(/<entry\b[\s\S]*?<\/entry>/gi, "");
    var feed = { title: text(head, "title"), entries: [], next: "", search: "", searchType: "" };
    var ls = links(head);
    for (var i = 0; i < ls.length; i++) {
        var rel = ls[i].rel || "";
        if (rel === "next") feed.next = resolve(base, ls[i].href);
        else if (rel === "search" && !feed.search) {
            feed.search = resolve(base, ls[i].href);
            feed.searchType = ls[i].type || "";
        }
    }
    var m, re = /<entry\b[^>]*>([\s\S]*?)<\/entry>/gi;
    while ((m = re.exec(xml)) !== null) {
        var e = parseEntry(m[1], base);
        if (e.nav || e.files.length) feed.entries.push(e);
    }
    return feed;
}

function looksLikeFeed(t) { return /<feed\b/i.test(t || ""); }

// cb(err, feed)
function openFeed(url, cat, cb) {
    fetchText(url, cat, function (err, t) {
        if (err) return cb(err, null);
        if (!looksLikeFeed(t)) return cb("not an OPDS catalog", null);
        cb(null, parseFeed(t, url));
    });
}

// ---------------------------------------------------------------- search

function fillTemplate(tpl, q) {
    return tpl.replace(/\{searchTerms\??\}/g, encodeURIComponent(q))
              .replace(/\{startPage\??\}/g, "1").replace(/\{startIndex\??\}/g, "")
              .replace(/\{count\??\}/g, "").replace(/\{language\??\}/g, "")
              .replace(/\{[^}]*\?\}/g, "");
}

// cb(err, url of the results feed)
function searchUrl(feed, q, cat, cb) {
    if (!feed || !feed.search) return cb("no search", null);
    if (/\{searchTerms/.test(feed.search)) return cb(null, fillTemplate(feed.search, q));
    // OpenSearch description: pick the Atom template.
    fetchText(feed.search, cat, function (err, t) {
        if (err) return cb(err, null);
        var best = "", m, re = /<Url\b([^>]*)\/?>/gi;
        while ((m = re.exec(t)) !== null) {
            var a = attrs(m[1]);
            if (!a.template) continue;
            if (isFeedType(a.type) || !best) best = a.template;
            if (isFeedType(a.type)) break;
        }
        if (!best) return cb("no search", null);
        cb(null, resolve(feed.search, fillTemplate(best, q)));
    });
}

// ---------------------------------------------------------------- download into the library

function uuid() {
    var h = "0123456789abcdef", s = "";
    for (var i = 0; i < 36; i++) {
        if (i === 8 || i === 13 || i === 18 || i === 23) s += "-";
        else if (i === 14) s += "4";
        else if (i === 19) s += h[8 + Math.floor(Math.random() * 4)];
        else s += h[Math.floor(Math.random() * 16)];
    }
    return s;
}

function putData(url, data) {
    var x = new XMLHttpRequest();
    x.open("PUT", url);
    x.send(data);
}

function metadata(type, name, parent) {
    var now = String(Date.now());
    return JSON.stringify({
        createdTime: now, lastModified: now, lastOpened: "0", lastOpenedPage: 0,
        parent: parent, pinned: false, type: type, visibleName: name,
        deleted: false, metadatamodified: false, modified: false, synced: false, version: 0
    });
}

// The "OPDS" folder in the library; made again if the reader deleted it.
function ensureFolder(cb) {
    var make = function () {
        state.folder = uuid();
        save();
        putData(libraryDir + state.folder + ".metadata", metadata("CollectionType", "OPDS", ""));
        putData(libraryDir + state.folder + ".content", "{}");
        cb(state.folder);
    };
    if (!state.folder) return make();
    News.readJson(libraryDir + state.folder + ".metadata", function (md) {
        if (!md || md.deleted || md.parent === "trash") make();
        else cb(state.folder);
    });
}

function magic(buf) {
    var b = new Uint8Array(buf, 0, Math.min(4, buf.byteLength));
    if (b[0] === 0x50 && b[1] === 0x4B) return "epub";           // PK: a zip, i.e. EPUB
    if (b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46) return "pdf";   // %PDF
    return "";
}

// cb(err, { uuid, fileType })
function download(entry, file, cat, cb) {
    var xhr = new XMLHttpRequest();
    xhr.responseType = "arraybuffer";
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        var buf = xhr.response;
        if (xhr.status !== 200 || !buf || buf.byteLength < 100)
            return cb(xhr.status === 401 ? "401" : "HTTP " + xhr.status, null);
        var kind = magic(buf);
        if (!kind) return cb("not an EPUB or PDF file", null);
        ensureFolder(function (folder) {
            var id = uuid();
            try {
                putData(libraryDir + id + "." + kind, buf);
                putData(libraryDir + id + ".content", JSON.stringify({ fileType: kind }));
                // Metadata last: xochitl only lists documents that have it.
                putData(libraryDir + id + ".metadata", metadata("DocumentType", entry.title || "Untitled", folder));
            } catch (e) {
                return cb(String(e), null);
            }
            state.books[entry.id] = { uuid: id, title: entry.title, at: Date.now() };
            save();
            cb(null, { uuid: id, fileType: kind });
        });
    };
    try {
        xhr.open("GET", file.url);
        var a = authHeader(cat);
        if (a) xhr.setRequestHeader("Authorization", a);
        xhr.send();
    } catch (e) {
        cb(String(e), null);
    }
}
