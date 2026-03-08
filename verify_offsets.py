"""
Verify table offset calculations for WinMD files.
Replicates the logic in win-zig-metadata/tables.zig parse() function.
"""
import struct
import sys
from pathlib import Path

# Table IDs matching coded_index.zig
TABLE_NAMES = {
    0: "Module", 1: "TypeRef", 2: "TypeDef", 3: "FieldPtr", 4: "Field",
    5: "MethodPtr", 6: "MethodDef", 7: "ParamPtr", 8: "Param",
    9: "InterfaceImpl", 10: "MemberRef", 11: "Constant", 12: "CustomAttribute",
    13: "FieldMarshal", 14: "DeclSecurity", 15: "ClassLayout", 16: "FieldLayout",
    17: "StandAloneSig", 18: "EventMap", 19: "EventPtr", 20: "Event",
    21: "PropertyMap", 22: "PropertyPtr", 23: "Property", 24: "MethodSemantics",
    25: "MethodImpl", 26: "ModuleRef", 27: "TypeSpec", 28: "ImplMap",
    29: "FieldRVA", 30: "ENCLog", 31: "ENCMap", 32: "Assembly",
    33: "AssemblyProcessor", 34: "AssemblyOS", 35: "AssemblyRef",
    36: "AssemblyRefProcessor", 37: "AssemblyRefOS", 38: "File",
    39: "ExportedType", 40: "ManifestResource", 41: "NestedClass",
    42: "GenericParam", 43: "MethodSpec", 44: "GenericParamConstraint",
}

# Tables supported by rowSize() in tables.zig
SUPPORTED_TABLES = {
    0, 1, 2, 4, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20,
    21, 23, 24, 25, 26, 27, 28, 29, 32, 33, 34, 35, 36, 37, 38,
    39, 40, 41, 42, 43, 44
}


def find_metadata_stream(data):
    """Find the #~ stream in a PE/CLI assembly."""
    # Parse PE header
    if data[:2] != b'MZ':
        raise ValueError("Not a PE file")
    pe_offset = struct.unpack_from('<I', data, 0x3C)[0]
    if data[pe_offset:pe_offset+4] != b'PE\x00\x00':
        raise ValueError("Invalid PE signature")

    # COFF header
    coff_start = pe_offset + 4
    machine = struct.unpack_from('<H', data, coff_start)[0]
    num_sections = struct.unpack_from('<H', data, coff_start + 2)[0]
    size_of_optional = struct.unpack_from('<H', data, coff_start + 16)[0]
    optional_start = coff_start + 20

    # Optional header magic
    magic = struct.unpack_from('<H', data, optional_start)[0]
    if magic == 0x10b:  # PE32
        cli_rva_offset = optional_start + 208  # DataDirectory[14]
    elif magic == 0x20b:  # PE32+
        cli_rva_offset = optional_start + 224
    else:
        raise ValueError(f"Unknown optional header magic: {magic:#x}")

    cli_rva = struct.unpack_from('<I', data, cli_rva_offset)[0]
    cli_size = struct.unpack_from('<I', data, cli_rva_offset + 4)[0]

    # Parse section headers to resolve RVA -> file offset
    sections_start = optional_start + size_of_optional
    sections = []
    for i in range(num_sections):
        sec_off = sections_start + i * 40
        name = data[sec_off:sec_off+8].rstrip(b'\x00')
        vsize = struct.unpack_from('<I', data, sec_off + 8)[0]
        vrva = struct.unpack_from('<I', data, sec_off + 12)[0]
        raw_size = struct.unpack_from('<I', data, sec_off + 16)[0]
        raw_ptr = struct.unpack_from('<I', data, sec_off + 20)[0]
        sections.append((name, vrva, vsize, raw_ptr, raw_size))

    def rva_to_offset(rva):
        for name, vrva, vsize, raw_ptr, raw_size in sections:
            if vrva <= rva < vrva + raw_size:
                return rva - vrva + raw_ptr
        raise ValueError(f"Cannot resolve RVA {rva:#x}")

    # CLI header
    cli_off = rva_to_offset(cli_rva)
    metadata_rva = struct.unpack_from('<I', data, cli_off + 8)[0]
    metadata_size = struct.unpack_from('<I', data, cli_off + 12)[0]

    # Metadata root
    meta_off = rva_to_offset(metadata_rva)
    if data[meta_off:meta_off+4] != b'BSJB':
        raise ValueError("Invalid metadata signature")

    # Skip version string
    ver_len = struct.unpack_from('<I', data, meta_off + 12)[0]
    streams_offset = meta_off + 16 + ver_len
    # Align to 4 bytes (version string is already padded in the length)
    flags = struct.unpack_from('<H', data, streams_offset)[0]
    num_streams = struct.unpack_from('<H', data, streams_offset + 2)[0]
    pos = streams_offset + 4

    # Find #~ stream
    for _ in range(num_streams):
        s_offset = struct.unpack_from('<I', data, pos)[0]
        s_size = struct.unpack_from('<I', data, pos + 4)[0]
        pos += 8
        # Read null-terminated name, aligned to 4 bytes
        name_start = pos
        while data[pos] != 0:
            pos += 1
        name = data[name_start:pos].decode('ascii')
        pos += 1  # skip null
        # Align to 4
        pos = (pos + 3) & ~3

        if name == '#~':
            return data[meta_off + s_offset: meta_off + s_offset + s_size], meta_off + s_offset
        if name == '#-':
            return data[meta_off + s_offset: meta_off + s_offset + s_size], meta_off + s_offset

    raise ValueError("No #~ stream found")


