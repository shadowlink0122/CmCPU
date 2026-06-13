# 制御文字の可読表現およびコンパイラCFGバグ修正設計書

## 背景と目的
現在、`src/hdmi/text/animation_ctrl.cm` では制御文字（NUL, SOHなど）の3文字略記をアスキーコード `0x4E554C` などの直接の数値で扱っていました。これは可読性の観点から好ましくありません。また、`pos` (0〜2桁目) の条件分岐が各所に分散して定義されているため、可読性と保守性の向上を目的としてリファクタリングを行います。

また、CmのSystemVerilog (SV) バックエンドにおいて、関数呼び出し (`MirTerminator::Call`) を伴う `SwitchInt` のトランスパイル時に、後続の分岐 (`switch (pos)`) が誤って先行する分岐 (`case 0: begin ... end`) の中にネストして出力されるバグ、および定数式 `const` 内の `init_expr` が `localparam` 定義として出力されないバグが見つかったため、これらを修正します。

---

## コンパイラ修正方針 (`codegen.cpp` の修正)

### 1. `findMergeBlock` における `Call` ターミネータの追跡漏れ修正
`SVCodeGen::findMergeBlock` は、分岐（`SwitchInt`）の後に合流するブロック（`merge_block`）を探索する関数です。
先行する分岐の中で関数呼び出し（`MirTerminator::Call`）が行われると、制御フロー上に `Call` ターミネータが出現します。
現行のコードでは、`then_reachable`（`then` ブランチから到達可能なブロック集合）を収集するループにおいて、`Call` ターミネータの遷移先 `success` が追跡対象から漏れていました。そのため、`then_reachable` が正しく構築されず、合流ブロックが `SIZE_MAX` (見つからない) として判定され、後続の `switch` ブロックが最初の `case` の中に誤ってインライン出力されていました。

**修正案**:
`findMergeBlock` の最初の `then_reachable` 収集ループに、`Call` ターミネータの追跡処理を追加します。

```cpp
// codegen.cpp
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

### 2. `const` 変数の非リテラル定数式の `localparam` 初期化対応
`const` 変数でキャストやビットシフトを用いた定数式（例: `(('N' as uint) << 16)`）を定義した際、フロントエンドの定数畳み込みでは `gv->init_value` (リテラル定数) に展開されず、`gv->init_expr` (HIRの評価式) として保持されます。
SVコード生成部では `gv->init_value` のみがチェックされていたため、値の伴わない `localparam logic [31:0] NAME;` のような空の宣言が出力されてしまい、論理合成でエラーになっていました。

**修正案**:
`codegen.cpp` の const 変数出力部分で、`gv->init_value` がない場合に `gv->init_expr` を評価して出力するように修正します。

```cpp
            std::string localparam_decl = "localparam " + mapType(gv->type) + " " + param_name;
            if (gv->init_value) {
                localparam_decl += " = " + emitConstant(*gv->init_value, gv->type);
            } else if (gv->init_expr) {
                localparam_decl += " = " + emitHirExpr(*gv->init_expr);
            }
            localparam_decl += ";";
```

---

## HDMI側リファクタリング設計 (`animation_ctrl.cm`)

### 1. パック定数の定義
3文字略記を視覚的に表現するため、文字定数のビット演算を用いて `const` 定数を定義します。
```cm
// 制御文字の3文字略記の定義
const uint NUL = (('N' as uint) << 16) | (('U' as uint) << 8) | ('L' as uint);
const uint SOH = (('S' as uint) << 16) | (('O' as uint) << 8) | ('H' as uint);
const uint STX = (('S' as uint) << 16) | (('T' as uint) << 8) | ('X' as uint);
...
```

### 2. `pos` 管理の集約化
従来は `get_ctrl_abbrev(val, pos)` の中で `val` と `pos` の2次元の `switch` 分岐が複雑にネストされていました。
リファクタリング後は、以下のように役割を明確に分離します。
- `get_ctrl_abbrev(val)`: `val` に応じた3文字パック値（`uint`）を返す。
- `extract_char(packed_val, pos)`: パック値から指定した `pos` (0〜2) の1文字（`utiny`）を抽出する。

```cm
// 指定位置の文字を抽出する共通関数
utiny extract_char(uint packed_val, utiny pos) {
    utiny c = ' ' as utiny;
    switch (pos) {
        case (0) { c = ((packed_val >> 16) & 0xFF) as utiny; }
        case (1) { c = ((packed_val >> 8) & 0xFF) as utiny; }
        case (2) { c = (packed_val & 0xFF) as utiny; }
        else     { c = ' ' as utiny; }
    }
    return c;
}

// 制御文字のパック値を取得する
uint get_ctrl_abbrev(utiny val) {
    uint abbrev = pack3(' ', ' ', ' ');
    switch (val) {
        case (0)   { abbrev = NUL; }
        case (1)   { abbrev = SOH; }
        ...
        else       { abbrev = pack3(' ', ' ', ' '); }
    }
    return abbrev;
}
```

これにより、`pos` の管理を個別の `case` に記述するのではなく、`extract_char` 内に集約させ、コード全体の記述量を大幅に削減し可読性を高めます。

---

## 検証計画

### 1. コンパイラテスト
- `pack_test.cm` を再コンパイルし、`case (pos)` が `case (val)` の外側（フラットな位置）に正しく合流して出力されること。
- 生成された `pack_test.sv` 内の `localparam` 宣言に、定数式から評価された初期化値（例: `= 32'd78 << 32'd16 ...`）が正しく出力されていること。
- `make -C Cm test-sv` がすべて PASS すること。

### 2. HDMI Text 実機検証
- `make text-build` が正常終了し、`hdmi_text.sv` が正常に生成され `verilator` リントを通過すること。
- `make text-gowin` で Gowin FPGAの論理合成が通り、`make text-flash` で実機で制御文字略記（`[NUL]` 等）が正しく画面に表示されること。
