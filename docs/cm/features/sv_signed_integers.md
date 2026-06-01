# Feature: SV バックエンドの符号付き整数対応

## 概要

Cm SV バックエンドにおける符号付き整数型 (`int`, `short`, `tiny`) の
SystemVerilog `signed` 修飾子付きレジスタ/ワイヤとしての生成対応。

## 現状

### 確認済みの状況

- Cm フロントエンドは `int` (符号付き 32bit), `short` (符号付き 16bit),
  `tiny` (符号付き 8bit) 型をサポート
- SV バックエンドは主に `uint`, `ushort`, `utiny` (unsigned) のみを対象に設計
- `#[sv::param] int FREQ_DIV = 4` はパラメータとして使用されているが、
  ロジック内での符号付き演算の SV 生成は未確認

### SV の符号付き型

```systemverilog
// unsigned (現在サポート)
logic [7:0] data;          // utiny → 8bit unsigned
logic [31:0] counter;      // uint → 32bit unsigned

// signed (必要)
logic signed [7:0] offset;  // tiny → 8bit signed
logic signed [31:0] count;  // int → 32bit signed
```

## 必要性

HDMI プロジェクトの TMDS エンコーダでは **符号付きディスパリティカウンタ** が必要:

```
ランニングディスパリティ (cnt):
  - 範囲: 約 -8 ～ +8
  - 操作: cnt + (N1 - N0), cnt - 2 * (~q_m[8]) + (N1 - N0)
  - 比較: if (cnt > 0), if (cnt < 0)
```

### 回避策 (符号なし整数でのオフセット表現)

```cm
// cnt の実値範囲: -16 ~ +16
// オフセット: +16 → uint 範囲: 0 ~ 32
// cnt == 0 → cnt_reg == 16
uint cnt_reg = 16;

// cnt > 0 のチェック
if (cnt_reg > 16) { ... }

// cnt < 0 のチェック
if (cnt_reg < 16) { ... }

// cnt + delta
cnt_reg = cnt_reg + delta;  // delta もオフセット調整が必要
```

> [!WARNING]
> **オフセット方式のリスク**: 減算結果がアンダーフロー (負の値) になると
> unsigned 表現では巨大な正の値になる。加減算の前にバウンドチェックが必要。

## 実装要件

### 型マッピング

| Cm 型 | SystemVerilog | ビット幅 |
|-------|---------------|----------|
| `tiny` | `logic signed [7:0]` | 8bit signed |
| `short` | `logic signed [15:0]` | 16bit signed |
| `int` | `logic signed [31:0]` | 32bit signed |
| `long` | `logic signed [63:0]` | 64bit signed |

### 比較演算子

符号付き型同士の比較は SV の `signed` セマンティクスに従う:

```systemverilog
// Cm: if (cnt > 0)
// SV: 符号付き比較
if (cnt > 32'sd0) begin ... end
```

### 混合演算

符号付きと符号なしの混合演算は SV で暗黙の符号拡張が発生するため注意:

```systemverilog
// 危険: signed と unsigned の混合
logic signed [7:0] a;
logic [7:0] b;
logic [15:0] c = a + b;  // a が unsigned に昇格する可能性
```

## 優先度

**MEDIUM** — TMDS エンコーダのディスパリティ計算に直接影響するが、
オフセット方式で回避可能。ただし、オフセット方式はバグの温床になりやすい。

## 関連

- [Cm SV Syntax Conventions](../../../.gemini/antigravity-ide/knowledge/cm_systemverilog_backend_implementation/artifacts/usage/syntax_and_conventions.md)
