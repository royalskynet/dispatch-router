# x_pool_changes：從 @opencode 推文第一行讀出改名／上架／下架。邏輯改錯這支要 fail。
import importlib.machinery, importlib.util, os, sys, tempfile
here = os.path.dirname(os.path.abspath(__file__))
l = importlib.machinery.SourceFileLoader("ofc", os.path.join(here, "..", "bin", "oc-free-check"))
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("ofc", l)); l.exec_module(m)
ofc_age = m.x_age_days
m.x_age_days = lambda tid: 10 if tid == "6" else 0  # 6 號當 10 天前的舊文
known = {"space-bunny-free", "minimax-m3.1-flash-free", "beam-free", "glm-5.3-flash", "glm-5.3-flash-free",
         "cat-jam-free", "exo-free", "gemini-4-argon"}
posts = [("1", "", "Space Bunny was MiniMax M3.1 Flash  #1 on OpenCode for 12 consecutive days"),
         ("2", "", "DeepSeek V4.1 Flash updated to 1017 in OpenCode Go and Free  No changes"),
         ("3", "", "Beam is now available in OpenCode\n- 1M Context - Free for a limited time"),
         ("4", "", "Gemini 4 Argon is now available in OpenCode Go  $60 usage"),
         ("5", "", "GLM 5.3 Flash is now free in OpenCode"),
         ("6", "", "Cat Jam (stealth model) is now free in OpenCode  - very fast"),
         ("7", "", "Exo Free is no longer free on OpenCode"),
         ("8", "", "Totally Unknown Model is now free in OpenCode")]
got = m.x_pool_changes(posts, known)
want = [("1", "GONE", "space-bunny-free"), ("1", "NEW", "minimax-m3.1-flash-free"), ("3", "NEW", "beam-free"),
        ("5", "NEW", "glm-5.3-flash-free"), ("7", "GONE", "exo-free")]
assert got == want, f"got {got}"
d = tempfile.mkdtemp(); f = os.path.join(d, "x-pool.tsv")
assert len(m.record_x_pool(f, got)) == 5 and m.record_x_pool(f, got) == [], "重跑不該重記"
real = 2112156205938626954  # 10-19 Space Bunny 推文
assert 0 < ofc_age(real) < 30, ofc_age(real)
print("PASS x_pool")
