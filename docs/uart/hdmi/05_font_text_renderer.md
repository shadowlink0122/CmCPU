# Phase 2: フォント ROM & テキストレンダラ

## 概要

8×8 ピクセルの ASCII フォントデータを BRAM に格納し、
テキスト文字列をピクセルデータに変換するモジュール群。

## フォント ROM 設計

### 8×8 ASCII フォント仕様

| パラメータ | 値 |
|------------|-----|
| 文字サイズ | 8 × 8 ピクセル |
| 文字セット | ASCII 0x20 ~ 0x7E (95 文字) |
| データ形式 | 1bpp (1bit/pixel) |
| 合計容量 | 95 × 8 = 760 バイト |
| BRAM 使用 | 1 ブロック以下 |

### フォントデータ形式

各文字は 8 バイト (8 行 × 8 ビット) で表現:

```
'H' (0x48) のフォントデータ:
行0: 0b10000010 = 0x82  ■□□□□□■□
行1: 0b10000010 = 0x82  ■□□□□□■□
行2: 0b10000010 = 0x82  ■□□□□□■□
行3: 0b11111110 = 0xFE  ■■■■■■■□
行4: 0b10000010 = 0x82  ■□□□□□■□
行5: 0b10000010 = 0x82  ■□□□□□■□
行6: 0b10000010 = 0x82  ■□□□□□■□
行7: 0b00000000 = 0x00  □□□□□□□□
```

### Cm 実装 (BRAM フォント ROM)

```cm
//! platform: sv

// フォント ROM: 8×8 ASCII フォント
// ASCII 0x20 (' ') から 0x7E ('~') まで
// アドレス = (文字コード - 0x20) * 8 + 行番号

#[sv::bram]
utiny font_data[760];  // 95文字 × 8行

// 初期化は合成時に初期値として設定
// 実装では const 配列として if/else チェーンで
// ROM のように振る舞わせる
```

> [!IMPORTANT]
> **Cm SV バックエンドの BRAM 対応状況**:
> `#[sv::bram]` 属性は MIR に伝達されるが、配列宣言が SV の
> `reg [7:0] font_data [0:759]` として正しく生成されるか確認が必要。
> 
> **代替案**: 配列が使えない場合、`if/else` チェーンによる
> ハードコーディング ROM として実装する（合成ツールが最適化）。
> 既存の `uart_hello.cm` でも同様のパターンが使用されている。

### ハードコーディング ROM パターン (フォールバック)

```cm
// フォントルックアップ (ハードコード方式)
// char_code: ASCII コード, row: 行番号 (0-7)
// → font_byte: 8bit フォントデータ

uint font_byte = 0;

void lookup_font(posedge pixel_clk) {
    // 'H' = 0x48
    if (char_code == 72) {
        if (row == 0) { font_byte = 130; }  // 0x82
        if (row == 1) { font_byte = 130; }
        if (row == 2) { font_byte = 130; }
        if (row == 3) { font_byte = 254; }  // 0xFE
        if (row == 4) { font_byte = 130; }
        if (row == 5) { font_byte = 130; }
        if (row == 6) { font_byte = 130; }
        if (row == 7) { font_byte = 0; }
    }
    // 'e' = 0x65
    if (char_code == 101) {
        if (row == 0) { font_byte = 0; }
        if (row == 1) { font_byte = 0; }
        if (row == 2) { font_byte = 124; }  // 0x7C
        if (row == 3) { font_byte = 130; }  // 0x82
        if (row == 4) { font_byte = 254; }  // 0xFE
        if (row == 5) { font_byte = 128; }  // 0x80
        if (row == 6) { font_byte = 124; }  // 0x7C
        if (row == 7) { font_byte = 0; }
    }
    // ... (残りの文字)
}
```

## テキストレンダラ設計

### テキストバッファ

GBC 解像度 160×144 で 8×8 フォントを使用すると:
- 水平: 160 / 8 = **20 文字/行**
- 垂直: 144 / 8 = **18 行**
- 合計: 20 × 18 = **360 文字**

```
┌────────── 160 px ──────────┐
│ H  e  l  l  o  ,     W  o │ 行 0
│ r  l  d  !              │ 行 1
│                           │ 行 2
│        (空白)             │  :
│                           │ 行17
└───────────────────────────┘
  20文字 × 18行 = 360文字
```

### テキストバッファの実装

```cm
// テキストバッファ (20×18 = 360 文字)
// 各エントリは ASCII コード (utiny)
uint text_buf[360];  // 360 バイト (uint で宣言、下位 8bit 使用)

// テキストバッファのアドレス計算
// text_addr = text_row * 20 + text_col
```

### ピクセル生成パイプライン

```
座標入力 (gbc_x, gbc_y)
    │
    ├── text_col = gbc_x / 8  (文字列位置)
    ├── text_row = gbc_y / 8  (行位置)
    ├── font_col = gbc_x & 7  (フォント内X)
    └── font_row = gbc_y & 7  (フォント内Y)
         │
         ▼
    text_buf[text_row * 20 + text_col] → char_code
         │
         ▼
    font_rom[char_code * 8 + font_row] → font_byte
         │
         ▼
    pixel = (font_byte >> (7 - font_col)) & 1
         │
         ▼
    if pixel == 1:
        color = foreground_palette
    else:
        color = background_palette
```

> [!WARNING]
> **`& 7` (AND 7) によるモジュロ 8**:
> Cm SV バックエンドで `&` がビットwise AND として正しく生成されることは
> 既存の `uart_hello.cm` で確認済み。
> ただし `>>` (右シフト) については要確認。

> [!WARNING]
> **除算 `/8` の回避**:
> `gbc_x / 8` は右シフト `gbc_x >> 3` と等価だが、
> Cm SV バックエンドでのシフト演算子対応が不明な場合は `/8` を使用する。
> 合成ツール (Gowin) は 2のべき乗除算をシフトに最適化する。

## テスト計画

| テスト | 検証内容 | 合格基準 |
|--------|----------|----------|
| TB-FR-01 | フォント ROM 読み出し | 'H' のフォントデータが正しい |
| TB-FR-02 | テキストバッファ参照 | (0,0) → 最初の文字 |
| TB-FR-03 | ピクセル生成 | 'H' の (0,0) → 1 (黒ピクセル) |
| TB-FR-04 | カラーパレット適用 | fg/bg 色が正しく選択 |
| TB-FR-05 | 20×18 テキスト範囲 | 全セルがアドレス可能 |
