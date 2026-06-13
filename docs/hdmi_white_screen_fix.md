# HDMI画面白一色問題の修正設計設計書

## 1. 概要
HDMIテキスト表示プログラム (`hdmi_text_top`) を実行した際、実機で画面が白一色になってしまう不具合を解決するための設計書です。

## 2. 原因分析
### 2.1 RAMの読み書き競合による DPRAM 推論失敗
`text_renderer.cm` の `render_process` において、同一のクロック同期プロセス（SystemVerilog の同一 `always` ブロック）で `text_buf` への書き込みと読み出しが混在しています。これにより、Gowin Synthesis がデュアルポート RAM（DPRAM）としてのインファレンス（推論）に失敗し、書き込みポートが機能しなくなっていました。その結果、RAMから常に `0`（またはスペース `32`）が読み出され、画面全体が白（`r_out/g_out/b_out = 255, 255, 255`）になっていました。

### 2.2 深い条件分岐ネストによる合成最適化の失敗
`font_rom.cm` の `lookup_font` 関数は、95文字の ASCII コードを判定するために `else if` による 95 レベルの深い条件分岐ネストになっていました。SystemVerilog 上でこのような深いネストが存在すると、合成器が論理最適化のフェーズで失敗し、戻り値を `0` に固定してしまう不具合を引き起こします。

## 3. 対策・設計詳細

### 3.1 RAM書き込みと読み出しのプロセス分離
`text_buf` に対する書き込み処理を独立したプロセス `write_process` に分離します。

```cm
// text_renderer.cm
export async void write_process(posedge pixel_clk) {
    if (text_we == true) {
        if (text_addr < TEXT_BUF_SIZE as ushort) {
            text_buf[text_addr] = text_char;
        }
    }
}
```

同時に、`render_process` からは上記の書き込みブロックを削除し、読み出し専用プロセスとします。これにより、SystemVerilog 出力時には別個の `always @(posedge pixel_clk)` ブロックが生成され、標準的な DPRAM の記述パターンに適合します。

### 3.2 フォント ROM ルックアップ関数のフラット化
`generate_font.py` 内の `font_rom.cm` 生成ロジックを修正し、`lookup_font` 内の `char_code` に対する条件分岐において、`else if` を廃止し、独立した `if` 文を平坦に並べる形式に変更します。

```cm
// 変更後 (font_rom.cm イメージ)
export uint lookup_font(utiny char_code, utiny row) {
    uint font_byte = 0;

    if (char_code == 32 as utiny) {
        font_byte = 0;
    }
    if (char_code == 33 as utiny) {
        if (row == 0) { font_byte = 0x18; }
        // ...
    }
    // ...
    return font_byte;
}
```

これにより、SystemVerilog 上のネストの深さが解消され、合成ツールが正しくパラレルなマルチプレクサまたは ROM ブロックとして回路化できるようになります。

## 4. 影響範囲
本変更はテキスト描画部 (`text_renderer.cm`) およびフォント ROM 生成スクリプト (`generate_font.py`) に限定され、HDMIのカラーバー出力やタイミング生成のロジックには影響を及ぼしません。
