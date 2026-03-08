"""
MethodDef table binary decoder for WinMD files.
Parses PE -> CLI header -> metadata root -> streams -> MethodDef table rows.
"""
import struct
import sys
import os

def read_u16(data, off):
    return struct.unpack_from('<H', data, off)[0]

def read_u32(data, off):
    return struct.unpack_from('<I', data, off)[0]

def read_u64(data, off):
    return struct.unpack_from('<Q', data, off)[0]

def get_string(strings_heap, index):
    """Read null-terminated string from strings heap."""
    if index == 0:
        return ""
    if index >= len(strings_heap):
        return f"<INVALID: {index} >= {len(strings_heap)}>"
    end = strings_heap.index(b'\x00', index)
    return strings_heap[index:end].decode('utf-8', errors='replace')

def parse_winmd(filepath):
    """Parse a WinMD file and return MethodDef table decode results."""
    with open(filepath, 'rb') as f:
        data = f.read()

    result = {}
    result['file'] = os.path.basename(filepath)
    result['file_size'] = len(data)

    # --- PE Header ---
    if data[:2] != b'MZ':
        return {'error': 'Not a PE file'}

    pe_offset = read_u32(data, 0x3C)
    if data[pe_offset:pe_offset+4] != b'PE\x00\x00':
        return {'error': 'Invalid PE signature'}

    coff_offset = pe_offset + 4
    num_sections = read_u16(data, coff_offset + 2)
    optional_hdr_size = read_u16(data, coff_offset + 16)
    optional_offset = coff_offset + 20

    # PE32 or PE32+?
    magic = read_u16(data, optional_offset)
    if magic == 0x10b:  # PE32
        cli_dir_offset = optional_offset + 208  # DataDirectory[14]
    elif magic == 0x20b:  # PE32+
        cli_dir_offset = optional_offset + 224  # DataDirectory[14]
    else:
        return {'error': f'Unknown PE magic: {magic:#x}'}

    cli_rva = read_u32(data, cli_dir_offset)
    cli_size = read_u32(data, cli_dir_offset + 4)
    result['cli_header_rva'] = f"0x{cli_rva:x}"

    # --- Section table ---
    section_table_offset = optional_offset + optional_hdr_size
    sections = []
    for i in range(num_sections):
        sec_off = section_table_offset + i * 40
        name = data[sec_off:sec_off+8].rstrip(b'\x00').decode('ascii', errors='replace')
        virtual_size = read_u32(data, sec_off + 8)
        virtual_addr = read_u32(data, sec_off + 12)
        raw_size = read_u32(data, sec_off + 16)
        raw_offset = read_u32(data, sec_off + 20)
        sections.append({
            'name': name, 'va': virtual_addr, 'vs': virtual_size,
            'raw_off': raw_offset, 'raw_size': raw_size
        })

    def rva_to_offset(rva):
        for sec in sections:
            if sec['va'] <= rva < sec['va'] + sec['raw_size']:
                return rva - sec['va'] + sec['raw_off']
        return None

    # --- CLI Header ---
    cli_file_offset = rva_to_offset(cli_rva)
    metadata_rva = read_u32(data, cli_file_offset + 8)
    metadata_size = read_u32(data, cli_file_offset + 12)
    metadata_offset = rva_to_offset(metadata_rva)
    result['metadata_offset'] = f"0x{metadata_offset:x}"
    result['metadata_size'] = metadata_size

    # --- Metadata Root ---
    md = metadata_offset
    if data[md:md+4] != b'BSJB':
        return {'error': 'Invalid metadata signature'}

    version_len = read_u32(data, md + 12)
    version_str = data[md+16:md+16+version_len].rstrip(b'\x00').decode('ascii', errors='replace')
    result['version'] = version_str

    # Stream headers
    flags = read_u16(data, md + 16 + version_len)
    num_streams = read_u16(data, md + 16 + version_len + 2)
    result['num_streams'] = num_streams

    stream_cursor = md + 16 + version_len + 4
    streams = {}
    for _ in range(num_streams):
        s_offset = read_u32(data, stream_cursor)
        s_size = read_u32(data, stream_cursor + 4)
        stream_cursor += 8
        # Read name (null-terminated, padded to 4 bytes)
        name_start = stream_cursor
        while data[stream_cursor] != 0:
            stream_cursor += 1
        s_name = data[name_start:stream_cursor].decode('ascii')
        stream_cursor += 1  # skip null
        # Align to 4 bytes
        stream_cursor = (stream_cursor + 3) & ~3

        streams[s_name] = {
            'offset': md + s_offset,  # absolute file offset
            'size': s_size,
            'rel_offset': s_offset
        }

    result['streams'] = {k: {'offset': f"0x{v['offset']:x}", 'size': v['size']} for k, v in streams.items()}

    # --- Strings Heap ---
    strings_info = streams.get('#Strings')
    if not strings_info:
        return {**result, 'error': 'No #Strings stream'}
    strings_heap = data[strings_info['offset']:strings_info['offset']+strings_info['size']]
    result['strings_heap_size'] = len(strings_heap)

    # --- #~ (Tables) Stream ---
    tables_stream_name = '#~' if '#~' in streams else '#-'
    tables_info = streams[tables_stream_name]
    ts_offset = tables_info['offset']
    ts_data = data[ts_offset:ts_offset + tables_info['size']]
    result['tables_stream_size'] = len(ts_data)

    # Parse tables stream header
    heap_sizes = ts_data[6]
    valid_mask = read_u64(ts_data, 8)
    sorted_mask = read_u64(ts_data, 16)
    result['heap_sizes'] = f"0x{heap_sizes:02x}"
    result['valid_mask'] = f"0x{valid_mask:016x}"

    str_ix = 4 if (heap_sizes & 0x01) else 2
    guid_ix = 4 if (heap_sizes & 0x02) else 2
    blob_ix = 4 if (heap_sizes & 0x04) else 2
    result['index_sizes'] = {'string': str_ix, 'guid': guid_ix, 'blob': blob_ix}

    # Read row counts
    cursor = 24
    row_counts = {}
    table_ids_present = []
    for i in range(64):
        if valid_mask & (1 << i):
            row_counts[i] = read_u32(ts_data, cursor)
            table_ids_present.append(i)
            cursor += 4
        else:
            row_counts[i] = 0

    # Table names for display
    TABLE_NAMES = {
        0x00: 'Module', 0x01: 'TypeRef', 0x02: 'TypeDef', 0x04: 'Field',
        0x06: 'MethodDef', 0x08: 'Param', 0x09: 'InterfaceImpl',
        0x0A: 'MemberRef', 0x0B: 'Constant', 0x0C: 'CustomAttribute',
        0x0D: 'FieldMarshal', 0x0E: 'DeclSecurity', 0x0F: 'ClassLayout',
        0x10: 'FieldLayout', 0x11: 'StandAloneSig', 0x12: 'EventMap',
        0x14: 'Event', 0x15: 'PropertyMap', 0x17: 'Property',
        0x18: 'MethodSemantics', 0x19: 'MethodImpl', 0x1A: 'ModuleRef',
        0x1B: 'TypeSpec', 0x1C: 'ImplMap', 0x1D: 'FieldRVA',
        0x20: 'Assembly', 0x21: 'AssemblyProcessor', 0x22: 'AssemblyOS',
        0x23: 'AssemblyRef', 0x24: 'AssemblyRefProcessor', 0x25: 'AssemblyRefOS',
        0x26: 'File', 0x27: 'ExportedType', 0x28: 'ManifestResource',
        0x29: 'NestedClass', 0x2A: 'GenericParam', 0x2B: 'MethodSpec',
        0x2C: 'GenericParamConstraint',
    }

    result['key_row_counts'] = {}
    for tid in [0x02, 0x04, 0x06, 0x08, 0x09, 0x0A, 0x0C, 0x2A]:
        if tid in row_counts and row_counts[tid] > 0:
            result['key_row_counts'][TABLE_NAMES.get(tid, f'0x{tid:02x}')] = row_counts[tid]

    # --- Compute coded index sizes ---
    def coded_size(tag_bits, table_list):
        max_rows = max(row_counts.get(t, 0) for t in table_list)
        if max_rows < (1 << (16 - tag_bits)):
            return 2
        return 4

    def simple_size(table_id):
        return 2 if row_counts.get(table_id, 0) < 65536 else 4

    # Coded index sizes
    tdor = coded_size(2, [0x02, 0x01, 0x1B])  # TypeDefOrRef
    hc = coded_size(2, [0x04, 0x08, 0x17])     # HasConstant
    hca = coded_size(5, [0x06, 0x04, 0x01, 0x02, 0x08, 0x09, 0x0A, 0x00, 0x0E, 0x17, 0x14, 0x11, 0x1A, 0x1B, 0x20, 0x23, 0x26, 0x27, 0x28, 0x2A, 0x2C, 0x2B])  # HasCustomAttribute
    cat = coded_size(3, [0x06, 0x0A])           # CustomAttributeType
    mrp = coded_size(3, [0x02, 0x01, 0x1A, 0x06, 0x1B])  # MemberRefParent
    hfm = coded_size(1, [0x04, 0x08])           # HasFieldMarshal
    hds = coded_size(2, [0x02, 0x06, 0x20])     # HasDeclSecurity
    mf = coded_size(1, [0x04, 0x06])            # MemberForwarded
    mdor = coded_size(1, [0x06, 0x0A])          # MethodDefOrRef
    hs = coded_size(1, [0x14, 0x17])            # HasSemantics
    rs = coded_size(2, [0x00, 0x1A, 0x23, 0x01]) # ResolutionScope
    tomd = coded_size(1, [0x02, 0x06])          # TypeOrMethodDef

    # --- Compute row sizes for all present tables ---
    def compute_row_size(tid):
        if tid == 0x00:  # Module
            return 2 + str_ix + guid_ix * 3
        elif tid == 0x01:  # TypeRef
            return rs + str_ix + str_ix
        elif tid == 0x02:  # TypeDef
            return 4 + str_ix + str_ix + tdor + simple_size(0x04) + simple_size(0x06)
        elif tid == 0x04:  # Field
            return 2 + str_ix + blob_ix
        elif tid == 0x06:  # MethodDef
            return 4 + 2 + 2 + str_ix + blob_ix + simple_size(0x08)
        elif tid == 0x08:  # Param
            return 2 + 2 + str_ix
        elif tid == 0x09:  # InterfaceImpl
            return simple_size(0x02) + tdor
        elif tid == 0x0A:  # MemberRef
            return mrp + str_ix + blob_ix
        elif tid == 0x0B:  # Constant
            return 2 + hc + blob_ix
        elif tid == 0x0C:  # CustomAttribute
            return hca + cat + blob_ix
        elif tid == 0x0D:  # FieldMarshal
            return hfm + blob_ix
        elif tid == 0x0E:  # DeclSecurity
            return 2 + hds + blob_ix
        elif tid == 0x0F:  # ClassLayout
            return 2 + 4 + simple_size(0x02)
        elif tid == 0x10:  # FieldLayout
            return 4 + simple_size(0x04)
        elif tid == 0x11:  # StandAloneSig
            return blob_ix
        elif tid == 0x12:  # EventMap
            return simple_size(0x02) + simple_size(0x14)
        elif tid == 0x14:  # Event
            return 2 + str_ix + tdor
        elif tid == 0x15:  # PropertyMap
            return simple_size(0x02) + simple_size(0x17)
        elif tid == 0x17:  # Property
            return 2 + str_ix + blob_ix
        elif tid == 0x18:  # MethodSemantics
            return 2 + simple_size(0x06) + hs
        elif tid == 0x19:  # MethodImpl
            return simple_size(0x02) + mdor + mdor
        elif tid == 0x1A:  # ModuleRef
            return str_ix
        elif tid == 0x1B:  # TypeSpec
            return blob_ix
        elif tid == 0x1C:  # ImplMap
            return 2 + mf + str_ix + simple_size(0x1A)
        elif tid == 0x1D:  # FieldRVA
            return 4 + simple_size(0x04)
        elif tid == 0x20:  # Assembly
            return 4 + 2*4 + 4 + blob_ix + str_ix + str_ix
        elif tid == 0x21:  # AssemblyProcessor
            return 4
        elif tid == 0x22:  # AssemblyOS
            return 4 + 4 + 4
        elif tid == 0x23:  # AssemblyRef
            return 2*4 + 4 + blob_ix + str_ix + str_ix + blob_ix
        elif tid == 0x24:  # AssemblyRefProcessor
            return 4 + simple_size(0x23)
        elif tid == 0x25:  # AssemblyRefOS
            return 4 + 4 + 4 + simple_size(0x23)
        elif tid == 0x26:  # File
            return 4 + str_ix + blob_ix
        elif tid == 0x27:  # ExportedType
            return 4 + 4 + str_ix + str_ix + tdor
        elif tid == 0x28:  # ManifestResource
            return 4 + 4 + str_ix + tdor
        elif tid == 0x29:  # NestedClass
            return simple_size(0x02) + simple_size(0x02)
        elif tid == 0x2A:  # GenericParam
            return 2 + 2 + tomd + str_ix
        elif tid == 0x2B:  # MethodSpec
            return mdor + blob_ix
        elif tid == 0x2C:  # GenericParamConstraint
            return simple_size(0x2A) + tdor
        else:
            return None

    # Compute table offsets within the tables stream
    table_offsets = {}  # tid -> offset within ts_data
    data_cursor = cursor  # cursor is already past the row counts
    for tid in sorted(table_ids_present):
        rs_val = compute_row_size(tid)
        if rs_val is None:
            result['error'] = f'Unknown table 0x{tid:02x}'
            return result
        table_offsets[tid] = data_cursor
        data_cursor += rs_val * row_counts[tid]

    # --- MethodDef table ---
    methoddef_tid = 0x06
    methoddef_row_size = compute_row_size(methoddef_tid)
    methoddef_offset = table_offsets.get(methoddef_tid)
    methoddef_count = row_counts.get(methoddef_tid, 0)

    result['methoddef'] = {
        'row_size': methoddef_row_size,
        'row_count': methoddef_count,
        'offset_in_tables_stream': f"0x{methoddef_offset:x}" if methoddef_offset else None,
        'param_index_size': simple_size(0x08),
    }

    # Decode first 10 rows
    decoded_rows = []
    num_to_decode = min(10, methoddef_count)
    for i in range(num_to_decode):
        row_off = methoddef_offset + i * methoddef_row_size
        pos = row_off

        rva = read_u32(ts_data, pos); pos += 4
        impl_flags = read_u16(ts_data, pos); pos += 2
        flags = read_u16(ts_data, pos); pos += 2

        if str_ix == 4:
            name_idx = read_u32(ts_data, pos)
        else:
            name_idx = read_u16(ts_data, pos)
        pos += str_ix

        if blob_ix == 4:
            sig_idx = read_u32(ts_data, pos)
        else:
            sig_idx = read_u16(ts_data, pos)
        pos += blob_ix

        param_sz = simple_size(0x08)
        if param_sz == 4:
            param_list = read_u32(ts_data, pos)
        else:
            param_list = read_u16(ts_data, pos)
        pos += param_sz

        in_range = name_idx < len(strings_heap)
        name_str = get_string(strings_heap, name_idx) if in_range else f"<OUT_OF_RANGE: 0x{name_idx:x}>"

        decoded_rows.append({
            'row': i + 1,
            'offset': f"0x{row_off:x}",
            'rva': f"0x{rva:08x}",
            'impl_flags': f"0x{impl_flags:04x}",
            'flags': f"0x{flags:04x}",
            'name_idx': f"0x{name_idx:x}",
            'name_idx_dec': name_idx,
            'signature': f"0x{sig_idx:x}",
            'param_list': param_list,
            'name_in_range': in_range,
            'name_str': name_str,
        })

    result['first_10_rows'] = decoded_rows

    # --- Check for any out-of-range name values in ALL rows ---
    out_of_range_count = 0
    first_bad_row = None
    for i in range(methoddef_count):
        row_off = methoddef_offset + i * methoddef_row_size
        pos = row_off + 8  # skip rva(4) + impl_flags(2) + flags(2)
        if str_ix == 4:
            name_idx = read_u32(ts_data, pos)
        else:
            name_idx = read_u16(ts_data, pos)
        if name_idx >= len(strings_heap):
            out_of_range_count += 1
            if first_bad_row is None:
                first_bad_row = {
                    'row': i + 1,
                    'name_idx': f"0x{name_idx:x}",
                    'name_idx_dec': name_idx,
                    'strings_heap_size': len(strings_heap),
                }

    result['out_of_range_names'] = {
        'count': out_of_range_count,
        'total_rows': methoddef_count,
        'first_bad': first_bad_row,
    }

    # --- TypeDef table: find IPointerPoint ---
    typedef_tid = 0x02
    typedef_row_size = compute_row_size(typedef_tid)
    typedef_offset = table_offsets.get(typedef_tid)
    typedef_count = row_counts.get(typedef_tid, 0)

    ipointerpoint_info = None
    if typedef_offset is not None:
        for i in range(typedef_count):
            row_off = typedef_offset + i * typedef_row_size
            pos = row_off
            td_flags = read_u32(ts_data, pos); pos += 4
            if str_ix == 4:
                td_name_idx = read_u32(ts_data, pos)
            else:
                td_name_idx = read_u16(ts_data, pos)
            pos += str_ix

            if td_name_idx < len(strings_heap):
                td_name = get_string(strings_heap, td_name_idx)
                if td_name == 'IPointerPoint':
                    # Read rest of TypeDef row
                    if str_ix == 4:
                        td_ns_idx = read_u32(ts_data, pos)
                    else:
                        td_ns_idx = read_u16(ts_data, pos)
                    pos += str_ix
                    td_ns = get_string(strings_heap, td_ns_idx) if td_ns_idx < len(strings_heap) else "?"

                    # extends (coded index)
                    if tdor == 4:
                        extends = read_u32(ts_data, pos)
                    else:
                        extends = read_u16(ts_data, pos)
                    pos += tdor

                    # field_list
                    fs = simple_size(0x04)
                    if fs == 4:
                        field_list = read_u32(ts_data, pos)
                    else:
                        field_list = read_u16(ts_data, pos)
                    pos += fs

                    # method_list
                    ms = simple_size(0x06)
                    if ms == 4:
                        method_list = read_u32(ts_data, pos)
                    else:
                        method_list = read_u16(ts_data, pos)

                    # Next TypeDef's method_list for range
                    next_method_list = methoddef_count + 1
                    if i + 1 < typedef_count:
                        next_row_off = typedef_offset + (i + 1) * typedef_row_size
                        npos = next_row_off + 4 + str_ix + str_ix + tdor + simple_size(0x04)
                        if ms == 4:
                            next_method_list = read_u32(ts_data, npos)
                        else:
                            next_method_list = read_u16(ts_data, npos)

                    ipointerpoint_info = {
                        'typedef_row': i + 1,
                        'name': td_name,
                        'namespace': td_ns,
                        'method_list_start': method_list,
                        'method_list_end': next_method_list,
                        'method_count': next_method_list - method_list,
                    }

                    # Decode IPointerPoint's methods
                    ipp_methods = []
                    for mi in range(method_list, min(next_method_list, method_list + 20)):
                        if mi < 1 or mi > methoddef_count:
                            ipp_methods.append({'row': mi, 'error': 'out of range'})
                            continue
                        mrow_off = methoddef_offset + (mi - 1) * methoddef_row_size
                        mpos = mrow_off
                        m_rva = read_u32(ts_data, mpos); mpos += 4
                        m_impl = read_u16(ts_data, mpos); mpos += 2
                        m_flags = read_u16(ts_data, mpos); mpos += 2
                        if str_ix == 4:
                            m_name_idx = read_u32(ts_data, mpos)
                        else:
                            m_name_idx = read_u16(ts_data, mpos)
                        mpos += str_ix
                        if blob_ix == 4:
                            m_sig = read_u32(ts_data, mpos)
                        else:
                            m_sig = read_u16(ts_data, mpos)
                        mpos += blob_ix
                        psz = simple_size(0x08)
                        if psz == 4:
                            m_param = read_u32(ts_data, mpos)
                        else:
                            m_param = read_u16(ts_data, mpos)

                        m_in_range = m_name_idx < len(strings_heap)
                        m_name = get_string(strings_heap, m_name_idx) if m_in_range else f"<OUT: 0x{m_name_idx:x}>"

                        ipp_methods.append({
                            'row': mi,
                            'rva': f"0x{m_rva:08x}",
                            'flags': f"0x{m_flags:04x}",
                            'name_idx': f"0x{m_name_idx:x}",
                            'name_in_range': m_in_range,
                            'name': m_name,
                            'sig': f"0x{m_sig:x}",
                            'param_list': m_param,
                        })

                    ipointerpoint_info['methods'] = ipp_methods
                    break

    result['ipointerpoint'] = ipointerpoint_info

    return result

