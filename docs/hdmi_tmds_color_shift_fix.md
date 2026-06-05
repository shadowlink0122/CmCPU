# HDMIカラーバー境界の色ずれバグ修正設計書

## 1. 現象
HDMIでカラーバーを表示した際、カラーバーの境界部分において数ピクセル分だけ隣の色が重なって（ずれて）表示されてしまう不具合が発生しています。

## 2. 原因
現在の `encoder.cm` の実装では、TMDSエンコード処理（`tmds_encode`）全体が `async func` （SystemVerilogの `always_ff @(posedge pixel_clk)` ブロック）として記述されています。

また、Gowin EDAの制限（`always_ff` ブロック内でのブロッキング代入があると合成クラッシュする）を回避するため、中間計算変数（`r_n1`, `r_use_xnor`, `r_q0`-`r_q7`, `r_qm`, `r_n1_qm`）がすべてモジュールスコープ（グローバル変数）として定義されています。

この組み合わせにより、SystemVerilog生成時に中間変数への代入がすべて**非ブロッキング代入（`<=`）**に変換されてしまっていました。
これにより、例えば `r_q1` の計算式が同一クロック内で代入された `r_q0` の値ではなく、前のクロックでの `r_q0` の値（1ピクセル前の値）を参照してしまい、これがカスケードして `r_q7` まで伝播することで、最大8ピクセル分のデータ伝播遅延が発生していました。これがカラーバーの境界部分での数ピクセル分の色ずれ（前ピクセルの値の残り）の根本原因です。

## 3. 対策
TMDSエンコーダの計算（組み合わせ回路）と、計算結果をクロックに同期してレジスタに格納する処理（順序回路）を明確に分離します。

### (1) 組み合わせ回路の追加
新たに `always_comb void tmds_encode_comb()` を定義し、TMDSエンコード処理のすべての計算式（XOR/XNOR選択、遷移最小化、DCバランス計算）をこの中に配置します。
- これらの中間変数への代入はすべて `always_comb` 内で行われるため、SystemVerilog上では**ブロッキング代入（`=`）**として出力され、同一クロックサイクル内で遅延なく即座に計算が完了します。
- 計算された次の `tmds_r/g/b` および次の累積不均衡カウンタ `cnt_r/g/b` を格納するために、新しいモジュールスコープ変数 `next_tmds_r/g/b` および `next_cnt_r/g/b` を定義し、計算結果を代入します。

### (2) 順序回路の簡素化
`export async func tmds_encode(posedge pixel_clk)` は、クロックの立ち上がりエッジで `next_tmds_*` および `next_cnt_*` の値を実際の `tmds_*` および `cnt_*` レジスタにロードするだけの処理にします。
- これは `always_ff` ブロックとなるため、代入はすべて**非ブロッキング代入（`<=`）**になり、Gowin EDAの合成クラッシュを完璧に回避できます。

## 4. 実装変更計画

### (1) `encoder.cm` への変数追加
```cm
// 組み合わせ回路用の一時レジスタ
int next_tmds_r = 0;
int next_tmds_g = 0;
int next_tmds_b = 0;
int next_cnt_r = 0;
int next_cnt_g = 0;
int next_cnt_b = 0;
```

### (2) `always_comb void tmds_encode_comb()` の実装
`tmds_encode` の中身のロジックを移行し、 `tmds_r` や `cnt_r` への代入箇所を `next_tmds_r` や `next_cnt_r` に置き換えます。

### (3) `tmds_encode` 関数の書き換え
```cm
export async func tmds_encode(posedge pixel_clk) {
    tmds_r = next_tmds_r;
    tmds_g = next_tmds_g;
    tmds_b = next_tmds_b;
    cnt_r = next_cnt_r;
    cnt_g = next_cnt_g;
    cnt_b = next_cnt_b;
}
```

## 5. 検証項目
1. ビルドが正常に通ること (`./builder.sh hdmi`)
2. 生成された `build/hdmi/hdmi_colorbar.sv` を確認し、 `always_comb` 内で中間変数へのブロッキング代入 (`=`) が行われ、 `always @(posedge)` 内で非ブロッキング代入 (`<=`) が行われていることを確認する。
3. Gowin EDAでの論理合成・配置配線が正常に終了すること (`./builder.sh --apply hdmi`)
4. 実機に書き込まれた後、カラーバーの境界で色ずれが発生しないことを確認する。
