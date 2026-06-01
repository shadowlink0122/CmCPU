# Phase 2: GBC 画面設定

## 概要

ゲームボーイカラー (GBC) の標準画面仕様に基づいた表示設定モジュール。
GBC のネイティブ解像度 160×144 ピクセルを 640×480 HDMI 出力に
整数スケーリングでマッピングする。

## GBC 画面仕様

| パラメータ | 値 | 説明 |
|------------|-----|------|
| **解像度** | 160 × 144 | ネイティブピクセル数 |
| **画面サイズ** | 2.32インチ (59mm) | STN LCD パネル |
| **アスペクト比** | 10:9 | ほぼ正方形 |
| **カラー深度** | 15bit RGB (5-5-5) | 32,768 色表現可能 |
| **同時表示色** | 最大 56 色 | 8 BG パレット × 4色 + 8 OBJ パレット × 3色 |
| **パレット構成** | 8 BG + 8 OBJ パレット | 各 4 色 (OBJ は透明色含む) |
| **リフレッシュレート** | 59.73 Hz | ~4.194 MHz CPU → 70224 クロック/フレーム |

## スケーリング設計

### 3× 整数スケーリング

GBC の 160×144 を整数倍して 640×480 に収める。

```
GBC ネイティブ: 160 × 144 ピクセル
3× スケーリング: 480 × 432 ピクセル (表示領域)
640×480 画面:    640 × 480 (HDMI 出力)

水平方向: (640 - 480) / 2 = 80 ピクセル左右黒帯
垂直方向: (480 - 432) / 2 = 24 ピクセル上下黒帯
```

```
 ┌───────── 640 px ──────────┐
 │  80px │  480 px   │  80px │
 │ ┌─────┼───────────┼─────┐ │ ─┬─ 24px (黒帯)
 │ │     │           │     │ │  │
 │ │     │  GBC 表示 │     │ │  │
 │ │     │  480×432  │     │ │  │ 432px (表示領域)
 │ │     │  (3x倍)   │     │ │  │
 │ │     │           │     │ │  │
 │ └─────┼───────────┼─────┘ │ ─┴─ 24px (黒帯)
 └───────────────────────────┘
```

### 座標変換

HDMI 出力座標 (hc, vc) から GBC 座標 (gbc_x, gbc_y) への変換:

```
H_OFFSET = 80    // 水平黒帯オフセット
V_OFFSET = 24    // 垂直黒帯オフセット
SCALE = 3        // 整数スケーリング倍率

// GBC 表示領域判定
gbc_active = (hc >= H_OFFSET) AND (hc < H_OFFSET + 480)
           AND (vc >= V_OFFSET) AND (vc < V_OFFSET + 432)

// GBC ピクセル座標
gbc_x = (hc - H_OFFSET) / 3   // 0-159
gbc_y = (vc - V_OFFSET) / 3   // 0-143
```

> [!WARNING]
> **除算の合成コスト**: Cm SV バックエンドでの `/3` は合成ツールが
> 除算器を推論する。3 の倍数の除算は以下のいずれかで回避可能:
> 1. **カウンタ方式**: 3 クロックごとにカウンタでインクリメント
> 2. **ルックアップテーブル**: 0-479 → 0-159 の対応表 (BRAM)
> 推奨は **カウンタ方式** (リソース効率が良い)。

## 15bit RGB カラーパレット

### GBC カラーフォーマット

GBC は 15bit RGB (5-5-5) カラーを使用する:

```
ビット [14:10] = Blue  (5bit, 0-31)
ビット [ 9: 5] = Green (5bit, 0-31)
ビット [ 4: 0] = Red   (5bit, 0-31)
```

### 15bit → 24bit 変換 (HDMI 出力用)

HDMI は 24bit RGB (8-8-8) を使用するため、5bit → 8bit の変換が必要。

```
方式 1: 上位ビット複製 (推奨)
  R[7:0] = { R[4:0], R[4:2] }   // 5bit を 8bit に拡張
  G[7:0] = { G[4:0], G[4:2] }
  B[7:0] = { B[4:0], B[4:2] }

方式 2: 単純シフト
  R[7:0] = R[4:0] << 3          // 暗くなる傾向
```

> [!IMPORTANT]
> **Cm SV バックエンドでのビット連結**: 現在のバックエンドでは
> ビット連結 `{a, b}` 演算子が存在しない可能性が高い。
> **回避策**: 乗算とOR で代替する。
> ```cm
> // R[4:0] を 8bit に拡張
> uint r8 = (r5 * 8) | (r5 / 4);  // {R[4:0], R[4:2]}
> ```

