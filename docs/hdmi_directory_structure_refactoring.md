# HDMI実装のフォルダ階層整理と `main.cm` への統合

## 1. 概要
HDMIモジュールのディレクトリ構成について、`src/hdmi/` 直下にはエントリーポイントとなる `main.cm` のみを配置し、それ以外のすべての `.cm` ファイル（定数定義を含む）をサブディレクトリに配置するリファクタリングを行います。

## 2. 目的
- `src/hdmi/` ディレクトリ直下の構成をシンプルにし、`main.cm` がエントリーポイントであることが自明な構成にする。
- 定数定義 `hdmi_constants.cm` を専用の `constants/` ディレクトリに移動し、モジュールごとの役割分担をより明確にする。

## 3. ディレクトリ構成の変更

変更前：
```
src/hdmi/
├── hdmi_colorbar.cm  (トップレベル、git mv済)
├── hdmi_constants.cm (定数定義、git mv済)
├── constants/
│   └── (空)
...
```

変更後：
```
src/hdmi/
├── main.cm           (トップレベル。直下にある唯一の.cmファイル)
├── constants/
│   └── hdmi_constants.cm (移動後)
├── pll/
│   └── pll.cm
├── timing/
│   └── timing.cm
├── pattern/
│   └── pattern.cm
├── encoder/
│   └── encoder.cm
└── serdes/
    ├── oser.cm
    └── obuf.cm
```

## 4. 修正対象ファイルと変更内容

### ① `src/hdmi/main.cm` (トップレベル)
- `import hdmi_constants;` を `import ./constants/hdmi_constants;` に変更する。

### ② 各サブモジュール (`timing.cm`, `pattern.cm`, `encoder.cm`)
- 定数定義へのインポートパスを `import ../hdmi_constants;` から `import ../constants/hdmi_constants;` に更新する。

### ③ `Makefile`
- トップレベルソースコードのパス指定を `hdmi_colorbar.cm` から `main.cm` に更新する。
  - `HDMI_SRC := $(SRC_DIR)/hdmi/main.cm`

## 5. 動作検証計画
- `make hdmi-build` を実行し、CmからSystemVerilogへのトランスパイルが正常に通ることを検証する。
- 生成された `build/hdmi/hdmi_colorbar.sv` に対して、従来のビルドフロー（ポストプロセスおよびGowin合成）が正常に機能し、ビットストリームが生成されるか (`make hdmi-gowin`) を検証する。