def format_result(r):
    """Format parse result as readable text."""
    lines = []
    lines.append(f"## {r.get('file', '?')}")
    lines.append(f"- File size: {r.get('file_size', 0):,} bytes")
    lines.append(f"- Metadata offset: {r.get('metadata_offset', '?')}")
    lines.append(f"- heap_sizes: {r.get('heap_sizes', '?')}")
    lines.append(f"- Index sizes: {r.get('index_sizes', {})}")

    if 'streams' in r:
        lines.append(f"- Streams:")
        for name, info in r['streams'].items():
            lines.append(f"  - {name}: offset={info['offset']}, size={info['size']:,}")

    if 'key_row_counts' in r:
        lines.append(f"- Key row counts:")
        for name, cnt in r['key_row_counts'].items():
            lines.append(f"  - {name}: {cnt:,}")

    md = r.get('methoddef', {})
    if md:
        lines.append(f"\n### MethodDef Table")
        lines.append(f"- Row size: {md.get('row_size')} bytes")
        lines.append(f"- Row count: {md.get('row_count'):,}")
        lines.append(f"- Offset in tables stream: {md.get('offset_in_tables_stream')}")
        lines.append(f"- Param index size: {md.get('param_index_size')}")

    rows = r.get('first_10_rows', [])
    if rows:
        lines.append(f"\n### First 10 MethodDef Rows")
        lines.append(f"| Row | Offset | RVA | Flags | Name Idx | In Range | Name | Signature | ParamList |")
        lines.append(f"|-----|--------|-----|-------|----------|----------|------|-----------|-----------|")
        for row in rows:
            lines.append(f"| {row['row']} | {row['offset']} | {row['rva']} | {row['flags']} | {row['name_idx']} ({row['name_idx_dec']}) | {'YES' if row['name_in_range'] else '**NO**'} | {row['name_str']} | {row['signature']} | {row['param_list']} |")

    oor = r.get('out_of_range_names', {})
    if oor:
        lines.append(f"\n### Out-of-Range Name Index Scan")
        lines.append(f"- Total rows: {oor.get('total_rows', 0):,}")
        lines.append(f"- Out-of-range count: {oor.get('count', 0)}")
        if oor.get('first_bad'):
            fb = oor['first_bad']
            lines.append(f"- First bad row: #{fb['row']}, name_idx={fb['name_idx']} ({fb['name_idx_dec']}), heap_size={fb['strings_heap_size']:,}")

    ipp = r.get('ipointerpoint')
    if ipp:
        lines.append(f"\n### IPointerPoint")
        lines.append(f"- TypeDef row: {ipp['typedef_row']}")
        lines.append(f"- Namespace: {ipp['namespace']}")
        lines.append(f"- Method range: [{ipp['method_list_start']}, {ipp['method_list_end']}) ({ipp['method_count']} methods)")
        if ipp.get('methods'):
            lines.append(f"\n| Row | Flags | Name Idx | In Range | Name | Sig | ParamList |")
            lines.append(f"|-----|-------|----------|----------|------|-----|-----------|")
            for m in ipp['methods']:
                if 'error' in m:
                    lines.append(f"| {m['row']} | ERROR: {m['error']} |")
                else:
                    lines.append(f"| {m['row']} | {m['flags']} | {m['name_idx']} | {'YES' if m['name_in_range'] else '**NO**'} | {m['name']} | {m['sig']} | {m['param_list']} |")
    elif ipp is None:
        lines.append(f"\n### IPointerPoint: Not found in TypeDef table")

    return '\n'.join(lines)

