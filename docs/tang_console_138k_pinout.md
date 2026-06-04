# Tang Console 138K ピンアサイン表

## デバイス情報

| 項目 | 値 |
|------|-----|
| SoM | Tang Mega 138K |
| FPGA | GW5AST-LV138FPG676A (Arora V) |
| パッケージ | FPG676 (BGA 676pin) |
| IDE 設定 | GW5AST-138: GW5AST-LV138FPG676AC1/I0 |

> **注意**: macOS Education版 Gowin EDA では FPG676 パッケージが未登録の場合があり、
> ローカルでの P&R が不可能です。合成のみ実行し、P&R は別環境で行う必要があります。

## 基本ピンアサイン

| Signal | Pin | Bank | 機能 | 備考 |
|--------|-----|------|------|------|
| **SYS_CLK** | V10 | Bank 8 | システムクロック | 50MHz 水晶 |
| **SYS_ACT** | W12 | Bank 5 | ステータス LED | LED1 Green (Config) |
| **READY** | U12 | Bank 10 | ステータス LED | LED1 Red |
| **DONE** | G11 | Bank 10 | ステータス LED | LED1 Blue |
| **EX_KEY0** | AA13 | Bank 5 | ユーザーボタン | 内部プルアップ必要 |
| **EX_KEY1** | AB13 | Bank 5 | ユーザーボタン | 内部プルアップ必要 |
| **EX_KEY2** | Y12 | Bank 5 | ユーザーボタン | 内部プルアップ必要 |
| **UART_TX** | U15 | Bank 5 | Debug UART | FPGA → BL616 → PC |
| **UART_RX** | Y14 | Bank 5 | Debug UART | PC → BL616 → FPGA |

## HDMI 出力 (TMDS)

HDMI TX 信号はすべて **Bank 3** に配置されています。差動ペアで接続。

| Signal | Pin+ | Pin- | I/O Type | チャネル |
|--------|------|------|----------|---------|
| HDMI_D2 (Red) | AA22 | AA23 | LVCMOS33D | CH2 |
| HDMI_D1 (Green) | V24 | W24 | LVCMOS33D | CH1 |
| HDMI_D0 (Blue) | AB24 | AC24 | LVCMOS33D | CH0 |
| HDMI_CLK | Y22 | Y23 | LVCMOS33D | Clock |

> **制約事項**: HDMI信号は差動ペア (LVCMOS33D) を使用。
> Gowin EDA ではシリアライザとして `OSER10` を使用し、5:1 DDRシリアライズで
> ピクセルクロック (25.175MHz) の5倍 = 125.875MHz のシリアルクロックが必要です。

## SD Card

| Signal | Pin | Bank |
|--------|-----|------|
| TF_SDIO_CLK | V15 | Bank 5 |
| TF_SDIO_CMD | Y16 | Bank 5 |
| TF_SDIO_D0 | AA15 | Bank 5 |

## リファレンス

- [Sipeed Tang Console Wiki](https://wiki.sipeed.com/hardware/en/tang/tang-console/mega-console.html)
- [Sipeed TangMega-138K-example (GitHub)](https://github.com/sipeed/TangMega-138K-example)
- [LiteX Boards - Tang Mega 138K](https://github.com/litex-hub/litex-boards)
