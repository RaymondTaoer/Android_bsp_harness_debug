#!/usr/bin/env python3
"""pdf_schematic.py —— 从矢量原理图 PDF 重建候选连接关系（供 pdf2md --schematic 调用）

为什么不用通用 PDF→Markdown：
    PDF 里的"连线"是矢量线段，"网络名"是散落的文字，"连接关系"只存在于两者
    的**几何位置关系**里。任何文字流转换（pymupdf4llm / marker / pdftotext /
    OpenDataLoader）都只输出文字，拓扑必然丢失。

本脚本做什么：
    1. 取文字 word 及其 bbox；2. 取矢量线段（含细长矩形画的线）；
    3. 剔除图框 / 标题栏（它们不是导线，却是最容易把整页网络并成一片的东西）；
    4. 端点按容差吸附，并按**夹角**过滤——原理图走线只有 0°（直延）和 90°
       （拐角/丁字），没有结点标记的 45° 交接必然是接插件/二极管符号的美术图形；
    5. 丁字连接（端点落在另一条线中段）只在**有结点标记**时成立；
    6. 并查集求连通分量；文字分类（网络名/引脚号/元件值/位号）后把网络名挂上去；
    7. 同一分量里出现两个以上不同网络名 = 几何并了但语义冲突，单独列出。

**结果只是候选**：几何上"线连在一起"不等于设计者意图。输出分三档标注可信度
（净 / 冲突 / 未命名），冲突项必须回原图核对；有源文件
（.SchDoc/.dsn/.kicad_sch）时应优先用源文件导网表。

用法：
    python pdf_schematic.py --pdf X.pdf --out Y.md [--pages 1-3] [--tol 2.0]
                            [--label-tol 6] [--max-nets 300] [--no-frame-guard]
环境变量 PDF2MD_FRONT 提供 Markdown 头部（由 pdf2md 生成）。
"""
from __future__ import annotations

import argparse
import math
import os
import re
import sys
from collections import Counter, defaultdict

try:
    import pymupdf
except Exception:  # noqa: BLE001
    try:
        import fitz as pymupdf  # type: ignore
    except Exception:  # noqa: BLE001
        sys.stderr.write("error: 需要 PyMuPDF（pip install pymupdf）\n")
        sys.exit(3)

# 45° 附近的交接角带：没结点标记时一律当作符号美术图形，不合并
ART_ANGLE_LO, ART_ANGLE_HI = 25.0, 65.0
# 结点标记（junction dot）有效半径
DOT_R = 3.0

# ---- 文字分类 ---------------------------------------------------------------
RE_PIN = re.compile(r"^\d{1,3}$")
RE_REFDES = re.compile(r"^[A-Z]{1,5}\d{2,4}[A-Z]?$")
RE_VALUE = re.compile(r"^\d+(\.\d+)?\s*(p|n|u|µ|m|k|K|M|G|R)?\s*(F|H|Ω|V|A|W|Hz|Ohm|R)?$")
RE_NET = re.compile(r"^[0-9A-Z][0-9A-Z]*(_[0-9A-Z]+)+[0-9A-Z]*$")
RE_POWER = re.compile(r"^\+?\d+V\d+$|^\+[0-9.]+V$|^(VCC|VDD|VSS|VBAT|VBUS|AVDD|DVDD|VREF)[0-9A-Z_]*$")
POWER_WORDS = {
    "GND", "AGND", "DGND", "PGND", "GNDPWR", "EARTH", "CHASSIS",
    "VCC", "VDD", "VSS", "VBAT", "VBUS", "VREF", "AVDD", "DVDD",
}