# ===== Main =====
if __name__ == '__main__':
    winmd_universal = r"C:\Program Files (x86)\Windows Kits\10\References\10.0.26100.0\Windows.Foundation.UniversalApiContract\19.0.0.0\Windows.Foundation.UniversalApiContract.winmd"
    winmd_xaml = r"C:\Users\yuuji\.nuget\packages\microsoft.windowsappsdk\1.6.250108002\lib\uap10.0\Microsoft.UI.Xaml.winmd"

    print("=" * 80)
    print("MethodDef Binary Decode Verification")
    print("=" * 80)

    results = []
    for path in [winmd_universal, winmd_xaml]:
        print(f"\nParsing: {path}")
        if not os.path.exists(path):
            print(f"  FILE NOT FOUND!")
            results.append({'file': os.path.basename(path), 'error': 'File not found'})
            continue
        r = parse_winmd(path)
        formatted = format_result(r)
        print(formatted)
        results.append((r, formatted))

    # Write combined markdown output
    output_lines = ["# MethodDef Binary Decode Verification\n"]
    for item in results:
        if isinstance(item, tuple):
            r, formatted = item
            output_lines.append(formatted)
            output_lines.append("")
        else:
            output_lines.append(f"Error: {item}")

    output_path = os.path.join(os.path.dirname(__file__), 'decode_result.md')
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(output_lines))
    print(f"\nResults saved to: {output_path}")
