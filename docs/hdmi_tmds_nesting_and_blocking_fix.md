# HDMI TMDSエンコーダのチャネルネスト解消および代入方式（ブロッキング/ノンブロッキング）の修正設計

## 1. 背景と問題の事象
HDMIカラーバー出力を `./builder.sh hdmi --apply` でデプロイした際、ディスプレイ側が信号を検知せず、「何も接続されていない」状態（信号なし）になる問題が発生していました。

## 2. 原因調査結果
生成されたSystemVerilogコード (`build/hdmi/hdmi_colorbar.sv`) を解析した結果、以下の2つの重大な問題が特定されました。

### 原因①: チャネル間ネストバグ
本来並列であるべきRed, Green, BlueのTMDSエンコーダ処理が、Redチャネル内の `if` 分岐の中にGreenがネストし、さらにその中にBlueがネストする構造になっていました。
これにより、Redチャネルの `de_reg == 1` かつ `r_n1_qm == 4` のケースなど、特定の条件が満たされない限り、GreenやBlueのエンコード論理（ブランキング期間の同期シグナルCTRLトークン出力含む）が実行されないため、HDMIレシーバーが同期信号を受信できず「未接続」となっていました。

* **コンパイラのバグ箇所**: `Cm/src/codegen/sv/codegen.cpp` の `findMergeBlock` 関数。
  * `then_block` 側の探索では `SwitchInt` (分岐) を辿って合流先を収集していましたが、`else_block` 側からの探索では `Goto` 以外の terminator が現れると探索が停止してしまっていました。
  * `else` 側にさらに `if` 分岐 (SwitchInt) があると、合流ブロックを検出できず `SIZE_MAX` (合流なし) を返し、結果として後続の文が全て先行 `if` の `then` ブロック内部にインライン展開（ネスト）されていました。

### 原因②: 非ブロッキング代入による中間値参照の遅延
`encoder.cm` で定義されている中間計算用変数（`r_n1`, `r_use_xnor`, `r_q0`〜`r_q7` 等）は、現在モジュールレベルの広域変数として定義されています。
これらを `async func` (クロック同期) 内で代入すると、コンパイラはSystemVerilogの非ブロッキング代入 (`<=`) を生成します。このため、同サイクル内で代入した中間変数の値をすぐ下の行の `if` 等で参照した際に、1クロック前の古い値が読み出されてしまい、論理回路として完全に崩壊していました。

## 3. 修正方針

### ① Cmコンパイラ (SystemVerilogバックエンド) の修正
`Cm/src/codegen/sv/codegen.cpp` を修正します。

#### 3.1.1. `findMergeBlock` 関数の拡張
`else_block` からの探索ループにおいて、`SwitchInt` および `Call` ターミネータを検知した場合も、その遷移先ターゲットを `work` に積むように修正し、複雑なネスト `if` が存在する場合でも正しく合流ブロックを検出できるようにします。

```cpp
        const auto& bb = *func.basic_blocks[bid];
        if (bb.terminator) {
            if (bb.terminator->kind == mir::MirTerminator::Goto) {
                auto& gd = std::get<mir::MirTerminator::GotoData>(bb.terminator->data);
                work.push_back(gd.target);
            } else if (bb.terminator->kind == mir::MirTerminator::SwitchInt) {
                auto& sd = std::get<mir::MirTerminator::SwitchIntData>(bb.terminator->data);
                for (const auto& [val, target] : sd.targets) {
                    work.push_back(target);
                }
                work.push_back(sd.otherwise);
            } else if (bb.terminator->kind == mir::MirTerminator::Call) {
                auto& cd = std::get<mir::MirTerminator::CallData>(bb.terminator->data);
                work.push_back(cd.success);
            }
        }
```

#### 3.1.2. 代入方式の最適化 (ローカル変数のブロッキング代入化)
`emitStatement` および `emitTerminator` (CallData) において、代入先ターゲットが「ローカル変数」 (`is_global == false`) である場合は、`always_ff` ブロック内であっても非ブロッキング代入 (`<=`) ではなくブロッキング代入 (`=`) を使用して即座に評価されるようにします。これにより、中間計算用変数が同一クロックサイクル内で順序正しく評価されます。

### ② HDMIソースコードの修正
`src/hdmi/encoder/encoder.cm` を修正します。
* `r_n1`, `r_use_xnor`, `r_q0`〜`r_q7`, `r_qm`, `r_n1_qm`（およびG, B各チャネルの同等変数）の定義をモジュール直下から `tmds_encode` 関数内のローカル変数宣言へ移動します。

---

## 4. 検証計画

1. **コンパイラのビルド**:
   ```bash
   cd Cm
   make build
   ```
2. **HDMIのビルドとコード確認**:
   ```bash
   ./builder.sh hdmi
   ```
   * `build/hdmi/hdmi_colorbar.sv` を開き、以下の点を確認します。
     * Red, Green, Blueの各エンコード処理が並列（ネストなし）に出力されていること。
     * 中間変数（`r_n1` 等）への代入にブロッキング代入 `=` が使用されていること。
     * 状態変数（`cnt_r`, `tmds_r` 等）への代入にはノンブロッキング代入 `<=` が使用されていること。
3. **実機デプロイ**:
   ```bash
   ./builder.sh hdmi --apply
   ```
   * Gowin EDA の合成・配置配線が正常終了し、ディスプレイがHDMI信号を検知してカラーバーが正常に描画されることを確認します。