def classify(txt: str) -> str:
    """文字分类：net / power / net_lc / pin / refdes / value / other。

    net     —— 带下划线的大写网络名（RK_CAN1_TX、4G_DTR），最可靠
    power   —— GND、VCC3V3_PMU、+5V 一类电源名
    net_lc  —— 大写但无下划线（CAN1H、RS485），可能是网络名也可能是符号内引脚名
    pin     —— 纯数字引脚号
    refdes  —— 位号/型号（U1003、TJA1051T）
    value   —— 阻容值（100nF、22uF、±1%）
    other   —— 其余，不入网名
    """
    s = txt.strip()
    if not s:
        return "other"
    if any(c in s for c in "±Ω%µ"):
        return "value"
    if RE_PIN.fullmatch(s):
        return "pin"
    up = s.upper()
    if up in POWER_WORDS or RE_POWER.fullmatch(up):
        return "power"
    if RE_REFDES.fullmatch(s):
        return "refdes"
    if RE_VALUE.fullmatch(s):
        return "value"
    if RE_NET.fullmatch(s) and len(s) >= 4:
        return "net"
    if s.isupper() and len(s) >= 3 and not s.isdigit():
        return "net_lc"
    return "other"


# ---- 基础几何 ---------------------------------------------------------------


class DSU:
    def __init__(self) -> None:
        self.p: dict[object, object] = {}

    def add(self, x) -> None:
        self.p.setdefault(x, x)

    def find(self, x):
        root = x
        while self.p[root] != root:
            root = self.p[root]
        while self.p[x] != root:
            self.p[x], x = root, self.p[x]
        return root

    def union(self, a, b) -> bool:
        ra, rb = self.find(a), self.find(b)
        if ra == rb:
            return False
        self.p[rb] = ra
        return True


def dist_point_seg(px: float, py: float, x1: float, y1: float, x2: float, y2: float) -> float:
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return math.hypot(px - x1, py - y1)
    t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))


def seg_angle_deg(a, b) -> float:
    """两条线段方向的夹角，归一到 0~90°。"""
    a1 = math.atan2(a[3] - a[1], a[2] - a[0])
    a2 = math.atan2(b[3] - b[1], b[2] - b[0])
    d = abs(math.degrees(a1 - a2)) % 180.0
    return min(d, 180.0 - d)


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
                    pa, pb = pts[i], pts[(i + 1) % 4]
                    if math.hypot(pb.x - pa.x, pb.y - pa.y) > 1.0:
                        segs.append((pa.x, pa.y, pb.x, pb.y))
            elif kind == "c":  # 曲线：只把小圆当结点标记，其余忽略
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


def find_frame(page):
    """找出图纸边框矩形（占页面一半以上面积的最大矩形）。"""
    best, best_area = None, 0.0
    try:
        for d in page.get_drawings():
            for it in d.get("items", []):
                if it[0] == "re":
                    r = it[1]
                    area = r.width * r.height
                    if area > best_area:
                        best, best_area = r, area
        pa = page.rect.width * page.rect.height
    except Exception:  # noqa: BLE001
        return None
    return best if best is not None and best_area > 0.55 * pa else None


def frame_segments(segs, frame) -> set[int]:
    """标记图框边线、内框刻度线、右下标题栏里的线段 —— 它们不是导线。

    图框内外两条矩形边线横贯整页，标题栏（Title/Size/Date/Rev）又是一堆表格线；
    把它们当导线，会把整页靠边的网络并成一片（实测能把 6 条互不相干的信号并成
    一个 120 线段的假网络）。
    """
    if frame is None:
        return set()
    out: set[int] = set()
    fw, fh = frame.x1 - frame.x0, frame.y1 - frame.y0
    title_x = frame.x1 - 0.30 * fw
    title_y = frame.y1 - 0.14 * fh
    for i, (x1, y1, x2, y2) in enumerate(segs):
        # 1) 贴图框四边（±3pt）
        if (
            (abs(x1 - frame.x0) < 3 and abs(x2 - frame.x0) < 3)
            or (abs(x1 - frame.x1) < 3 and abs(x2 - frame.x1) < 3)
            or (abs(y1 - frame.y0) < 3 and abs(y2 - frame.y0) < 3)
            or (abs(y1 - frame.y1) < 3 and abs(y2 - frame.y1) < 3)
        ):
            out.add(i)
            continue
        # 2) 落在图框内但贴边 12pt 以内（内框 + 分区刻度）
        if (
            min(x1, x2) > frame.x0
            and max(x1, x2) < frame.x1
            and min(y1, y2) > frame.y0
            and max(y1, y2) < frame.y1
        ):
            margin = min(
                min(x1, x2) - frame.x0,
                frame.x1 - max(x1, x2),
                min(y1, y2) - frame.y0,
                frame.y1 - max(y1, y2),
            )
            if margin < 12:
                out.add(i)
                continue
        # 3) 整段落在右下标题栏
        if min(x1, x2) >= title_x - 2 and min(y1, y2) >= title_y - 2:
            out.add(i)
    return out


