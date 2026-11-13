#!/usr/bin/env python3
"""pdf_schematic.py —— 从矢量原理图 PDF 重建候选连接关系（供 pdf2md --schematic 调用）

为什么不用通用 PDF→Markdown：
    PDF 里的"连线"是矢量线段，"网络名"是散落的文字，"连接关系"只存在于两者
    的**几何位置关系**里。任何文字流转换（pymupdf4llm / marker / pdftotext /
    OpenDataLoader）都只输出文字，拓扑必然丢失。

本脚本做什么：
    1. 取文字 word 及其 bbox；2. 取矢量线段（含细长矩形画的线）；3. 端点吸附到
    容差网格；4. 端点落在另一条线段上（T 型连接）也并入；5. 并查集求连通分量；
    6. 把靠近线段的文字当作网络名/引脚标注挂到对应分量上。

**结果只是候选**：几何上"线连在一起"不等于设计者意图，文字旋转/重叠/偏移都会错配。
输出中明确标注可信度，改板前必须回原图核对；有源文件（.SchDoc/.dsn/.kicad_sch）时
应优先用源文件导网表。

用法：
    python pdf_schematic.py --pdf X.pdf --out Y.md [--pages 1-3] [--tol 2.0]
                            [--label-tol 10] [--max-nets 300]
环境变量 PDF2MD_FRONT 提供 Markdown 头部（由 pdf2md 生成）。
"""
from __future__ import annotations

import argparse
import math
import os
import sys
from collections import defaultdict

try:
    import pymupdf
except Exception:  # noqa: BLE001
    try:
        import fitz as pymupdf  # type: ignore
    except Exception:  # noqa: BLE001
        sys.stderr.write("error: 需要 PyMuPDF（pip install pymupdf）\n")
        sys.exit(3)


class DSU:
    def __init__(self) -> None:
        self.p: dict[tuple[int, int], tuple[int, int]] = {}

    def add(self, x: tuple[int, int]) -> None:
        self.p.setdefault(x, x)

    def find(self, x: tuple[int, int]) -> tuple[int, int]:
        root = x
        while self.p[root] != root:
            root = self.p[root]
        while self.p[x] != root:
            self.p[x], x = root, self.p[x]
        return root

    def union(self, a: tuple[int, int], b: tuple[int, int]) -> None:
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.p[rb] = ra


def dist_point_seg(px: float, py: float, x1: float, y1: float, x2: float, y2: float) -> float:
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return math.hypot(px - x1, py - y1)
    t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))


def collect_segments(page, tol: float):
    """返回 (线段列表, 结点坐标列表, 其它图元计数)"""
    segs: list[tuple[float, float, float, float]] = []
    dots: list[tuple[float, float]] = []
    other = 0
    try:
        drawings = page.get_drawings()
    except Exception:  # noqa: BLE001
        return segs, dots, other

    for d in drawings:
        filled = d.get("fill") is not None
        for it in d.get("items", []):
            kind = it[0]
            if kind == "l":  # ('l', p1, p2)
                p1, p2 = it[1], it[2]
                if math.hypot(p2.x - p1.x, p2.y - p1.y) > 1.0:
                    segs.append((p1.x, p1.y, p2.x, p2.y))
            elif kind == "re":  # ('re', rect, orientation)
                r = it[1]
                w, h = r.width, r.height
                if w <= 6 and h <= 6:  # 小方块 = 结点标记
                    dots.append((r.x0 + w / 2, r.y0 + h / 2))
                elif min(w, h) <= 2.5 and max(w, h) > 3:
                    # 细长矩形：很多 CAD 导出把线画成填充矩形，取中心线
                    if w >= h:
                        cy = r.y0 + h / 2
                        segs.append((r.x0, cy, r.x1, cy))
                    else:
                        cx = r.x0 + w / 2
                        segs.append((cx, r.y0, cx, r.y1))
                else:
                    other += 1
            elif kind == "qu":  # 四边形按 4 条边近似
                q = it[1]
                pts = [q.ul, q.ur, q.lr, q.ll]
                for i in range(4):
                    a, b = pts[i], pts[(i + 1) % 4]
                    if math.hypot(b.x - a.x, b.y - a.y) > 1.0:
                        segs.append((a.x, a.y, b.x, b.y))
            elif kind == "c":  # 曲线：用小圆近似为结点，其余忽略
                p1, _, _, p4 = it[1], it[2], it[3], it[4]
                if math.hypot(p4.x - p1.x, p4.y - p1.y) <= 6:
                    dots.append(((p1.x + p4.x) / 2, (p1.y + p4.y) / 2))
                else:
                    other += 1
            else:
                other += 1
    # 圆点常被拆成多段曲线，同一位置会产生重复结点标记 —— 按 tol 去重
    uniq: list[tuple[float, float]] = []
    for dx, dy in dots:
        if all(math.hypot(dx - ux, dy - uy) > tol * 2 for ux, uy in uniq):
            uniq.append((dx, dy))
    return segs, uniq, other


