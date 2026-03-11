# Tang Console 138K ピンアサイン表

## GW5AST-LV138PG484A

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

### HDMI (TMDS)

| Signal | Pin | Bank |
|--------|-----|------|
| HDMI_D2P | AA22 | Bank 3 |
| HDMI_D2N | AA23 | Bank 3 |
| HDMI_D1P | V24 | Bank 3 |
| HDMI_D1N | W24 | Bank 3 |
| HDMI_D0P | AB24 | Bank 3 |
| HDMI_D0N | AC24 | Bank 3 |
| HDMI_CKP | Y22 | Bank 3 |
| HDMI_CKN | Y23 | Bank 3 |

### SD Card

| Signal | Pin | Bank |
|--------|-----|------|
| TF_SDIO_CLK | V15 | Bank 5 |
| TF_SDIO_CMD | Y16 | Bank 5 |
| TF_SDIO_D0 | AA15 | Bank 5 |
