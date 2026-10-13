import Foundation

/// Files for a computer or CAD, generated from a (corrected) RoomPlan document.
/// Plan coordinates: CAD X = world x, CAD Y = −world z (seen from above), metres.
enum RoomExport {
    struct Labels {
        var title = "Room"
        var wall = "Wall", door = "Door", window = "Window", opening = "Opening", stairs = "Stairs"
        var floorArea = "Floor area", grossWall = "Gross wall area", netWall = "Net wall area", height = "Room height"
        var width = "Width", heightShort = "Height", plan = "Floor plan", model = "3D", dimensions = "Dimensions"
        var note = "Values from automatic detection. Check important dimensions on site."
        var language = "en"
        var markers = "Markers", furniture = "Furniture", photos = "Photos", assignee = "Responsible"
        var kinds = ["defect": "Defect", "question": "Question", "idea": "Idea", "measure": "To measure"]
        var open = "open", done = "done"
    }

    /// Photo-textured wall/floor tiles for the HTML 3D view, in plan coordinates
    /// (x, y = −z, height above the floor) with texture coordinates.
    struct PhotoTiles { var tiles: [[Double]] = []; var images: [Data] = [] }

    static func photoTiles(_ mesh: RoomPhotoMesh, floorY: Double, images: [Int: Data]) -> PhotoTiles {
        var result = PhotoTiles()
        var slot: [Int: Int] = [:]
        for bucket in mesh.buckets {
            guard let photo = bucket.photoIndex, let data = images[photo] else { continue }
            let index: Int
            if let existing = slot[photo] { index = existing } else {
                result.images.append(data)
                index = result.images.count - 1
                slot[photo] = index
            }
            for t in 0..<bucket.tiles {
                var row = [Double(index)]
                for corner in 0..<4 {
                    let v = t * 4 + corner
                    let x = bucket.positions[v * 3], y = bucket.positions[v * 3 + 1], z = bucket.positions[v * 3 + 2]
                    row += [x, -z, y - floorY, bucket.uvs[v * 2], bucket.uvs[v * 2 + 1]]
                }
                result.tiles.append(row.map { ($0 * 1000).rounded() / 1000 })
            }
        }
        return result
    }

    struct PlanWall { let id: String; let a: (Double, Double); let b: (Double, Double); let height: Double; let length: Double }
    struct PlanOpening { let kind: String; let a: (Double, Double); let b: (Double, Double); let width: Double; let height: Double; let bottom: Double; let top: Double; let wall: Int }

    /// Walls (bottom edges) and their openings projected onto the floor plan.
    static func plan(_ document: RoomPlanDocument) -> (walls: [PlanWall], openings: [PlanOpening], floors: [[(Double, Double)]], floorY: Double) {
        let surfaces = document.surfaces
        let walls = surfaces.filter { $0.kind == "wall" && $0.transform.count == 16 && $0.dimensions.count == 3 }
        func p(_ point: RoomPlanGeometry.Point) -> (Double, Double) { (point.x, -point.z) }
        let floors = surfaces.filter { $0.kind == "floor" && $0.polygonCorners != nil && $0.transform.count == 16 }
        let floorPoints = floors.flatMap { f in f.polygonCorners!.map { RoomPlanGeometry.world($0, f.transform) } }
        let floorY = floorPoints.isEmpty ? (walls.map { RoomPlanGeometry.world([0, -$0.dimensions[1] / 2, 0], $0.transform).y }.min() ?? 0) : floorPoints.map { $0.y }.reduce(0, +) / Double(floorPoints.count)
        let byWall = RoomPlanGeometry.openingsByWall(surfaces)
        var planWalls: [PlanWall] = [], planOpenings: [PlanOpening] = []
        for (index, wall) in walls.enumerated() {
            let w = wall.dimensions[0], h = wall.dimensions[1]
            planWalls.append(PlanWall(id: wall.id, a: p(RoomPlanGeometry.world([-w / 2, -h / 2, 0], wall.transform)), b: p(RoomPlanGeometry.world([w / 2, -h / 2, 0], wall.transform)), height: h, length: w))
            for o in byWall[wall.id] ?? [] {
                let bottom = RoomPlanGeometry.world([0, o.y0, 0], wall.transform).y - floorY, top = RoomPlanGeometry.world([0, o.y1, 0], wall.transform).y - floorY
                planOpenings.append(PlanOpening(kind: o.kind, a: p(RoomPlanGeometry.world([o.x0, -h / 2, 0], wall.transform)), b: p(RoomPlanGeometry.world([o.x1, -h / 2, 0], wall.transform)),
                                                width: o.x1 - o.x0, height: o.y1 - o.y0, bottom: bottom, top: top, wall: index))
            }
        }
        let outlines = floors.map { f in f.polygonCorners!.map { p(RoomPlanGeometry.world($0, f.transform)) } }
        return (planWalls, planOpenings, outlines, floorY)
    }