def coded_index_size(row_counts, tag_bits, table_ids):
    """Replicate codedIndexSize from coded_index.zig"""
    max_small_rows = (1 << (16 - tag_bits)) - 1
    max_rows = max(row_counts[t] for t in table_ids)
    return 2 if max_rows <= max_small_rows else 4


def simple_size(row_counts, table_id):
    """Replicate simpleSize from tables.zig"""
    return 2 if row_counts[table_id] < 65536 else 4


def compute_row_size(table_id, row_counts, idx):
    """Replicate rowSize from tables.zig. Returns (size, formula_str)."""
    s = idx  # shorthand

    def ss(tid):
        return simple_size(row_counts, tid)

    formulas = {
        0:  lambda: (2 + s['string'] + s['guid'] * 3,
                     f"2 + {s['string']}(str) + {s['guid']}(guid)*3"),
        1:  lambda: (s['rs'] + s['string'] + s['string'],
                     f"{s['rs']}(rs) + {s['string']}(str) + {s['string']}(str)"),
        2:  lambda: (4 + s['string'] + s['string'] + s['tdor'] + ss(4) + ss(6),
                     f"4 + {s['string']}(str) + {s['string']}(str) + {s['tdor']}(tdor) + {ss(4)}(Field) + {ss(6)}(MethodDef)"),
        4:  lambda: (2 + s['string'] + s['blob'],
                     f"2 + {s['string']}(str) + {s['blob']}(blob)"),
        6:  lambda: (4 + 2 + 2 + s['string'] + s['blob'] + ss(8),
                     f"4 + 2 + 2 + {s['string']}(str) + {s['blob']}(blob) + {ss(8)}(Param)"),
        8:  lambda: (2 + 2 + s['string'],
                     f"2 + 2 + {s['string']}(str)"),
        9:  lambda: (ss(2) + s['tdor'],
                     f"{ss(2)}(TypeDef) + {s['tdor']}(tdor)"),
        10: lambda: (s['mrp'] + s['string'] + s['blob'],
                     f"{s['mrp']}(mrp) + {s['string']}(str) + {s['blob']}(blob)"),
        11: lambda: (2 + s['hc'] + s['blob'],
                     f"2 + {s['hc']}(hc) + {s['blob']}(blob)"),
        12: lambda: (s['hca'] + s['cat'] + s['blob'],
                     f"{s['hca']}(hca) + {s['cat']}(cat) + {s['blob']}(blob)"),
        13: lambda: (s['hfm'] + s['blob'],
                     f"{s['hfm']}(hfm) + {s['blob']}(blob)"),
        14: lambda: (2 + s['hds'] + s['blob'],
                     f"2 + {s['hds']}(hds) + {s['blob']}(blob)"),
        15: lambda: (2 + 4 + ss(2),
                     f"2 + 4 + {ss(2)}(TypeDef)"),
        16: lambda: (4 + ss(4),
                     f"4 + {ss(4)}(Field)"),
        17: lambda: (s['blob'],
                     f"{s['blob']}(blob)"),
        18: lambda: (ss(2) + ss(20),
                     f"{ss(2)}(TypeDef) + {ss(20)}(Event)"),
        20: lambda: (2 + s['string'] + s['tdor'],
                     f"2 + {s['string']}(str) + {s['tdor']}(tdor)"),
        21: lambda: (ss(2) + ss(23),
                     f"{ss(2)}(TypeDef) + {ss(23)}(Property)"),
        23: lambda: (2 + s['string'] + s['blob'],
                     f"2 + {s['string']}(str) + {s['blob']}(blob)"),
        24: lambda: (2 + ss(6) + s['hs'],
                     f"2 + {ss(6)}(MethodDef) + {s['hs']}(hs)"),
        25: lambda: (ss(2) + s['mdor'] + s['mdor'],
                     f"{ss(2)}(TypeDef) + {s['mdor']}(mdor) + {s['mdor']}(mdor)"),
        26: lambda: (s['string'],
                     f"{s['string']}(str)"),
        27: lambda: (s['blob'],
                     f"{s['blob']}(blob)"),
        28: lambda: (2 + s['mf'] + s['string'] + ss(26),
                     f"2 + {s['mf']}(mf) + {s['string']}(str) + {ss(26)}(ModuleRef)"),
        29: lambda: (4 + ss(4),
                     f"4 + {ss(4)}(Field)"),
        32: lambda: (4 + 2*4 + 4 + s['blob'] + s['string'] + s['string'],
                     f"4 + 2*4 + 4 + {s['blob']}(blob) + {s['string']}(str) + {s['string']}(str)"),
        33: lambda: (4, "4"),
        34: lambda: (4 + 4 + 4, "4 + 4 + 4"),
        35: lambda: (2*4 + 4 + s['blob'] + s['string'] + s['string'] + s['blob'],
                     f"2*4 + 4 + {s['blob']}(blob) + {s['string']}(str) + {s['string']}(str) + {s['blob']}(blob)"),
        36: lambda: (4 + ss(35),
                     f"4 + {ss(35)}(AssemblyRef)"),
        37: lambda: (4 + 4 + 4 + ss(35),
                     f"4 + 4 + 4 + {ss(35)}(AssemblyRef)"),
        38: lambda: (4 + s['string'] + s['blob'],
                     f"4 + {s['string']}(str) + {s['blob']}(blob)"),
        39: lambda: (4 + 4 + s['string'] + s['string'] + s['tdor'],
                     f"4 + 4 + {s['string']}(str) + {s['string']}(str) + {s['tdor']}(tdor)"),
        40: lambda: (4 + 4 + s['string'] + s['tdor'],
                     f"4 + 4 + {s['string']}(str) + {s['tdor']}(tdor)"),
        41: lambda: (ss(2) + ss(2),
                     f"{ss(2)}(TypeDef) + {ss(2)}(TypeDef)"),
        42: lambda: (2 + 2 + s['tomd'] + s['string'],
                     f"2 + 2 + {s['tomd']}(tomd) + {s['string']}(str)"),
        43: lambda: (s['mdor'] + s['blob'],
                     f"{s['mdor']}(mdor) + {s['blob']}(blob)"),
        44: lambda: (ss(42) + s['tdor'],
                     f"{ss(42)}(GenericParam) + {s['tdor']}(tdor)"),
    }

    if table_id not in formulas:
        return None, f"UNSUPPORTED (table {table_id} = {TABLE_NAMES.get(table_id, '?')})"

    size, formula = formulas[table_id]()
    return size, formula


