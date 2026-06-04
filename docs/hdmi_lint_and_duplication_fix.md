# HDMIリントチェック失敗と重複宣言の修正設計書

## 1. 現象と原因分析

### ① Verilator リントでの重複宣言エラー
`builder.sh --apply hdmi` 実行時、Verilator リントにおいて `hc`, `vc`, `hsync_reg` 等のグローバル変数が重複宣言されている旨のエラーが多数発生します。

**原因**:
Cmのコンパイラプリプロセッサ（`ImportPreprocessor`）は、インポートされたファイルをテキストレベルで再帰的に展開し、インポート元の名前空間（`namespace`）でラップします。
HDMIモジュールの細分化に伴い、`timing.cm` などの共通モジュールが複数のサブモジュール（`pattern.cm` や `encoder.cm`）から多重インポートされているため、展開後の単一ソース内には同一の変数定義（例: `hc`）が異なる名前空間内に複数出現します。
HIRからMIRへの lowering の際、関数名や `localparam`（定数）は `codegen.cpp` にて名前ベースの重複排除（`emitted_function_names` や `emitted_param_names`）が行われていましたが、通常のグローバル変数（レジスタ・ワイヤ・ポート等）にはこの重複排除処理が存在しなかったため、生成された SystemVerilog 上に `logic [31:0] hc;` が複数出力されていました。

### ② `builder.sh` でのビットストリーム見つからないエラー
`main.cm` にリネームしたことで、`builder.sh` がプロジェクト名を `main` と誤判定し、Gowin の生成物である `build/hdmi/hdmi_colorbar/impl/pnr/hdmi_colorbar.fs` ではなく `build/hdmi/main/impl/pnr/main.fs` を探しに行ってしまいエラーになっていました。

**原因**:
`builder.sh` がエントリーポイントのファイル名（`main.cm`）から `PROJECT_NAME="main"` を自動決定するためです。

---

## 2. 対策方針

### ① SVバックエンド (`codegen.cpp`) の修正
`Cm/src/codegen/sv/codegen.cpp` のグローバル変数処理ループにおいて、`emitted_var_names` という `std::set<std::string>` を追加し、変数名（および必要に応じて名前空間プレフィックスを除去した単純名）を元に重複排除を行います。

対象の変数種別:
- 外部入力/出力ポート (`is_input`, `is_output`, `is_inout`)
- 内部レジスタ・ワイヤ (`reg_declarations`)
- 連続代入文 (`is_assign` 時の `wire_declarations` および `assign_statements`)
- BRAM/LutRAM 定義
- extern struct インスタンス化 (`instance_blocks`)

これにより、多重インポートされた同一シンボルが生成される SV ファイル上で一度だけ定義されるようになり、Verilator リントおよび Gowin 合成時の多重定義エラーが解消されます。

### ② `builder.sh` の修正
エントリーポイントファイル名が `main.cm` の場合、プロジェクト名を親ディレクトリ名等にフォールバック、または `hdmi` ディレクトリ時は `hdmi_colorbar` に置換するロジックを `builder.sh` の `detect_project` に追加します。

---

## 3. 動作検証計画
1. `Cm` コンパイラをビルドし、テストを実行します。
2. `make hdmi-build` を実行し、生成された `hdmi_colorbar.sv` に重複宣言がないことを目視確認します。
3. `./builder.sh hdmi --apply` を実行し、リントチェック（Verilator）および Gowin 合成・配置配線がすべて正常終了し、ビットストリームが検出されることを検証します。
