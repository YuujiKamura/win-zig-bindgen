# MethodDef Binary Decode Verification

## Windows.Foundation.UniversalApiContract.winmd
- File size: 6,127,104 bytes
- Metadata offset: 0x250
- heap_sizes: 0x05
- Index sizes: {'string': 4, 'guid': 2, 'blob': 4}
- Streams:
  - #~: offset=0x2c4, size=4,308,788
  - #Strings: offset=0x41c1f8, size=937,548
  - #US: offset=0x501044, size=8
  - #GUID: offset=0x50104c, size=16
  - #Blob: offset=0x50105c, size=878,808
- Key row counts:
  - TypeDef: 12,506
  - Field: 9,910
  - MethodDef: 62,959
  - Param: 78,401
  - InterfaceImpl: 6,703
  - MemberRef: 23,494
  - CustomAttribute: 56,148

### MethodDef Table
- Row size: 20 bytes
- Row count: 62,959
- Offset in tables stream: 0x6de84
- Param index size: 4

### First 10 MethodDef Rows
| Row | Offset | RVA | Flags | Name Idx | In Range | Name | Signature | ParamList |
|-----|--------|-----|-------|----------|----------|------|-----------|-----------|
| 1 | 0x6de84 | 0x00000000 | 0x09e6 | 0x4ef79 (323449) | YES | get_AddAppointmentOperation | 0xf1 | 1 |
| 2 | 0x6de98 | 0x00000000 | 0x09e6 | 0x4ef9b (323483) | YES | get_Verb | 0xf7 | 2 |
| 3 | 0x6deac | 0x00000000 | 0x09e6 | 0x4efa4 (323492) | YES | get_Kind | 0xfb | 3 |
| 4 | 0x6dec0 | 0x00000000 | 0x09e6 | 0x4efad (323501) | YES | get_PreviousExecutionState | 0x100 | 4 |
| 5 | 0x6ded4 | 0x00000000 | 0x09e6 | 0x4efc8 (323528) | YES | get_SplashScreen | 0x105 | 5 |
| 6 | 0x6dee8 | 0x00000000 | 0x09e6 | 0x4efd9 (323545) | YES | get_User | 0x10b | 6 |
| 7 | 0x6defc | 0x00000000 | 0x09e6 | 0x4f003 (323587) | YES | get_RemoveAppointmentOperation | 0x135 | 7 |
| 8 | 0x6df10 | 0x00000000 | 0x09e6 | 0x4ef9b (323483) | YES | get_Verb | 0xf7 | 8 |
| 9 | 0x6df24 | 0x00000000 | 0x09e6 | 0x4efa4 (323492) | YES | get_Kind | 0xfb | 9 |
| 10 | 0x6df38 | 0x00000000 | 0x09e6 | 0x4efad (323501) | YES | get_PreviousExecutionState | 0x100 | 10 |

### Out-of-Range Name Index Scan
- Total rows: 62,959
- Out-of-range count: 0

### IPointerPoint
- TypeDef row: 8140
- Namespace: Windows.UI.Input
- Method range: [39170, 39178) (8 methods)

| Row | Flags | Name Idx | In Range | Name | Sig | ParamList |
|-----|-------|----------|----------|------|-----|-----------|
| 39170 | 0x0dc6 | 0xaed2c | YES | get_PointerDevice | 0x20941 | 50481 |
| 39171 | 0x0dc6 | 0x59357 | YES | get_Position | 0x322e | 50482 |
| 39172 | 0x0dc6 | 0xaed3e | YES | get_RawPosition | 0x322e | 50483 |
| 39173 | 0x0dc6 | 0xaed4e | YES | get_PointerId | 0x518 | 50484 |
| 39174 | 0x0dc6 | 0x7d481 | YES | get_FrameId | 0x518 | 50485 |
| 39175 | 0x0dc6 | 0x58b33 | YES | get_Timestamp | 0x76a | 50486 |
| 39176 | 0x0dc6 | 0xaed5c | YES | get_IsInContact | 0x2ba | 50487 |
| 39177 | 0x0dc6 | 0x58527 | YES | get_Properties | 0x20947 | 50488 |

## Microsoft.UI.Xaml.winmd
- File size: 1,618,464 bytes
- Metadata offset: 0x250
- heap_sizes: 0x05
- Index sizes: {'string': 4, 'guid': 2, 'blob': 4}
- Streams:
  - #~: offset=0x2c4, size=1,136,740
  - #Strings: offset=0x115b28, size=261,220
  - #US: offset=0x15578c, size=8
  - #GUID: offset=0x155794, size=16
  - #Blob: offset=0x1557a4, size=209,324
- Key row counts:
  - TypeDef: 3,048
  - Field: 1,567
  - MethodDef: 18,461
  - Param: 21,367
  - InterfaceImpl: 1,141
  - MemberRef: 6,207
  - CustomAttribute: 16,936

### MethodDef Table
- Row size: 18 bytes
- Row count: 18,461
- Offset in tables stream: 0x1907e
- Param index size: 2

### First 10 MethodDef Rows
| Row | Offset | RVA | Flags | Name Idx | In Range | Name | Signature | ParamList |
|-----|--------|-----|-------|----------|----------|------|-----------|-----------|
| 1 | 0x1907e | 0x00000000 | 0x1884 | 0x119fe (72190) | YES | .ctor | 0xa | 1 |
| 2 | 0x19090 | 0x00000000 | 0x01e6 | 0x34547 (214343) | YES | GetValue | 0x4dca | 1 |
| 3 | 0x190a2 | 0x00000000 | 0x01e6 | 0x1468d (83597) | YES | SetValue | 0x4dd1 | 3 |
| 4 | 0x190b4 | 0x00000000 | 0x01e6 | 0x34a00 (215552) | YES | ClearValue | 0x4dd9 | 5 |
| 5 | 0x190c6 | 0x00000000 | 0x01e6 | 0x34a0b (215563) | YES | ReadLocalValue | 0x4dca | 6 |
| 6 | 0x190d8 | 0x00000000 | 0x01e6 | 0x34a1a (215578) | YES | GetAnimationBaseValue | 0x4dca | 8 |
| 7 | 0x190ea | 0x00000000 | 0x01e6 | 0x34a30 (215600) | YES | RegisterPropertyChangedCallback | 0x4de0 | 10 |
| 8 | 0x190fc | 0x00000000 | 0x01e6 | 0x34a50 (215632) | YES | UnregisterPropertyChangedCallback | 0x4dea | 13 |
| 9 | 0x1910e | 0x00000000 | 0x09e6 | 0x34a91 (215697) | YES | get_Dispatcher | 0x4df2 | 15 |
| 10 | 0x19120 | 0x00000000 | 0x09e6 | 0x34ac9 (215753) | YES | get_DispatcherQueue | 0x4df8 | 16 |

### Out-of-Range Name Index Scan
- Total rows: 18,461
- Out-of-range count: 0

### IPointerPoint: Not found in TypeDef table