def compute_index_sizes(row_counts, heap_sizes):
    """Replicate computeIndexSizes from tables.zig"""
    str_ix = 4 if (heap_sizes & 0x01) else 2
    guid_ix = 4 if (heap_sizes & 0x02) else 2
    blob_ix = 4 if (heap_sizes & 0x04) else 2

    return {
        'string': str_ix,
        'guid': guid_ix,
        'blob': blob_ix,
        'tdor': coded_index_size(row_counts, 2, [2, 1, 27]),  # TypeDef, TypeRef, TypeSpec
        'hc': coded_index_size(row_counts, 2, [4, 8, 23]),  # Field, Param, Property
        'hca': coded_index_size(row_counts, 5, [6, 4, 1, 2, 8, 9, 10, 0, 14, 23, 20, 17, 26, 27, 32, 35, 38, 39, 40, 42, 44, 43]),
        'cat': coded_index_size(row_counts, 3, [6, 10]),  # MethodDef, MemberRef
        'mrp': coded_index_size(row_counts, 3, [2, 1, 26, 6, 27]),  # TypeDef, TypeRef, ModuleRef, MethodDef, TypeSpec
        'hfm': coded_index_size(row_counts, 1, [4, 8]),  # Field, Param
        'hds': coded_index_size(row_counts, 2, [2, 6, 32]),  # TypeDef, MethodDef, Assembly
        'mf': coded_index_size(row_counts, 1, [4, 6]),  # Field, MethodDef
        'mdor': coded_index_size(row_counts, 1, [6, 10]),  # MethodDef, MemberRef
        'hs': coded_index_size(row_counts, 1, [20, 23]),  # Event, Property
        'rs': coded_index_size(row_counts, 2, [0, 26, 35, 1]),  # Module, ModuleRef, AssemblyRef, TypeRef
        'tomd': coded_index_size(row_counts, 1, [2, 6]),  # TypeDef, MethodDef
    }


