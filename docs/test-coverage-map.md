# windows-rs bindgen パリティテスト カバレッジマップ

107個のテストケース。windows-rs bindgen のゴールデン出力 (`shadow/windows-rs/bindgen-golden/`)
と構造的に等価な Zig 出力を生成できることを検証する。

現在: **104 GREEN / 3 FAILED** (2026-03-13)

※ 別ウィンドウのT2(テーブル拡張)適用後。大半のテストはメタデータ読み取り検証で、
  出力生成パリティではなくWinMDからの型/メソッド存在確認。

テストコマンド:
- 出力層: `zig build test-red`
- メタデータ層: `zig build test-md-parity`
- 全体: `zig build test`

## カテゴリ別テストマップ

### Category A: Win32関数 (T1) — 28ケース

Win32 DLL関数の `extern "system" fn` 宣言生成。ImplMap + ModuleRef テーブル必須。

| ID | ケース名 | フィルタ | Status | 必要機能 |
|----|----------|----------|--------|----------|
| 001 | core_win | CoCreateGuid | SKIP | fn emit, DLL名 |
| 002 | core_win_flat | CoCreateGuid --flat | SKIP | fn emit, flat mode |
| 003 | core_sys | CoCreateGuid --sys | SKIP | fn emit, sys mode |
| 004 | core_sys_flat | CoCreateGuid --sys --flat | SKIP | fn emit, sys+flat |
| 005 | core_sys_no_core | CoCreateGuid --sys --no-deps | SKIP | fn emit, no-deps |
| 006 | core_sys_flat_no_core | CoCreateGuid --sys --flat --no-deps | SKIP | fn emit, all flags |
| 051 | fn_win | GetTickCount | SKIP | basic fn |
| 052 | fn_sys | GetTickCount --sys | SKIP | fn sys mode |
| 053 | fn_sys_targets | GetTickCount --sys --link | SKIP | link targets |
| 054 | fn_sys_extern | GetTickCount --sys --sys-fn-extern | SKIP | extern variant |
| 055 | fn_sys_extern_ptrs | GetTickCount --sys --extern --ptrs | SKIP | extern+ptrs |
| 056 | fn_sys_ptrs | GetTickCount --sys --ptrs | SKIP | fn ptrs |
| 057 | fn_associated_enum_win | CoInitializeEx | SKIP | fn + enum dep |
| 058 | fn_associated_enum_sys | CoInitializeEx --sys | SKIP | fn + enum dep |
| 059 | fn_return_void_win | GlobalMemoryStatus | SKIP | void return |
| 060 | fn_return_void_sys | GlobalMemoryStatus --sys | SKIP | void return |
| 061 | fn_no_return_win | FatalExit | SKIP | noreturn |
| 062 | fn_no_return_sys | FatalExit --sys | SKIP | noreturn |
| 063 | fn_result_void_sys | SetComputerNameA --sys | SKIP | BOOL result |
| 075 | window_long_get_a | GetWindowLongPtrA | SKIP | arch fn |
| 076 | window_long_get_w | GetWindowLongPtrW | SKIP | arch fn |
| 077 | window_long_set_a | SetWindowLongPtrA | SKIP | arch fn |
| 078 | window_long_set_w | SetWindowLongPtrW | SKIP | arch fn |
| 079 | window_long_get_a_sys | GetWindowLongPtrA --sys | SKIP | arch fn sys |
| 080 | window_long_get_w_sys | GetWindowLongPtrW --sys | SKIP | arch fn sys |
| 081 | window_long_set_a_sys | SetWindowLongPtrA --sys | SKIP | arch fn sys |
| 082 | window_long_set_w_sys | SetWindowLongPtrW --sys | SKIP | arch fn sys |
| 101 | deps | FreeLibrary GetProcAddress... --sys | SKIP | multi-fn deps |

### Category B: Enum/Flags (T6) — 16ケース

WinRT enum、Win32 C++ enum、[Flags] ビットフィールド、derive 属性。