### テキスト表示用デフォルトパレット

テキスト表示に使用するシンプルな GBC 風パレット:

| パレットID | 色 0 (BG) | 色 1 | 色 2 | 色 3 (FG) | 用途 |
|------------|-----------|------|------|-----------|------|
| 0 | `0x7FFF` (白) | `0x56B5` (薄灰) | `0x294A` (濃灰) | `0x0000` (黒) | 標準テキスト |
| 1 | `0x0000` (黒) | `0x294A` (濃灰) | `0x56B5` (薄灰) | `0x7FFF` (白) | 反転テキスト |
| 2 | `0x7C00` (青BG) | `0x56B5` | `0x03E0` (緑) | `0x001F` (赤) | カラーテスト |

## Cm 実装設計

### モジュールインターフェース

```cm
//! platform: sv

// GBC 画面設定定数
const uint GBC_WIDTH  = 160;    // GBC 水平解像度
const uint GBC_HEIGHT = 144;    // GBC 垂直解像度
const uint SCALE      = 3;      // 整数スケーリング倍率
const uint H_OFFSET   = 80;     // 水平黒帯 (640 - 480) / 2
const uint V_OFFSET   = 24;     // 垂直黒帯 (480 - 432) / 2
const uint DISP_WIDTH = 480;    // 表示領域幅 (160 × 3)
const uint DISP_HEIGHT = 432;   // 表示領域高さ (144 × 3)

// ポート
#[input]  posedge pixel_clk;
#[input]  ushort h_count = 0;    // ビデオタイミングからの水平座標
#[input]  ushort v_count = 0;    // ビデオタイミングからの垂直座標
#[input]  bool   de_in   = false; // データイネーブル入力

#[output] utiny  gbc_x   = 0;   // GBC X 座標 (0-159)
#[output] utiny  gbc_y   = 0;   // GBC Y 座標 (0-143)
#[output] bool   gbc_active = false; // GBC 表示領域内フラグ

// 内部レジスタ (カウンタ方式)
uint sub_x = 0;  // 水平サブピクセルカウンタ (0-2)
uint sub_y = 0;  // 垂直サブピクセルカウンタ (0-2)
uint px = 0;     // GBC X 座標 (uint)
uint py = 0;     // GBC Y 座標 (uint)
```

### カウンタ方式による座標変換

```cm
void process(posedge pixel_clk) {
    // GBC 表示領域判定
    if (h_count >= H_OFFSET) {
        if (h_count < H_OFFSET + DISP_WIDTH) {
            if (v_count >= V_OFFSET) {
                if (v_count < V_OFFSET + DISP_HEIGHT) {
                    gbc_active = true;
                } else {
                    gbc_active = false;
                }
            } else {
                gbc_active = false;
            }
        } else {
            gbc_active = false;
        }
    } else {
        gbc_active = false;
    }

    // 水平カウンタ (3 ピクセルごとに gbc_x をインクリメント)
    if (h_count == H_OFFSET) {
        px = 0;
        sub_x = 0;
    } else {
        if (gbc_active == true) {
            if (sub_x == 2) {
                sub_x = 0;
                px = px + 1;
            } else {
                sub_x = sub_x + 1;
            }
        }
    }

    // 垂直カウンタ (3 ラインごとに gbc_y をインクリメント)
    if (v_count == V_OFFSET) {
        if (h_count == 0) {
            py = 0;
            sub_y = 0;
        }
    } else {
        if (h_count == 0) {
            if (sub_y == 2) {
                sub_y = 0;
                py = py + 1;
            } else {
                sub_y = sub_y + 1;
            }
        }
    }

    gbc_x = px as utiny;
    gbc_y = py as utiny;
}
```

## テスト計画

| テスト | 検証内容 | 合格基準 |
|--------|----------|----------|
| TB-GBC-01 | 表示領域判定 | gbc_active が正しい座標範囲で HIGH |
| TB-GBC-02 | 3× スケーリング | 3 ピクセルごとに gbc_x がインクリメント |
| TB-GBC-03 | 黒帯位置 | 上下 24px, 左右 80px が非アクティブ |
| TB-GBC-04 | gbc_x 範囲 | 0-159 でラップ |
| TB-GBC-05 | gbc_y 範囲 | 0-143 でラップ |
| TB-GBC-06 | 15bit→24bit 変換 | 白 0x7FFF → R=FF, G=FF, B=FF |