def analyze_winmd(filepath):
    """Parse a WinMD file and compute table offsets."""
    print(f"\n{'='*80}")
    print(f"FILE: {filepath}")
    print(f"{'='*80}")

    data = Path(filepath).read_bytes()
    stream_data, stream_file_offset = find_metadata_stream(data)

    print(f"#~ stream file offset: {stream_file_offset:#x} ({stream_file_offset})")
    print(f"#~ stream size: {len(stream_data)} bytes")

    # Parse header (same as Zig code)
    cursor = 0
    cursor += 4  # reserved
    major = stream_data[cursor]; cursor += 1
    minor = stream_data[cursor]; cursor += 1
    heap_sizes = stream_data[cursor]; cursor += 1
    cursor += 1  # reserved

    valid = struct.unpack_from('<Q', stream_data, cursor)[0]; cursor += 8
    sorted_mask = struct.unpack_from('<Q', stream_data, cursor)[0]; cursor += 8

    print(f"Version: {major}.{minor}")
    print(f"HeapSizes: {heap_sizes:#04x} (strings={'4B' if heap_sizes & 1 else '2B'}, "
          f"guid={'4B' if heap_sizes & 2 else '2B'}, blob={'4B' if heap_sizes & 4 else '2B'})")
    print(f"Valid mask: {valid:#018x}")

    # Count present tables
    present_tables = []
    for i in range(64):
        if valid & (1 << i):
            present_tables.append(i)
    print(f"Present tables: {len(present_tables)}")

    # Read row counts
    row_counts = [0] * 64
    for i in range(64):
        if valid & (1 << i):
            row_counts[i] = struct.unpack_from('<I', stream_data, cursor)[0]
            cursor += 4

    print(f"\nRow counts header ends at cursor={cursor} (stream-relative)")

    # Compute index sizes
    idx = compute_index_sizes(row_counts, heap_sizes)
    print(f"\nIndex sizes:")
    for k, v in sorted(idx.items()):
        print(f"  {k}: {v}B")

    # Compute offsets
    data_off = cursor
    print(f"\nTable data starts at offset {data_off} (stream-relative)")
    print(f"Table data starts at offset {stream_file_offset + data_off} (file-relative)")

    results = []
    unsupported = []

    print(f"\n{'ID':>3} {'Table':<25} {'Rows':>8} {'RowSize':>8} {'Offset':>10} {'Bytes':>10} {'EndOff':>10}  Formula")
    print("-" * 110)

    for i in present_tables:
        name = TABLE_NAMES.get(i, f"Unknown({i})")
        row_size, formula = compute_row_size(i, row_counts, idx)

        if row_size is None:
            unsupported.append((i, name))
            print(f"{i:>3} {name:<25} {row_counts[i]:>8} {'???':>8} {data_off:>10} {'???':>10} {'???':>10}  {formula}")
            # We can't continue accumulating offsets correctly
            results.append({
                'id': i, 'name': name, 'rows': row_counts[i],
                'row_size': None, 'offset': data_off, 'bytes': None,
                'error': 'UnsupportedTable'
            })
            continue

        total_bytes = row_size * row_counts[i]
        end_off = data_off + total_bytes

        print(f"{i:>3} {name:<25} {row_counts[i]:>8} {row_size:>8} {data_off:>10} {total_bytes:>10} {end_off:>10}  {formula}")

        results.append({
            'id': i, 'name': name, 'rows': row_counts[i],
            'row_size': row_size, 'offset': data_off, 'bytes': total_bytes,
        })

        data_off += total_bytes

    print(f"\nFinal data_off: {data_off}")
    print(f"Stream size:    {len(stream_data)}")
    print(f"Remaining:      {len(stream_data) - data_off} bytes")

    if unsupported:
        print(f"\n*** UNSUPPORTED TABLES: {unsupported}")
        print("*** Zig rowSize() would return error.UnsupportedTable for these!")

    # Boundary check
    if data_off > len(stream_data):
        print(f"\n*** ERROR: Computed data extends {data_off - len(stream_data)} bytes beyond stream!")
    else:
        print(f"\nBoundary check: OK (data fits within stream)")

    return results, row_counts, idx, present_tables, unsupported, heap_sizes