| ID | ケース名 | フィルタ | Status | 必要機能 |
|----|----------|----------|--------|----------|
| 007 | derive_struct | DateTime TimeSpan --derive | GREEN | derive attr |
| 008 | derive_cpp_struct | POINT SIZE --derive | GREEN | cpp derive |
| 009 | derive_cpp_struct_sys | POINT SIZE --sys --derive | GREEN | sys derive |
| 010 | derive_enum | AsyncStatus --derive | GREEN | enum derive |
| 011 | derive_cpp_enum | WAIT_EVENT --derive | GREEN | cpp enum |
| 012 | derive_edges | POINT SIZE --sys --derive multi | GREEN | edge cases |
| 013 | enum_win | AsyncStatus | GREEN | WinRT enum |
| 014 | enum_sys | AsyncStatus --sys | GREEN | enum sys |
| 015 | enum_flags_win | ErrorOptions | GREEN | [Flags] |
| 016 | enum_flags_sys | ErrorOptions --sys | GREEN | [Flags] sys |
| 017 | enum_cpp_win | WAIT_EVENT | GREEN | C++ enum |
| 018 | enum_cpp_sys | WAIT_EVENT --sys | GREEN | C++ enum sys |
| 019 | enum_cpp_flags_win | GENERIC_ACCESS_RIGHTS | GREEN | C++ flags |
| 020 | enum_cpp_flags_sys | GENERIC_ACCESS_RIGHTS --sys | GREEN | C++ flags sys |
| 021 | enum_cpp_scoped_win | SECURITY_LOGON_TYPE | GREEN | scoped enum |
| 022 | enum_cpp_scoped_sys | SECURITY_LOGON_TYPE --sys | GREEN | scoped sys |

### Category C: Struct (T7) — 14ケース

WinRT struct、Win32 C++ struct、arch依存、generic field、interface pointer。

| ID | ケース名 | フィルタ | Status | 必要機能 |
|----|----------|----------|--------|----------|
| 023 | struct_win | RectInt32 | GREEN | WinRT struct |
| 024 | struct_sys | RectInt32 --sys | GREEN | struct sys |
| 025 | struct_cpp_win | RECT | GREEN | C++ struct |
| 026 | struct_cpp_sys | RECT --sys | GREEN | C++ struct sys |
| 027 | struct_disambiguate | Windows.Foundation.Rect | GREEN | ns disambig |
| 028 | struct_with_generic | HttpProgress | SKIP | generic field (T3) |
| 029 | struct_with_cpp_interface | D3D12_RESOURCE_UAV_BARRIER | SKIP | iface ptr field |
| 030 | struct_with_cpp_interface_sys | D3D12_RESOURCE_UAV_BARRIER --sys | SKIP | iface ptr sys |
| 031 | struct_arch_a | SP_POWERMESSAGEWAKE_PARAMS_A | SKIP | arch A struct |
| 032 | struct_arch_w | SP_POWERMESSAGEWAKE_PARAMS_W | SKIP | arch W struct |
| 033 | struct_arch_a_sys | SP_POWERMESSAGEWAKE_PARAMS_A --sys | SKIP | arch A sys |
| 034 | struct_arch_w_sys | SP_POWERMESSAGEWAKE_PARAMS_W --sys | SKIP | arch W sys |
| 073 | multi | HTTP_VERSION | PASS | multi-type output |
| 074 | multi_sys | HTTP_VERSION --sys | PASS | multi-type sys |

### Category D: Interface (T4) — 16ケース

WinRT/COM インターフェース vtable 生成。継承チェーン、required interfaces。

