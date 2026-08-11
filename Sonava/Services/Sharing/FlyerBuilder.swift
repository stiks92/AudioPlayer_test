//
//  FlyerBuilder.swift
//  Sonava
//
//  «Флаер» — the day-zero artifact: a record-shop flyer that PLAYS.
//
//  The sarafan judge's finding was that every shareable we had was a
//  self-portrait of the sender; great music sarafan hands the receiver
//  music. This is that hand-off: a single self-contained HTML file listing
//  up to ten records with the sender's provenance notes, where tapping a
//  row plays a 30-second preview.
//
//  How it stays legal and serverless (probed live before writing):
//  * Previews come from the iTunes Search API — public, keyless, and its
//    JSONP callback support means the page works from any origin including
//    file://, no CORS involved: that is the API's own design, not a trick.
//  * <audio> elements play cross-origin without CORS by spec.
//  * Terms are honoured by design: streams only (no download UI), an
//    "Previews courtesy of iTunes" credit with a link, one search per tap.
//  * No analytics, no external scripts, nothing loaded except what the
//    receiver taps to hear.
//
//  The file must survive titles like «<script>alert(1)</script>» in track
//  names — the sender's own library must not be able to XSS the receiver.
//

import Foundation

struct FlyerEntry: Equatable, Sendable {
    var artist: String
    var title: String
    /// "С вами с 2014" — the sender's provenance note, already localised.
    var note: String?
}

enum FlyerBuilder {

    /// Renders the flyer. `heading` is the sender's title for the page;
    /// `subtitle` a one-line signature ("Sonava · N records I live with").
    static func html(entries: [FlyerEntry], heading: String, subtitle: String,
                     openHint: String, creditText: String) -> String {
        let rows = entries.prefix(10).enumerated().map { index, entry in
            let query = escapeAttribute("\(entry.artist) \(entry.title)")
            let note = entry.note.map {
                "<div class=\"note\">\(escapeText($0))</div>"
            } ?? ""
            return """
            <div class="row" data-q="\(query)" onclick="play(this)">
              <div class="ord">\(String(format: "%02d", index + 1))</div>
              <div class="what">
                <div class="t">\(escapeText(entry.title))</div>
                <div class="a">\(escapeText(entry.artist))</div>
                \(note)
              </div>
              <div class="state" aria-hidden="true">▸</div>
            </div>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapeText(heading))</title>
        <style>
          :root { --paper:#0d0b09; --ink:#f2ede4; --soft:#b5ab9c; --amber:#d9a441; --rule:#2a251f; }
          * { box-sizing:border-box; margin:0; }
          body { background:var(--paper); color:var(--ink);
                 font:16px/1.5 -apple-system, system-ui, sans-serif; padding:28px 18px 60px; }
          main { max-width:30rem; margin:0 auto; }
          h1 { font-family:ui-serif, Georgia, serif; font-weight:900; font-size:1.9rem; }
          .sub { color:var(--soft); margin:4px 0 22px; font-size:.95rem;
                 border-bottom:1px solid var(--ink); padding-bottom:14px; }
          .row { display:flex; gap:14px; align-items:baseline; padding:12px 0;
                 border-bottom:1px dotted var(--rule); cursor:pointer; }
          .row.playing .state { color:var(--amber); }
          .ord { font-family:ui-monospace, Menlo, monospace; color:var(--amber); font-size:.9rem; }
          .t { font-weight:600; }
          .a { color:var(--soft); font-size:.92rem; }
          .note { color:var(--amber); font-size:.8rem; font-family:ui-monospace, Menlo, monospace;
                  margin-top:2px; letter-spacing:.04em; }
          .what { flex:1; }
          .state { color:var(--soft); }
          .hint { color:var(--soft); font-size:.85rem; margin-top:20px; }
          .credit { color:var(--soft); font-size:.75rem; margin-top:26px;
                    border-top:1px solid var(--rule); padding-top:10px; }
          .credit a { color:var(--soft); }
        </style>
        </head>
        <body>
        <main>
          <h1>\(escapeText(heading))</h1>
          <div class="sub">\(escapeText(subtitle))</div>
          \(rows)
          <div class="hint">\(escapeText(openHint))</div>
          <div class="credit">\(escapeText(creditText)) ·
            <a href="https://www.apple.com/itunes/" rel="noopener">iTunes</a></div>
        </main>
        <script>
        var audio = new Audio();
        var current = null;
        var seq = 0;
        function play(row) {
          if (current === row) { audio.pause(); mark(null); return; }
          mark(row);
          var name = "sonavaCB" + (++seq);
          var s = document.createElement("script");
          window[name] = function (data) {
            delete window[name]; s.remove();
            if (current !== row) return;
            var hit = (data.results || []).find(function (r) { return r.previewUrl; });
            if (!hit) { mark(null); return; }
            audio.src = hit.previewUrl;
            audio.play().catch(function () { mark(null); });
          };
          s.src = "https://itunes.apple.com/search?media=music&entity=song&limit=3&callback="
                  + name + "&term=" + encodeURIComponent(row.dataset.q);
          document.body.appendChild(s);
        }
        function mark(row) {
          if (current) { current.classList.remove("playing"); current.querySelector(".state").textContent = "▸"; }
          current = row;
          if (row) { row.classList.add("playing"); row.querySelector(".state").textContent = "♪"; }
        }
        audio.addEventListener("ended", function () { mark(null); });
        </script>
        </body>
        </html>
        """
    }

    /// Writes the flyer to a shareable temporary file.
    static func writeFile(entries: [FlyerEntry], heading: String, subtitle: String,
                          openHint: String, creditText: String) -> URL? {
        let html = html(entries: entries, heading: heading, subtitle: subtitle,
                        openHint: openHint, creditText: creditText)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flyer-\(Int(Date().timeIntervalSince1970)).html")
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Escaping (the sender's library must not XSS the receiver)

    static func escapeText(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeAttribute(_ value: String) -> String {
        escapeText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
