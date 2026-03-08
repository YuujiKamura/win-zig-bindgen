"""Analyze .winmd files: extract valid_mask, list present table IDs,
and cross-check against rowSize switch coverage in tables.zig."""

import struct
import sys

def parse_winmd_tables(path):
    with open(path, 'rb') as f:
        data = f.read()

    e_lfanew = struct.unpack_from('<I', data, 0x3C)[0]
    pe_sig = data[e_lfanew:e_lfanew+4]
    assert pe_sig == b'PE\x00\x00', f"Not a PE file: {pe_sig}"

    coff_start = e_lfanew + 4
    num_sections = struct.unpack_from('<H', data, coff_start + 2)[0]
    optional_hdr_size = struct.unpack_from('<H', data, coff_start + 16)[0]
    optional_start = coff_start + 20

    magic = struct.unpack_from('<H', data, optional_start)[0]
    if magic == 0x10b:
        cli_rva_offset = optional_start + 208
    elif magic == 0x20b:
        cli_rva_offset = optional_start + 224
    else:
        raise ValueError(f"Unknown PE magic: {hex(magic)}")

    cli_rva = struct.unpack_from('<I', data, cli_rva_offset)[0]

    sections_start = optional_start + optional_hdr_size
    sections = []
    for i in range(num_sections):
        off = sections_start + i * 40
        name = data[off:off+8].rstrip(b'\x00').decode('ascii', errors='replace')
        vsize = struct.unpack_from('<I', data, off + 8)[0]
        va = struct.unpack_from('<I', data, off + 12)[0]
        raw_size = struct.unpack_from('<I', data, off + 16)[0]
        raw_ptr = struct.unpack_from('<I', data, off + 20)[0]
        sections.append((name, va, vsize, raw_ptr, raw_size))

    def rva_to_offset(rva):
        for name, va, vsize, raw_ptr, raw_size in sections:
            if va <= rva < va + max(vsize, raw_size):
                return rva - va + raw_ptr
        raise ValueError(f"Cannot resolve RVA {hex(rva)}")

    cli_off = rva_to_offset(cli_rva)
    metadata_rva = struct.unpack_from('<I', data, cli_off + 8)[0]
    metadata_off = rva_to_offset(metadata_rva)

    assert data[metadata_off:metadata_off+4] == b'BSJB', "No BSJB signature"
    version_len = struct.unpack_from('<I', data, metadata_off + 12)[0]
    version_len_aligned = (version_len + 3) & ~3
    streams_offset = metadata_off + 16 + version_len_aligned
    num_streams = struct.unpack_from('<H', data, streams_offset + 2)[0]

    cursor = streams_offset + 4
    tilde_offset = None
    for _ in range(num_streams):
        s_offset = struct.unpack_from('<I', data, cursor)[0]
        s_size = struct.unpack_from('<I', data, cursor + 4)[0]
        cursor += 8
        name_start = cursor
        while data[cursor] != 0:
            cursor += 1
        name = data[name_start:cursor].decode('ascii')
        cursor += 1
        cursor = (cursor + 3) & ~3
        if name in ('#~', '#-'):
            tilde_offset = metadata_off + s_offset
            break

    assert tilde_offset is not None, "No #~ stream found"

    heap_sizes = data[tilde_offset + 6]
    valid_mask = struct.unpack_from('<Q', data, tilde_offset + 8)[0]

    present_ids = []
    for i in range(64):
        if valid_mask & (1 << i):
            present_ids.append(i)

    # Also read row counts
    rc_cursor = tilde_offset + 24
    row_counts = {}
    for tid in present_ids:
        row_counts[tid] = struct.unpack_from('<I', data, rc_cursor)[0]
        rc_cursor += 4

    return valid_mask, present_ids, heap_sizes, row_counts


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

ROWSIZE_HANDLED = {
    0, 1, 2, 4, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 23,
    24, 25, 26, 27, 28, 29, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44
}

TABLEID_ENUM = set(range(45))