    // MARK: DXF

    /// AutoCAD R12 ASCII DXF in metres ($INSUNITS = 6). Layers: KANTURA_WALLS
    /// (bottom wall lines), KANTURA_OPENINGS, KANTURA_FLOOR (closed outline),
    /// KANTURA_DIMENSIONS (text with lengths). Lines, not associative dimensions.
    static func dxf(_ document: RoomPlanDocument, labels: Labels = Labels(), extras: RoomExtras = RoomExtras()) -> String {
        let plan = plan(document)
        var out = "0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1009\n9\n$INSUNITS\n70\n6\n0\nENDSEC\n"
        out += "0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLAYER\n70\n4\n"
        for (name, color) in [("KANTURA_WALLS", 7), ("KANTURA_OPENINGS", 4), ("KANTURA_FLOOR", 8), ("KANTURA_DIMENSIONS", 2), ("KANTURA_FURNITURE", 6), ("KANTURA_MARKERS", 1)] {
            out += "0\nLAYER\n2\n\(name)\n70\n0\n62\n\(color)\n6\nCONTINUOUS\n"
        }
        out += "0\nENDTAB\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n"
        func n(_ v: Double) -> String { String(format: "%.4f", v) }
        func line(_ a: (Double, Double), _ b: (Double, Double), _ layer: String) {
            out += "0\nLINE\n8\n\(layer)\n10\n\(n(a.0))\n20\n\(n(a.1))\n30\n0.0\n11\n\(n(b.0))\n21\n\(n(b.1))\n31\n0.0\n"
        }
        func text(_ value: String, at p: (Double, Double), height: Double, angle: Double, layer: String) {
            let safe = value.unicodeScalars.map { $0.value < 128 && $0.value >= 32 ? String($0) : String(format: "\\U+%04X", $0.value) }.joined()
            out += "0\nTEXT\n8\n\(layer)\n10\n\(n(p.0))\n20\n\(n(p.1))\n30\n0.0\n40\n\(n(height))\n1\n\(safe)\n50\n\(n(angle))\n72\n1\n11\n\(n(p.0))\n21\n\(n(p.1))\n31\n0.0\n"
        }
        for wall in plan.walls {
            line(wall.a, wall.b, "KANTURA_WALLS")
            let mid = ((wall.a.0 + wall.b.0) / 2, (wall.a.1 + wall.b.1) / 2)
            var angle = atan2(wall.b.1 - wall.a.1, wall.b.0 - wall.a.0) * 180 / .pi
            if angle > 90 { angle -= 180 } else if angle < -90 { angle += 180 }
            text(String(format: "%.2f m", wall.length), at: mid, height: 0.12, angle: angle, layer: "KANTURA_DIMENSIONS")
        }
        for o in plan.openings {
            line(o.a, o.b, "KANTURA_OPENINGS")
            let mid = ((o.a.0 + o.b.0) / 2, (o.a.1 + o.b.1) / 2)
            let name = o.kind == "door" ? labels.door : o.kind == "window" ? labels.window : labels.opening
            text(name + String(format: " %.2f x %.2f m", o.width, o.height), at: (mid.0, mid.1 - 0.2), height: 0.08, angle: 0, layer: "KANTURA_OPENINGS")
        }
        for outline in plan.floors where outline.count >= 3 {
            out += "0\nPOLYLINE\n8\nKANTURA_FLOOR\n66\n1\n70\n1\n"
            for p in outline { out += "0\nVERTEX\n8\nKANTURA_FLOOR\n10\n\(n(p.0))\n20\n\(n(p.1))\n30\n0.0\n" }
            out += "0\nSEQEND\n8\nKANTURA_FLOOR\n"
        }
        for f in extras.furniture {
            out += "0\nPOLYLINE\n8\nKANTURA_FURNITURE\n66\n1\n70\n1\n"
            for c in FurnitureLayout.corners(f) { out += "0\nVERTEX\n8\nKANTURA_FURNITURE\n10\n\(n(c.x))\n20\n\(n(-c.z))\n30\n0.0\n" }
            out += "0\nSEQEND\n8\nKANTURA_FURNITURE\n"
            text(f.name, at: (f.x, -f.z), height: 0.08, angle: 0, layer: "KANTURA_FURNITURE")
        }
        for (i, m) in extras.markers.enumerated() {
            out += "0\nCIRCLE\n8\nKANTURA_MARKERS\n10\n\(n(m.position[0]))\n20\n\(n(-m.position[2]))\n30\n0.0\n40\n0.1\n"
            text("\(i + 1) " + m.title, at: (m.position[0] + 0.15, -m.position[2]), height: 0.09, angle: 0, layer: "KANTURA_MARKERS")
        }
        out += "0\nENDSEC\n0\nEOF\n"
        return out
    }

