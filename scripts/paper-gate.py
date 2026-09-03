#!/usr/bin/env python3
"""Slip design gate — phase 1: Paper boards.
Pulls computed styles for every node of every artboard from the Paper MCP HTTP
server and enforces mechanical rules derived from the scraped HIG corpus
(~/Developer/midnight-ios-spike/hig/) and the Sealed design-system laws.

Checks:
  G1  palette discipline   — every color must be a system token value (or exempt)
  G2  no pure black/white text-on-bg combos outside tokens
  G3  type scale           — fontSize ∈ scale; flags strays
  G4  HIG body             — text blocks >80 chars must be ≥17px
  G5  WCAG contrast        — text vs effective bg ≥4.5:1 (<18px) / ≥3:1 (≥18px or ≥14px bold)
  G6  tap targets          — pressable-looking nodes (bg+radius+text) ≥44px height
  G7  one wax moment       — >2 distinct wax clusters per screen board = fail
  G8  wax never means loss — wax color on nodes whose text contains ✗/lost
  G9  board hygiene        — phone boards are 393×852(+); home indicator present
Exit 0 = pass, 1 = violations. --json for machine output.
"""
import json, os, re, subprocess, sys, urllib.request

BASE = "http://127.0.0.1:29979/mcp"
SESS = "/tmp/paper-gate-session.txt"

TOKENS = {  # v3 native palette
    "#F7F7F6": "bg", "#FFFFFF": "card/on-seal", "#EFEFED": "fill", "#E8E8E6": "separator",
    "#17171A": "ink", "#66666E": "secondary", "#C63A2B": "seal", "#FAE8E5": "seal-tint",
    "#1F7A43": "win", "#E3EEF9": "crest-sky", "#2F6395": "crest-sky-deep",
    "#FBEFDC": "crest-amber", "#8A5A18": "crest-amber-deep",
    "#EEE9F4": "art-slip-base", "#EDEFEA": "art-office-base",
    "#5E5560": "ambient", "#232126": "ticket", "#67D08F": "win-on-dark",
    "#0A0A0A": "bg-dark", "#1C1C1E": "card-dark", "#232326": "fill-dark",
    "#2C2C2E": "separator-dark", "#F2F2F7": "ink-dark", "#98989F": "secondary-dark",
}
TYPE_SCALE = {10, 12, 13, 15, 17, 20, 22, 28, 34}
TYPE_SCALE_AX = {10, 17, 18, 19, 21, 22, 23, 26, 28, 34, 40}  # HIG xxxLarge Dynamic Type; boards named "(AX)"
WAX = {"#C63A2B"}