files = {
    "UniversalApiContract": r"C:\Program Files (x86)\Windows Kits\10\References\10.0.26100.0\Windows.Foundation.UniversalApiContract\19.0.0.0\Windows.Foundation.UniversalApiContract.winmd",
    "Microsoft.UI.Xaml": r"C:\Users\yuuji\.nuget\packages\microsoft.windowsappsdk\1.6.250108002\lib\uap10.0\Microsoft.UI.Xaml.winmd",
}

print("=" * 70)
print("rowSize switch coverage analysis")
print("=" * 70)

print(f"\n## rowSize handled IDs ({len(ROWSIZE_HANDLED)} total):")
for tid in sorted(ROWSIZE_HANDLED):
    print(f"  {tid:2d} = {TABLE_NAMES.get(tid, '???')}")

print(f"\n## NOT handled by rowSize (=> UnsupportedTable):")
not_handled = TABLEID_ENUM - ROWSIZE_HANDLED
for tid in sorted(not_handled):
    print(f"  {tid:2d} = {TABLE_NAMES.get(tid, '???')}")

results = {}
for label, path in files.items():
    print(f"\n{'=' * 70}")
    print(f"## {label}")
    print(f"   {path}")
    print(f"{'=' * 70}")
    try:
        valid_mask, present_ids, heap_sizes, row_counts = parse_winmd_tables(path)
        print(f"   valid_mask = 0x{valid_mask:016X}")
        print(f"   heap_sizes = 0x{heap_sizes:02X}")
        print(f"   Present tables ({len(present_ids)}):")
        for tid in present_ids:
            handled = "OK" if tid in ROWSIZE_HANDLED else "MISSING!"
            in_enum = "enum-ok" if tid in TABLEID_ENUM else "NOT-IN-ENUM!"
            rows = row_counts.get(tid, 0)
            print(f"     {tid:2d} = {TABLE_NAMES.get(tid, '???'):25s} rows={rows:6d} [{handled}] [{in_enum}]")

        gaps = [tid for tid in present_ids if tid not in ROWSIZE_HANDLED]
        enum_gaps = [tid for tid in present_ids if tid not in TABLEID_ENUM]

        if gaps:
            print(f"\n   *** COVERAGE GAP: {len(gaps)} table(s) present but NOT handled by rowSize:")
            for tid in gaps:
                print(f"       {tid} = {TABLE_NAMES.get(tid, '???')}")
        else:
            print(f"\n   No coverage gap: all present tables are handled by rowSize.")

        if enum_gaps:
            print(f"\n   *** ENUM GAP: {len(enum_gaps)} table(s) present but NOT in TableId enum:")
            for tid in enum_gaps:
                print(f"       {tid}")

        results[label] = {
            'valid_mask': valid_mask,
            'present': present_ids,
            'gaps': gaps,
            'enum_gaps': enum_gaps,
            'heap_sizes': heap_sizes,
            'row_counts': row_counts,
        }
    except Exception as e:
        print(f"   ERROR: {e}")
        import traceback
        traceback.print_exc()
        results[label] = {'error': str(e)}

print(f"\n{'=' * 70}")
print("## CONCLUSION")
print(f"{'=' * 70}")
all_pass = True
for label, r in results.items():
    if 'error' in r:
        print(f"  {label}: PARSE ERROR - {r['error']}")
        all_pass = False
    elif r['gaps']:
        print(f"  {label}: FAIL - {len(r['gaps'])} unhandled table(s): {r['gaps']}")
        all_pass = False
    else:
        print(f"  {label}: PASS - all {len(r['present'])} present tables covered by rowSize")

if all_pass:
    print("\n  => rowSize coverage is NOT the cause of the InvalidIndex error.")
    print("     The root cause lies elsewhere (coded index sizes, heap parsing, etc.)")
else:
    print("\n  => rowSize coverage gap found! This is likely the cause of the error.")
    print("     Add missing table row size definitions to tables.zig rowSize().")