    // MARK: HTML

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// One self-contained HTML file (no network): SVG floor plan with
    /// dimension lines, a rotatable 3D dollhouse (canvas), and a table.
    static func html(_ document: RoomPlanDocument, labels: Labels = Labels(), photos: [(name: String, jpeg: Data)] = [],
                     extras: RoomExtras = RoomExtras(), markerPhotos: [String: Data] = [:], walls: PhotoTiles = PhotoTiles()) -> String {
        let plan = plan(document)
        let summary = RoomPlanSummary(document)
        let number = NumberFormatter()
        number.locale = Locale(identifier: labels.language)
        number.minimumFractionDigits = 2
        number.maximumFractionDigits = 2
        func m(_ v: Double?) -> String { v.map { (number.string(from: NSNumber(value: $0)) ?? String(format: "%.2f", $0)) + " m" } ?? "—" }
        func m2(_ v: Double?) -> String { v.map { (number.string(from: NSNumber(value: $0)) ?? String(format: "%.2f", $0)) + " m²" } ?? "—" }

        // SVG plan, fitted into a 1000-unit wide view.
        let points = plan.walls.flatMap { [$0.a, $0.b] } + plan.floors.flatMap { $0 }
        let minX = points.map { $0.0 }.min() ?? 0, maxX = points.map { $0.0 }.max() ?? 1
        let minY = points.map { $0.1 }.min() ?? 0, maxY = points.map { $0.1 }.max() ?? 1
        let span = max(maxX - minX, maxY - minY, 1), scale = 760 / span, pad = 120.0
        func sx(_ p: (Double, Double)) -> (Double, Double) { ((p.0 - minX) * scale + pad, (maxY - p.1) * scale + pad) }
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        var svg = ""
        for outline in plan.floors where outline.count >= 3 {
            svg += "<polygon class=\"floor\" points=\"" + outline.map { let q = sx($0); return String(format: "%.1f,%.1f", q.0, q.1) }.joined(separator: " ") + "\"/>"
        }
        for wall in plan.walls {
            let a = sx(wall.a), b = sx(wall.b)
            svg += String(format: "<line class=\"wall\" x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\"/>", a.0, a.1, b.0, b.1)
            // Dimension line offset away from the room centre.
            let mid = ((wall.a.0 + wall.b.0) / 2, (wall.a.1 + wall.b.1) / 2)
            var ox = mid.0 - cx, oy = mid.1 - cy
            let dx = wall.b.0 - wall.a.0, dy = wall.b.1 - wall.a.1, len = max(1e-6, hypot(dx, dy))
            var nx = -dy / len, ny = dx / len
            if nx * ox + ny * oy < 0 { nx = -nx; ny = -ny }
            ox = nx * 0.45; oy = ny * 0.45
            let p1 = sx((wall.a.0 + ox, wall.a.1 + oy)), p2 = sx((wall.b.0 + ox, wall.b.1 + oy))
            svg += String(format: "<line class=\"dim\" x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\"/>", p1.0, p1.1, p2.0, p2.1)
            for (end, q) in [(wall.a, p1), (wall.b, p2)] {
                let e = sx((end.0 + nx * 0.15, end.1 + ny * 0.15))
                svg += String(format: "<line class=\"tick\" x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\"/>", e.0, e.1, q.0, q.1)
            }
            let t = sx((mid.0 + nx * 0.72, mid.1 + ny * 0.72))
            var angle = -atan2(dy, dx) * 180 / .pi
            if angle > 90 { angle -= 180 } else if angle < -90 { angle += 180 }
            svg += String(format: "<text class=\"len\" x=\"%.1f\" y=\"%.1f\" transform=\"rotate(%.1f %.1f %.1f)\">", t.0, t.1, angle, t.0, t.1) + escape(m(wall.length)) + "</text>"
        }
        for o in plan.openings {
            let a = sx(o.a), b = sx(o.b)
            svg += String(format: "<line class=\"%@\" x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\"><title>%@</title></line>", o.kind == "window" ? "win" : "door", a.0, a.1, b.0, b.1, escape(m(o.width) + " × " + m(o.height)))
        }
        for f in extras.furniture {
            let c = FurnitureLayout.corners(f).map { sx(($0.x, -$0.z)) }
            svg += "<polygon class=\"furn\" points=\"" + c.map { String(format: "%.1f,%.1f", $0.0, $0.1) }.joined(separator: " ") + "\"><title>" + escape(f.name) + "</title></polygon>"
            let t = sx((f.x, -f.z))
            svg += String(format: "<text class=\"furnlabel\" x=\"%.1f\" y=\"%.1f\">", t.0, t.1) + escape(f.name) + "</text>"
        }
        let markerColor = ["defect": "#e5484d", "question": "#f08c00", "idea": "#3b82f6", "measure": "#8b5cf6"]
        for (i, m) in extras.markers.enumerated() {
            let t = sx((m.position[0], -m.position[2]))
            let fill = markerColor[m.kind] ?? "#555555"
            svg += String(format: "<g class=\"pin\"><circle cx=\"%.1f\" cy=\"%.1f\" r=\"20\" fill=\"", t.0, t.1) + fill
                + String(format: "\"/><text x=\"%.1f\" y=\"%.1f\" class=\"pinno\">%d</text></g>", t.0, t.1, i + 1)
        }
        let centre = sx((cx, cy))
        svg += String(format: "<text class=\"area\" x=\"%.1f\" y=\"%.1f\">", centre.0, centre.1) + escape(m2(summary.floorArea)) + "</text>"
        let svgSize = String(format: "0 0 %.0f %.0f", (maxX - minX) * scale + 2 * pad, (maxY - minY) * scale + 2 * pad)

        // Table rows.
        var rows = ""
        let kindName = ["wall": labels.wall, "door": labels.door, "window": labels.window, "opening": labels.opening]
        var counts: [String: Int] = [:]
        for s in document.surfaces where s.kind != "floor" && s.dimensions.count == 3 {
            counts[s.kind, default: 0] += 1
            rows += "<tr><td>\(escape((kindName[s.kind] ?? s.kind) + " \(counts[s.kind]!)"))</td><td>\(escape(m(s.dimensions[0])))</td><td>\(escape(m(s.dimensions[1])))</td></tr>"
        }
        for object in document.objects ?? [] where object.category == "stairs" {
            rows += "<tr><td>\(escape(labels.stairs))</td><td>\(escape(m(object.dimensions[0])))</td><td>\(escape(m(object.dimensions[1])))</td></tr>"
        }

        // Model data for the canvas 3D view.
        let modelWalls = plan.walls.map { w in [w.a.0, w.a.1, w.b.0, w.b.1, w.height] }
        let modelOpenings = plan.openings.map { o in [o.a.0, o.a.1, o.b.0, o.b.1, o.bottom, o.top, o.kind == "window" ? 1.0 : 0.0] }
        let modelData = (try? JSONSerialization.data(withJSONObject: ["walls": modelWalls, "openings": modelOpenings, "floors": plan.floors.map { $0.map { [$0.0, $0.1] } }]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        var markerRows = ""
        for (i, marker) in extras.markers.enumerated() {
            let photo = marker.photo.flatMap { markerPhotos[$0] }.map { "<img alt=\"\" src=\"data:image/jpeg;base64,\($0.base64EncodedString())\">" } ?? ""
            let meta = [labels.kinds[marker.kind] ?? marker.kind, marker.status == "done" ? labels.done : labels.open,
                        marker.assignee.isEmpty ? nil : labels.assignee + ": " + marker.assignee].compactMap { $0 }.joined(separator: " · ")
            let detail = escape(marker.detail).replacingOccurrences(of: "\n", with: "<br>")
            markerRows += "<article class=\"marker \(escape(marker.kind)) \(escape(marker.status))\"><h3><span class=\"no\">\(i + 1)</span> \(escape(marker.title))</h3><p class=\"muted\">\(escape(meta))</p><p>\(detail)</p>\(photo)</article>"
        }
        let markerSection = markerRows.isEmpty ? "" : "<h2 class=\"section\">\(escape(labels.markers))</h2><div class=\"markers\">\(markerRows)</div>"
        var furnitureRows = ""
        for f in extras.furniture {
            furnitureRows += "<tr><td>\(escape(f.name))</td><td>\(escape(m(f.width)))</td><td>\(escape(m(f.depth)))</td><td>\(escape(m(f.height)))</td></tr>"
        }
        let furnitureSection = furnitureRows.isEmpty ? "" : "<h2 class=\"section\">\(escape(labels.furniture))</h2><table><tbody>\(furnitureRows)</tbody></table>"
        let furnitureData = extras.furniture.map { f in FurnitureLayout.corners(f).flatMap { [$0.x, -$0.z] } + [f.height] }
        let tileData = (try? JSONSerialization.data(withJSONObject: ["tiles": walls.tiles, "furniture": furnitureData])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let textures = walls.images.map { "\"data:image/jpeg;base64,\($0.base64EncodedString())\"" }.joined(separator: ",")
        let photoToggle = walls.tiles.isEmpty ? "" : "<label class=\"toggle\"><input type=\"checkbox\" id=\"photos\" checked> \(escape(labels.photos))</label>"
        let gallery = photos.prefix(24).map { "<img loading=\"lazy\" alt=\"\(escape($0.name))\" src=\"data:image/jpeg;base64,\($0.jpeg.base64EncodedString())\">" }.joined()
        let title = escape(document.building?.room ?? document.name)
        let context = document.building.map { escape($0.name + " · " + $0.floor) } ?? ""

        return """
        <!doctype html>
        <html lang="\(escape(labels.language))"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:">
        <title>\(title) · KANTURA</title>
        <style>
        :root{--ink:#251a40;--mint:#70edc5;--paper:#faf9f6;--muted:#6c6477;--line:#e3dfe8}
        @media (prefers-color-scheme:dark){:root{--ink:#f2eefa;--paper:#15111f;--muted:#b8b0c6;--line:#3b3248}}
        body{margin:0;font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:var(--paper);color:var(--ink)}
        main{max-width:1100px;margin:0 auto;padding:24px 16px 48px}
        h1{margin:0 0 4px;font-size:28px}.muted{color:var(--muted)}
        .stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin:20px 0}
        .stat{border:1px solid var(--line);border-radius:14px;padding:14px}.stat b{display:block;font-size:22px;font-variant-numeric:tabular-nums}
        .views{display:grid;grid-template-columns:1fr 1fr;gap:16px}@media(max-width:800px){.views{grid-template-columns:1fr}}
        .card{border:1px solid var(--line);border-radius:18px;padding:12px;overflow:hidden}
        h2{font-size:16px;margin:4px 6px 10px}
        svg{width:100%;height:auto;display:block}
        .floor{fill:#e8d4b4;stroke:none}.wall{stroke:var(--ink);stroke-width:9;stroke-linecap:square}
        .dim,.tick{stroke:var(--muted);stroke-width:1.6}.door{stroke:#2fbf8f;stroke-width:13}.win{stroke:#2aa6c8;stroke-width:13}
        text{fill:var(--ink);font-size:24px;text-anchor:middle;dominant-baseline:middle;font-variant-numeric:tabular-nums}
        .area{font-size:30px;font-weight:600}.len{font-weight:600}
        canvas{width:100%;aspect-ratio:4/3;display:block;touch-action:none;cursor:grab}
        table{width:100%;border-collapse:collapse;margin-top:20px;font-variant-numeric:tabular-nums}
        td,th{text-align:left;padding:8px;border-bottom:1px solid var(--line)}
        .gallery{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:8px;margin-top:20px}.gallery img{width:100%;border-radius:10px}
        .furn{fill:rgba(139,120,190,.35);stroke:#6d5bb0;stroke-width:2}.furnlabel{font-size:16px;fill:#4b3d86}
        .pinno{fill:#fff;font-size:20px;font-weight:700}
        .section{font-size:20px;margin:28px 0 10px}.markers{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:12px}
        .marker{border:1px solid var(--line);border-left:6px solid #888;border-radius:14px;padding:12px}.marker h3{margin:0 0 4px;font-size:16px}
        .marker.defect{border-left-color:#e5484d}.marker.question{border-left-color:#f08c00}.marker.idea{border-left-color:#3b82f6}.marker.measure{border-left-color:#8b5cf6}
        .marker.done{opacity:.6}.marker img{width:100%;border-radius:10px;margin-top:6px}
        .no{display:inline-grid;place-items:center;width:24px;height:24px;border-radius:50%;background:var(--ink);color:var(--paper);font-size:13px}
        .toggle{float:right;font-size:13px;font-weight:400}
        @media print{.card canvas{display:none}}
        </style></head><body><main>
        <h1>\(title)</h1><p class="muted">\(context)</p>
        <div class="stats">
        <div class="stat"><b>\(escape(m2(summary.floorArea)))</b>\(escape(labels.floorArea))</div>
        <div class="stat"><b>\(escape(m2(summary.walls > 0 ? summary.netWallArea : nil)))</b>\(escape(labels.netWall))</div>
        <div class="stat"><b>\(escape(m2(summary.walls > 0 ? summary.grossWallArea : nil)))</b>\(escape(labels.grossWall))</div>
        <div class="stat"><b>\(escape(m(summary.wallHeight)))</b>\(escape(labels.height))</div>
        </div>
        <div class="views">
        <div class="card"><h2>\(escape(labels.plan))</h2><svg viewBox="\(svgSize)" xmlns="http://www.w3.org/2000/svg">\(svg)</svg></div>
        <div class="card"><h2>\(escape(labels.model))\(photoToggle)</h2><canvas id="model" width="900" height="675"></canvas></div>
        </div>
        <table><thead><tr><th>\(escape(labels.dimensions))</th><th>\(escape(labels.width))</th><th>\(escape(labels.heightShort))</th></tr></thead><tbody>\(rows)</tbody></table>
        \(markerSection)
        \(furnitureSection)
        <p class="muted">\(escape(labels.note)) · KANTURA</p>
        <div class="gallery">\(gallery)</div>
        </main>
        <script>
        const data=\(modelData);
        const extra=\(tileData);
        const tex=[\(textures)].map(src=>{const i=new Image();i.onload=()=>draw();i.src=src;return i;});
        const photoBox=document.getElementById('photos');if(photoBox)photoBox.addEventListener('change',()=>draw());
        const c=document.getElementById('model'),g=c.getContext('2d');
        let yaw=0.7,pitch=0.75,zoom=1,drag=null;
        const pts=data.walls.flatMap(w=>[[w[0],w[1]],[w[2],w[3]]]);
        const cx=pts.reduce((s,p)=>s+p[0],0)/Math.max(1,pts.length),cy=pts.reduce((s,p)=>s+p[1],0)/Math.max(1,pts.length);
        const span=Math.max(1,...pts.map(p=>Math.hypot(p[0]-cx,p[1]-cy)))*2;
        function proj(x,y,z){x-=cx;y-=cy;const a=Math.cos(yaw),b=Math.sin(yaw);let X=x*a-y*b,Y=x*b+y*a;const ca=Math.cos(pitch),sa=Math.sin(pitch);const Z=z*ca-Y*sa,D=Y*ca+z*sa;const s=c.width/span*0.75*zoom;return[c.width/2+X*s,c.height*0.58-Z*s,D];}
        function quad(p,fill,stroke){g.beginPath();p.forEach((q,i)=>i?g.lineTo(q[0],q[1]):g.moveTo(q[0],q[1]));g.closePath();g.fillStyle=fill;g.fill();if(stroke){g.strokeStyle=stroke;g.lineWidth=1;g.stroke();}}
        function draw(){g.clearRect(0,0,c.width,c.height);const faces=[];
         data.floors.forEach(f=>faces.push({p:f.map(q=>proj(q[0],q[1],0)),fill:'#e8d4b4',d:-1e9}));
         data.walls.forEach(w=>{const p=[proj(w[0],w[1],0),proj(w[2],w[3],0),proj(w[2],w[3],w[4]),proj(w[0],w[1],w[4])];
          const nx=-(w[3]-w[1]),ny=w[2]-w[0],l=Math.hypot(nx,ny)||1,lit=0.78+0.2*Math.abs(Math.cos(Math.atan2(ny,nx)-yaw));
          faces.push({p,fill:`rgb(${Math.round(236*lit)},${Math.round(234*lit)},${Math.round(240*lit)})`,d:p.reduce((s,q)=>s+q[2],0)/4});});
         data.openings.forEach(o=>{const p=[proj(o[0],o[1],o[4]),proj(o[2],o[3],o[4]),proj(o[2],o[3],o[5]),proj(o[0],o[1],o[5])];
          faces.push({p,fill:o[6]?'rgba(42,166,200,.55)':'rgba(47,191,143,.55)',d:p.reduce((s,q)=>s+q[2],0)/4-0.01});});
         const usePhotos=photoBox&&photoBox.checked&&extra.tiles.length;
         if(usePhotos){faces.length=0;extra.tiles.forEach(t=>{const p=[0,1,2,3].map(k=>proj(t[1+k*5],t[2+k*5],t[3+k*5]));const uv=[0,1,2,3].map(k=>[t[4+k*5],t[5+k*5]]);faces.push({p,img:tex[t[0]],uv,d:p.reduce((s,q)=>s+q[2],0)/4});});}
         extra.furniture.forEach(f=>{const h=f[8],c=[0,1,2,3].map(k=>[f[k*2],f[k*2+1]]);
          for(let k=0;k<4;k++){const a=c[k],b=c[(k+1)%4],p=[proj(a[0],a[1],0),proj(b[0],b[1],0),proj(b[0],b[1],h),proj(a[0],a[1],h)];faces.push({p,fill:'rgba(139,120,190,.9)',d:p.reduce((s,q)=>s+q[2],0)/4});}
          const top=c.map(q=>proj(q[0],q[1],h));faces.push({p:top,fill:'rgba(170,152,220,.95)',d:top.reduce((s,q)=>s+q[2],0)/4-0.05});});
         faces.sort((a,b)=>b.d-a.d).forEach(f=>f.img?textured(f):quad(f.p,f.fill,'rgba(37,26,64,.35)'));}
        function tri(img,p0,p1,p2,t0,t1,t2){const w=img.naturalWidth,h=img.naturalHeight;if(!w)return;
         const x0=t0[0]*w,y0=t0[1]*h,x1=t1[0]*w,y1=t1[1]*h,x2=t2[0]*w,y2=t2[1]*h,den=(x1-x0)*(y2-y0)-(x2-x0)*(y1-y0);if(Math.abs(den)<1e-6)return;
         const a=((p1[0]-p0[0])*(y2-y0)-(p2[0]-p0[0])*(y1-y0))/den,b=((p1[1]-p0[1])*(y2-y0)-(p2[1]-p0[1])*(y1-y0))/den,
               c=((p2[0]-p0[0])*(x1-x0)-(p1[0]-p0[0])*(x2-x0))/den,d=((p2[1]-p0[1])*(x1-x0)-(p1[1]-p0[1])*(x2-x0))/den;
         g.save();g.beginPath();g.moveTo(p0[0],p0[1]);g.lineTo(p1[0],p1[1]);g.lineTo(p2[0],p2[1]);g.closePath();g.clip();
         g.setTransform(a,b,c,d,p0[0]-a*x0-c*y0,p0[1]-b*x0-d*y0);g.drawImage(img,0,0);g.restore();}
        function textured(f){const p=f.p,u=f.uv;tri(f.img,p[0],p[1],p[2],u[0],u[1],u[2]);tri(f.img,p[0],p[2],p[3],u[0],u[2],u[3]);}
        c.addEventListener('pointerdown',e=>{drag=[e.clientX,e.clientY,yaw,pitch];c.setPointerCapture(e.pointerId);});
        c.addEventListener('pointermove',e=>{if(!drag)return;yaw=drag[2]+(e.clientX-drag[0])*0.01;pitch=Math.max(0.1,Math.min(1.5,drag[3]+(e.clientY-drag[1])*0.01));draw();});
        c.addEventListener('pointerup',()=>drag=null);
        c.addEventListener('wheel',e=>{e.preventDefault();zoom=Math.max(0.4,Math.min(4,zoom*(e.deltaY<0?1.1:0.9)));draw();},{passive:false});
        draw();
        </script></body></html>
        """
    }
}
