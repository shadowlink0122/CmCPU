# HDMIモジュールのディレクトリ構成整理（直下のクリーンアップ）

## 1. 概要
`src/hdmi/` 直下の構成をよりクリーンにするため、`main.cm` 以外のサブモジュールのディレクトリ（`constants`, `encoder`, `pattern`, `pll`, `serdes`, `timing`）を、新たに作成する `src/hdmi/main/` ディレクトリ配下に移動・整理します。

これにより、`src/hdmi/` 直下にはエントリーポイントとなる `main.cm` とビルド関連ファイル（`.tcl`, `.sv`, `.cst`等）のみが存在する構成になります。

## 2. 目的
- `src/hdmi/` 直下のソースコード関連ファイルとしては `main.cm` のみになるようにし、直下の見通しを向上させる。
- 細分化された各サブモジュールが `main/` ディレクトリ内に隠蔽されるため、プロジェクト全体のディレクトリ構造が整理されます。

## 3. ディレクトリ構成の変更

変更前：
```
src/hdmi/
├── main.cm
├── constants/
│   └── hdmi_constants.cm
├── encoder/
│   └── encoder.cm
├── pattern/
│   └── pattern.cm
├── pll/
│   └── pll.cm
├── serdes/
│   ├── oser.cm
│   └── obuf.cm
├── timing/
│   └── timing.cm
├── gowin_hdmi.tcl
├── hdmi_colorbar_top.sv
├── postprocess_sv.sh
├── tang_console_138k_hdmi.cst
└── tang_console_138k_hdmi_pg484.cst
```

変更後：
```
src/hdmi/
├── main.cm           (直下にある唯一の.cmソースファイル)
├── main/             (新設: サブモジュール格納用)
│   ├── constants/
│   │   └── hdmi_constants.cm
│   ├── encoder/
│   │   └── encoder.cm
│   ├── pattern/
│   │   └── pattern.cm
│   ├── pll/
│   │   └── pll.cm
│   ├── serdes/
│   │   ├── oser.cm
│   │   └── obuf.cm
│   └── timing/
│       └── timing.cm
├── gowin_hdmi.tcl
├── hdmi_colorbar_top.sv
├── postprocess_sv.sh
├── tang_console_138k_hdmi.cst
└── tang_console_138k_hdmi_pg484.cst
```

## 4. 修正内容

### ① `src/hdmi/main.cm`
インポートパスを `./main/...` 配下を指すように更新します。

```cm
import ./main/constants/hdmi_constants;
import ./main/pll/pll;
import ./main/timing/timing;
import ./main/pattern/pattern;
import ./main/encoder/encoder;
import ./main/serdes/oser;
import ./main/serdes/obuf;
```

### ② 各サブモジュール
サブモジュール同士の相対位置（例：`timing/` から `constants/`）は `main/` ディレクトリに一緒に移動するため、お互いの相対パス関係は維持されます。
したがって、各サブモジュール内部のインポート文（例: `import ../constants/hdmi_constants;`）の変更は不要です。

### ③ Makefile / builder.sh
- `Makefile` 内の `HDMI_SRC := $(SRC_DIR)/hdmi/main.cm` は変更がないため、修正は不要です。
- `builder.sh` も `src/hdmi/` 直下の `.cm` ファイルを検索して `main.cm` を見つけるため、修正なしでそのまま動作します。

## 5. 動作検証計画
- ディレクトリ移動およびインポート文修正後、`./builder.sh hdmi` を実行し、コンパイルとVerilatorリントがエラーなく通ることを確認します。
- `git status` を確認し、想定外のファイルが `src/hdmi/` 直下や `src/hdmi/main/` 以外の場所に残っていないことを検証します。
