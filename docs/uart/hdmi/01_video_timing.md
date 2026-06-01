# Phase 1: ビデオタイミングジェネレータ

## 概要

640×480@60Hz (VGA 標準) のビデオタイミング信号を生成するモジュール。
HDMI/DVI 出力の基盤となるコンポーネントで、水平・垂直同期信号 (HSYNC, VSYNC) と
データイネーブル信号 (DE) を適切なタイミングで出力する。

## VGA 640×480@60Hz タイミング仕様

### ピクセルクロック

- **標準**: 25.175 MHz
- **実用値**: 25.2 MHz (PLL で生成しやすい近似値。ほとんどのモニタで許容)

### 水平タイミング (1ライン = 800 ピクセルクロック)

| パラメータ | 値 | 説明 |
|------------|-----|------|
| H_ACTIVE | 640 | アクティブ表示領域 |
| H_FP | 16 | フロントポーチ |
| H_SYNC | 96 | 同期パルス幅 |
| H_BP | 48 | バックポーチ |
| H_TOTAL | 800 | 1ライン合計 |

### 垂直タイミング (1フレーム = 525 ライン)

| パラメータ | 値 | 説明 |
|------------|-----|------|
| V_ACTIVE | 480 | アクティブ表示領域 |
| V_FP | 10 | フロントポーチ |
| V_SYNC | 2 | 同期パルス幅 |
| V_BP | 33 | バックポーチ |
| V_TOTAL | 525 | 1フレーム合計 |

### 同期パルス極性

- **HSYNC**: 負極性 (アクティブ LOW)
- **VSYNC**: 負極性 (アクティブ LOW)

## Cm 実装設計

### モジュールインターフェース

```cm
//! platform: sv

// === タイミング定数 ===
const uint H_ACTIVE = 640;
const uint H_FP     = 16;
const uint H_SYNC   = 96;
const uint H_BP     = 48;
const uint H_TOTAL  = 800;

const uint V_ACTIVE = 480;
const uint V_FP     = 10;
const uint V_SYNC   = 2;
const uint V_BP     = 33;
const uint V_TOTAL  = 525;

// === ポート ===
#[input]  posedge pixel_clk;       // 25.2MHz ピクセルクロック

#[output] bool hsync = true;       // 水平同期 (負極性)
#[output] bool vsync = true;       // 垂直同期 (負極性)
#[output] bool de    = false;      // データイネーブル
#[output] ushort h_count = 0;      // 水平カウンタ (デバッグ用)
#[output] ushort v_count = 0;      // 垂直カウンタ (デバッグ用)

// === 内部レジスタ ===
uint hc = 0;   // 水平ピクセルカウンタ
uint vc = 0;   // 垂直ラインカウンタ
```

### ステートマシン

```
                 ┌─────────────────────────┐
                 │      hc カウントアップ    │
                 │   0 → H_TOTAL-1 → 0     │
                 │                          │
 hc == H_TOTAL-1 ──→ vc カウントアップ      │
                 │   0 → V_TOTAL-1 → 0     │
                 └─────────────────────────┘

 ■ HSYNC: hc が [H_ACTIVE + H_FP, H_ACTIVE + H_FP + H_SYNC) の範囲で LOW
 ■ VSYNC: vc が [V_ACTIVE + V_FP, V_ACTIVE + V_FP + V_SYNC) の範囲で LOW
 ■ DE:    hc < H_ACTIVE かつ vc < V_ACTIVE の時に HIGH
```

### プロセス関数

```cm
void process(posedge pixel_clk) {
    // 水平カウンタ
    if (hc == H_TOTAL - 1) {
        hc = 0;
        // 垂直カウンタ
        if (vc == V_TOTAL - 1) {
            vc = 0;
        } else {
            vc = vc + 1;
        }
    } else {
        hc = hc + 1;
    }

    // HSYNC 生成 (負極性)
    if (hc >= H_ACTIVE + H_FP) {
        if (hc < H_ACTIVE + H_FP + H_SYNC) {
            hsync = false;
        } else {
            hsync = true;
        }
    } else {
        hsync = true;
    }

    // VSYNC 生成 (負極性)
    if (vc >= V_ACTIVE + V_FP) {
        if (vc < V_ACTIVE + V_FP + V_SYNC) {
            vsync = false;
        } else {
            vsync = true;
        }
    } else {
        vsync = true;
    }

    // データイネーブル
    if (hc < H_ACTIVE) {
        if (vc < V_ACTIVE) {
            de = true;
        } else {
            de = false;
        }
    } else {
        de = false;
    }

    // デバッグ出力
    h_count = hc as ushort;
    v_count = vc as ushort;
}
```

## テスト計画

### テストベンチ項目

| テスト | 検証内容 | 合格基準 |
|--------|----------|----------|
| TB-VT-01 | H_TOTAL サイクルで hc がラップ | hc: 0→799→0 |
| TB-VT-02 | V_TOTAL サイクルで vc がラップ | vc: 0→524→0 |
| TB-VT-03 | HSYNC パルス幅 | 96 ピクセルクロック |
| TB-VT-04 | VSYNC パルス幅 | 2 ライン × 800 クロック |
| TB-VT-05 | DE アクティブ領域 | 640×480 ピクセル |
| TB-VT-06 | フレームレート | 800 × 525 = 420,000 クロック/フレーム |

### Verilator リント

```bash
verilator --lint-only --timing -Wno-fatal -Wno-MODMISSING build/video_timing.sv
```

## 注意事項

> [!WARNING]
> **カウンタのビット幅**: `hc` と `vc` は `uint` (32bit) で宣言しているが、
> 実際に必要なのは `hc` が 10bit (0-799)、`vc` が 10bit (0-524) である。
> 合成時にGowin EDA が不要ビットを最適化するが、Verilator は `WIDTHTRUNC` 警告を
> 出す可能性がある。Cm SV バックエンドの `ushort` (16bit) への変更も検討すること。

> [!NOTE]
> **Cm SV バックエンドの制約**: 現在の `>=` (Greater-or-Equal) 比較演算子が
> SV バックエンドで正しく生成されるか、事前に確認が必要。
> 問題がある場合は、等価な `>` + `==` の組み合わせで回避する。
