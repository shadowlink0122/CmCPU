# 制御文字の文字列配列化およびコンパイラSVバックエンド拡張設計書

## 1. 背景と目的
制御文字の3文字略記は、これまでに単一の `string` を用いたインデックス計算 `(idx * 3 + offset)` で管理されていました。しかし、この方法ではスペースの挿入ミスによるオフセットズレ（例: `GSRS` 部分の空白欠落による `DEL` が `ELA` になるバグ）が起きやすく、可読性も低いという問題があります。

前回の検討では、`utiny[3][34]` の多次元配列定義へ移行する方針としましたが、ユーザーからのフィードバックにより、プログラマ視点での可読性や扱いやすさを考慮し、**`string` の1次元配列 (`const string[34] CTRL_ABBREVS`) として宣言し、変換時に `utiny` にキャストするアプローチ**がより優れていると判断しました。

本設計では、`const string[34] CTRL_ABBREVS` による制御文字定義へと移行し、CmコンパイラのSystemVerilogバックエンドにおいて、文字列配列の文字抽出や配列リテラル内の文字列定数が正しくコード生成されるように拡張を行います。

---

## 2. 設計詳細

### 2.1 CmコンパイラのSystemVerilogバックエンド拡張 (`Cm/src/codegen/sv/codegen.cpp`)

#### ① 配列リテラル内の文字列定数対応 (`emitHirExpr`)
`emitHirExpr` の `HirLiteral` ケースにおいて、`std::string` の値が含まれている場合の変換処理を追加します。これにより、配列リテラル内に存在する各文字列（例: `"NUL"`, `"SOH"` など）が、SystemVerilogの対応する文字列リテラル形式（`"NUL"`）として正しくトランスパイルされます。

```cpp
            } else if (std::holds_alternative<std::string>(value)) {
                return "\"" + std::get<std::string>(value) + "\"";
            }
```

#### ② 文字列配列要素へのインデックスアクセスにおけるビットスライス処理 (`emitPlace` & `__builtin_string_charAt`)
`CTRL_ABBREVS[code]` のように文字列配列の要素にアクセスした結果の `string` に対し、さらにインデックスアクセス `[offset]` を行う際、SystemVerilog側の表現（`logic [23:0]`）に対してビットレベルの添字ではなく、バイト単位（8ビット）の適切なビットスライスを生成する必要があります。

- `global_string_lengths_` のキー検索時、式中に含まれる配列添字（例: `[code]`）を無視してベースの変数名（例: `CTRL_ABBREVS`）を抽出できるようにします。
- `global_string_lengths_` に登録されていない場合（または配列の要素型としての `String` の場合）、`current_type` が `String` であれば `getBitWidth(current_type) / 8` （デフォルトで 24bit / 8 = 3バイト）をフォールバック値 `L` として使用します。
- これにより、`CTRL_ABBREVS[code][offset]` のトランスパイル結果が SystemVerilog 側で `CTRL_ABBREVS[code][(2 - offset) * 8 +: 8]` となり、正しい文字データを取得できるようになります。

### 2.2 制御文字の文字列配列定義 (`src/hdmi/text/ctrl_abbrev.cm`)
`ctrl_abbrev.cm` において、`const string[34] CTRL_ABBREVS` として34個の制御文字略記を定義します。

```cm
module ctrl_abbrev;

// 34個の制御文字略記 (各3文字、DELはインデックス33に対応)
export const string[34] CTRL_ABBREVS = [
    "NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL",
    "BCK", "TAB", "RTN", "VT ", "FF ", "CR ", "SO ", "SI ",
    "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB",
    "CAN", "EM ", "SUB", "ESC", "FS ", "GS ", "RS ", "US ",
    "SPC", "DEL"
];
```

### 2.3 アニメーション制御における文字抽出の実装 (`src/hdmi/text/animation_ctrl.cm`)
`get_string_char` での制御文字抽出ロジックを、文字列配列へのアクセスおよび `utiny` へのキャスト（`as utiny`）で実装します。

```cm
utiny get_string_char(bool is_title, utiny idx, utiny offset) {
    if (is_title) {
        return (TITLE[idx] as utiny);
    } else {
        utiny code = idx;
        if (idx == 127) {
            code = 33;
        }
        return (CTRL_ABBREVS[code][offset] as utiny);
    }
}
```

---

## 3. 検証計画

### 3.1 統合ビルドおよびVerilatorリント検証
- `make build -C Cm` でコンパイラを再構築します。
- `make text-build` を実行し、CmからSVへのトランスパイル、および Verilator によるリントチェックが警告・エラーなしで合格することを確認します。

### 3.2 物理合成・実機検証
- `make text-gowin` を実行し、Gowin EDA 物理合成が正常に終了することを確認します。
- `make text-flash` を実行し、実機でタイトルおよび制御文字略記（特に `[DEL]` が正しく表示されること）を確認します。