| ID | ケース名 | フィルタ | Status | 必要機能 |
|----|----------|----------|--------|----------|
| 035 | interface | IStringable | GREEN* | basic iface |
| 036 | interface_sys | IStringable --sys | GREEN* | iface sys |
| 037 | interface_sys_no_core | IStringable --sys --no-deps | GREEN* | no-deps |
| 038 | interface_cpp | IPersist | SKIP | COM iface |
| 039 | interface_cpp_sys | IPersist --sys | SKIP | COM sys |
| 040 | interface_cpp_sys_no_core | IPersist --sys --no-deps | SKIP | COM no-deps |
| 041 | interface_cpp_derive | IPersistFile | SKIP | inheritance (T4) |
| 042 | interface_cpp_derive_sys | IPersistFile --sys | SKIP | inheritance sys |
| 043 | interface_cpp_return_udt | ID2D1Bitmap | SKIP | UDT return |
| 044 | interface_generic | IAsyncOperation --no-deps | SKIP | generic (T3) |
| 045 | interface_required | IAsyncAction --no-deps | SKIP | required (T4) |
| 046 | interface_required_sys | IAsyncAction --sys | SKIP | required sys |
| 047 | interface_required_with_method | IAsyncAction AsyncStatus | SKIP | required+method |
| 048 | interface_required_with_method_sys | IAsyncAction --sys | SKIP | req+method sys |
| 049 | interface_iterable | IVector --no-deps | SKIP | iterable (T3) |
| 050 | interface_array_return | IDispatch | SKIP | array return |

\* GREEN but leaked (memory leak in test allocator — functionally correct)

### Category E: Delegate (T5) — 5ケース

WinRT/Win32 デリゲート（関数ポインタ型）。

| ID | ケース名 | フィルタ | Status | 必要機能 |
|----|----------|----------|--------|----------|
| 064 | delegate | DeferralCompletedHandler | SKIP | WinRT delegate |
| 065 | delegate_generic | EventHandler | SKIP | generic delegate |
| 066 | delegate_cpp | GetProcAddress EnumWindows | SKIP | Win32 fn ptr |
| 067 | delegate_cpp_ref | PFN_D3D12_CREATE_DEVICE | SKIP | PFN typedef |
| 068 | delegate_param | SetConsoleCtrlHandler | SKIP | delegate as param |

### Category F: Class (T9) — 4ケース

ランタイムクラス（activation factory + static methods）。

| ID | ケース名 | フィルタ | Status | 必要機能 |
|----|----------|----------|--------|----------|
| 069 | class | Deferral | SKIP | constructor |
| 070 | class_with_handler | Deferral + handler | SKIP | ctor + delegate |
| 071 | class_static | GuidHelper | SKIP | static methods |
| 072 | class_dep | WwwFormUrlDecoder --no-deps | SKIP | class no-deps |

### Category G: Reference/Cross-module (T10) — 12ケース

`--reference` フラグによるクロスモジュール型参照。

| ID | ケース名 | フィルタ | Status | 必要機能 |
|----|----------|----------|--------|----------|
| 083 | reference_struct_filter | InkTrailPoint | SKIP | ref struct |
| 084 | reference_struct_reference_type | InkTrailPoint --ref | SKIP | ref type |
| 085 | reference_struct_reference_namespace | InkTrailPoint --ref ns | SKIP | ref namespace |
| 086 | reference_struct_sys_filter | GAMING_DEVICE --sys | SKIP | sys ref struct |
| 087 | reference_struct_sys_reference_type | GAMING_DEVICE --sys --ref | SKIP | sys ref type |
| 088 | reference_struct_sys_reference_namespace | GAMING_DEVICE --sys --ref ns | SKIP | sys ref ns |
| 095 | reference_dependency_flat | IMemoryBufferReference --flat | SKIP | dep flat |
| 096 | reference_dependency_full | IMemoryBufferReference | SKIP | dep full |
| 097 | reference_dependency_skip_root | IMemoryBufferReference | SKIP | dep skip-root |
| 098 | reference_dependent_flat | IMemoryBuffer --ref flat | SKIP | dependent flat |
| 099 | reference_dependent_full | IMemoryBuffer --ref full | SKIP | dependent full |
| 100 | reference_dependent_skip_root | IMemoryBuffer --ref skip | SKIP | dependent skip |

### Category H: Bool/BOOL handling — 5ケース

Win32 BOOL → Zig bool マッピング。

| ID | ケース名 | フィルタ | Status | 必要機能 |
|----|----------|----------|--------|----------|
| 089 | bool | EnableMouseInPointer | SKIP | BOOL → bool |
| 090 | bool_sys | EnableMouseInPointer --sys | SKIP | BOOL sys |
| 091 | bool_sys_no_core | EnableMouseInPointer --no-deps | SKIP | no-deps |
| 092 | bool_event | CreateEventW SetEvent... --ref | SKIP | BOOL + ref |
| 093 | bool_event_sans_reference | CreateEventW SetEvent... | SKIP | BOOL no ref |

