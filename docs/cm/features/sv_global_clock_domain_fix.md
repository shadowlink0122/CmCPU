# SVグローバルクロックドメイン感度リストの修正

## 課題
Cmコンパイラにおいて、モジュールレベルで宣言された入力クロックなどのグローバル変数（例：`#[input] posedge clk_50m;`）は、内部的に各 `async func` 内で `is_global = true` のローカル変数（`LocalDecl`）として登録されます。

SystemVerilogのコード生成フェーズ（`codegen.cpp`）では、関数内の `posedge` / `negedge` 型のローカル変数をすべて走査して、`always_ff` ブロックの感度リスト（sensitivity list）を自動生成しています。しかし、この走査時に `local.is_global` フラグが考慮されておらず、関数がパラメータとして受け取る本来のクロック以外のグローバルクロック（例：`clk_50m`）まで感度リストに含まれてしまいます。

その結果、生成されるSystemVerilogコードにおいて以下のように複数のクロックを持つ不正な感度リストが生成されます。
```sv
always_ff @(posedge clk_50m or posedge pixel_clk) begin
```
これにより、Gowin EDA合成時に以下のエラーが発生してビルドに失敗します。
`ERROR (EX3833) : If-condition does not match any sensitivity list edge`

## 解決策
`Cm/src/codegen/sv/codegen.cpp` 内で `func.locals` を走査してクロックエッジ（`posedge` / `negedge`）を判定している箇所において、`local.is_global` が `true` の場合は走査をスキップ（`continue`）するように修正します。

修正対象の箇所：
1. `always_ff` ブロックの感度リスト（`all_edges`）を構築する箇所 (L900付近)
2. 代入文でノンブロッキング代入を使用するか判断する箇所 (L549, L1803, L1874付近)

これにより、グローバル宣言されたクロック信号は感度リストや代入判定から除外され、各 `async func` のパラメータで指定されたクロックのみが正しく設定されるようになります。

## 期待される結果
`hdmi_colorbar.sv` において、`always_ff` の感度リストが各ブロックで想定する単一のクロックになります。
```sv
// 修正前:
always_ff @(posedge clk_50m or posedge pixel_clk) begin

// 修正後:
always_ff @(posedge pixel_clk) begin
```
これにより、Gowin EDAの合成（GowinSynthesis）が正常に通過するようになります。
