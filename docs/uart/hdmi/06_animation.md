# Phase 4: Hello World アニメーション

## 概要

"Hello, World!" 文字列を HDMI 画面上に 1 文字ずつ順次表示する
アニメーション制御モジュール。GBC 風のテキスト表示に
レトロゲーム的な演出 (タイプライタ効果、カーソル点滅) を加える。

## アニメーション仕様

### タイプライタ効果

"Hello, World!" の各文字を一定間隔で 1 文字ずつ表示する。

| パラメータ | 値 | 説明 |
|------------|-----|------|
| 文字列 | `"Hello, World!"` | 13 文字 |
| 表示間隔 | 6 フレーム (~100ms @60Hz) | タイプライタ速度 |
| 表示開始位置 | (3, 8) | テキストバッファ座標 (col, row) — 画面中央付近 |
| 完了後 | カーソル点滅 | 30 フレームごとに ON/OFF |

### ステートマシン

```
  ┌──────────┐     起動待機完了
  │  IDLE    │──────────────────┐
  │ (起動待機)│                  │
  └──────────┘                  ▼
                          ┌──────────┐
                          │  TYPING  │
                          │ (文字表示)│
                          └─────┬────┘
                                │ 全文字表示完了
                                ▼
                          ┌──────────┐
                          │  DONE    │
                          │(カーソル │
                          │  点滅)   │
                          └──────────┘
```

### タイミング設計

```
25.2 MHz pixel_clk
÷ 800 × 525 = 420,000 clk/frame
÷ 60 fps

フレームカウンタ: 420,000 クロック/フレーム
文字表示間隔: 6 フレーム = 2,520,000 クロック ≈ 100ms
カーソル点滅: 30 フレーム = 12,600,000 クロック ≈ 500ms
起動待機: 60 フレーム = 25,200,000 クロック ≈ 1秒
```

## Cm 実装設計

### 定数とポート

```cm
//! platform: sv

// アニメーション定数
const uint FRAME_CLOCKS   = 420000;  // 1フレーム = 800 × 525 クロック
const uint TYPE_INTERVAL  = 6;       // 文字表示間隔 (フレーム数)
const uint CURSOR_INTERVAL = 30;     // カーソル点滅間隔 (フレーム数)
const uint STARTUP_FRAMES = 60;      // 起動待機 (フレーム数)
const uint MSG_LEN = 13;             // "Hello, World!" の長さ
const uint TEXT_COL_START = 3;       // 表示開始列
const uint TEXT_ROW_START = 8;       // 表示開始行
const uint TEXT_COLS = 20;           // テキストバッファ幅

// ポート
#[input]  posedge pixel_clk;

// テキストバッファへの書き込みインターフェース
#[output] ushort text_addr = 0;      // テキストバッファアドレス
#[output] utiny  text_char = 0;      // 書き込む文字コード
#[output] bool   text_we   = false;  // 書き込みイネーブル

// カーソル制御
#[output] utiny cursor_col = 0;      // カーソル列位置
#[output] utiny cursor_row = 0;      // カーソル行位置
#[output] bool  cursor_visible = false; // カーソル表示

// ステータス
#[output] bool  anim_active = false; // アニメーション中
#[output] bool  anim_done   = false; // アニメーション完了

// 内部レジスタ
uint state = 0;          // ステートマシン (0=IDLE, 1=TYPING, 2=DONE)
uint frame_cnt = 0;      // フレームカウンタ (0-419999)
uint frame_num = 0;      // フレーム番号
uint char_idx = 0;       // 表示済み文字数
uint type_timer = 0;     // タイプライタタイマー
uint cursor_timer = 0;   // カーソル点滅タイマー
uint cursor_on = 0;      // カーソル表示状態
uint msg_char = 0;       // 現在の文字コード
```

### メッセージ ROM

