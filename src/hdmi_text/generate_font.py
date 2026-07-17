#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# font_rom.txt から任意のNxNフォント（Nは2の累乗）を検出し、合成可能な font_rom.cm を自動生成するスクリプト

import os
import sys
import math

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_path = os.path.join(script_dir, "font_rom.txt")
    output_path = os.path.join(script_dir, "font_rom.cm")

    if not os.path.exists(input_path):
        print(f"エラー: {input_path} が見つかりません。")
        sys.exit(1)

    chars = {}
    current_char = None
    rows = []

    # テキスト定義ファイルの読み込み
    with open(input_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("char "):
                if current_char is not None:
                    chars[current_char] = rows
                try:
                    # 'char 32:' のような行から文字コードを取得
                    current_char = int(line.split()[1].replace(":", ""))
                except Exception as e:
                    print(f"行のパースエラー: {line}")
                    sys.exit(1)
                rows = []
            else:
                rows.append(line)
        
        if current_char is not None:
            chars[current_char] = rows

    if not chars:
        print("エラー: 有効な文字データが見つかりませんでした。")
        sys.exit(1)

    # フォントサイズ N の自動検出
    first_char_code = sorted(chars.keys())[0]
    first_char_rows = chars[first_char_code]
    if not first_char_rows:
        print(f"エラー: 文字 {first_char_code} のデータが空です。")
        sys.exit(1)
    
    N = len(first_char_rows[0])
    
    # N が2の累乗かつ8以上であることを検証 (8, 16, 32など)
    if N < 8 or (N & (N - 1)) != 0:
        print(f"エラー: フォント幅/高さ N ({N}) は8以上の2の累乗でなければなりません。")
        sys.exit(1)

    # 全体の整合性チェック
    for char_code, char_rows in chars.items():
        if len(char_rows) != N:
            print(f"エラー: 文字 {char_code} の行数が {N} ではありません (実際: {len(char_rows)})。")
            sys.exit(1)
        for r_idx, r_str in enumerate(char_rows):
            if len(r_str) != N:
                print(f"エラー: 文字 {char_code} の {r_idx} 行目の長さが {N} ではありません (実際: {len(r_str)})。")
                sys.exit(1)

    # 設計定数の計算
    log2_N = int(math.log2(N))
    text_cols = 640 // N
    text_rows = 480 // N
    text_buf_size = text_cols * text_rows
    # ASCII 32〜127 (合計96文字) を表示するため、メッセージ長は 96 固定
    msg_len = 96

    # フォントデータをフラット配列化（index = (char_code - BASE) * N + row）
    BASE = 32
    max_char = max(chars.keys())
    entries = (max_char - BASE + 1) * N
    data = [0] * entries
    for char_code, char_rows in chars.items():
        for r_idx, r_str in enumerate(char_rows):
            val = 0
            for c in r_str:
                if c in (".", " "):
                    val = val << 1
                elif c in ("X", "#"):
                    val = (val << 1) | 1
                else:
                    print(f"エラー: 文字 {char_code} のドット絵に不正な文字 '{c}' があります。")
                    sys.exit(1)
            data[(char_code - BASE) * N + r_idx] = val

    # font_rom.hex の出力（$readmemh用、1行1バイト）
    hex_path = os.path.join(script_dir, "font_rom.hex")
    with open(hex_path, "w", encoding="utf-8") as out:
        for v in data:
            out.write(f"{v:02x}\n")

    # font_rom.cm の出力（BRAM + $readmemh。旧: 83KBの巨大if列 → 合成効率と
    # 可読性のため #[sv::memfile] 方式へ移行）
    with open(output_path, "w", encoding="utf-8") as out:
        out.write("// このファイルは generate_font.py により自動生成されました。手動で編集しないでください。\n")
        out.write("// フォントデータ本体は font_rom.hex（$readmemhで読み込み）。\n")
        out.write("module font_rom;\n\n")

        out.write(f"export const uint FONT_SIZE = {N};\n")
        out.write(f"export const uint LOG2_FONT_SIZE = {log2_N};\n")
        out.write(f"export const uint TEXT_COLS = {text_cols};\n")
        out.write(f"export const uint TEXT_ROWS = {text_rows};\n")
        out.write(f"export const uint TEXT_BUF_SIZE = {text_buf_size};\n")
        out.write(f"export const uint MSG_LEN = {msg_len};\n\n")

        out.write(f"const uint FONT_BASE = {BASE};\n")
        out.write(f"const uint FONT_ENTRIES = {entries};\n\n")

        out.write("// フォントROM（BRAM推論 + font_rom.hex から初期化）\n")
        out.write("#[sv::bram]\n")
        out.write('#[sv::memfile("font_rom.hex")]\n')
        out.write(f"utiny[{entries}] font_data;\n\n")

        out.write("export uint lookup_font(ushort char_code, utiny row) {\n")
        out.write(f"    if (char_code < {BASE} as ushort || char_code > {max_char} as ushort) {{\n")
        out.write("        return 0;\n")
        out.write("    }\n")
        out.write(f"    uint idx = ((char_code as uint) - FONT_BASE) * {N} + (row as uint);\n")
        out.write("    return font_data[idx] as uint;\n")
        out.write("}\n")

    print(f"生成完了: {output_path} ({N}x{N}, {len(chars)}文字, {entries}エントリ)")
    print(f"生成完了: {hex_path}")


if __name__ == "__main__":
    main()
