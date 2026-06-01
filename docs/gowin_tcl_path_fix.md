# Gowin EDA Tclスクリプトの出力パス不整合の修正設計

## 1. 課題の背景と現状
`builder.sh` でビルドを実行した際、コンパイル後のSystemVerilogファイル（`.sv`）の出力先と、Gowin EDA（`gw_sh`）が読み込むファイルの場所、および生成されたビットストリームファイル（`.fs`）の検出場所がずれているため、フルビルド成功時に書き込みエラー（見つからないエラー）が発生しています。

### 具体的なエラーログ
```
✅ ビルド完了! /Users/shadowlink/Documents/git/CmCPU/build/blink.fs
[OK] Gowin EDA ビルド完了

[ERROR] ビットストリームファイルが見つかりません: /Users/shadowlink/Documents/git/CmCPU/build/blink/blink/impl/pnr/blink.fs
[ERROR] Gowin EDA の出力パスを確認してください
```

### 現状のパス設定と発生している不整合
- `builder.sh` の設計：
  - SV出力: `${BUILD_DIR}/${dir}/${PROJECT_NAME}.sv`
    - 例 (blink): `build/blink/blink.sv`
  - Gowinプロジェクト出力先: `${BUILD_DIR}/${dir}/${PROJECT_NAME}/`
    - 例 (blink): `build/blink/blink/`
  - 期待するFSファイルパス: `build/blink/blink/impl/pnr/blink.fs`
- 一方、`src/blink/gowin_build.tcl` や `src/uart/gowin_*.tcl` の設計：
  - 読み込むSVパス: `${project_root}/build/blink.sv` （親ディレクトリを参照してしまっている）
  - プロジェクト作成ディレクトリ (`output_dir`): `${project_root}/build`
  - 実際のプロジェクト格納パス: `build/blink/`
  - 実際のFSファイル生成パス: `build/blink/impl/pnr/blink.fs`

このため、Gowin Tclが古い親ディレクトリの `.sv` を参照してビルドし、さらに生成先も `${BUILD_DIR}/${PROJECT_NAME}/impl/pnr/` となり、`builder.sh` が探索する `${BUILD_DIR}/${dir}/${PROJECT_NAME}/impl/pnr/` と二重フォルダ（`build/blink/blink/...`）にならずに不整合が起きています。

---

## 2. 対策方針
`builder.sh` でのプロジェクト格納ディレクトリ設計（`${BUILD_DIR}/${dir}/${PROJECT_NAME}/`）に統一するため、各Tclスクリプト内の `sv_file` および `output_dir` パス、完了時のログ出力を修正します。

これにより、プロジェクト構成を以下に統一します。

| プロジェクト | ディレクトリ | SV入力パス | Tcl出力先 (output_dir) | 生成プロジェクトパス | 生成FSファイルパス |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **blink** | `blink` | `build/blink/blink.sv` | `build/blink` | `build/blink/blink` | `build/blink/blink/impl/pnr/blink.fs` |
| **uart (hello)** | `uart` | `build/uart/uart_hello.sv` | `build/uart` | `build/uart/uart_hello` | `build/uart/uart_hello/impl/pnr/uart_hello.fs` |
| **uart (button)** | `uart` | `build/uart/uart_button.sv` | `build/uart` | `build/uart/uart_button` | `build/uart/uart_button/impl/pnr/uart_button.fs` |
| **hdmi** | `hdmi` | `build/hdmi/hdmi_colorbar.sv` | `build/hdmi` | `build/hdmi/hdmi_colorbar` | `build/hdmi/hdmi_colorbar/impl/pnr/hdmi_colorbar.fs` |

---

## 3. 具体的な変更内容

### ① `src/blink/gowin_build.tcl` の修正
- `sv_file` パスを変更:
  ```tcl
  set sv_file "${project_root}/build/blink/blink.sv"
  ```
- `output_dir` パスを変更:
  ```tcl
  set output_dir "${project_root}/build/blink"
  ```
- 完了時ログ出力のFSファイルパスを修正:
  ```tcl
  puts "✅ ビルド完了! ${output_dir}/${project_name}/impl/pnr/${project_name}.fs"
  ```

### ② `src/uart/gowin_build.tcl` の修正
- `sv_file` パスを変更:
  ```tcl
  set sv_file "${project_root}/build/uart/uart_hello.sv"
  ```
- `output_dir` パスを変更:
  ```tcl
  set output_dir "${project_root}/build/uart"
  ```
- 完了時ログ出力のFSファイルパスを修正:
  ```tcl
  puts "✅ ビルド完了! ${output_dir}/${project_name}/impl/pnr/${project_name}.fs"
  ```

### ③ `src/uart/gowin_button.tcl` の修正
- `sv_file` パスを変更:
  ```tcl
  set sv_file "${project_root}/build/uart/uart_button.sv"
  ```
- `output_dir` パスを変更:
  ```tcl
  set output_dir "${project_root}/build/uart"
  ```
- 完了時ログ出力のFSファイルパスを修正:
  ```tcl
  puts "✅ ビルド完了! ${output_dir}/${project_name}/impl/pnr/${project_name}.fs"
  ```

### ④ `src/hdmi/gowin_hdmi.tcl` の修正
- 完了時ログ出力のFSファイルパスを修正:
  ```tcl
  puts "✅ HDMI ビルド完了! ${output_dir}/${project_name}/impl/pnr/${project_name}.fs"
  ```