```cm
// "Hello, World!" メッセージ ROM
// 既存の uart_hello.cm と同じパターン
void load_msg_char(posedge pixel_clk) {
    if (char_idx == 0)  { msg_char = 72; }   // 'H'
    if (char_idx == 1)  { msg_char = 101; }  // 'e'
    if (char_idx == 2)  { msg_char = 108; }  // 'l'
    if (char_idx == 3)  { msg_char = 108; }  // 'l'
    if (char_idx == 4)  { msg_char = 111; }  // 'o'
    if (char_idx == 5)  { msg_char = 44; }   // ','
    if (char_idx == 6)  { msg_char = 32; }   // ' '
    if (char_idx == 7)  { msg_char = 87; }   // 'W'
    if (char_idx == 8)  { msg_char = 111; }  // 'o'
    if (char_idx == 9)  { msg_char = 114; }  // 'r'
    if (char_idx == 10) { msg_char = 108; }  // 'l'
    if (char_idx == 11) { msg_char = 100; }  // 'd'
    if (char_idx == 12) { msg_char = 33; }   // '!'
}
```

### メインプロセス

```cm
void process(posedge pixel_clk) {
    text_we = false;  // デフォルト: 書き込み無効

    // フレームカウンタ
    if (frame_cnt == FRAME_CLOCKS - 1) {
        frame_cnt = 0;
        frame_num = frame_num + 1;
    } else {
        frame_cnt = frame_cnt + 1;
    }

    // === IDLE: 起動待機 ===
    if (state == 0) {
        if (frame_num == STARTUP_FRAMES) {
            state = 1;
            anim_active = true;
            char_idx = 0;
            type_timer = 0;
        }
    }

    // === TYPING: 1文字ずつ表示 ===
    if (state == 1) {
        if (frame_cnt == 0) {
            type_timer = type_timer + 1;
            if (type_timer == TYPE_INTERVAL) {
                type_timer = 0;
                // 文字をテキストバッファに書き込む
                text_addr = (TEXT_ROW_START * TEXT_COLS + TEXT_COL_START + char_idx) as ushort;
                text_char = msg_char as utiny;
                text_we = true;

                char_idx = char_idx + 1;

                // カーソル位置更新
                cursor_col = (TEXT_COL_START + char_idx) as utiny;
                cursor_row = TEXT_ROW_START as utiny;

                if (char_idx == MSG_LEN) {
                    state = 2;
                    anim_active = false;
                    anim_done = true;
                    cursor_timer = 0;
                }
            }
        }
    }

    // === DONE: カーソル点滅 ===
    if (state == 2) {
        if (frame_cnt == 0) {
            cursor_timer = cursor_timer + 1;
            if (cursor_timer == CURSOR_INTERVAL) {
                cursor_timer = 0;
                if (cursor_on == 0) {
                    cursor_on = 1;
                    cursor_visible = true;
                } else {
                    cursor_on = 0;
                    cursor_visible = false;
                }
            }
        }
    }
}
```

## テスト計画

| テスト | 検証内容 | 合格基準 |
|--------|----------|----------|
| TB-AN-01 | 起動待機 | 60 フレーム後に TYPING 開始 |
| TB-AN-02 | タイプライタ間隔 | 6 フレームごとに 1 文字 |
| TB-AN-03 | メッセージ ROM | 正しい文字コードがロード |
| TB-AN-04 | テキストバッファ書き込み | text_addr, text_char, text_we が正しい |
| TB-AN-05 | 完了遷移 | 13 文字後に DONE 状態 |
| TB-AN-06 | カーソル点滅 | 30 フレームごとに ON/OFF |
| TB-AN-07 | カーソル位置 | 最後の文字の次の位置 |

## LED ステータス連携

| LED | 状態 | 意味 |
|-----|------|------|
| led_ready (Red) | HIGH | アニメーション実行中 |
| led_done (Blue) | HIGH | アニメーション完了 |
| led_ready | LOW, led_done | LOW | 起動待機中 |