def post(payload, sess=None):
    req = urllib.request.Request(BASE, data=json.dumps(payload).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json, text/event-stream")
    if sess: req.add_header("mcp-session-id", sess)
    r = urllib.request.urlopen(req, timeout=120)
    sid = r.headers.get("mcp-session-id"); body = r.read().decode()
    out = None
    for line in body.splitlines():
        if line.startswith("data:"):
            try: out = json.loads(line[5:])
            except json.JSONDecodeError: pass
    return out, sid

def session():
    if os.path.exists(SESS): return open(SESS).read().strip()
    r, sid = post({"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"design-gate","version":"1"}}})
    open(SESS,"w").write(sid or "")
    post({"jsonrpc":"2.0","method":"notifications/initialized"}, sid)
    return sid

def call(tool, args):
    r, _ = post({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":tool,"arguments":args}}, session())
    if r is None: raise RuntimeError(f"{tool}: no response")
    if "error" in r:
        if "session" in json.dumps(r["error"]).lower():  # stale session
            os.remove(SESS); return call(tool, args)
        raise RuntimeError(f"{tool}: {r['error']}")
    txt = "".join(c.get("text","") for c in r["result"].get("content",[]) if c.get("type")=="text")
    return json.loads(txt) if txt.strip().startswith("{") else txt

TOKEN_MAP = {}
def hex_norm(c):
    if not c: return None
    c = c.strip()
    m = re.match(r"var\((--[a-zA-Z0-9_-]+)\)", c)
    seen = set()
    while m:
        name = m.group(1)
        if name in seen: return None
        seen.add(name)
        c = str(TOKEN_MAP.get(name, "")).strip()
        if not c: return None
        m = re.match(r"var\((--[a-zA-Z0-9_-]+)\)", c)
    c = c.lower()
    m = re.match(r"rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)", c)
    if m:
        r,g,b = (int(m.group(i)) for i in (1,2,3)); a = float(m.group(4) or 1)
        if a < 0.99: return None  # translucent = derived, skip palette check
        return f"#{r:02X}{g:02X}{b:02X}"
    m = re.match(r"#([0-9a-f]{6})([0-9a-f]{2})$", c)
    if m:  # 8-digit hex with alpha
        if int(m.group(2), 16) < 252: return None  # translucent — composite unknown
        return "#" + m.group(1).upper()
    m = re.match(r"#([0-9a-f]{6})$", c)
    if m: return "#" + m.group(1).upper()
    if c.startswith("var(") or c in ("transparent","none"): return None
    return None

def lum(hexc):
    r,g,b = (int(hexc[i:i+2],16)/255 for i in (1,3,5))
    f = lambda x: x/12.92 if x <= 0.04045 else ((x+0.055)/1.055)**2.4
    return 0.2126*f(r)+0.7152*f(g)+0.0722*f(b)

def contrast(a,b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la,lb), min(la,lb)
    return (hi+0.05)/(lo+0.05)

LINE = re.compile(r'^(\s*)(\w[\w ]*?) "((?:[^"\\]|\\.)*)" \(([\w-]+)\) (\d+)×(\d+)(?: "(.*)")?$')
def parse_tree(summary):
    nodes, stack = [], []  # stack of (indent, id)
    for line in summary.splitlines():
        m = LINE.match(line)
        if not m:
            continue
        indent = len(m.group(1)) // 2
        comp, name, nid = m.group(2), m.group(3), m.group(4)
        w, h = int(m.group(5)), int(m.group(6))
        text = m.group(7)
        while stack and stack[-1][0] >= indent:
            stack.pop()
        parent = stack[-1][1] if stack else None
        nodes.append({"id": nid, "comp": comp, "name": name, "w": w, "h": h,
                      "text": text, "parent": parent})
        stack.append((indent, nid))
    return nodes

def main():
    as_json = "--json" in sys.argv
    info = call("get_basic_info", {})
    for t in info.get("tokens", {}).get("items", []):
        TOKEN_MAP[t["name"]] = t["value"]
    findings, boards_checked = [], 0
    F = lambda board, rule, node, msg: findings.append({"board": board, "rule": rule, "node": node, "msg": msg})

    for ab in info["artboards"]:
        bid, bname = ab["id"], ab["name"]
        boards_checked += 1
        tree = call("get_tree_summary", {"nodeId": bid, "depth": 24})
        nodes = parse_tree(tree["summary"] if isinstance(tree, dict) else tree)
        ids = [n["id"] for n in nodes]
        styles = {}
        for i in range(0, len(ids), 40):
            batch = call("get_computed_styles", {"nodeIds": ids[i:i+40]})
            for k, v in (batch.get("styles", batch) if isinstance(batch, dict) else {}).items():
                styles[k] = v
        parent_of = {n["id"]: n["parent"] for n in nodes if n["parent"]}
        name_of = {n["id"]: n["name"] for n in nodes}
        size_of = {n["id"]: (n["w"], n["h"]) for n in nodes}
        text_of = {n["id"]: (n["text"] if n["text"] is not None else n["name"]) for n in nodes if n["comp"] == "Text"}

        def eff_bg(nid):
            cur = nid
            while cur:
                bg = hex_norm(styles.get(cur,{}).get("backgroundColor"))
                if bg: return bg
                cur = parent_of.get(cur)
            return "#F7F7F6"

        wax_clusters = set()
        is_phone = abs(ab["width"] - 393) < 4 or abs(ab["width"] - 375) < 4
        for nid in ids:
            st = styles.get(nid, {})
            comp_is_text = nid in text_of
            # G1/G2 palette
            for prop in ("color","backgroundColor","borderColor"):
                h = hex_norm(st.get(prop))
                if h and h not in TOKENS:
                    F(bname,"G1",nid,f"{prop} {h} not in system palette ({name_of.get(nid,'')[:24]})")
                if h == "#000000":
                    F(bname,"G2",nid,f"pure {h} on {prop}")
            # G3/G4 type
            fs = st.get("fontSize")
            if comp_is_text and fs:
                fs_s = str(fs).strip()
                mv = re.match(r"var\((--[a-zA-Z0-9_-]+)\)", fs_s)
                if mv: fs_s = str(TOKEN_MAP.get(mv.group(1), fs_s))
                try: px = float(fs_s.replace("px",""))
                except ValueError:
                    F(bname,"G3",nid,f"fontSize {fs} unresolvable"); continue
                is_ax = "(AX)" in bname
                scale = TYPE_SCALE_AX if is_ax else TYPE_SCALE
                body_min = 23 if is_ax else 17
                if int(px) not in scale:
                    F(bname,"G3",nid,f"fontSize {px}px off-scale ('{text_of[nid][:24]}')")
                full = text_of.get(nid,"")
                if len(full) >= 59:
                    ni = call("get_node_info", {"nodeId": nid})
                    full = ni.get("textContent") or full
                    text_of[nid] = full
                fam = hexf = str(st.get("fontFamily",""))
                if fam.startswith("var("):
                    fam = str(TOKEN_MAP.get(fam[4:-1], fam))
                if px < body_min and len(full) > 80 and "Mono" not in fam:
                    F(bname,"G4",nid,f"long text at {px}px (<{body_min} HIG body) ('{text_of[nid][:30]}…')")
                # G5 contrast
                fg = hex_norm(st.get("color"))
                if fg:
                    bg = eff_bg(parent_of.get(nid, nid))
                    ratio = contrast(fg, bg)
                    w_raw = str(st.get("fontWeight","400")).replace("normal","400").replace("bold","700")
                    weight = int(re.match(r"\d+", w_raw).group(0)) if re.match(r"\d+", w_raw) else 400
                    large = px >= 18.66 or (px >= 14 and weight >= 700)
                    need = 3.0 if large else 4.5
                    if ratio < need:
                        F(bname,"G5",nid,f"contrast {ratio:.2f}:1 (<{need}) {fg} on {bg} @{px:.0f}px ('{text_of[nid][:24]}')")
            # G6 tap targets (pressable heuristic)
            bg = hex_norm(st.get("backgroundColor"))
            br = str(st.get("borderRadius","0"))
            h = st.get("height")
            border_ink = hex_norm(st.get("borderColor")) == "#1C1814"
            affordant = bg in WAX or bg == "#1C1814" or border_ink
            w_, h_ = size_of.get(nid, (0, 0))
            child_texts = [text_of[t] for t in text_of if parent_of.get(t) == nid]
            is_avatar = w_ == h_ and w_ <= 44 and child_texts and max(len(t) for t in child_texts) <= 2
            if affordant and not is_avatar and br not in ("0","0px","") and nid not in text_of and is_phone:
                kids_text = bool(child_texts)
                if kids_text:
                    hv = size_of.get(nid, (0, 0))[1]
                    if 20 <= hv < 44:
                        F(bname,"G6",nid,f"pressable-looking node height {hv}px < 44 ({name_of.get(nid,'')[:20]})")
            # G7 wax census — only MOMENTS (>=28px tall); tiny seal-dots may repeat
            if bg in WAX and size_of.get(nid,(0,0))[1] >= 28:
                top = nid
                while parent_of.get(top):
                    cand = parent_of[top]
                    if hex_norm(styles.get(cand,{}).get("backgroundColor")) in WAX and size_of.get(cand,(0,0))[1] >= 28: top = cand
                    else: break
                wax_clusters.add(top)
            # G8 wax-as-loss
            if comp_is_text and hex_norm(st.get("color")) in WAX and re.search(r"[✗x]\s*0|lost", text_of[nid], re.I):
                F(bname,"G8",nid,"wax color used for a loss")
        if is_phone and len(wax_clusters) > 1:
            F(bname,"G7","-",f"{len(wax_clusters)} large wax moments on one screen (law: one; small seal-dots exempt)")
        if is_phone and ab["height"] >= 800:
            hi = [nid for nid in ids if size_of.get(nid,(0,0))[1] == 5 and str(styles.get(nid,{}).get("borderRadius","")).startswith("999")]
            if not hi:
                F(bname,"G9","-","phone board missing home indicator")
            if abs(ab["width"]-375) < 4:
                F(bname,"G9","-","board is 375pt — system canvas is 393 (iPhone 16/17)")

    if as_json:
        print(json.dumps({"boards": boards_checked, "findings": findings}, indent=1))
    else:
        print(f"design-gate: {boards_checked} boards, {len(findings)} finding(s)")
        for f in findings:
            print(f"  [{f['rule']}] {f['board']}: {f['msg']}")
    sys.exit(1 if findings else 0)

main()
