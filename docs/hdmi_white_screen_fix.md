# HDMI画面白一色問題の修正設計設計書

## 1. 概要
HDMIテキスト表示プログラム (`hdmi_text_top`) を実行した際、実機で画面が白一色になってしまう不具合を解決するための設計書です。

## 2. 原因分析

### 2.1 RAMの読み書き競合による DPRAM 推論失敗
`text_renderer.cm` の `render_process` において、同一のクロック同期プロセス（SystemVerilog の同一 `always` ブロック）で `text_buf` への書き込みと読み出しが混在していました。これにより、Gowin Synthesis がデュアルポート RAM（DPRAM）としてのインファレンス（推論）に失敗し、書き込みポートが機能しなくなっていました。その結果、RAMから常に `0`（またはスペース `32`）が読み出され、画面全体が白になっていました。

### 2.2 深い条件分岐ネストによる合成最適化の失敗
`font_rom.cm` の `lookup_font` 関数は、95文字の ASCII コードを判定するために `else if` による 95 レベルの深い条件分岐ネストになっていました。SystemVerilog 上でこのような深いネストが存在すると、合成器が論理最適化のフェーズで失敗し、戻り値を `0` に固定してしまう不具合を引き起こしていました。

### 2.3 コンパイラのスコープ生成バグ（変数代入の誤ネスト）
同一のプロセス `process_anim` 内で複数のステート分岐から共通の出力レジスタ (`anim_ready`, `anim_done`) を更新しようとすると、CmコンパイラのSystemVerilogコード生成処理においてスコープ解決バグが発生し、`state == 3`（描画終了状態）の判定ブロックが誤って `row_idx == 0`（最初のヘッダー描画）の内部にネストして出力されていました。これにより、描画自体は完了するものの、状態遷移が正常に完了しない、もしくは予期せぬロックアップを引き起こしていました。

### 2.4 Gowin Synthesis におけるデフォルト非ブロッキング代入の制限
プロセス先頭で `text_we = false` などのデフォルト値を代入し、条件成立時のみ `true` に更新する記述パターンについて、Gowin Synthesisが正しく優先度マルチプレクサを合成できず、`text_we`（書き込み有効信号）が常に `0` に固定されてしまう問題がありました。

---

## 3. 対策・設計詳細

### 3.1 RAM書き込みと読み出しのプロセス分離
`text_buf` に対する書き込み処理を独立したプロセス `write_process` に分離しました。これによってSystemVerilog出力時に別個の `always @(posedge pixel_clk)` ブロックが生成され、標準的な DPRAM の記述パターンに適合します。

### 3.2 フォント ROM ルックアップ関数のフラット化
`font_rom.cm` の生成ロジックを変更し、`lookup_font` 内の `char_code` に対する条件分岐において、`else if` を廃止し、独立した `if` 文を平坦に並べる形式に変更しました。これにより深いネストが解消され、正しく並列なマルチプレクサとして回路化されます。

### 3.3 LED制御用の独立プロセスの新設
`anim_ready` と `anim_done` の割り当てを `process_anim` から完全に削除し、独立したプロセス `led_control_process` に分離しました。
これにより `process_anim` 内での変数割り当ての衝突やネストバグを完全に回避し、状態遷移を安定化させました。

```cm
// animation_ctrl.cm
export async void led_control_process(posedge pixel_clk) {
    if (state == 2) {
        anim_ready = true;
        anim_done = false;
    }
    else if (state == 3) {
        anim_ready = false;
        anim_done = true;
    }
    else {
        anim_ready = false;
        anim_done = false;
    }
}
```

### 3.4 明示的な書き込み有効信号（`text_we`）の代入
プロセスの先頭における `text_we` のデフォルト値代入を排除し、各状態分岐において明示的に `text_we = true;` または `text_we = false;` を割り当てる形式にリファクタリングしました。これにより、合成ツールでの意図しない論理固定を完全に排除します。

---

## 4. 影響範囲
本変更はテキスト描画部 (`text_renderer.cm` / `animation_ctrl.cm`) およびフォント ROM 生成スクリプト (`generate_font.py`) に限定され、HDMIのカラーバー出力やタイミング生成のロジックには影響を及ぼしません。
