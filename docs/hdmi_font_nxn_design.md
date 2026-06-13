# HDMIフォントNxN対応および設計仕様書

## 1. 概要
本設計書は、HDMIテキスト出力モジュールにおいて、任意の $N \times N$（ただし $N = 2^n$, 例: 8x8, 16x16, 32x32など）のフォントサイズに対応可能とし、フォントデータを「文字列の2次元配列」形式で管理・メンテナンス可能にするための設計変更について定めます。

CmコンパイラおよびSystemVerilogの制約により、Cmコード内での動的な文字列配列の合成が不可能なため、Pythonスクリプトによるビルド前コード生成（コードジェネレータ方式）を踏襲しつつ、任意のフォントサイズ $N$ に適応できるように一般化を行います。

## 2. 設計方針

### 2.1 Pythonによるフォント表現と自動検出
- 開発者がフォントを定義する `font_rom.txt`（または `generate_font.py` 内の構造）において、各文字を $N$ 行 $\times$ $N$ 列の「文字列の2次元配列」として表現します。
- `generate_font.py` は、定義ファイルからフォントサイズ $N$ を自動検出し、以下の整合性をチェックします：
  - $N$ が2の累乗（8, 16, 32など）であること。
  - すべての文字ブロックが正確に $N \times N$ のドット数で定義されていること。

### 2.2 Cm出力コードの一般化
従来のコードジェネレータは 8x8 固定で、マクロ風ヘルパー関数 `L(...)` を生成していましたが、任意の $N$ に対応するため、以下の変更を行います：
- 各行の `.` (0) と `X` or `#` (1) の文字列表現を、Python側で直接ビット値に変換し、Cmの16進数リテラル（例：`0x18`, `0x00FF`）として出力します。
- `font_rom.cm` に以下の設計定数をエクスポートします：
  - `FONT_SIZE` : $N$（フォントの幅・高さ）
  - `LOG2_FONT_SIZE` : $\log_2(N)$（ビットシフト用定数）
  - `TEXT_COLS` : $160 / N$（画面の列数）
  - `TEXT_ROWS` : $144 / N$（画面の行数）
  - `TEXT_BUF_SIZE` : `TEXT_COLS * TEXT_ROWS`（テキストバッファ全体のサイズ）
  - `MSG_LEN` : `TEXT_BUF_SIZE - 2 * TEXT_COLS`（表示可能な最大ASCII文字数、最大95）

### 2.3 `text_renderer.cm` の動的パラメータ化
`FONT_SIZE` に依存していたハードコーディングを排除し、`font_rom.cm` からインポートした定数でレンダリング座標およびバッファアドレスを計算します：
1. **座標マスク**: `gbc_x & (FONT_SIZE - 1)` / `gbc_y & (FONT_SIZE - 1)`
2. **バッファアドレス**: `((gbc_y >> LOG2_FONT_SIZE) * TEXT_COLS) + (gbc_x >> LOG2_FONT_SIZE)`
3. **ピクセル抽出シフト**: `font_byte >> ((FONT_SIZE - 1) - font_col_reg)`
4. **カーソル表示スケール**: カーソル（"Hello World" の相対描画）の内部座標 `cx`, `cy` について、フォントサイズに応じて適切にスケーリングを行うことで、8x8以外のフォントでも表示位置・大きさが自動追従するようにします。
   - `cx = (font_col_reg * 8 / FONT_SIZE)`
   - `cy = (font_row_reg * 8 / FONT_SIZE)`

### 2.4 `animation_ctrl.cm` の動的パラメータ化
- 定数 `TEXT_COLS` および `MSG_LEN` を `font_rom.cm` からのインポート値に基づいて動的に処理します。
- バッファのアドレス計算や行・列の折り返し計算を、フォントサイズから算出された列数で実行します。

---

## 3. 実装詳細

### 3.1 `generate_font.py` の一般化ロジック
入力データから $N$ を検出し、妥当性を検証後、次のように `font_rom.cm` を生成します：
```python
# $N$ は検出されたフォントサイズ
log2_N = int(math.log2(N))
text_cols = 160 // N
text_rows = 144 // N
text_buf_size = text_cols * text_rows
msg_len = min(95, text_buf_size - 2 * text_cols)
```
各行のビット列は以下のように16進数にパースされます：
```python
val = 0
for char in row_str:
    val = (val << 1) | (1 if char in ('X', '#') else 0)
hex_literal = f"0x{val:0{N//4}X}" # 8x8なら 0xXX, 16x16なら 0xXXXX
```

### 3.2 座標変換・スケール処理
`text_renderer.cm` における座標スケーリング計算は、除算が定数で除されるため、合成ツールによって自動的に効率的な論理回路（定数シフトや加算）へ最適化されます。
