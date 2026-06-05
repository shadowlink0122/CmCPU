# HDMIタイミング不整合およびelse-if正規化バグの修正設計

## 1. 現状の課題と原因

HDMIカラーバー回路を実機に書き込んだ際、ディスプレイが信号を検知せず「接続されていない/信号なし」状態になる問題について、生成されたSystemVerilogコードとタイミングの分析から以下の2つのバグを特定しました。

### 原因1: 制御信号（DE/HSYNC/VSYNC）とカラーデータ（R/G/B）の1サイクルタイミング不整合
Cmの `timing` モジュールは `posedge pixel_clk` で `de_reg` や `hc` を更新（1サイクル遅延）します。
`pattern` モジュール（カラーバー生成）も `posedge pixel_clk` で `de_reg` および `hc` を参照して `r_out` などを決定するため、`r_out` は `de_reg` に対してさらに1サイクル遅れて出力されます（計2サイクル遅延）。
しかし、`encoder` モジュールは `de_reg` と `r_out` を同じタイミングで参照してTMDSエンコードを行います。
この結果、以下の問題が発生します。
- アクティブ期間の最初のピクセルが、前のラインのブランキング黒データをエンコードする（黒で始まる）。
- `de_reg` が `false` になった瞬間、エンコーダは即座にコントロールトークン（同期信号）を出力し始め、`r_out` の最終ピクセル（1サイクル遅延している）をエンコードせずにカットする。
- これにより、1ラインあたりのアクティブビデオキャラクター数が仕様の640ピクセルから**639ピクセル**に減少してしまい、多くのHDMIモニターで「タイミング範囲外/信号なし」として検出拒否されます。

### 原因2: コンパイラの `else-if` 正規化処理における文の誤配置バグ
Cmコンパイラの `codegen.cpp` の `else-if` 正規化最適化（`else` ブロックの直後に `if` がある場合に `else if` に結合する処理）において、`else` ブロック内に `if` 以外の文（例: `cnt_b = 0`）が後続して存在する場合でも、これを無視して `else if` に結合してしまっていました。
この結果、Blueチャネルエンコーダ (`tmds_encode_b`) のブランキング処理において、`cnt_b <= 32'd0;`（DCバランスカウンタのリセット）が `vsync_reg == 1'b0` の `else` ブロック（すなわち `vsync_reg == 1'b1` の時だけ）に誤ってネストされ、`vsync_reg == 1'b0` の時は `cnt_b` が更新されない（ラッチ/レジスタ値保持）状態になっていました。

---

## 2. 対策方針

### 対策1: 遅延同期信号の導入（タイミングアライメント）
`de_reg`、`hsync_reg`、`vsync_reg` をそれぞれ1サイクル遅延させた `de_del`、`hsync_del`、`vsync_del` を `timing` モジュールに導入します。
カラーバーデータ `r_out`/`g_out`/`b_out` と全く同じタイミングで1サイクル遅延した制御信号をエンコーダに与えることで、完全にアライメントが一致した640ピクセル×480ラインの映像データと同期信号が送信されるようになります。

### 対策2: コンパイラの `else-if` 正規化処理の厳格化
`else` ブロック内の `if` ステートメントの終了位置（`end`）を `begin/end` のネスト数を追跡することで厳密に特定します。
その終了位置からアウター `else` の終了位置（`end`）までの間に、空行・コメント以外の有効なステートメントが存在する場合は、`else-if` 結合をスキップするように修正します。これにより、`cnt_b <= 32'd0;` などの後続処理が正しくアウター `else` 直下で並列に実行されるようになります。

---

## 3. 具体的な変更内容

### ① [timing.cm](file:///Users/shadowlink/Documents/git/CmCPU/src/hdmi/timing/timing.cm)
1サイクル遅延した制御信号（`de_del`, `hsync_del`, `vsync_del`）を定義し、クロック立ち上がり時に現在のレジスタ値をコピーします。

```cm
export bool hsync_del = true;
export bool vsync_del = true;
export bool de_del    = false;

export async func video_timing(posedge pixel_clk) {
    // 1サイクル前の状態を遅延信号にコピー（ノンブロッキング代入相当）
    de_del = de_reg;
    hsync_del = hsync_reg;
    vsync_del = vsync_reg;

    // 水平/垂直カウンタ、およびオリジナルの de_reg, hsync_reg, vsync_reg 計算（既存のまま）
    ...
}
```

### ② [encoder.cm](file:///Users/shadowlink/Documents/git/CmCPU/src/hdmi/encoder/encoder.cm)
`de_reg`, `hsync_reg`, `vsync_reg` を参照している箇所をすべて `de_del`, `hsync_del`, `vsync_del` に変更します。

### ③ [codegen.cpp](file:///Users/shadowlink/Documents/git/CmCPU/Cm/src/codegen/sv/codegen.cpp)
`else if` 正規化ロジックにおいて、インナーステートメントの範囲をネスト解析し、後続処理がある場合の結合を防止するチェックを追加します。

---

## 4. 検証計画

1. **コンパイラの再ビルド**:
   `cd Cm && make build` が正常に通ることを確認します。
2. **HDMIモジュールのコンパイル検証**:
   `./builder.sh hdmi` を実行し、コンパイルと Verilator リントチェックが正常にパスすることを確認します。
3. **生成されたSVコードの静的確認**:
   `build/hdmi/hdmi_colorbar.sv` を目視し、以下を確認します。
   - `tmds_encode_b` の `else` ブロック内で、`cnt_b <= 32'd0;` が `vsync_reg` の条件分岐の外側（`de_del == 1'b1` の `else` 直下）に正しく出力されていること。
   - エンコーダが `de_del`, `hsync_del`, `vsync_del` を参照して動作していること。
4. **実機デプロイ・表示検証**:
   `./builder.sh hdmi --apply` を実行して実機に書き込み、HDMIモニターにカラーバーが安定して表示されることを確認します。
