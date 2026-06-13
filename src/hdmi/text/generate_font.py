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

    # font_rom.cm の出力
    with open(output_path, "w", encoding="utf-8") as out:
        out.write("// このファイルは generate_font.py により自動生成されました。手動で編集しないでください。\n")
        out.write("module font_rom;\n\n")
        
        # 設計パラメータのエクスポート
        out.write(f"export const uint FONT_SIZE = {N};\n")
        out.write(f"export const uint LOG2_FONT_SIZE = {log2_N};\n")
        out.write(f"export const uint TEXT_COLS = {text_cols};\n")
        out.write(f"export const uint TEXT_ROWS = {text_rows};\n")
        out.write(f"export const uint TEXT_BUF_SIZE = {text_buf_size};\n")
        out.write(f"export const uint MSG_LEN = {msg_len};\n\n")

        # フォントテーブル引き当て関数
        out.write("export uint lookup_font(utiny char_code, utiny row) {\n")
        out.write("    uint font_byte = 0;\n\n")

        first = True
        # 文字コード昇順で出力し、合成時の分岐ツリーを最適化
        for char_code in sorted(chars.keys()):
            char_rows = chars[char_code]
            if first:
                out.write(f"    if (char_code == {char_code} as utiny) {{\n")
                first = False
            else:
                out.write(f"    else if (char_code == {char_code} as utiny) {{\n")

            # 全行空 (ドットのみ) かどうか
            all_empty = all(all(c in ('.', ' ') for c in r_str) for r_str in char_rows)
            if all_empty:
                out.write("        font_byte = 0;\n")
            else:
                first_row_if = True
                for r_idx, r_str in enumerate(char_rows):
                    # 空行はデフォルトの0のままスキップ
                    if all(c in ('.', ' ') for c in r_str):
                        continue
                    
                    # 二進数文字列を数値リテラルに変換
                    val = 0
                    for c in r_str:
                        if c in ('.', ' '):
                            val = val << 1
                        elif c in ('X', '#'):
                            val = (val << 1) | 1
                        else:
                            print(f"エラー: 文字 {char_code} のドット絵に不正な文字 '{c}' があります。")
                            sys.exit(1)
                    
                    # Nに応じて適切な桁数の16進数表記にする
                    hex_val = f"0x{val:0{N//4}X}"
                    
                    if first_row_if:
                        out.write(f"        if (row == {r_idx}) {{ font_byte = {hex_val}; }}\n")
                        first_row_if = False
                    else:
                        out.write(f"        else if (row == {r_idx}) {{ font_byte = {hex_val}; }}\n")

            out.write("    }\n")

        out.write("\n    return font_byte;\n")
        out.write("}\n")

    print(f"✓ font_rom.cm が正常に自動生成されました。(フォントサイズ: {N}x{N}, 文字数: {len(chars)})")

if __name__ == "__main__":
    main()