# ---- 连通性 ----------------------------------------------------------------


def build_components(segs, dots, tol: float, excluded: set[int]):
    """按几何关系求连通分量，返回 (seg_root 列表, 被夹角规则拒绝的连接数)。

    连接规则严格对齐原理图制图习惯：
      * 端点吸附：两条线的端点落在同一 tol 网格内视为同一点；
      * 夹角过滤：同一节点上夹角在 25°~65° 且**没有**结点标记 → 判为符号美术
        图形，不合并（原理图导线只走 0°/90°）；
      * 丁字连接：端点落在另一条线中段 → 必须有 junction dot 才认。
    """
    key = lambda x, y: (int(round(x / tol)), int(round(y / tol)))  # noqa: E731
    dsu = DSU()
    at_node: dict[tuple[int, int], list[int]] = defaultdict(list)
    for i, (x1, y1, x2, y2) in enumerate(segs):
        dsu.add(i)
        if i in excluded:
            continue
        at_node[key(x1, y1)].append(i)
        at_node[key(x2, y2)].append(i)

    dot_pts = [(dx, dy) for dx, dy in dots]

    def dot_near(x: float, y: float) -> bool:
        return any(math.hypot(x - dx, y - dy) <= DOT_R for dx, dy in dot_pts)

    rejected = 0
    # 同一节点上的多段线：按夹角决定是否合并
    for k, ids in at_node.items():
        if len(ids) < 2:
            continue
        cx, cy = k[0] * tol, k[1] * tol
        has_dot = dot_near(cx, cy)
        for ai in range(len(ids)):
            for bi in range(ai + 1, len(ids)):
                ia, ib = ids[ai], ids[bi]
                if ia == ib:
                    continue
                if ART_ANGLE_LO <= seg_angle_deg(segs[ia], segs[ib]) <= ART_ANGLE_HI and not has_dot:
                    rejected += 1
                    continue
                dsu.union(ia, ib)

    # 丁字连接：端点落在另一条线段中段 —— 必须有结点标记
    cell = max(8.0, tol * 6)
    grid: dict[tuple[int, int], list[int]] = defaultdict(list)
    for i, (x1, y1, x2, y2) in enumerate(segs):
        if i in excluded:
            continue
        for gx in range(int(min(x1, x2) // cell), int(max(x1, x2) // cell) + 1):
            for gy in range(int(min(y1, y2) // cell), int(max(y1, y2) // cell) + 1):
                grid[(gx, gy)].append(i)
    for k, ids in at_node.items():
        if not ids:
            continue
        cx, cy = k[0] * tol, k[1] * tol
        if not dot_near(cx, cy):
            continue  # 无点不认丁字，避免"端点压在无关长线中段"式假短路
        for i in grid.get((int(cx // cell), int(cy // cell)), []):
            x1, y1, x2, y2 = segs[i]
            if dist_point_seg(cx, cy, x1, y1, x2, y2) > tol:
                continue
            if min(math.hypot(cx - x1, cy - y1), math.hypot(cx - x2, cy - y2)) <= tol:
                continue  # 端点对端点，上面已处理
            for s in ids:
                dsu.union(s, i)

    seg_root = [None if i in excluded else dsu.find(i) for i in range(len(segs))]
    return seg_root, rejected


def hidden_text_boxes(page):
    """返回"隐藏属性文字"的 bbox 列表。

    Altium 等工具导出 PDF 时会叠一层隐藏属性文字（`PI<位号><引脚>`、`NL<网络名>`），
    字体子集还常把 `_` 映射成 `0`（`NLRK0CAN10TX`）。它们不是可读标注，进入网络名
    只会制造 `RK_CAN1_TX` / `NLRK0CAN10TX` 这类重复噪声。

    判据（两条都基于结构，不猜字符串）：
      1. 等宽字体（monospaced，flags & 8）且字号低于本页主字号的 95%——实测这层
         隐藏文字只比正文小 5%~55%，用 80% 会漏掉 `COC1001`(4.14pt vs 主字号 4.79pt)；
      2. 或字号低于主字号的 50%（明显读不出来的都算）。
    绝对字号阈值不可用——不同图纸正常标签从 3.4pt 到 6.5pt 不等。落选文字仍会
    出现在产物的「文字清单」里，只是不参与网络命名，信息不丢。
    """
    spans = []
    try:
        for b in page.get_text("dict")["blocks"]:
            for ln in b.get("lines", []):
                for s in ln.get("spans", []):
                    if s["text"].strip():
                        spans.append((s["size"], s.get("flags", 0), s["bbox"]))
    except Exception:  # noqa: BLE001
        return []
    if not spans:
        return []
    sizes = Counter(round(sz, 1) for sz, _, _ in spans)
    mode = sizes.most_common(1)[0][0]
    out = []
    for sz, flags, bb in spans:
        if sz < 0.5 * mode or ((flags & 8) and sz < 0.95 * mode):
            out.append(bb)
    return out


def attach_labels(page, segs, seg_root, tol: float, label_tol: float):
    """把文字挂到最近线段所属的分量上，按类别分桶存放。

    网络名一般**压在导线上方**（Altium 默认基线在线上 2~4pt），所以对"位于文字
    下方的线段"给一点评分优惠，避免两条相邻信号（间距 7pt）互相抢标签。
    隐藏属性文字（见 hidden_text_boxes）直接跳过。返回 (分量表, 被跳过的隐藏词数)。
    """
    cell = max(8.0, tol * 6)
    grid: dict[tuple[int, int], list[int]] = defaultdict(list)
    for i, (x1, y1, x2, y2) in enumerate(segs):
        if seg_root[i] is None:
            continue
        for gx in range(int(min(x1, x2) // cell), int(max(x1, x2) // cell) + 1):
            for gy in range(int(min(y1, y2) // cell), int(max(y1, y2) // cell) + 1):
                grid[(gx, gy)].append(i)

    comps: dict[object, dict] = {}

    def slot(root):
        return comps.setdefault(
            root,
            {"segs": set(), "net": [], "power": [], "net_lc": [], "pin": [], "refdes": [], "value": [], "other": []},
        )

    for i, r in enumerate(seg_root):
        if r is not None:
            slot(r)["segs"].add(i)

    try:
        words = [w for w in page.get_text("words") if w[4].strip()]
    except Exception:  # noqa: BLE001
        words = []

    hidden = hidden_text_boxes(page)
    n_hidden = 0
    orphans: list[str] = []

    for w in words:
        x0, y0, x1, y1, txt = w[0], w[1], w[2], w[3], w[4]
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        if hidden and any(h[0] <= cx <= h[2] and h[1] <= cy <= h[3] for h in hidden):
            n_hidden += 1
            continue
        best_i, best_score = -1, 1e9
        for gx in range(int((cx - label_tol) // cell), int((cx + label_tol) // cell) + 1):
            for gy in range(int((cy - label_tol) // cell), int((cy + label_tol) // cell) + 1):
                for i in grid.get((gx, gy), []):
                    sx1, sy1, sx2, sy2 = segs[i]
                    d = dist_point_seg(cx, cy, sx1, sy1, sx2, sy2)
                    if d > label_tol:
                        continue
                    seg_y = (sy1 + sy2) / 2
                    score = d - (0.8 if seg_y > cy else 0.0)
                    if score < best_score:
                        best_i, best_score = i, score
        if best_i < 0:
            cls = classify(txt)
            if cls in ("net", "power", "net_lc"):
                orphans.append(txt)
            continue
        root = seg_root[best_i]
        if root is None:
            cls = classify(txt)
            if cls in ("net", "power", "net_lc"):
                orphans.append(txt)
            continue
        bucket = slot(root)[classify(txt)]
        if txt not in bucket:
            bucket.append(txt)

    return comps, n_hidden, orphans


def net_names(c: dict):
    """返回 (权威网络名, 低置信网络名)。电源名与下划线名算权威。"""
    strong = list(c["net"]) + [p for p in c["power"] if p not in c["net"]]
    weak = [w for w in c["net_lc"] if w not in strong]
    return strong, weak


def collect_entries(comps_by_page):
    entries = []
    for pno, comps in comps_by_page:
        for c in comps.values():
            if not c["segs"]:
                continue
            strong, weak = net_names(c)
            entries.append(
                {
                    "page": pno,
                    "strong": strong,
                    "weak": weak,
                    "segs": len(c["segs"]),
                    "pins": sorted(c["pin"], key=lambda s: (len(s), s)),
                    "refdes": c["refdes"][:8],
                    "values": c["value"][:6],
                }
            )
    return entries


def primary_name(e) -> str:
    names = sorted(set(e["strong"] or e["weak"]), key=lambda s: (len(s), s))
    return names[0] if names else ""


def render(stat_rows, entries, total_segs, total_dots, text_sections, rejected, max_nets,
           orphan_rows=None, total_hidden=0) -> str:
    named = [e for e in entries if e["strong"] or e["weak"]]
    conflict = [e for e in named if len(set(e["strong"])) > 1]
    clean = [e for e in named if len(set(e["strong"])) == 1]
    weak_only = [e for e in named if not e["strong"]]
    unnamed = [e for e in entries if not e["strong"] and not e["weak"]]

    clean.sort(key=lambda e: (primary_name(e), -e["segs"]))
    weak_only.sort(key=lambda e: (primary_name(e), -e["segs"]))
    conflict.sort(key=lambda e: (primary_name(e), -e["segs"]))
    unnamed.sort(key=lambda e: -e["segs"])

    out: list[str] = []
    out.append(os.environ.get("PDF2MD_FRONT", "").rstrip() + "\n")
    out.append(
        "> 可信度：本文网络是**几何候选**，分三档 ——「净」（一个分量里只有一个网名，"
        "可作检索线索）、「冲突」（几何相连但网名不一致，必须人工判定）、"
        "「未命名」（只有拓扑没有名字）。**改板、算电流、查短路前一律回原图核对**；"
        "有 `.SchDoc`/`.dsn`/`.kicad_sch` 源文件时应以源文件导出的网表为准。\n"
    )

    out.append("\n## 1. 图形统计\n")
    out.append("| 页 | 线段 | 结点 | 连通网络 | 具名 | 冲突 | 文字 | 其它图元 |")
    out.append("|---:|---:|---:|---:|---:|---:|---:|---:|")
    for r in stat_rows:
        out.append("| %d | %d | %d | %d | %d | %d | %d | %d |" % r)
    out.append(
        "\n合计：线段 %d、结点 %d、连通网络 %d —— 净 %d / 冲突 %d / 仅低置信名 %d / 未命名 %d。"
        % (total_segs, total_dots, len(entries), len(clean), len(conflict), len(weak_only), len(unnamed))
    )
    out.append(
        "按夹角规则判为符号美术图形、未合并的连接 %d 处；跳过隐藏属性文字 %d 条"
        "（`PI<位号><引脚>`/`NL<网络名>` 一类的不可读标注）。" % (rejected, total_hidden)
    )
    if total_segs == 0:
        out.append(
            "\n> **该 PDF 没有矢量线段** —— 大概率是位图/扫描件或加密导出。\n"
            "> 这种情况下无法重建连接关系，只能 `--ocr` 取文字（仍无拓扑），或改用原理图源文件。\n"
        )

    out.append("\n## 2. 净网络（按网名归组，可作检索线索）\n")
    if not clean:
        out.append("（无）\n")
    # 同一网名在图上是多个互不相连的片段（网标处一段、芯片引脚处一段），
    # 按名字归组才能回答"这条信号连到哪些脚/哪些页"。
    groups: dict[str, list] = defaultdict(list)
    for e in clean:
        groups[primary_name(e)].append(e)
    shown = 0
    for name in sorted(groups):
        frags = groups[name]
        shown += 1
        if shown > max_nets:
            break
        alias = set()
        for f in frags:
            alias.update(f["strong"])
        alias.discard(name)
        title = "`%s`" % name
        if alias:
            title += "（别名 %s）" % "、".join("`%s`" % x for x in sorted(alias)[:4])
        title += " — %d 处" % len(frags)
        out.append("### %d. %s" % (shown, title))
        for f in sorted(frags, key=lambda x: (x["page"], -x["segs"]))[:6]:
            bits = ["第 %d 页" % f["page"], "线段 %d" % f["segs"]]
            if f["pins"]:
                bits.append("引脚 " + "/".join(f["pins"][:8]))
            if f["refdes"]:
                bits.append("器件 " + "/".join(f["refdes"][:6]))
            if f["values"]:
                bits.append("值 " + "/".join(f["values"][:3]))
            out.append("- " + " · ".join(bits))
        if len(frags) > 6:
            out.append("- 其余 %d 处未列出" % (len(frags) - 6))
        out.append("")
    if len(groups) > max_nets:
        out.append("> 净网络名共 %d 个，仅显示前 %d 个。\n" % (len(groups), max_nets))

    out.append("\n## 3. 冲突网络（几何相连但网名不一致 —— 必须人工判定）\n")
    if not conflict:
        out.append("（无）\n")
    else:
        out.append(
            "这些分量几何上连在一起，却出现了两个以上独立网络名。成因通常是 PDF 把接插件"
            "符号、总线分支画成与导线同坐标的图形。**不能当作短路结论**，需回原图确认"
            "这几条信号是否真的共网。\n"
        )
        for i, e in enumerate(conflict[:max_nets], 1):
            names = sorted(set(e["strong"]), key=lambda s: (len(s), s))
            out.append(
                "### C%d · %s\n- 第 %d 页 · 线段 %d · 引脚 %s · 器件 %s"
                % (
                    i,
                    " / ".join("`%s`" % n for n in names),
                    e["page"],
                    e["segs"],
                    "/".join(e["pins"][:8]) or "-",
                    "/".join(e["refdes"][:6]) or "-",
                )
            )
            out.append("")
        if len(conflict) > max_nets:
            out.append("> 冲突网络共 %d 个，仅显示前 %d 个。\n" % (len(conflict), max_nets))

    out.append("\n## 4. 仅低置信名（大写无下划线，可能是符号内引脚名）\n")
    if not weak_only:
        out.append("（无）\n")
    for e in weak_only[:max_nets]:
        out.append(
            "- `%s` · 第 %d 页 · 线段 %d · 器件 %s"
            % (primary_name(e), e["page"], e["segs"], "/".join(e["refdes"][:4]) or "-")
        )

    out.append("\n## 5. 未命名网络（只有拓扑）\n")
    for e in unnamed[:max_nets]:
        tail = (" · 器件 " + "/".join(e["refdes"][:4])) if e["refdes"] else ""
        out.append("- 第 %d 页 · 线段 %d%s" % (e["page"], e["segs"], tail))
    if len(unnamed) > max_nets:
        out.append("\n> 未命名网络共 %d 个，仅显示前 %d 个。" % (len(unnamed), max_nets))

    orphan_rows = orphan_rows or []
    orphan_total = sum(len(v) for _, v in orphan_rows)
    out.append("\n## 6. 孤立网络名（图上存在，但 label_tol 内找不到导线）\n")
    if not orphan_total:
        out.append("（无）\n")
    else:
        out.append(
            "这些网络名离任何导线都超过 label_tol，挂不上去。常见于电源端口符号画成填充"
            "多边形（不产生线段）、或标签被放在符号图形内部。**名字本身有效**，可用于"
            "检索，只是本工具没算出它属于哪条网络。\n"
        )
        for pno, names in orphan_rows:
            if names:
                uniq = list(dict.fromkeys(names))
                out.append("- 第 %d 页：%s" % (pno, "、".join("`%s`" % x for x in uniq[:12])))
        out.append("")

    out.append("\n## 7. 文字清单（按页，便于对照原图）\n")
    for idx, body in enumerate(text_sections):
        out.append("### 第 %d 页\n" % (idx + 1))
        out.append("| y | 文字（按 x 排序） |")
        out.append("|---:|---|")
        out.append(body + "\n")

    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--pdf", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--pages", default="")
    ap.add_argument("--tol", type=float, default=2.0)
    ap.add_argument("--label-tol", type=float, default=6.0)
    ap.add_argument("--max-nets", type=int, default=300)
    ap.add_argument("--no-frame-guard", action="store_true", help="关闭图框/标题栏剔除（对比用）")
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
    comps_by_page = []
    text_sections = []
    total_segs = total_dots = total_rejected = total_hidden = 0
    orphan_rows: list[tuple[int, list[str]]] = []

    for pno in range(first, last + 1):
        page = doc[pno]
        segs, dots, other = collect_segments(page, a.tol)
        frame = None if a.no_frame_guard else find_frame(page)
        excluded = frame_segments(segs, frame)
        total_segs += len(segs)
        total_dots += len(dots)

        seg_root, rejected = build_components(segs, dots, a.tol, excluded)
        total_rejected += rejected
        comps, n_hidden, orphans = attach_labels(page, segs, seg_root, a.tol, a.label_tol)
        total_hidden += n_hidden
        orphan_rows.append((pno + 1, orphans))
        comps_by_page.append((pno + 1, comps))

        alive = [c for c in comps.values() if c["segs"]]
        named = sum(1 for c in alive if c["net"] or c["power"] or c["net_lc"])
        conflict = sum(1 for c in alive if len(set(list(c["net"]) + c["power"])) > 1)
        words = [w for w in page.get_text("words") if w[4].strip()]
        stat_rows.append((pno + 1, len(segs), len(dots), len(alive), named, conflict, len(words), other))

        # 文字清单：按 y 聚类成行，便于人工对照原图
        lines: list[list[tuple[float, float, str]]] = []
        for w in sorted(words, key=lambda w: (round(w[1] / 6), w[0])):
            if lines and abs(lines[-1][0][1] - w[1]) <= 6:
                lines[-1].append((w[0], w[1], w[4]))
            else:
                lines.append([(w[0], w[1], w[4])])
        body = "\n".join("| %d | %s |" % (int(ln[0][1]), " ".join(t for _, _, t in ln)) for ln in lines)
        text_sections.append(body if body else "| - | （该页无文字层） |")

    doc.close()

    entries = collect_entries(comps_by_page)
    md = render(stat_rows, entries, total_segs, total_dots, text_sections, total_rejected, a.max_nets,
                orphan_rows, total_hidden)
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(md)

    n_named = sum(1 for e in entries if e["strong"] or e["weak"])
    sys.stderr.write(
        "SCHEMATIC pages=%d segs=%d dots=%d nets=%d named=%d art_skip=%d\n"
        % (last - first + 1, total_segs, total_dots, len(entries), n_named, total_rejected)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
