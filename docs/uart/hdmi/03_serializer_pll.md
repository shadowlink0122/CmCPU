# Phase 1: TMDS シリアライザ & PLL

## 概要

TMDS エンコーダが出力する 10bit パラレルデータを、高速シリアルデータに変換する
モジュール。Gowin GW5AST FPGA の内蔵プリミティブ (OSER10, TLVDS_OBUF) を使用する。

## クロック構成

### 必要クロック

| クロック | 周波数 | 用途 |
|----------|--------|------|
| pixel_clk | 25.2 MHz | ピクセルクロック、タイミング生成 |
| serial_clk | 126 MHz | OSER10 用 5× ピクセルクロック (DDR) |
| ※ 252 MHz | 252 MHz | SDR の場合 (推奨しない) |

> [!NOTE]
> **DDR (Double Data Rate) 方式**: OSER10 は DDR で動作するため、
> 実効 10:1 シリアライズには 5× ピクセルクロック = 126 MHz が必要。
> SDR (252 MHz) よりタイミング制約が緩く推奨される。

### PLL 設定 (Gowin rPLL)

Tang Console 138K の 50MHz 入力クロックから、PLL で必要なクロックを生成する。

```
入力: 50 MHz (Pin V10)
  ├── 出力1: 25.2 MHz (pixel_clk)  — 50 × 63/125 ≈ 25.2 MHz
  └── 出力2: 126 MHz (serial_clk)  — 50 × 63/25 = 126 MHz
```

> [!IMPORTANT]
> **Gowin PLL IP の使用**: rPLL は Gowin EDA の IP Core Generator で生成する。
> Cm からは `extern struct` として宣言し、生成されたVerilogモジュールをインスタンス化する。
> Cm 単体での PLL 記述は不可能（FPGA ベンダー固有プリミティブのため）。

### Cm での PLL 宣言

```cm
//! platform: sv

// Gowin rPLL プリミティブ (extern として宣言)
extern struct rPLL {
    #[sv::param] int FCLKIN   = 50;     // 入力クロック周波数 (MHz)
    #[sv::param] int IDIV_SEL = 4;      // 入力分周比
    #[sv::param] int FBDIV_SEL = 24;    // フィードバック分周比
    #[sv::param] int ODIV_SEL = 4;      // 出力分周比
    #[input]  bool CLKIN  = clk_50m;    // 50MHz 入力
    #[output] bool CLKOUT = pixel_clk;  // 25.2MHz 出力
    #[output] bool LOCK   = pll_locked; // PLL ロック信号
}
```

## OSER10 シリアライザ

### Gowin OSER10 プリミティブ

OSER10 は Gowin FPGA の内蔵 10:1 シリアライザ。DDR 出力により、
5× クロックで 10bit データを 1bit シリアルストリームに変換する。

```
          ┌────────────┐
 D[9:0] ──│   OSER10   │── Q (シリアル出力)
          │            │
 PCLK   ──│ (pixel)    │
 FCLK   ──│ (fast)     │
 RST    ──│            │
          └────────────┘
```

### Cm での OSER10 宣言

```cm
// Gowin OSER10 プリミティブ
extern struct OSER10 {
    #[sv::param] int GSREN = 0;        // グローバルリセット無効
    #[sv::param] int LSREN = 1;        // ローカルリセット有効
    #[input]  bool PCLK   = pixel_clk; // ピクセルクロック
    #[input]  bool FCLK   = serial_clk; // 高速クロック (5×)
    #[input]  bool RESET  = false;
    #[input]  bool D0     = false;     // bit 0 (LSB first)
    #[input]  bool D1     = false;
    #[input]  bool D2     = false;
    #[input]  bool D3     = false;
    #[input]  bool D4     = false;
    #[input]  bool D5     = false;
    #[input]  bool D6     = false;
    #[input]  bool D7     = false;
    #[input]  bool D8     = false;
    #[input]  bool D9     = false;     // bit 9 (MSB)
    #[output] bool Q0     = tmds_d0_serial; // シリアル出力
}
```

