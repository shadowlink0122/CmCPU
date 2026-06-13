# Switch構文によるリファクタリング設計設計書

## 背景と目的
`src/hdmi/text/animation_ctrl.cm` には、文字表示テーブル描画用の複数の文字・略記・グリッド変換関数（`get_header_char`, `get_ctrl_abbrev`, `get_table_char`）において、非常に多くの `if` 文が存在していました。これらをCm言語の `switch` 構文に書き換えることで、コードの可読性を飛躍的に高めます。

また、CmのSystemVerilogバックエンドでは、OR/Rangeパターンの `switch` がトランスパイルされる際に、同一遷移先ブロックを二重に処理した結果、最初のケース以外が空（`begin end`）になるコンパイラバグが判明したため、このバグも同時に修正します。

---

## コンパイラ修正方針 (`codegen.cpp` の修正)

### 現状の動作
```cpp
// 各ターゲットのケース
for (const auto& [val, target] : sd.targets) {
    ss << indent() << val << ": begin\n";
    increaseIndent();
    std::set<size_t> case_visited = visited;
    emitBlockRecursive(func, target, case_visited, ss, merge);
    visited.insert(case_visited.begin(), case_visited.end());
    decreaseIndent();
    ss << indent() << "end\n";
}
```
OR/Rangeパターンの場合、異なるケース値（`val`）が同一の遷移先ブロック（`target`）を持ちます。
このループの初回で `target` が処理されると、`visited` に追加され、2回目のループでは `case_visited.count(target)` が真となるため、`emitBlockRecursive` が即時リターンしてしまい空のブロックが生成されてしまいます。

### 修正後のロジック
同一の遷移先 `BlockId` を持つケース値（`val`）をグループ化し、SystemVerilogのカンマ区切りケースラベル（例: `0, 1, 2: begin ... end`）としてトランスパイルします。

```cpp
// 遷移先ブロック ID ごとにケース値をグループ化
std::map<size_t, std::vector<int64_t>> target_groups;
std::vector<size_t> target_order;
for (const auto& [val, target] : sd.targets) {
    if (target_groups.find(target) == target_groups.end()) {
        target_order.push_back(target);
    }
    target_groups[target].push_back(val);
}

// グループごとにケースを生成
for (size_t target : target_order) {
    const auto& vals = target_groups[target];
    ss << indent();
    for (size_t i = 0; i < vals.size(); ++i) {
        ss << vals[i];
        if (i + 1 < vals.size()) {
            ss << ", ";
        }
    }
    ss << ": begin\n";
    increaseIndent();
    std::set<size_t> case_visited = visited;
    emitBlockRecursive(func, target, case_visited, ss, merge);
    visited.insert(case_visited.begin(), case_visited.end());
    decreaseIndent();
    ss << indent() << "end\n";
}
```

---

## `animation_ctrl.cm` のリファクタリング設計

### 1. `get_header_char(idx)` の `switch` 化
文字ごとに該当する `idx` を OR パターン `|` で結合して判定します。
```cm
utiny get_header_char(utiny idx) {
    utiny c = ' ' as utiny;
    switch (idx) {
        case (0 | 1 | 2 | 40 | 41 | 42) { c = '=' as utiny; }
        case (4 | 14 | 28) { c = 'C' as utiny; }
        case (5) { c = 'h' as utiny; }
        case (6 | 8 | 20) { c = 'a' as utiny; }
        case (7 | 12) { c = 'r' as utiny; }
        case (9) { c = 'c' as utiny; }
        case (10) { c = 't' as utiny; }
        case (11 | 17 | 23) { c = 'e' as utiny; }
        case (15) { c = 'o' as utiny; }
        case (16) { c = 'd' as utiny; }
        case (19) { c = 'T' as utiny; }
        case (21) { c = 'b' as utiny; }
        case (22) { c = 'l' as utiny; }
        case (25) { c = '(' as utiny; }
        case (26 | 35 | 37) { c = 'A' as utiny; }
        case (27) { c = 'S' as utiny; }
        case (29 | 30) { c = 'I' as utiny; }
        case (32) { c = '&' as utiny; }
        case (34) { c = 'K' as utiny; }
        case (36) { c = 'N' as utiny; }
        case (38) { c = ')' as utiny; }
        else { c = ' ' as utiny; }
    }
    return c;
}
```

### 2. `get_ctrl_abbrev(val, pos)` の `switch` 化
外側に `val` の `switch`、内側に `pos` の `switch` を置く二重の `switch` 構文にリファクタリングします。

### 3. `get_table_char(r, idx)` の `switch` 化
- `idx` から列 `c` および `offset` を求める処理: Rangeパターン (`0 ... 9`) を使用。
- 100の位/10の位を求める処理: Rangeパターンを使用。
- `is_ctrl` 判定: ORとRangeパターンの組み合わせ（`0 ... 32 | 127`）を使用。
- `offset` による `res_char` 出力判定: `switch` を使用。

---

## 検証計画
1. **コンパイラの単体・統合テスト**: 新規テスト `Cm/tests/sv/control/switch_or.cm` でトランスパイル後のSVのケース構造を確認。
2. **HDMI Textビルド**: `make text-build` が正常に通過し、`build/hdmi/hdmi_text.sv` に `case (x) 0, 1, 2: begin ... end` 形式が出力されているか確認。
3. **実機検証**: `make text-gowin` および `make text-flash` を通して、実機で崩れやブラックアウトがないことを最終確認。
