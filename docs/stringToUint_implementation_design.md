# stringToUint関数および文字列インデックスSVトランスパイル設計書

## 1. 背景と目的
現在、`src/hdmi/text/` 内のタイトル文字列（`TITLE_0`〜`TITLE_10`）や制御文字の略記（`NUL`〜`DEL`）は、アスキー文字をビットシフトを用いて `uint` パックした定数で定義されています。このアプローチは合成可能であるものの、プログラマ視点での可読性が極めて低く、保守も困難です。

本設計では、これらの文字列・文字コードテーブル情報を Cm 側で `string` 型（例: `"NUL"`, `"=== Character Code Table ... ==="`）として管理し、SystemVerilog (SV) バックエンドで合成可能なコードへ変換する `stringToUint` 関数および文字列のインデックスアクセス変換を導入します。

---

## 2. 構成・設計詳細

### 2.1 コンパイラの改修 (`Cm/src/codegen/sv/codegen.cpp`)

#### 1. 文字列インデックスアクセス (`__builtin_string_charAt`) のSVトランスパイル対応
Cm 側での `my_str[idx]` アクセスは、MIR 上で `__builtin_string_charAt(my_str, idx)` 呼び出しに展開されます。これを SV のビットスライス構文に手動で翻訳します。
- `dest = my_str[(L-1-idx)*8 +: 8]` 形式で出力します。
- ここで `L` はグローバル定数から取得した文字列の文字長です。

#### 2. コピー追跡 (`copy_map`) を用いた文字列長 `L` の特定
MIR 生成過程で、グローバル定数がローカル変数やテンポラリ変数にコピーされる場合（例: `_5 = copy(TITLE_0); _6 = __builtin_string_charAt(_5, _7)`）に対応するため、`analyzeFunction` 内の文を走査してコピー・移動・参照の代入関係を記録するマップを構築します。
- `ref_map`, `copy_map`, `const_map` を統合・拡張し、テンポラリ変数を経由して元のグローバル文字列定数名を逆引きできるようにします。
- `global_string_lengths_` からオリジナルの文字列長 `L` を引いてスライス幅を計算します。

#### 3. `stringToUint` 関数のトランスパイル
`codegen.cpp` は `stringToUint` 関数を特別に扱い、SV の function ブロックとして出力します。
```sv
function automatic logic [31:0] stringToUint(input logic [23:0] s);
    return {8'd0, s};
endfunction
```
※3文字略記は24ビットの `logic [23:0]` で表されるため、32ビットの `uint` へ変換します。

### 2.2 アプリケーションコードの改修

#### 1. `src/hdmi/text/display_strings.cm`
個別の 4 文字パック定数 `TITLE_0` 〜 `TITLE_10` を廃止し、連続した 1 つの `const string` として定義します。
```cm
module display_strings;

export const string TITLE = "=== Character Code Table (ASCII & KANA) ===";
```

#### 2. `src/hdmi/text/ctrl_abbrev.cm`
各制御文字略記定数（`NUL`, `SOH` など）を `stringToUint` を用いた定義に置き換えます。また、Cm 側のシミュレーション/コンパイル用フォールバックとして `stringToUint` 関数の本体も定義します。
```cm
module ctrl_abbrev;

// Cmコンパイル・シミュレーション用のフォールバック実装
export uint stringToUint(string s) {
    uint val = 0;
    // 3文字目のASCIIパック
    val = ((s[0] as uint) << 16) | ((s[1] as uint) << 8) | (s[2] as uint);
    return val;
}

export const uint NUL = stringToUint("NUL");
export const uint SOH = stringToUint("SOH");
// ...他30個強の制御文字定数も同様
```

#### 3. `src/hdmi/text/animation_ctrl.cm`
ヘッダー文字列の取得処理 `get_header_char` を、新しく定義された `string` 型の `TITLE` に対するインデックスアクセス `TITLE[idx]` に基づくシンプルな形に更新します。
```cm
utiny get_header_char(utiny idx) {
    return (display_strings::TITLE[idx] as utiny);
}
```

---

## 3. 検証計画

### 3.1 単体テスト・コンパイル検証
- コンパイラをビルド (`make build -C Cm`) します。
- 一時テストファイル `.tmp/test_string.cm` を作成し、`const string` 定数、インデックスアクセス、`stringToUint` 呼び出しが正常にコンパイルされ、正しい SV が生成されることを確認します。

### 3.2 HDMIアセンブリ・合成検証
- `make text-build` を実行し、生成された `build/hdmi/hdmi_text.sv` が文法的に正しく、Verilator でのリントエラーがないことを確認します。
- `make text-gowin` を実行し、Gowin EDA 物理合成が警告・エラーなく通ることを確認します。
- `make text-flash` を実行し、Tang Console 138K 開発ボードでヘッダータイトルおよび制御文字略記が正しく描画されることを確認します。