def extract_page(page, tol: float, label_tol: float):
    segs, dots, other = collect_segments(page, tol)
    words = []
    try:
        for w in page.get_text("words"):
            x0, y0, x1, y1, txt = w[0], w[1], w[2], w[3], w[4]
            if txt.strip():
                words.append((x0, y0, x1, y1, txt))
    except Exception:  # noqa: BLE001
        pass

    key = lambda x, y: (int(round(x / tol)), int(round(y / tol)))  # noqa: E731
    dsu = DSU()
    nodes: dict[tuple[int, int], list[float]] = {}
    for x1, y1, x2, y2 in segs:
        for x, y in ((x1, y1), (x2, y2)):
            k = key(x, y)
            dsu.add(k)
            nodes.setdefault(k, [0.0, 0.0, 0])
            nodes[k][0] += x
            nodes[k][1] += y
            nodes[k][2] += 1
        dsu.union(key(x1, y1), key(x2, y2))

    # T 型连接：端点落在另一条线段上也算连通（按 bbox 分桶，避免 O(N*M) 全比）
    cell = max(8.0, tol * 6)
    grid: dict[tuple[int, int], list[int]] = defaultdict(list)
    for i, (x1, y1, x2, y2) in enumerate(segs):
        for gx in range(int(min(x1, x2) // cell), int(max(x1, x2) // cell) + 1):
            for gy in range(int(min(y1, y2) // cell), int(max(y1, y2) // cell) + 1):
                grid[(gx, gy)].append(i)
    for k in list(nodes):
        cx = nodes[k][0] / nodes[k][2]
        cy = nodes[k][1] / nodes[k][2]
        for i in grid.get((int(cx // cell), int(cy // cell)), []):
            x1, y1, x2, y2 = segs[i]
            if dist_point_seg(cx, cy, x1, y1, x2, y2) <= tol:
                dsu.union(k, key(x1, y1))

    # 结点标记：把附近的端点并到同一分量
    for dx, dy in dots:
        k = key(dx, dy)
        if k in dsu.p:
            continue
        best = None
        bestd = 1e9
        for nk in list(nodes):
            nx = nodes[nk][0] / nodes[nk][2]
            ny = nodes[nk][1] / nodes[nk][2]
            d = math.hypot(nx - dx, ny - dy)
            if d < bestd:
                best, bestd = nk, d
        if best is not None and bestd <= max(tol * 2, 6):
            dsu.add(k)
            dsu.union(k, best)

    comps: dict[tuple[int, int], dict] = {}
    for k in list(dsu.p):
        r = dsu.find(k)
        c = comps.setdefault(r, {"nodes": 0, "labels": [], "dots": 0, "seg_ids": set()})
        c["nodes"] += 1
    for i, (x1, y1, x2, y2) in enumerate(segs):
        r = dsu.find(key(x1, y1))
        if r in comps:
            comps[r]["seg_ids"].add(i)
    for dx, dy in dots:
        k = key(dx, dy)
        if k in dsu.p:
            comps[dsu.find(k)]["dots"] += 1

    # 文字挂到最近**线段**（网络名一般压在线上或紧贴上/下方，而不是靠近端点；
    # 只按端点匹配会漏掉整条横线中间的网络名）。找不到线段再退回最近端点。
    for x0, y0, x1, y1, txt in words:
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        gx0 = int((cx - label_tol) // cell)
        gx1 = int((cx + label_tol) // cell)
        gy0 = int((cy - label_tol) // cell)
        gy1 = int((cy + label_tol) // cell)
        best_i, best_d = -1, 1e9
        for gx in range(gx0, gx1 + 1):
            for gy in range(gy0, gy1 + 1):
                for i in grid.get((gx, gy), []):
                    sx1, sy1, sx2, sy2 = segs[i]
                    d = dist_point_seg(cx, cy, sx1, sy1, sx2, sy2)
                    if d < best_d:
                        best_i, best_d = i, d
        attached = False
        if best_i >= 0 and best_d <= label_tol:
            r = dsu.find(key(segs[best_i][0], segs[best_i][1]))
            if r in comps and txt not in comps[r]["labels"]:
                comps[r]["labels"].append(txt)
                attached = True
        if attached:
            continue
        best = None
        bestd = 1e9
        for k in list(nodes):
            nx = nodes[k][0] / nodes[k][2]
            ny = nodes[k][1] / nodes[k][2]
            d = math.hypot(nx - cx, ny - cy)
            if d < bestd:
                best, bestd = k, d
        if best is not None and bestd <= label_tol:
            r = dsu.find(best)
            if r in comps and txt not in comps[r]["labels"]:
                comps[r]["labels"].append(txt)

    return segs, dots, other, words, comps


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--pdf", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--pages", default="")
    ap.add_argument("--tol", type=float, default=2.0)
    ap.add_argument("--label-tol", type=float, default=10.0)
    ap.add_argument("--max-nets", type=int, default=300)
    a = ap.parse_args()

    try:
        doc = pymupdf.open(a.pdf)
    except Exception as e:  # noqa: BLE001
        sys.stderr.write("error: 打不开 PDF: %s\n" % e)
        return 1

    first, last = 0, doc.page_count - 1
    if a.pages:
        s, _, e = a.pages.partition("-")
        first = max(0, int(s) - 1)
        last = min(doc.page_count - 1, int(e or s) - 1)

    stat_rows = []
    nets = []
    text_sections = []
    total_segs = total_dots = 0

    for pno in range(first, last + 1):
        page = doc[pno]
        segs, dots, other, words, comps = extract_page(page, a.tol, a.label_tol)
        total_segs += len(segs)
        total_dots += len(dots)
        named = sum(1 for c in comps.values() if c["labels"])
        stat_rows.append(
            (pno + 1, len(segs), len(dots), len(comps), named, len(comps) - named, len(words), other)
        )
        for c in comps.values():
            nets.append(
                {
                    "page": pno + 1,
                    "labels": sorted(c["labels"]),
                    "segs": len(c["seg_ids"]),
                    "dots": c["dots"],
                    "nodes": c["nodes"],
                }
            )
        # 文字清单：按 y 聚类成行，便于人工对照原图
        lines: list[list[tuple[float, float, str]]] = []
        for x0, y0, x1, y1, txt in sorted(words, key=lambda w: (round(w[1] / 6), w[0])):
            if lines and abs(lines[-1][0][1] - y0) <= 6:
                lines[-1].append((x0, y0, txt))
            else:
                lines.append([(x0, y0, txt)])
        body = "\n".join(
            "| %d | %s |" % (int(ln[0][1]), " ".join(t for _, _, t in ln)) for ln in lines
        )
        text_sections.append(body if body else "| - | （该页无文字层） |")

    doc.close()

    nets.sort(key=lambda n: (0 if n["labels"] else 1, -n["segs"]))
    truncated = len(nets) > a.max_nets
    shown = nets[: a.max_nets]
    named_n = sum(1 for n in nets if n["labels"])

    out = []
    out.append(os.environ.get("PDF2MD_FRONT", "").rstrip() + "\n")
    out.append(
        "> 结论可信度: **候选结果**。几何重建只证明「线段相连」，不等于设计者意图；\n"
        "> 网络名与元件号可能因文字旋转/重叠/坐标偏移错配。**改板、算电流、查短路前必须回原图核对**；\n"
        "> 若手上有原理图源文件（`.SchDoc` / `.dsn` / `.kicad_sch`），应以源文件导出的网表为准。\n"
    )
    out.append("\n## 1. 图形统计\n")
    out.append("| 页 | 线段 | 结点标记 | 连通网络 | 具名 | 未命名 | 文字 | 其它图元 |")
    out.append("|---:|---:|---:|---:|---:|---:|---:|---:|")
    for r in stat_rows:
        out.append("| %d | %d | %d | %d | %d | %d | %d | %d |" % r)
    out.append(
        "\n合计：线段 %d、结点 %d、连通网络 %d（具名 %d）。" % (total_segs, total_dots, len(nets), named_n)
    )
    if total_segs == 0:
        out.append(
            "\n> **该 PDF 没有矢量线段** —— 大概率是位图/扫描件或加密导出。\n"
            "> 这种情况下无法重建连接关系，只能 `--ocr` 取文字（仍无拓扑），或改用原理图源文件。\n"
        )
    out.append("\n## 2. 候选网络表\n")
    out.append("命名网络排在前面（有网络名/引脚标注，可信度相对高）；未命名网络只有拓扑。\n")
    for i, n in enumerate(shown, 1):
        if n["labels"]:
            out.append("### N%d · `%s`" % (i, "` / `".join(n["labels"][:6])))
        else:
            out.append("### N%d · 未命名" % i)
        out.append(
            "- 第 %d 页 · 线段 %d · 结点 %d · 端点 %d%s"
            % (n["page"], n["segs"], n["dots"], n["nodes"], " · 含结点标记" if n["dots"] else "")
        )
        if len(n["labels"]) > 6:
            out.append("- 其余标注: " + ", ".join(n["labels"][6:30]))
        out.append("")
    if truncated:
        out.append("> 网络数 %d 超过 --max-nets=%d，仅显示前 %d 个。\n" % (len(nets), a.max_nets, a.max_nets))
    out.append("\n## 3. 文字清单（按页，便于对照原图）\n")
    for idx, body in enumerate(text_sections):
        out.append("### 第 %d 页\n" % (first + idx + 1))
        out.append("| y | 文字（按 x 排序） |")
        out.append("|---:|---|")
        out.append(body + "\n")

    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))

    sys.stderr.write("SCHEMATIC pages=%d segs=%d dots=%d nets=%d named=%d\n" %
                     (last - first + 1, total_segs, total_dots, len(nets), named_n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