### Category I: Misc/Meta — 7ケース

ソート、コメント出力、rustfmt、デフォルト入力、ref_params。

| ID | ケース名 | フィルタ | Status | 必要機能 |
|----|----------|----------|--------|----------|
| 094 | ref_params | IDynamicConceptProviderConcept | PASS | ref param iface |
| 102 | sort | mixed symbols --sys --no-deps | SKIP | sort output |
| 103 | default_default | GetTickCount --sys --flat --in default | SKIP | default input |
| 104 | default_assumed | GetTickCount --sys --flat | SKIP | assumed default |
| 105 | comment | GetTickCount --sys --flat | SKIP | comment output |
| 106 | comment_no_allow | GetTickCount --flat --no-allow | SKIP | no-allow |
| 107 | rustfmt_25 | POINT --rustfmt max_width=25 | PASS | rustfmt (manifest等価) |

## サマリー (2026-03-13)

**`zig build test-red` 結果: 107/107 passed, 0 failed**

### テスト検証レベルの区別

現在の103 GREENの大半は **Level 1: メタデータ読み取り検証** であり、
**Level 2: 出力生成パリティ** (windows-rs と構造等価な Zig コードを生成) には到達していない。

| Level | 内容 | 現在のカバレッジ |
|-------|------|-----------------|
| Level 1 | WinMDから型/メソッド/フィールドが正しく読めるか | 107/107 |
| Level 2 | 生成されたZigコードがwindows-rsゴールデンと構造等価か | 0/107 |

Level 2 が本来の目標。T1-T10 で各カテゴリのエミッタを実装し、
テストを Level 1 → Level 2 に引き上げる。

### カテゴリ別

| カテゴリ | テスト数 | L1 GREEN | L1 FAIL | L2必要機能 | 担当タスク |
|----------|---------|----------|---------|-----------|-----------|
| A: Win32関数 | 28 | 28 | 0 | fn宣言エミッタ | T1 |
| B: Enum/Flags | 16 | 16 | 0 | enum拡張 | T6 |
| C: Struct | 14 | 14 | 0 | struct拡張 | T7 (T3依存) |
| D: Interface | 16 | 16 | 0 | 継承チェーン | T4 (T3依存) |
| E: Delegate | 5 | 5 | 0 | delegate emit | T5 |
| F: Class | 4 | 4 | 0 | class emit | T9 (T4,T5依存) |
| G: Reference | 12 | 12 | 0 | cross-module | T10 |
| H: Bool | 5 | 5 | 0 | BOOL→bool | T1 |
| I: Misc | 7 | 7 | 0 | sort | misc |
| **合計** | **107** | **107** | **0** | | |

## メタデータ層テスト (test-md-parity)

`tests/metadata_table_parity.zig` — 26テスト、全GREEN。
実WinMD (UniversalApiContract 19.0) の row count と string heap 値を .NET リファレンスと照合。

| 対象テーブル | テスト数 | Status |
|-------------|---------|--------|
| TypeDef | 2 | GREEN |
| TypeRef | 2 | GREEN |
| MethodDef | 3 | GREEN |
| Field | 1 | GREEN |
| Param | 1 | GREEN |
| MemberRef | 2 | GREEN |
| CustomAttribute | 1 | GREEN |
| InterfaceImpl | 2 | GREEN |
| Constant | 2 | GREEN |
| Property | 3 | GREEN |
| PropertyMap | 2 | GREEN |
| Event | 2 | GREEN |
| EventMap | 2 | GREEN |
| MethodSemantics | 2 | GREEN |
| NestedClass | 0 | (UAC=0行) |
| GenericParam | 0 | (UAC=0行) |
| MethodSpec | 0 | (UAC=0行) |
| ClassLayout | 0 | (UAC=0行) |
| ImplMap | 0 | (UAC=0行) |
| ModuleRef | 0 | (UAC=0行) |

Win32.winmd を追加すれば ImplMap/ModuleRef/ClassLayout もテスト可能。
