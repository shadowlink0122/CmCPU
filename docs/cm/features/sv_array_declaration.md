# Feature: SV バックエンドの配列宣言対応

## 概要

Cm SV バックエンドにおける固定長配列の SystemVerilog レジスタファイル /
メモリ配列としての生成対応。

## 現状

### 確認済みの状況

- `#[sv::bram]` 属性は MIR の `attributes` フィールドに伝達される
- SV バックエンドがこの属性を読み取り、`(* ram_style = "block" *)` を
  生成する仕組みは設計されている
- **配列型の SV コード生成が実装済みか未確認**

### 既存の回避策

`uart_hello.cm` / `uart_button.cm` では、配列の代わりに
`if/else` チェーンでルックアップテーブルを実現:

```cm
// 配列の代わりに if/else チェーン
if (msg_idx == 0) { tx_data = 'H' as utiny; }
if (msg_idx == 1) { tx_data = 'e' as utiny; }
// ...
```

## 必要性

HDMI プロジェクトでは以下のデータ構造に配列が必要:

| データ | サイズ | 用途 |
|--------|--------|------|
| フォント ROM | 760 バイト | 8×8 ASCII フォントデータ |
| テキストバッファ | 360 バイト | 20×18 文字グリッド |
| カラーパレット | 16 エントリ | GBC 15bit RGB パレット |
| フレームバッファ | 23,040 バイト (160×144) | ※ 将来の拡張用 |

### フォント ROM の場合

```cm
// 理想的な実装
#[sv::bram]
utiny font_rom[760];  // 95 文字 × 8 行

// フォントルックアップ
uint font_addr = (char_code - 32) * 8 + font_row;
uint font_byte = font_rom[font_addr];
```

### 期待される SV 出力

```systemverilog
(* ram_style = "block" *)
reg [7:0] font_rom [0:759];

// 初期化 (Gowin では $readmemh を使用)
initial begin
    $readmemh("font_rom.hex", font_rom);
end

// 読み出し
always_ff @(posedge clk) begin
    font_byte <= font_rom[font_addr];
end
```

## 実装要件

### 1. 配列宣言

Cm の固定長配列を SV の reg 配列として生成:

```
Cm:  utiny data[256];
SV:  reg [7:0] data [0:255];

Cm:  ushort buffer[1024];
SV:  reg [15:0] buffer [0:1023];
```

### 2. BRAM 属性

`#[sv::bram]` が付いた配列に合成ヒントを追加:

```
Cm:  #[sv::bram] utiny rom[760];
SV:  (* ram_style = "block" *) reg [7:0] rom [0:759];
```

### 3. 配列アクセス

```
Cm:  val = data[idx];
SV:  val = data[idx];

Cm:  data[idx] = val;
SV:  data[idx] <= val;  // (always_ff 内)
```

### 4. 初期化

配列の初期値設定方法:
- **方式 A**: `$readmemh` / `$readmemb` で外部ファイルから読み込み
- **方式 B**: `initial begin` ブロックで直接代入
- **方式 C**: 合成時定数として if/else ツリーで初期化 (フォールバック)

## 回避策 (配列未対応時)

配列が SV バックエンドで未対応の場合の実装パターン:

### パターン A: if/else ROM

```cm
// 小規模 ROM (< 100 エントリ) に適用
void lookup(posedge clk) {
    if (addr == 0) { data_out = 130; }
    if (addr == 1) { data_out = 130; }
    // ... (合成ツールが最適化)
}
```

### パターン B: Gowin IP ROM

Gowin EDA の IP Core Generator で ROM/RAM を生成し、
`extern struct` としてインスタンス化:

```cm
extern struct FontROM {
    #[input]  ushort ADDR = font_addr;
    #[output] utiny  DOUT = font_byte;
    #[input]  posedge CLK = pixel_clk;
}
FontROM font_rom_inst;
```

## 優先度

**MEDIUM** — if/else パターンと Gowin IP で回避可能だが、
コードの保守性と可読性に大きく影響する。
テキストバッファ (360 エントリ) の if/else チェーンは実用的でない。

## 関連

- [SV Backend: BRAM Inference](../../../.gemini/antigravity-ide/knowledge/cm_systemverilog_backend_implementation/artifacts/attributes_and_mapping.md)
- [MIR Extensions](../../../.gemini/antigravity-ide/knowledge/cm_systemverilog_backend_implementation/artifacts/mir_extensions.md)
