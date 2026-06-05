# HDMI TMDSエンコーダのローカル変数ブロッキング代入化設計

## 1. 背景と問題の事象
HDMIカラーバー回路をコンパイルして実機にデプロイした際、カラーバーの色が細い縦線に分裂し、その間に太い白色の縦線が出現する意図しないレイアウトバグが発生しています。

## 2. 原因調査結果
生成されたSystemVerilogコード（`build/hdmi/hdmi_colorbar.sv`）を静的解析した結果、`tmds_encode_r` などの `always_ff` ブロック内において、本来同一サイクル内で評価されるべき中間計算用のローカル変数（`r_n1`, `r_use_xnor`, `r_q0` 〜 `r_q7`, `r_qm`, `r_n1_qm`）への代入がすべて非ブロッキング代入（`<=`）で生成されていることが分かりました。

非ブロッキング代入によって、以下の問題が発生します。
1. `r_n1` から順に `r_use_xnor`、`r_q0`〜`r_q7`、`r_qm`、`r_n1_qm` の評価が1サイクルずつ遅延します。
2. その結果、最下段の `r_n1_qm` は `r_out` より最大 8 サイクル（8画素分）遅れて評価され、TMDSデータとして出力される `tmds_r` も 8 画素分の異なるピクセルデータが混ざり合った状態でエンコードされてしまいます。
3. これにより、TMDSエンコードデータが崩壊し、ディスプレイ上ではカラーデータの破壊とホワイトラインの出現（細い色と太い白線の混在）として可視化されていました。

### コンパイラ側の原因
`Cm/src/codegen/sv/codegen.cpp` の `emitStatement` および `emitTerminator` において、`always_ff` / `async` ブロック内では代入先変数の性質（グローバルレジスタかローカル一時変数か）を区別せず、一律で非ブロッキング代入（`<=`）を適用していたためです。

## 3. 対策方針
Cmコンパイラ（SystemVerilogバックエンド）のコード生成器 `codegen.cpp` を修正し、`always_ff` または `async` のクロック同期ブロック内であっても、**代入先ターゲットが「ローカル変数」 (`is_global == false`) である場合は、非ブロッキング代入 (`<=`) ではなくブロッキング代入 (`=`) を使用するように変更** します。
これにより、中間変数への代入は同一クロックサイクル内で即座に評価され、組み合わせ回路（Combinational Logic）として正しく動作するようになります。

## 4. 具体的な変更内容

### ① [codegen.cpp](file:///Users/shadowlink/Documents/git/CmCPU/Cm/src/codegen/sv/codegen.cpp) の修正

1. **`emitStatement` 内の `Assign` 判定**:
   ```cpp
   bool use_nonblocking =
       func.is_async || func.always_kind == mir::MirFunction::AlwaysKind::FF;
   if (use_nonblocking && assign.place.local < func.locals.size()) {
       if (!func.locals[assign.place.local].is_global) {
           use_nonblocking = false;
       }
   }
   ```
2. **`emitTerminator` 内の組み込み関数呼び出し判定 (`use_nb`)**:
   ```cpp
   bool use_nb = func.is_async || func.always_kind == mir::MirFunction::AlwaysKind::FF;
   if (use_nb && cd.destination && cd.destination->local < func.locals.size()) {
       if (!func.locals[cd.destination->local].is_global) {
           use_nb = false;
       }
   }
   ```
3. **`emitTerminator` 内の一般関数呼び出し判定 (`use_nb`)**:
   組み込み関数呼び出しと同様に、`use_nb` 判定にローカル変数チェックを追加します。

## 5. 検証計画

1. **コンパイラの再ビルド**:
   ```bash
   cd Cm && make build
   ```
2. **HDMI のビルドと生成コードの目視確認**:
   ```bash
   ./builder.sh hdmi
   ```
   `build/hdmi/hdmi_colorbar.sv` を確認し、以下の点を確認します。
   - `tmds_r` や `cnt_r` などの状態レジスタには `<= `（非ブロッキング）が使われていること。
   - `r_n1` や `r_qm` などのローカル中間変数には `= `（ブロッキング）が使われていること。
3. **実機デプロイ検証**:
   ```bash
   ./builder.sh --apply hdmi
   ```
   実機に書き込み、ディスプレイ上に白・黄・シアン・緑・マゼンタ・赤・青・黒の均等な幅の 8 色カラーバーが正しく描画されることを確認します。
