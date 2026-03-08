# windows-rs準拠 Zigテスト整備 完全ロードマップ

最終更新: 2026-03-08

## 1. 目的

- `shadow/windows-rs/bindgen-cases.json` の **107ケース全件**を、Zig実装で継続的に検証できる状態にする。
- Rust実装（`windows-rs` bindgen）を **仕様の正解（SSOT）** として扱い、Zig出力の構造等価性を担保する。
- 現在の「部分的・手作業テスト」から「全件自動・差分検出可能テスト」へ移行する。

## 2. 現状スナップショット

- Issue:
  - `#12` Roadmap: windows-rs bindgen完全互換に向けた実装計画（OPEN）
  - `#13` `simpleSize()` row_count参照バグ（OPEN、根本原因は特定済み）
- 現在の `tests/generation_parity.zig` は **30ケース相当**の個別実装（107全件未到達）。
- `bindgen-cases.json` は **107件**（`test_raw: 16`, `test: 90`, `bindgen: 1`）。
- `docs/test-coverage-map.md` はカテゴリ分解（A〜I）と不足機能が整理済み。

## 3. 完了定義 (Definition of Done)

以下を全て満たした時点で完了:

1. `bindgen-cases.json` 107件を1件も欠落なく実行できる。
2. 各ケースでRustゴールデンとZig生成結果を比較し、判定理由を機械可読で出力できる。
3. `zig build test-gen-parity` がCIで安定実行できる（環境依存ケースは明示SKIP）。
4. カテゴリA〜Iの未実装機能がIssueリンク付きで追跡され、RED/GREENが再現可能。
5. 「部分的個別テスト追加」ではなく、ケース追加時に自動追従する仕組みになっている。

## 4. 実装方針（Rustをお手本）

## 4.1 SSOT

- 入力仕様: `shadow/windows-rs/bindgen-cases.json`
- 期待値仕様: `shadow/windows-rs/bindgen-golden/*.rs`
- Zig側はケース定義を手書きしない。manifest駆動で全件を走査する。

## 4.2 比較レイヤ

- Level 1: メタデータ解決の健全性（型・メソッド発見）
- Level 2: 生成コードの構造等価性（型名、シグネチャ、定数値、vtableスロット、属性）
- 今回のゴールは **Level 2を107件に拡張**。

## 4.3 テスト設計

- `CaseLoader`: JSONから全ケースを読み込み（ID重複・欠落を検出）
- `CaseExecutor`: ケース引数をZig生成パイプラインへ変換し実行
- `GoldenLoader`: 対応 `.rs` を取得
- `Normalizer`: Rust/Zigの表記差を吸収（空白、属性順、allow/comment等）
- `Comparator`: 構造単位で比較し、差分を分類（missing/extra/mismatch）

## 5. ワークストリーム（サブ並列前提）

## WS0: 土台固定（必須）

- [ ] `#13` の修正を `win-zig-metadata` に適用・取り込み（row_count参照バグ解消）
- [ ] `zig build test-md-parity` をGREEN化
- [ ] `test-gen-parity` の起動時前提（WinMD探索、skip条件）を安定化

成果物:
- パーサ起因での偽陰性を排除した基線

## WS1: 全件ハーネス化（107件自動列挙）

- [ ] `tests/generation_parity.zig` を「個別手書き」から「manifestループ」へ移行
- [ ] 107件のID一覧と実行結果を1レポートに出力
- [ ] 未対応機能は `ExpectedFail` として理由コードで管理

成果物:
- 「全件実行できている」ことの機械的証明

## WS2: Rustゴールデン比較器（Level 2化）

- [ ] `.rs` ゴールデンをケースIDで解決
- [ ] 正規化ルールを最小セットで実装
- [ ] 差分をカテゴリ別に可視化（関数、enum、struct、interface、delegate、class）

成果物:
- 107件の構造比較結果（PASS/FAIL + 差分根拠）

## WS3: カテゴリA/C/D/E/F/G/H/Iの未実装を順次解消

- A (Win32関数): 001-006, 051-063, 075-082, 101
- C (struct拡張): 028-034, 073-074
- D (interface継承/required): 038-050
- E (delegate): 064-068
- F (class): 069-072
- G (reference): 083-088, 095-100
- H (BOOL): 089-093
- I (misc): 094, 102-107

成果物:
- 各カテゴリでRED→GREENを確認する回帰テスト

## WS4: CIゲート化

- [ ] `zig build test-gen-parity` を `zig build gate` に依存追加
- [ ] 失敗時に差分サマリを出力（ケースID単位）
- [ ] flaky検出（再実行で結果揺れ有無）を記録

成果物:
- PR段階で互換性崩れを自動検出

## 6. 進行順（依存関係）

1. WS0（土台固定）
2. WS1（全件列挙）
3. WS2（ゴールデン比較）
4. WS3（カテゴリ別実装修正）
5. WS4（CIゲート）

## 7. マイルストーン

- M1: 107件を列挙・実行できる（比較なし）
- M2: 107件すべてでRust比較の結果が出る
- M3: 主要カテゴリ（A/B/C/D/E）でGREEN率を引き上げる
- M4: 107件をCIゲート化し、回帰検知が機能する

## 8. 直近アクション（次の実装順）

1. `generation_parity.zig` に `CaseLoader`/`CaseExecutor` を追加して107件を自動実行化
2. `bindgen-golden` 読み込みと正規化比較を最小実装
3. まずは既存GREENカテゴリ（B中心）でLevel 2比較を通す
4. Category A（関数emit）を最優先でRED削減

## 9. リスクと対策

- リスク: 手書きテスト増加で漏れ再発
  - 対策: manifestを唯一の列挙元に固定
- リスク: 正規化が過剰で誤判定
  - 対策: 正規化ルールは最小・差分種別をログ出力
- リスク: WinMD環境差でCI不安定
  - 対策: 探索失敗時は明示SKIP + 理由コード

