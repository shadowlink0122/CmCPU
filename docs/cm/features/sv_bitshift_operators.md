# Feature: ビットシフト演算子の SV バックエンド対応

## 概要

Cm SV バックエンドにおけるビットシフト演算子 (`<<`, `>>`) の
SystemVerilog コード生成対応。

## 現状

### 確認済みの状況

- Cm フロントエンドは `<<` (左シフト) と `>>` (右シフト) を構文解析可能
- MIR には `Shl` (Shift Left) と `Shr` (Shift Right) 命令が存在
- **SV バックエンドでの動作が未確認**

### 既存の回避策

`uart_hello.cm` および `uart_button.cm` では、ビットシフトの代わりに
除算 (`/`) とビットマスク (`&`) を組み合わせて使用している:

```cm
// ビット 3 の抽出
// 本来: tx_bit = (tx_data >> 3) & 1;
// 現状の回避策:
tx_bit = (tx_data & 8) / 8;
```

## 必要性

HDMI テキスト出力プロジェクトでは以下の場面でビットシフトが必要:

| 用途 | 式 | 回避策 |
|------|-----|--------|
| TMDS エンコーダ: ビットカウント | `(d >> i) & 1` | `(d & (1 << i)) / (1 << i)` |
| TMDS DC バランス: ディスパリティ | `cnt + 2 * q_m[8]` | 乗算で代替 |
| フォント ROM: ピクセル抽出 | `(font_byte >> (7 - col)) & 1` | 8 通りの if/else |
| 15bit→24bit カラー変換 | `r5 << 3` | `r5 * 8` |
| GBC 座標: /8 相当 | `gbc_x >> 3` | `gbc_x / 8` |

## 実装要件

### SV バックエンドでの生成

MIR の `Shl` / `Shr` 命令に対して、以下の SystemVerilog コードを生成:

```systemverilog
// Shl: a << b
assign result = operand_a << operand_b;

// Shr (論理右シフト): a >> b
assign result = operand_a >> operand_b;
```

### ビット幅の考慮

- シフト量がリテラルの場合: `a << 3` → `a << 3'd3` (幅整合)
- シフト量が変数の場合: `a << b` → `a << b` (Verilator が幅チェック)
- 結果の幅: 入力オペランドと同じ幅

## 検証方法

### テストケース

```cm
//! platform: sv

#[input] posedge clk;
#[input] utiny data_in = 0;
#[output] utiny shifted_left = 0;
#[output] utiny shifted_right = 0;
#[output] bool bit_extract = false;

void process(posedge clk) {
    shifted_left = (data_in << 3) as utiny;
    shifted_right = (data_in >> 2) as utiny;
    bit_extract = ((data_in >> 5) & 1) == 1;
}
```

### 期待される SV 出力

```systemverilog
always_ff @(posedge clk) begin
    shifted_left <= data_in << 3;
    shifted_right <= data_in >> 2;
    bit_extract <= ((data_in >> 5) & 1) == 1;
end
```

## 優先度

**HIGH** — TMDS エンコーダの効率的な実装に不可欠。
回避策 (除算 + マスク) は動作するが、合成リソースが増大し、
コードの可読性が著しく低下する。

## 関連

- [SV Backend Implementation](../../../.gemini/antigravity-ide/knowledge/cm_systemverilog_backend_implementation/artifacts/overview.md)
- [Hazard #50: Temporary Variable Type Inference](../../../.gemini/antigravity-ide/knowledge/cm_compiler_hazards_and_limitations/artifacts/backend/systemverilog_hazards.md)
