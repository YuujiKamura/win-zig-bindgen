# windows-rs metadata crate — 部屋ごとの構造分析

## 規模サマリー

| 項目 | windows-rs metadata | win-zig-bindgen |
|------|---------------------|-----------------|
| 総行数 | 2,665行 / 32ファイル | 6,200行 / 20ファイル (core) |
| PE/テーブル読み取り | ~350行 (file.rs) | ~990行 (pe+tables+streams+metadata) |
| 統合インデックス | ~130行 (type_index.rs) | ~430行 (unified_index.zig) |
| シグネチャデコード | ~300行 (blob.rs) | ~470行 (sig_decode.zig) |
| コード生成 | 別crate (windows-bindgen) | ~1,114行 (emit.zig) |
| coded index | ~160行 (codes.rs) | ~392行 (coded_index.zig) |
| テーブルラッパー | ~520行 (tables/*.rs) | tables.zig内に統合 |
| 型システム | ~155行 (ty+type_name+signature+type_category) | context.zig内 TypeCategory等 |
| フラグ定義 | ~120行 (attributes.rs) | tables.zig内 |
| 値型 | ~45行 (value.rs) | 該当なし |

## 部屋一覧 (10部屋)

---

### Room 1: File (PE Reader) — `reader/file.rs` ~350行

**役割**: WinMDファイルを読み込み、PE/CLIヘッダーをパースし、テーブル・ヒープへの低レベルアクセスを提供。

**主要構造**:
```rust
pub struct File {
    bytes: Vec<u8>,
    strings: usize,  // #Strings heap offset
    blobs: usize,    // #Blob heap offset
    tables: [Table; 17],
}
struct Table { offset: usize, len: usize, width: usize, columns: [Column; 6] }
struct Column { offset: usize, width: usize }
```

**主要メソッド**:
- `File::read(path)` — ファイル読み込み+パース
- `usize(row, table, column)` — 任意テーブルの任意カラムの生の値
- `str(row, table, column)` — #Strings heapから文字列取得
- `blob(row, table, column)` — #Blob heapからバイト列取得
- `list(row, table, column)` — 1対多リストの範囲イテレータ
- `equal_range(table, column, value)` — ソート済みテーブルの二分探索
- `parent(row, table, column)` — 逆引き（子→親）

**win-zig-bindgenとの対応**: `pe.zig` + `tables.zig` + `streams.zig` + `metadata.zig` (合計~990行)
**差異**: windows-rsは`File`が全操作を集約。win-zig-bindgenは`tables.Info` + `streams.Heaps`に分離。分離自体は問題ない。

**必要度**: ★★★ 既存実装で十分。変更不要。

---

### Room 2: Row (バックポインタパターン) — `reader/row.rs` ~100行

**役割**: 全テーブル行の統一参照型。**TypeIndexへのバックポインタ**を持つことで、任意の行から全ファイル横断の操作が可能。

**主要構造**:
```rust
pub struct Row<'a> {
    pub(crate) index: &'a TypeIndex,  // ← これが核心
    pub(crate) file: usize,
    pub(crate) pos: usize,
}

pub trait AsRow<'a> {
    const TABLE: usize;
    fn to_row(&self) -> Row<'a>;
    fn from_row(row: Row<'a>) -> Self;
    // 提供メソッド（Row経由で全てTypeIndexにアクセス可能）:
    fn file(&self) -> &File;
    fn str(&self, column: usize) -> &str;
    fn usize(&self, column: usize) -> usize;
    fn decode<T: Decode>(&self, column: usize) -> T;
    fn blob(&self, column: usize) -> Blob;
    fn list<T: AsRow>(&self, column: usize) -> RowIterator<T>;
    fn equal_range<T: AsRow>(&self, column: usize, value: usize) -> RowIterator<T>;
}
```

**核心設計**: `Row.index`があるから:
1. `TypeDef.extends()` → `TypeDefOrRef` を返す → 別ファイルの型でも`index`経由で解決できる
2. `blob()` が返す `Blob` にも `index` が伝播 → シグネチャデコード中の型解決が透過的
3. ネストした型の探索も `index.nested()` で可能

**win-zig-bindgenとの対応**: **該当なし**（最大の構造的欠損）
- 現状: `tables.Info` + `streams.Heaps` を直接操作。バックポインタなし
- `UnifiedContext` がその代用だが、Context自体を全関数に渡す必要がある

**必要度**: ★★☆
Zigではlifetime referenceが使えないため、Rustと同じパターンは不可能。
代替戦略: `UnifiedContext`をコンテキスト引数として全関数に渡す（現在の方式を継続）。
本家と同等の**透過性**は得られないが、**機能**は同等に達成可能。

---

### Room 3: TypeIndex (統合インデックス) — `reader/type_index.rs` ~130行

**役割**: 全WinMDファイルのTypeDefを一つのHashMapに統合。型解決の中核。

**主要構造**:
```rust
pub struct TypeIndex {
    files: Vec<File>,
    types: HashMap<String, HashMap<String, Vec<(usize, usize)>>>,
    //     namespace      → name        → Vec<(file_idx, row_pos)>
    nested: HashMap<(usize, usize), Vec<usize>>,
    //     (file, outer_row) → [inner_row, ...]
}
```

**主要メソッド**:
- `new(files)` — 全ファイル走査、namespace.name で二段HashMap構築、NestedClass追跡
- `get(ns, name)` → `Iterator<TypeDef>` — 同名型が複数ファイルにあれば全て返す
- `expect(ns, name)` → `TypeDef` — 一意であることをassert
- `iter()` → `(ns, name, TypeDef)` — 全型走査
- `nested(TypeDef)` → `Iterator<TypeDef>` — ネスト型取得
- `contains(ns, name)`, `contains_namespace(ns)` — 存在確認

**設計ポイント**:
1. **二段HashMap**: `ns → name → Vec<(file, pos)>` — 名前空間で一次フィルタ、名前で二次フィルタ
2. **Vecで複数定義を許容**: 同名型が複数WinMDにある場合、全てを保持
3. `trim_tick(name)` でバッククォート除去後に格納
4. `namespace.is_empty()` をスキップ（`<Module>`とネスト型を除外）
5. **NestedClass**: `(file, outer_row) → [inner_row]` マップ

**win-zig-bindgenとの対応**: `unified_index.zig` UnifiedIndex (~200行)
**致命的差異**:
| windows-rs | win-zig-bindgen現状 |
|-----------|-------------------|
| `HashMap<ns, HashMap<name, Vec<(file,pos)>>>` | `StringHashMap("ns.name", TypeLocation)` |
| 二段HashMap | フラットHashMap |
| 同名型→Vec全保持 | 先勝ち1件のみ |
| NestedClass追跡 | なし |
| `get()` → Iterator | `findByFullName()` → ?TypeLocation (単一) |

**必要度**: ★★★ **再設計が必要**。

**再設計方針**:
```zig
const TypeIndex = struct {
    files: []const FileEntry,
    // namespace → NameMap
    types: std.StringHashMapUnmanaged(NameMap),
    // (file_idx, outer_row) → []inner_row
    nested: std.AutoHashMapUnmanaged(u48, []u32),
};
const NameMap = std.StringHashMapUnmanaged(std.ArrayListUnmanaged(TypeLocation));
```

---

### Room 4: Blob (シグネチャデコーダ) — `reader/blob.rs` ~300行

**役割**: #Blobヒープからシグネチャを読み取り、型情報にデコード。**index+fileを持つ**ことで、シグネチャ中のTypeDefOrRefを透過的に解決。

**主要構造**:
```rust
pub struct Blob<'a> {
    index: &'a TypeIndex,  // ← ここにもバックポインタ
    file: usize,
    slice: &'a [u8],
}
```

**主要メソッド**:
- `read_type_signature(generics)` → `Type` — ELEMENT_TYPE_*を読んで`Type`に変換
- `read_type_code(generics)` → `Type` — 単一型コードのデコード
- `read_method_signature(generics)` → `Signature` — メソッド全体のシグネチャ
- 0x11/0x12 (VALUETYPE/CLASS): `self.read_type_def_or_ref()` → TypeDefOrRef decoded **through index**
- 0x13 (VAR): ジェネリック引数参照
- 0x15 (GENERICINST): ジェネリック型のインスタンス化

**TypeRef解決パス**:
```
Blob.read_type_code()
  → 0x11/0x12: self.read_type_def_or_ref()
    → TypeDefOrRef::decode(self.index, self.file, code)
      → TypeRef の場合: namespace+name を取得
      → TypeDefOrRef.ty(generics) → Type::named(ns, name)
```
注意: windows-rsの`Blob`は`TypeRef → TypeDef`の直接解決はしない。`Type::Name(TypeName{ns, name})`を返し、後段で必要に応じて`TypeIndex.get(ns, name)`で解決する。

**win-zig-bindgenとの対応**: `sig_decode.zig` (~470行)
**差異**: sig_decodeは`Context`(現`UnifiedContext`)を受け取り、TypeRef解決時に`ctx.index.resolveTypeRef()`を呼ぶ。機能的には同等だが、Blobオブジェクト自体がindexを持つわけではない。

**必要度**: ★★☆ 現在の方式（Context引数渡し）で機能は達成。Zigではlifetimeがないので、Blob構造体にindexポインタを埋め込む設計は難しい（ポインタの寿命管理）。現行のContext引数方式が妥当。

---

### Room 5: Codes (coded index) — `reader/codes.rs` ~160行

**役割**: ECMA-335 coded index（TypeDefOrRef, HasAttribute等）のデコード。

**主要構造**: `code!` マクロで6つのcoded indexを定義:
- `TypeDefOrRef(2)` — TypeDef(0), TypeRef(1), TypeSpec(2)
- `HasAttribute(5)` — MethodDef(0), Field(1), TypeRef(2), TypeDef(3), ...
- `HasConstant(2)` — Field(0)
- `MemberForwarded(1)` — MethodDef(1)
- `MemberRefParent(3)` — TypeDef(0), TypeRef(1)
- `ResolutionScope(2)` — Module(0), ModuleRef(1), AssemblyRef(2), TypeRef(3)
- `TypeOrMethodDef(1)` — TypeDef(0)
- `AttributeType(3)` — MethodDef(2), MemberRef(3)

**核心**: `Decode` traitの`decode(index, file, code)` — ここでもindex+fileを受け取り、Rowを構築。

**win-zig-bindgenとの対応**: `coded_index.zig` (~392行)
**差異**: win-zig-bindgenは`Decoded{table: TableId, row: u32}`を返す（ファイル情報なし）。windows-rsは`Row{index, file, pos}`を含む型付きenumを返す。
Zigではenum+payloadで同等のことは可能だが、Rowにindexを持たせるかが鍵。現行方式（`Decoded`を返し、呼び出し側でContextから解決）でも機能する。

**必要度**: ★★☆ 現行で機能する。将来的な整理は可能だが優先度低。

---

### Room 6: Tables (テーブルラッパー) — `reader/tables/` ~520行

**役割**: 17のメタデータテーブルそれぞれに型付きラッパーを提供。

**テーブル一覧** (TABLE ID):
| テーブル | ID | 主要メソッド |
|---------|---|-------------|
| TypeDef | 8 | flags, name, namespace, extends, fields, methods, generic_params, interface_impls, category |
| TypeRef | 9 | scope, name, namespace |
| TypeSpec | 10 | ty(generics) |
| MethodDef | 6 | rva, flags, name, signature, params, parent, impl_map, calling_convention |
| Field | 2 | flags, name, ty, constant |
| InterfaceImpl | 4 | class, interface(generics) |
| Attribute | 1 | name, parent, ctor, value |
| MemberRef | 5 | parent, name, signature |
| GenericParam | 3 | sequence, flags, owner, name |
| NestedClass | 13 | inner, outer |
| Constant | 0 | ty, parent, value |
| ClassLayout | 16 | packing_size, class_size |
| ImplMap | 11 | flags, import_name, import_scope |
| MethodParam | 7 | flags, sequence, name |
| Module | 0 | (debug only) |
| ModuleRef | 12 | name |
| AssemblyRef | 0x23 | (debug only) |

**核心設計**: 全ラッパーが`AsRow`を実装 → `Row`経由で`usize/str/blob/list/equal_range/decode`にアクセス → 全て`TypeIndex`に到達可能。

**win-zig-bindgenとの対応**: `tables.zig` 内のTypeDefRow, MethodDefRow等 + metadata_nav.zig
**差異**: win-zig-bindgenはRowデータを直接構造体に展開。windows-rsはRowの参照+遅延読み取り。

**必要度**: ★☆☆ 現行で十分。型ラッパーの追加は便利だが必須ではない。

---

### Room 7: ItemIndex (コード生成用二次インデックス) — `reader/item_index.rs` ~120行

**役割**: TypeIndexの上に構築される二次インデックス。コード生成時にType/Fn/Constを名前空間ごとに整理。

**主要構造**:
```rust
enum Item { Type(TypeDef), Fn(MethodDef), Const(Field) }
struct ItemIndex(HashMap<&str, HashMap<&str, Vec<Item>>>);
```

**特殊処理**:
- `Apis`クラス（Win32関数とconst定数が入るコンテナ）を展開してメソッド・フィールドを直接登録
- unscoped enumのフィールドを名前空間直下に展開

**win-zig-bindgenとの対応**: **該当なし**
**必要度**: ☆☆☆ 不要。win-zig-bindgenはWinRT COM型のみを生成対象とし、Win32 APIの`Apis`クラスやunscoped enumは対象外。

---

### Room 8: Type System — `ty.rs` + `type_name.rs` + `type_category.rs` + `signature.rs` ~155行

**役割**: 型表現の中間表現（IR）。

**主要構造**:
```rust
enum Type { Void, Bool, I8, U8, ..., String, Object, Name(TypeName), Array(Box<Self>),
            Generic(String, u16), RefMut/RefConst/PtrMut/PtrConst/ArrayFixed }
struct TypeName { namespace: String, name: String, generics: Vec<Type> }
enum TypeCategory { Interface, Class, Enum, Struct, Delegate, Attribute }
struct Signature { flags: MethodCallAttributes, return_type: Type, types: Vec<Type> }
```

**win-zig-bindgenとの対応**:
- `TypeCategory` → `context.zig` の `TypeCategory`
- `Type` enum → 該当なし（sig_decodeは文字列ベースで直接emit）
- `Signature` → 該当なし

**必要度**: ☆☆☆ 不要。win-zig-bindgenはシグネチャを中間表現化せず、デコードしながら直接Zig文字列を生成する。この戦略は正当。

---

### Room 9: Attributes (フラグ定義) — `attributes.rs` ~120行

**役割**: TypeAttributes, MethodAttributes, FieldAttributes等のビットフラグ型。

**win-zig-bindgenとの対応**: `tables.zig` 内のフラグ定数
**必要度**: ★☆☆ 現行で十分。

---

### Room 10: Value (カスタム属性値) — `value.rs` ~45行

**役割**: カスタム属性のパラメータ値型。

**win-zig-bindgenとの対応**: 使用していない（GUID等はextractGuidで個別処理）
**必要度**: ☆☆☆ 不要。

---

## 必要なもの・不要なものの結論

### 必要 (★★★) — 再設計が必要

| Room | 理由 |
|------|------|
| Room 3: TypeIndex | **フラットHashMap→二段HashMap**。同名型のVec保持。NestedClass追跡 |

### 現行改善 (★★☆) — 現行設計で機能するが改善余地あり

| Room | 理由 |
|------|------|
| Room 2: Row | Zigではlifetimeがないのでバックポインタパターンは不可。Context引数渡しで代替。現行方式を維持 |
| Room 4: Blob | 同上。Context引数渡しで機能する |
| Room 5: Codes | Decoded{table, row}方式で機能する。indexなしでも呼び出し側が補う |

### 変更不要 (★☆☆ / ☆☆☆)

| Room | 理由 |
|------|------|
| Room 1: File | 既存PE/tables/streamsで十分 |
| Room 6: Tables | 既存tables.zigで十分 |
| Room 7: ItemIndex | WinRT COM専用のため不要 |
| Room 8: Type System | 直接emit方式を維持 |
| Room 9: Attributes | 既存で十分 |
| Room 10: Value | 不要 |

## アクションアイテム

**最優先**: `UnifiedIndex`のtype_mapを二段HashMap化する
1. `StringHashMap("ns.name", TypeLocation)` → `StringHashMap(namespace, NameMap)` where `NameMap = StringHashMap(name, ArrayList(TypeLocation))`
2. `findByFullName(ns, name)` → `Iterator(TypeLocation)` を返す（複数定義対応）
3. NestedClass追跡を追加
4. `findByShortName()` をnamespace省略検索に変更（全namespace走査）

**二次**: テスト修正
5. `tests/support/context.zig` をUnifiedContext対応に修正
6. `zig build gate --summary all` でparity test全通し