def main():
    winmd_xaml = r"C:\Users\yuuji\.nuget\packages\microsoft.windowsappsdk\1.6.250108002\lib\uap10.0\Microsoft.UI.Xaml.winmd"
    winmd_uac = r"C:\Program Files (x86)\Windows Kits\10\References\10.0.26100.0\Windows.Foundation.UniversalApiContract\19.0.0.0\Windows.Foundation.UniversalApiContract.winmd"

    results_xaml, rc_xaml, idx_xaml, pt_xaml, unsup_xaml, hs_xaml = analyze_winmd(winmd_xaml)
    results_uac, rc_uac, idx_uac, pt_uac, unsup_uac, hs_uac = analyze_winmd(winmd_uac)

    # Comparison
    print(f"\n\n{'='*80}")
    print("COMPARISON & ANALYSIS")
    print(f"{'='*80}")

    print(f"\nXaml: {len(pt_xaml)} tables, heap_sizes={hs_xaml:#04x}")
    print(f"UAC:  {len(pt_uac)} tables, heap_sizes={hs_uac:#04x}")

    # Check which tables are unique to UAC
    uac_only = set(pt_uac) - set(pt_xaml)
    xaml_only = set(pt_xaml) - set(pt_uac)
    if uac_only:
        print(f"\nTables in UAC only: {[(i, TABLE_NAMES.get(i, '?')) for i in sorted(uac_only)]}")
    if xaml_only:
        print(f"Tables in Xaml only: {[(i, TABLE_NAMES.get(i, '?')) for i in sorted(xaml_only)]}")

    # Check for unsupported tables
    if unsup_uac:
        print(f"\n*** CRITICAL: UAC has unsupported tables: {unsup_uac}")
        print("*** This means tables.zig parse() will return error.UnsupportedTable!")
    else:
        print(f"\nNo unsupported tables found in either file.")

    # Compare index sizes
    print(f"\nIndex size comparison:")
    print(f"{'Index':<10} {'Xaml':>6} {'UAC':>6} {'Match':>6}")
    for k in sorted(idx_xaml.keys()):
        match = "OK" if idx_xaml[k] == idx_uac[k] else "DIFF"
        print(f"{k:<10} {idx_xaml[k]:>5}B {idx_uac[k]:>5}B {match:>6}")

    # Compare row sizes for common tables
    print(f"\nRow size comparison (common tables):")
    common = set(pt_xaml) & set(pt_uac)
    xaml_by_id = {r['id']: r for r in results_xaml}
    uac_by_id = {r['id']: r for r in results_uac}
    for i in sorted(common):
        rx = xaml_by_id.get(i)
        ru = uac_by_id.get(i)
        if rx and ru and rx['row_size'] and ru['row_size']:
            match = "OK" if rx['row_size'] == ru['row_size'] else "DIFF"
            print(f"  {TABLE_NAMES[i]:<25} Xaml={rx['row_size']:>3}B  UAC={ru['row_size']:>3}B  {match}")

    # Check for tables > 65535 rows causing simple_size changes
    print(f"\nTables with >65535 rows (causes simple_size=4):")
    for i in pt_uac:
        if rc_uac[i] > 65535:
            print(f"  {TABLE_NAMES.get(i, '?')} (id={i}): {rc_uac[i]} rows")

    # Check coded index thresholds
    print(f"\nCoded index threshold analysis for UAC:")
    coded_indices = {
        'tdor': (2, [2, 1, 27]),
        'hc': (2, [4, 8, 23]),
        'hca': (5, [6, 4, 1, 2, 8, 9, 10, 0, 14, 23, 20, 17, 26, 27, 32, 35, 38, 39, 40, 42, 44, 43]),
        'cat': (3, [6, 10]),
        'mrp': (3, [2, 1, 26, 6, 27]),
        'hfm': (1, [4, 8]),
        'hds': (2, [2, 6, 32]),
        'mf': (1, [4, 6]),
        'mdor': (1, [6, 10]),
        'hs': (1, [20, 23]),
        'rs': (2, [0, 26, 35, 1]),
        'tomd': (1, [2, 6]),
    }
    for name, (tag_bits, tables) in coded_indices.items():
        threshold = (1 << (16 - tag_bits)) - 1
        max_rows = max(rc_uac[t] for t in tables)
        fits = max_rows <= threshold
        size = 2 if fits else 4
        print(f"  {name:<6}: tag_bits={tag_bits}, threshold={threshold:>6}, max_rows={max_rows:>6} -> {size}B {'(WIDE)' if not fits else ''}")


if __name__ == '__main__':
    main()
