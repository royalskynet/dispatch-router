#!/usr/bin/env perl
# mask-transcript.mjs 的 perl 版：機器上沒有 node 時 dcq 用這支（Grok 雲端 opencode 是獨立執行檔，不帶 node）。
# 規則與 .mjs 逐條對應，改一邊要改另一邊；test/dcq_mask_test.sh 比對兩版輸出必須相同。
# 用法：perl mask-transcript.pl <in> [out]
use strict; use warnings;
my $in = shift or die "usage: mask-transcript.pl <in> [out]\n";
my $out = shift // "$in.masked";
open my $fh, '<:raw', $in or die "read $in: $!\n"; local $/; my $t = <$fh>; close $fh;
my $n = 0;
# 0. URL 內嵌帳密
$n += ($t =~ s{\b([a-z][a-z0-9+.-]*://)[^\s/:@"'`]+:[^\s/@"'`]*@}{$1<MASKED_USERINFO>\@}gi);
# 1. 已知 key 前綴
$n += ($t =~ s/\b(?:sk|pk|rk)[-_][A-Za-z0-9_-]{12,}/<MASKED_KEY>/g);
$n += ($t =~ s/\b(?:gh[pousr]_|glpat-|xox[baprs]-|hf_|nvapi-|AIza|AKIA|ASIA)[A-Za-z0-9_-]{10,}/<MASKED_KEY>/g);
# 2. PEM
$n += ($t =~ s/-----BEGIN[^-]{0,40}-----[\s\S]*?-----END[^-]{0,40}-----/<MASKED_PEM>/g);
# 3. VAR=值（鍵名含憑證字樣）
$n += ($t =~ s/\b([A-Za-z0-9_]{0,64}(?:SECRET|PASSWORD|PASSWD|TOKEN|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY)[A-Za-z0-9_]{0,64})\s*[:=]\s*["']?[^\s"'`,;)\]}]{6,}/$1=<MASKED_VALUE>/gi);
# 4. 長不透明字串
$n += ($t =~ s{\b(?=[A-Za-z0-9+/_-]{24,})(?=[^\s]*[A-Z])(?=[^\s]*[0-9])[A-Za-z0-9+/_-]{24,}={0,2}\b}{<MASKED_OPAQUE>}g);
# 5. hex ≥32
$n += ($t =~ s/\b[0-9a-f]{32,}\b/<MASKED_HEX>/g);
# 6. email
$n += ($t =~ s/\b[A-Za-z0-9._%+-]+\@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/<MASKED_EMAIL>/g);
# 7. public IPv4
$n += ($t =~ s/\b(?!10\.|127\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.|0\.)(?:\d{1,3}\.){3}\d{1,3}\b/<MASKED_IP>/g);
# 8. passphrase 樣
$n += ($t =~ s/\bcorrect[a-z]{10,}\b/<MASKED_PASSPHRASE>/g);
# 9. 獨立 5 位數字
$n += ($t =~ s/(?<![\d.])\d{5}(?![\d.])/<MASKED_NUM5>/g);
open my $oh, '>:raw', $out or die "write $out: $!\n"; print $oh $t; close $oh;
print "masked $n spans -> $out\n";