### TLVDS_OBUF 差動出力バッファ

TMDS は LVDS ベースの差動信号。Gowin の TLVDS_OBUF プリミティブで
シングルエンド → 差動変換を行う。

```cm
// Gowin TLVDS_OBUF プリミティブ
extern struct TLVDS_OBUF {
    #[input]  bool I = tmds_serial;    // シングルエンド入力
    #[output] bool O = tmds_p;         // 差動出力 (+)
    #[output] bool OB = tmds_n;        // 差動出力 (-)
}
```

## ピン制約 (CST)

```tcl
// ============================================================
// Tang Console 138K ピン制約: HDMI TMDS 出力
// ============================================================

// HDMI Data Channel 2 (Red)
IO_LOC  "tmds_d2_p"  AA22;
IO_LOC  "tmds_d2_n"  AA23;
IO_PORT "tmds_d2_p"  IO_TYPE=LVCMOS33D;
IO_PORT "tmds_d2_n"  IO_TYPE=LVCMOS33D;

// HDMI Data Channel 1 (Green)
IO_LOC  "tmds_d1_p"  V24;
IO_LOC  "tmds_d1_n"  W24;
IO_PORT "tmds_d1_p"  IO_TYPE=LVCMOS33D;
IO_PORT "tmds_d1_n"  IO_TYPE=LVCMOS33D;

// HDMI Data Channel 0 (Blue)
IO_LOC  "tmds_d0_p"  AB24;
IO_LOC  "tmds_d0_n"  AC24;
IO_PORT "tmds_d0_p"  IO_TYPE=LVCMOS33D;
IO_PORT "tmds_d0_n"  IO_TYPE=LVCMOS33D;

// HDMI Clock Channel
IO_LOC  "tmds_clk_p" Y22;
IO_LOC  "tmds_clk_n" Y23;
IO_PORT "tmds_clk_p" IO_TYPE=LVCMOS33D;
IO_PORT "tmds_clk_n" IO_TYPE=LVCMOS33D;

// System Clock (50MHz)
IO_LOC  "clk_50m" V10;
IO_PORT "clk_50m" IO_TYPE=LVCMOS33;

// Status LEDs
IO_LOC  "led_ready" U12;
IO_PORT "led_ready" IO_TYPE=LVCMOS33 DRIVE=8;
IO_LOC  "led_done"  G11;
IO_PORT "led_done"  IO_TYPE=LVCMOS33 DRIVE=8;
```

## Cm SV バックエンドでの制約

> [!WARNING]
> **extern struct の制限**: Cm SV バックエンドの `extern struct` は
> Gowin プリミティブ (rPLL, OSER10, TLVDS_OBUF) のインスタンス化に使用するが、
> 以下の制約がある:
>
> 1. **パラメータの型**: `#[sv::param]` は `int` のみサポート。
>    文字列パラメータが必要な場合は手動で SV ラッパーを追加する必要がある。
> 2. **複数インスタンス**: 同一の `extern struct` を複数インスタンス化する場合、
>    変数名でインスタンスを区別する。
> 3. **PLL 生成**: 実際の PLL 設定は Gowin EDA IP Core Generator で生成した
>    Verilog ファイルを使用し、トップモジュールで結合する方が安全。

## テスト計画

| テスト | 検証内容 | 合格基準 |
|--------|----------|----------|
| TB-SER-01 | OSER10 ビット順序 | D0 が先に出力される |
| TB-SER-02 | PLL ロック | pll_locked が安定して HIGH |
| TB-SER-03 | TMDS クロックチャネル | pixel_clk がそのまま TMDS_CK に |
| TB-SER-04 | 差動出力 | O と OB が互いに反転 |

> [!NOTE]
> **シミュレーション制約**: OSER10 / TLVDS_OBUF / rPLL はベンダー固有の
> プリミティブのため、Verilator ではシミュレーションできない。
> これらのモジュールは `-Wno-MODMISSING` フラグでリントスキップし、
> 実機検証で動作確認する。
