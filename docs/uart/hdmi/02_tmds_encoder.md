# Phase 1: TMDS エンコーダ

## 概要

DVI/HDMI 出力に必要な TMDS (Transition Minimized Differential Signaling) エンコーダ。
8bit RGB データを 10bit TMDS シンボルに変換する。RGB 3チャネル分のエンコーダを
インスタンス化して使用する。

## TMDS エンコーディングアルゴリズム

### ステージ 1: 遷移最小化 (ビット 0-8)

8bit 入力を 9bit 中間コード (q_m) に変換する。

```
入力: D[7:0] (8bit データ)
出力: q_m[8:0] (9bit 中間コード)

1. N1 = popcount(D[7:0])  // 入力中の '1' の数をカウント
2. if (N1 > 4) OR (N1 == 4 AND D[0] == 0):
       q_m[0] = D[0]
       q_m[i] = q_m[i-1] XNOR D[i]  (i = 1..7)
       q_m[8] = 0   // XNOR を使用したことを示す
   else:
       q_m[0] = D[0]
       q_m[i] = q_m[i-1] XOR D[i]   (i = 1..7)
       q_m[8] = 1   // XOR を使用したことを示す
```

### ステージ 2: DC バランシング (ビット 9)

ランニングディスパリティ (累積 '1' と '0' の差) を追跡し、
DC バランスを維持するためにデータを反転するかどうかを決定する。

```
入力: q_m[8:0], cnt (ランニングディスパリティ)
出力: q_out[9:0] (10bit TMDS シンボル), cnt_next

1. N0 = q_m[7:0] 中の '0' の数
   N1 = q_m[7:0] 中の '1' の数

2. if (cnt == 0) OR (N0 == N1):
       q_out[9] = ~q_m[8]
       if q_m[8] == 0:
           q_out[7:0] = ~q_m[7:0]
           cnt_next = cnt + (N0 - N1)
       else:
           q_out[7:0] = q_m[7:0]
           cnt_next = cnt + (N1 - N0)
       q_out[8] = q_m[8]

3. else if (cnt > 0 AND N1 > N0) OR (cnt < 0 AND N0 > N1):
       q_out[9] = 1
       q_out[8] = q_m[8]
       q_out[7:0] = ~q_m[7:0]
       cnt_next = cnt + 2 * q_m[8] + (N0 - N1)

4. else:
       q_out[9] = 0
       q_out[8] = q_m[8]
       q_out[7:0] = q_m[7:0]
       cnt_next = cnt - 2 * (~q_m[8]) + (N1 - N0)
```

### コントロールトークン (ブランキング期間)

DE = 0 (ブランキング) の間、データの代わりにコントロールトークンを送信する。

| C1 (VSYNC) | C0 (HSYNC) | 10bit トークン |
|-------------|------------|----------------|
| 0 | 0 | `0010101011` |
| 0 | 1 | `1101010100` |
| 1 | 0 | `0010101010` |
| 1 | 1 | `1101010101` |

## Cm 実装設計

### Cm SV バックエンドでの実装上の課題

> [!IMPORTANT]
> **popcount (ビットカウント) の実装**:
> Cm SV バックエンドは現在 `popcount` 組み込み関数を持たない。
> 手動でのビットカウントが必要:
> ```cm
> // 8bit 入力のビットカウント (Cm SV で実装可能な形式)
> uint n1 = (d & 1) + ((d & 2) / 2) + ((d & 4) / 4) + ((d & 8) / 8)
>         + ((d & 16) / 16) + ((d & 32) / 32) + ((d & 64) / 64) + ((d & 128) / 128);
> ```

> [!IMPORTANT]
> **符号付き整数の必要性**:
> DC バランシングにおけるランニングディスパリティ `cnt` は符号付き整数が必要。
> Cm SV バックエンドは現在 `uint` (unsigned) のみサポート。
> **回避策**: オフセット付きの unsigned 表現を使用する。
> `cnt` を実質的に `+16` オフセットした `uint` で管理 (cnt_reg = 16 → 実際の cnt = 0)。
> 最大ディスパリティは ±8 程度のため、5bit unsigned (0-31) で十分。

> [!WARNING]
> **ビットシフト演算子**: `<<` と `>>` が Cm SV バックエンドで正しく
> 生成されるか確認が必要。既存の uart_hello.cm では除算 (`/`) による
> ビット抽出を使用しているため、同様のパターンで実装する。

### モジュール構造

```cm
//! platform: sv

// TMDS エンコーダ (1チャネル分)
// 入力: 8bit データ + 2bit コントロール + DE
// 出力: 10bit TMDS シンボル

// ポート
#[input]  posedge clk;
#[input]  utiny  data_in  = 0;     // 8bit RGB データ
#[input]  bool   c0       = false; // コントロール信号 0 (HSYNC)
#[input]  bool   c1       = false; // コントロール信号 1 (VSYNC)
#[input]  bool   de       = false; // データイネーブル

#[output] ushort tmds_out  = 0;    // 10bit TMDS (ushort の下位 10bit 使用)

// 内部レジスタ
uint cnt = 16;   // ランニングディスパリティ (オフセット +16, 16 = 0相当)
uint q_m = 0;    // 9bit 中間コード
uint n1  = 0;    // '1' のカウント
```

## テスト計画

| テスト | 検証内容 | 合格基準 |
|--------|----------|----------|
| TB-TE-01 | コントロールトークン出力 | DE=0 時に正しいトークンが出力される |
| TB-TE-02 | データエンコーディング | 既知入力に対する正しい 10bit 出力 |
| TB-TE-03 | DC バランス | 長期間の入力でディスパリティが制限内 |
| TB-TE-04 | 遷移最小化 | XOR/XNOR の正しい選択 |

## 参考

- DVI 1.0 Specification, Section 3.2: TMDS Encoding Algorithm
- [Wikipedia: TMDS](https://en.wikipedia.org/wiki/Transition-minimized_differential_signaling)
