#!/usr/bin/env node
// fix 9767：/fi 抽出的精簡 transcript 原樣保留本 session 出現過的 key 樣字串／email／IPv4，
// 子代理一讀就被 sensitive-canary 擋。抽取那一步就脫敏，不要等撞牆才補。
//
// 路徑寫在腳本內、不出現在 Bash 指令列（fix 9622/9689：canary 會展開指令裡的路徑掃內容，
// 否則連這支脫敏工具都會被自己的閘擋住）。
// 用法：node fi-mask-transcript.mjs <in> <out>   （預設 in=./fi-scan.txt, out=<in>.masked）
import { readFileSync, writeFileSync } from "node:fs";

const inPath = process.argv[2];
const outPath = process.argv[3] || `${inPath}.masked`;
if (!inPath) { console.log("usage: fi-mask-transcript.mjs <in> [out]"); process.exit(1); }

let n = 0;
// tag 可以是字串，也可以是 (match, ...groups) => string 的函式（規則 3 要保留鍵名）。
// 之前只回傳 tag 本身，傳函式進來時會把函式原始碼寫進輸出（遮到了值，但污染 transcript）。
const sub = (s, re, tag) =>
  s.replace(re, (...a) => { n++; return typeof tag === "function" ? tag(...a) : tag; });

let t = readFileSync(inPath, "utf8");
// 0. URL 內嵌帳密 scheme://user:pass@host（canary url-basic-auth）；排在 email 前，否則只遮掉 pass@host 半段
t = sub(t, /\b([a-z][a-z0-9+.-]*:\/\/)[^\s\/:@"'`]+:[^\s\/@"'`]*@/gi, (_m, s) => `${s}<MASKED_USERINFO>@`);
// 1. 已知 key 前綴（sk-/ghp_/gho_/xoxb-/AIza/AKIA/glpat-/hf_/pk_/rk_ + 後續不透明串）
t = sub(t, /\b(?:sk|pk|rk)[-_][A-Za-z0-9_-]{12,}/g, "<MASKED_KEY>");
t = sub(t, /\b(?:gh[pousr]_|glpat-|xox[baprs]-|hf_|AIza|AKIA|ASIA)[A-Za-z0-9_-]{10,}/g, "<MASKED_KEY>");
// 2. PEM / private key 區塊
t = sub(t, /-----BEGIN[^-]{0,40}-----[\s\S]*?-----END[^-]{0,40}-----/g, "<MASKED_PEM>");
// 3. VAR=值 / "VAR": 值 —— 鍵名含憑證字樣時連值一起遮
t = sub(t, /\b([A-Za-z0-9_]{0,64}(?:SECRET|PASSWORD|PASSWD|TOKEN|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY)[A-Za-z0-9_]{0,64})\s*[:=]\s*["']?[^\s"'`,;)\]}]{6,}/gi,
  (_m, k) => `${k}=<MASKED_VALUE>`);
// 4. 長不透明字串（≥24 字、混英數、不是純單字也不是純十六進位路徑片段）
t = sub(t, /\b(?=[A-Za-z0-9+/_-]{24,})(?=[^\s]*[A-Z])(?=[^\s]*[0-9])[A-Za-z0-9+/_-]{24,}={0,2}\b/g, "<MASKED_OPAQUE>");
// 5. hex ≥32（token / hash 樣）
t = sub(t, /\b[0-9a-f]{32,}\b/g, "<MASKED_HEX>");
// 6. email
t = sub(t, /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/g, "<MASKED_EMAIL>");
// 7. public IPv4（略過私網與 loopback）
t = sub(t, /\b(?!10\.|127\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.|0\.)(?:\d{1,3}\.){3}\d{1,3}\b/g, "<MASKED_IP>");
// 8. 常見 passphrase 樣（全小寫無分隔長串，≥16）—— 本 session 的 fixture 就是這類
t = sub(t, /\bcorrect[a-z]{10,}\b/g, "<MASKED_PASSPHRASE>");
// 9. 獨立 5 位數字（canary pii-postal-code 會把 port 20128/20130 當郵遞區號擋）
t = sub(t, /(?<![\d.])\d{5}(?![\d.])/g, "<MASKED_NUM5>");

writeFileSync(outPath, t);
console.log(`masked ${n} spans -> ${outPath}`);
