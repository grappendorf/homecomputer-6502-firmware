# HomeComputer 6502—Keyboard Matrix

Reference for the keyboard driver in the new firmware. It is based on `firmware/keys.s65` and `firmware/keys.h` from the previous firmware, where the matrix, scan codes, and ASCII tables are defined, as well as the schematic (`KEYBOARD` connector) and photographs of the keyboard. For a system overview, see [system-spec.md](system-spec.md).

The matrix was parsed mechanically from the source files and cross-checked: all 80 `KEY_*` constants in `keys.h` match the positions in the commented matrix in `keys.s65`, and the ASCII tables contain entries only at occupied positions.

## 1. The Keyboard

- Laptop keyboard with a **German layout**, PCB marking `601-2148_03`. It has **89 keys**: 87 are represented in the matrix, while **Fn** and the **Windows key** are not connected or assigned (see section 7).
- The keyboard has no connector of its own: 22 wires are soldered directly to the connection pads on the keyboard PCB and run to the 22-pin `KEYBOARD` header (JP6) on the mainboard.
- The photographs of the back show only traces, solder pads, and wires, with **no diodes or resistors** visible. Ghosting protection is therefore not expected (see section 7).
- The matrix has **14 rows** (active-low outputs) and **8 columns** (inputs). Of its 14 × 8 = 112 positions, 87 are occupied and 25 are empty.

### 1.1 Connection

| JP6 pin | Signal | VIA pin | Matrix |
|---|---|---|---|
| 1 | `VIA1_PB5` | VIA1 PB5 | Row 13 |
| 2 | `VIA1_PB4` | VIA1 PB4 | Row 12 |
| 3 | `VIA1_PB3` | VIA1 PB3 | Row 11 |
| 4 | `VIA1_PB2` | VIA1 PB2 | Row 10 |
| 5 | `VIA1_PB1` | VIA1 PB1 | Row 9 |
| 6 | `VIA1_PB0` | VIA1 PB0 | Row 8 |
| 7 | `VIA2_PB7` | VIA2 PB7 | Row 7 |
| 8 | `VIA2_PB6` | VIA2 PB6 | Row 6 |
| 9 | `VIA2_PB5` | VIA2 PB5 | Row 5 |
| 10 | `VIA2_PB4` | VIA2 PB4 | Row 4 |
| 11 | `VIA2_PB3` | VIA2 PB3 | Row 3 |
| 12 | `VIA2_PB2` | VIA2 PB2 | Row 2 |
| 13 | `VIA2_PB1` | VIA2 PB1 | Row 1 |
| 14 | `VIA2_PB0` | VIA2 PB0 | Row 0 |
| 15 | `VIA2_PA7` | VIA2 PA7 | Column 7 |
| 16 | `VIA2_PA6` | VIA2 PA6 | Column 6 |
| 17 | `VIA2_PA5` | VIA2 PA5 | Column 5 |
| 18 | `VIA2_PA4` | VIA2 PA4 | Column 4 |
| 19 | `VIA2_PA3` | VIA2 PA3 | Column 3 |
| 20 | `VIA2_PA2` | VIA2 PA2 | Column 2 |
| 21 | `VIA2_PA1` | VIA2 PA1 | Column 1 |
| 22 | `VIA2_PA0` | VIA2 PA0 | Column 0 |

This mapping is taken from the schematic netlist, revision *Final*. Registers: VIA1 `$7F20` (Port B = `$7F20`), VIA2 `$7F40` (Port A = `$7F41`, Port B = `$7F40`).

### 1.2 Electrical Behavior

- **Columns (inputs, VIA2 Port A):** No external pull-ups are fitted or required. The 6522 data sheet (MOS, page 3, *Figure 2*) shows a permanently enabled pull-up transistor from PA0–PA7 to +5 V; the author confirmed that the installed VIAs have pull-ups. An open column therefore reads as `1`; a column with a pressed key in the row currently driven low reads as `0`. The firmware inverts the result (`eor #$ff`), so a pressed key corresponds to a set bit.
- **Rows (outputs):** VIA2 Port B provides rows 0–7; VIA1 Port B PB0–PB5 provides rows 8–13. The old firmware keeps all rows high and drives exactly one low for reading. Port B outputs are push-pull (Darlington source to +5 V; low = ground).
- **Note:** The keyboard uses only PB0–PB5 of VIA1 Port B; PB6/PB7 are free. Rows 8–13 should therefore be modified only through a read-modify-write operation with mask `$3F`, as in the old firmware, so that future signals on PB6/PB7 remain unchanged. VIA1 Port A belongs to the LCD and LED and is unrelated to the keyboard.

## 2. Scan-Code Scheme

```
scan code = row * 8 + column        (0..111, $FF = no key)
row       = 0..13   (0..7 = VIA2 PB0..PB7, 8..13 = VIA1 PB0..PB5)
column    = 0..7    (bit n of VIA2 Port A, read after inversion)
```

Inverse mapping: `row = scan code >> 3`, `column = scan code & 7`.

## 3. Matrix (Row × Column)

Key legends are shown as on the photograph: “normal / Shift” plus additional mappings. Empty cells have no connected key.

| Row | Output | Col. 0 | Col. 1 | Col. 2 | Col. 3 | Col. 4 | Col. 5 | Col. 6 | Col. 7 |
|---|---|---|---|---|---|---|---|---|---|
| 0 | VIA2 PB0 | 1 ! <sub>0</sub> | A <sub>1</sub> | ^ ° <sub>2</sub> | Q @ <sub>3</sub> |  | Esc <sub>5</sub> | Y <sub>6</sub> | Tab <sub>7</sub> |
| 1 | VIA2 PB1 | 3 § ³ <sub>8</sub> | D <sub>9</sub> | F2 <sub>10</sub> | E € <sub>11</sub> |  | F4 <sub>13</sub> | C <sub>14</sub> | F3 <sub>15</sub> |
| 2 | VIA2 PB2 | 4 $ <sub>16</sub> | F <sub>17</sub> | 5 % <sub>18</sub> | R <sub>19</sub> | B <sub>20</sub> | G <sub>21</sub> | V <sub>22</sub> | T <sub>23</sub> |
| 3 | VIA2 PB3 | 7 / { <sub>24</sub> | J <sub>25</sub> | 6 & <sub>26</sub> | U <sub>27</sub> | N <sub>28</sub> | H <sub>29</sub> | M µ <sub>30</sub> | Z <sub>31</sub> |
| 4 | VIA2 PB4 | 8 ( [ <sub>32</sub> | K <sub>33</sub> | ´ ` <sub>34</sub> | I <sub>35</sub> |  | F6 <sub>37</sub> | , ; <sub>38</sub> | + * ~ <sub>39</sub> |
| 5 | VIA2 PB5 | 0 = } <sub>40</sub> | Ö <sub>41</sub> | ß ? \ <sub>42</sub> | P <sub>43</sub> | - _ <sub>44</sub> | Ä <sub>45</sub> | # ' <sub>46</sub> | Ü <sub>47</sub> |
| 6 | VIA2 PB6 | Print SysRq <sub>48</sub> |  |  | Scroll Lock <sub>51</sub> | AltGr <sub>52</sub> | Alt <sub>53</sub> |  |  |
| 7 | VIA2 PB7 | End <sub>56</sub> |  | Home <sub>58</sub> |  | Cursor ← <sub>60</sub> | Cursor ↑ <sub>61</sub> | Pause Break <sub>62</sub> | Menu <sub>63</sub> |
| 8 | VIA1 PB0 | F12 <sub>64</sub> | S <sub>65</sub> | Insert <sub>66</sub> | W <sub>67</sub> | Cursor → <sub>68</sub> | < > \| <sub>69</sub> | X <sub>70</sub> | Caps Lock (⇩) <sub>71</sub> |
| 9 | VIA1 PB1 | F10 <sub>72</sub> |  | F9 <sub>74</sub> |  | Space <sub>76</sub> | F5 <sub>77</sub> | Enter <sub>78</sub> | Backspace (⌫) <sub>79</sub> |
| 10 | VIA1 PB2 | Page Down <sub>80</sub> | L <sub>81</sub> | Page Up <sub>82</sub> | O <sub>83</sub> |  |  | . : <sub>86</sub> | F7 <sub>87</sub> |
| 11 | VIA1 PB3 |  |  |  |  |  |  | Right Shift (⇧) <sub>94</sub> | Left Shift (⇧) <sub>95</sub> |
| 12 | VIA1 PB4 | F11 <sub>96</sub> | 2 " ² <sub>97</sub> | Delete <sub>98</sub> | 9 ) ] <sub>99</sub> | Cursor ↓ <sub>100</sub> | F8 <sub>101</sub> | Num Lock <sub>102</sub> | F1 <sub>103</sub> |
| 13 | VIA1 PB5 |  |  | Left Ctrl <sub>106</sub> |  |  |  | Right Ctrl <sub>110</sub> |  |

The subscript number is the decimal scan code.

## 4. Physical Layout with Scan Codes

The keys are arranged as follows on the photographed keyboard, with decimal scan codes in parentheses. `--` means the key exists but is not part of the matrix.

- ESC (5) · F1 (103) · F2 (10) · F3 (15) · F4 (13) · F5 (77) · F6 (37) · F7 (87) · F8 (101) · F9 (74) · F10 (72) · F11 (96) · F12 (64) · NUM (102) · PRINT (48) · SCROLL (51) · BREAK (62)
- ^ (2) · 1 (0) · 2 (97) · 3 (8) · 4 (16) · 5 (18) · 6 (26) · 7 (24) · 8 (32) · 9 (99) · 0 (40) · ß (42) · ´ (34) · BACKSP (79) · HOME (58)
- TAB (7) · Q (3) · W (67) · E (11) · R (19) · T (23) · Z (31) · U (27) · I (35) · O (83) · P (43) · Ü (47) · + (39) · RETURN (78) · PAGE_UP (82)
- CAPSLCK (71) · A (1) · S (65) · D (9) · F (17) · G (21) · H (29) · J (25) · K (33) · L (81) · Ö (41) · Ä (45) · # (46) · PAGE_DN (80)
- SHIFT_L (95) · Y (6) · X (70) · C (14) · V (22) · B (20) · N (28) · M (30) · , (38) · . (86) · - (44) · SHIFT_R (94) · CRS_U (61) · END (56)
- CTRL_L (106) · FN (--) · WIN (--) · ALT (53) · < (69) · SPACE (76) · ALT_GR (52) · MENU (63) · CTRL_R (110) · INSERT (66) · DELETE (98) · CRS_L (60) · CRS_D (100) · CRS_R (68)

## 5. Scan-Code Table

Sorted by scan code. “normal” and “Shift” are the values from `code_to_ascii_lower` and `code_to_ascii_upper` in `keys.s65` (0 = no character). The umlauts and `°` use LCD character codes (`ä`=`$E1`, `ö`=`$EF`, `ü`=`$F5`, `ß`=`$E2`, `°`=`$DF`, matching the HD44780 character set), not ISO-8859-1 codes. `$F2` (Shift+3, key legend `§`) is an LCD character code that could not be identified unambiguously.

| Scan code | Hex | Row | Column | Key | `keys.h` | Normal | Shift |
|---|---|---|---|---|---|---|---|
| 0 | `$00` | 0 | 0 | 1 ! | `KEY_1` | `1` | `!` |
| 1 | `$01` | 0 | 1 | A | `KEY_A` | `a` | `A` |
| 2 | `$02` | 0 | 2 | ^ ° | `KEY_HAT` | `^` | `$DF` (°) |
| 3 | `$03` | 0 | 3 | Q @ | `KEY_Q` | `q` | `Q` |
| 5 | `$05` | 0 | 5 | Esc | `KEY_ESC` | `$1B` (ESC) | `$1B` (ESC) |
| 6 | `$06` | 0 | 6 | Y | `KEY_Y` | `y` | `Y` |
| 7 | `$07` | 0 | 7 | Tab | `KEY_TAB` | – | – |
| 8 | `$08` | 1 | 0 | 3 § ³ | `KEY_3` | `3` | `$F2` (§?) |
| 9 | `$09` | 1 | 1 | D | `KEY_D` | `d` | `D` |
| 10 | `$0A` | 1 | 2 | F2 | `KEY_F2` | – | – |
| 11 | `$0B` | 1 | 3 | E € | `KEY_E` | `e` | `E` |
| 13 | `$0D` | 1 | 5 | F4 | `KEY_F4` | – | – |
| 14 | `$0E` | 1 | 6 | C | `KEY_C` | `c` | `C` |
| 15 | `$0F` | 1 | 7 | F3 | `KEY_F3` | – | – |
| 16 | `$10` | 2 | 0 | 4 $ | `KEY_4` | `4` | `$` |
| 17 | `$11` | 2 | 1 | F | `KEY_F` | `f` | `F` |
| 18 | `$12` | 2 | 2 | 5 % | `KEY_5` | `5` | `%` |
| 19 | `$13` | 2 | 3 | R | `KEY_R` | `r` | `R` |
| 20 | `$14` | 2 | 4 | B | `KEY_B` | `b` | `B` |
| 21 | `$15` | 2 | 5 | G | `KEY_G` | `g` | `G` |
| 22 | `$16` | 2 | 6 | V | `KEY_V` | `v` | `V` |
| 23 | `$17` | 2 | 7 | T | `KEY_T` | `t` | `T` |
| 24 | `$18` | 3 | 0 | 7 / { | `KEY_7` | `7` | `/` |
| 25 | `$19` | 3 | 1 | J | `KEY_J` | `j` | `J` |
| 26 | `$1A` | 3 | 2 | 6 & | `KEY_6` | `6` | `&` |
| 27 | `$1B` | 3 | 3 | U | `KEY_U` | `u` | `U` |
| 28 | `$1C` | 3 | 4 | N | `KEY_N` | `n` | `N` |
| 29 | `$1D` | 3 | 5 | H | `KEY_H` | `h` | `H` |
| 30 | `$1E` | 3 | 6 | M µ | `KEY_M` | `m` | `M` |
| 31 | `$1F` | 3 | 7 | Z | `KEY_Z` | `z` | `Z` |
| 32 | `$20` | 4 | 0 | 8 ( [ | `KEY_8` | `8` | `(` |
| 33 | `$21` | 4 | 1 | K | `KEY_K` | `k` | `K` |
| 34 | `$22` | 4 | 2 | ´ ` | `KEY_EQUAL` | `` ` `` | `` ` `` |
| 35 | `$23` | 4 | 3 | I | `KEY_I` | `i` | `I` |
| 37 | `$25` | 4 | 5 | F6 | `KEY_F6` | – | – |
| 38 | `$26` | 4 | 6 | , ; | `KEY_COMMA` | `,` | `;` |
| 39 | `$27` | 4 | 7 | + * ~ | `KEY_RIGHT_BRACKET` | `+` | `*` |
| 40 | `$28` | 5 | 0 | 0 = } | `KEY_0` | `0` | `=` |
| 41 | `$29` | 5 | 1 | Ö | `KEY_SEMICOLON` | `$EF` (ö) | `$EF` (ö) |
| 42 | `$2A` | 5 | 2 | ß ? \ | `KEY_MINUS` | `$E2` (ß) | `?` |
| 43 | `$2B` | 5 | 3 | P | `KEY_P` | `p` | `P` |
| 44 | `$2C` | 5 | 4 | - _ | `KEY_SLASH` | `-` | `_` |
| 45 | `$2D` | 5 | 5 | Ä | `KEY_APOSTROPH` | `$E1` (ä) | `$E1` (ä) |
| 46 | `$2E` | 5 | 6 | # ' | `KEY_HASH` | `#` | `'` |
| 47 | `$2F` | 5 | 7 | Ü | `KEY_LEFT_BRACKET` | `$F5` (ü) | `$F5` (ü) |
| 48 | `$30` | 6 | 0 | Print SysRq | `KEY_PRINT` | – | – |
| 51 | `$33` | 6 | 3 | Scroll Lock | `KEY_SCROLL` | – | – |
| 52 | `$34` | 6 | 4 | AltGr | – | – | – |
| 53 | `$35` | 6 | 5 | Alt | – | – | – |
| 56 | `$38` | 7 | 0 | End | `KEY_END` | – | – |
| 58 | `$3A` | 7 | 2 | Home | `KEY_HOME` | – | – |
| 60 | `$3C` | 7 | 4 | Cursor ← | `KEY_CURSOR_LEFT` | – | – |
| 61 | `$3D` | 7 | 5 | Cursor ↑ | `KEY_CURSOR_UP` | – | – |
| 62 | `$3E` | 7 | 6 | Pause Break | `KEY_BREAK` | – | – |
| 63 | `$3F` | 7 | 7 | Menu | `KEY_MENU` | – | – |
| 64 | `$40` | 8 | 0 | F12 | `KEY_F12` | – | – |
| 65 | `$41` | 8 | 1 | S | `KEY_S` | `s` | `S` |
| 66 | `$42` | 8 | 2 | Insert | `KEY_INSERT` | – | – |
| 67 | `$43` | 8 | 3 | W | `KEY_W` | `w` | `W` |
| 68 | `$44` | 8 | 4 | Cursor → | `KEY_CURSOR_RIGHT` | – | – |
| 69 | `$45` | 8 | 5 | < > \| | `KEY_LESS` | `<` | `>` |
| 70 | `$46` | 8 | 6 | X | `KEY_X` | `x` | `X` |
| 71 | `$47` | 8 | 7 | Caps Lock (⇩) | – | – | – |
| 72 | `$48` | 9 | 0 | F10 | `KEY_F10` | – | – |
| 74 | `$4A` | 9 | 2 | F9 | `KEY_F9` | – | – |
| 76 | `$4C` | 9 | 4 | Space | `KEY_SPACE` | ` ` | ` ` |
| 77 | `$4D` | 9 | 5 | F5 | `KEY_F5` | – | – |
| 78 | `$4E` | 9 | 6 | Enter | – | `$0A` (LF) | `$0A` (LF) |
| 79 | `$4F` | 9 | 7 | Backspace (⌫) | `KEY_BACKSPACE` | – | – |
| 80 | `$50` | 10 | 0 | Page Down | `KEY_PAGE_DOWN` | – | – |
| 81 | `$51` | 10 | 1 | L | `KEY_L` | `l` | `L` |
| 82 | `$52` | 10 | 2 | Page Up | `KEY_PAGE_UP` | – | – |
| 83 | `$53` | 10 | 3 | O | `KEY_O` | `o` | `O` |
| 86 | `$56` | 10 | 6 | . : | `KEY_DOT` | `.` | `:` |
| 87 | `$57` | 10 | 7 | F7 | `KEY_F7` | – | – |
| 94 | `$5E` | 11 | 6 | Right Shift (⇧) | – | – | – |
| 95 | `$5F` | 11 | 7 | Left Shift (⇧) | – | – | – |
| 96 | `$60` | 12 | 0 | F11 | `KEY_F11` | – | – |
| 97 | `$61` | 12 | 1 | 2 " ² | `KEY_2` | `2` | `"` |
| 98 | `$62` | 12 | 2 | Delete | `KEY_DELETE` | – | – |
| 99 | `$63` | 12 | 3 | 9 ) ] | `KEY_9` | `9` | `)` |
| 100 | `$64` | 12 | 4 | Cursor ↓ | `KEY_CURSOR_DOWN` | – | – |
| 101 | `$65` | 12 | 5 | F8 | `KEY_F8` | – | – |
| 102 | `$66` | 12 | 6 | Num Lock | `KEY_NUM` | – | – |
| 103 | `$67` | 12 | 7 | F1 | `KEY_F1` | – | – |
| 106 | `$6A` | 13 | 2 | Left Ctrl | – | – | – |
| 110 | `$6E` | 13 | 6 | Right Ctrl | – | – | – |

## 6. Modifiers

Modifier keys do not produce their own scan codes; they set bits in `key_modifiers`. They occupy dedicated or almost dedicated rows:

| Modifier | Bit | Key | Position | Scan mask |
|---|---|---|---|---|
| `MOD_SHIFT` | `%001` | Left / right Shift | Row 11, column 7 / 6 | Row 11: `%11000000` are Shift keys; the remaining `%00111111` are normal keys (currently none) |
| `MOD_CTRL`  | `%010` | Left / right Ctrl | Row 13, column 2 / 6 | Row 13: `%01000100` are Ctrl keys; the remaining `%10111011` are normal keys (currently none) |
| `MOD_ALT`   | `%100` | Alt / AltGr | Row 6, column 5 / 4 | Row 6: `%00110000` are Alt/AltGr; the remaining `%11001111` are normal keys (Scroll Lock and Print) |

Note: The old firmware cannot distinguish Alt from AltGr; both set `MOD_ALT`. `Caps Lock` (scan code 71) is a normal scan code and has no lock logic there.

Current firmware (`src/keyboard.s65`): Caps Lock is physically a momentary key and does not latch. The firmware latches it in software. `kb_scan` masks row 8, column 7 out of the scan code and maintains two bits in `kb_mod` across scans: `MOD_CAPSKEY` (`$80`) represents the debounced key (a change must still be present 5 ms later), while `MOD_CAPS` (`$08`) is the latched state. A pressed edge toggles `MOD_CAPS`; holding the key does not repeat. `kb_init` initializes `MOD_CAPS` to off and `MOD_CAPSKEY` to pressed so a key held during reset does not count. After consulting the Shift table, `kb_ascii` swaps upper- and lowercase only for A–Z/a–z when `MOD_CAPS` is set, so Shift reverses Caps Lock.

Multiple simultaneous keys: `scan` searches rows 13 down to 0 and overwrites the result for each row containing a pressed key. The row with the **lowest number** therefore wins; within that row, the column with the **highest number** wins. All other simultaneously pressed keys are discarded.

## 7. Gaps and Notes for the New Firmware

1. **Fn and the Windows key** are physically present but absent from the matrix. The 22 wires presumably cover all rows and columns required for the other 87 keys. According to the author, pressing **Fn + Windows key together triggers a hard reset**—presumably through separate wiring to the reset circuit (JP2/NE555; see section 7 of [system-spec.md](system-spec.md)), not the NMI connector (JP3). The exact wiring—which key connects where and whether either does anything alone—is undocumented and cannot be handled in firmware anyway.
2. **Fn layer:** The blue secondary legends (7 8 9 0 / U I O P / J K L Ö / M , . - and page/arrow keys) form a numeric keypad under Fn. Because Fn is inaccessible, this layer is unavailable.
3. **25 empty matrix positions:** (row, column) = (0,4), (1,4), (4,4), (6,1), (6,2), (6,6), (6,7), (7,1), (7,3), (9,1), (9,3), (10,4), (10,5), (11,0), (11,1), (11,2), (11,3), (11,4), (11,5), (13,0), (13,1), (13,3), (13,4), (13,5), (13,7). Row 11 is empty except for the Shift keys; row 13 is empty except for the Ctrl keys.
4. **No AltGr layer** exists in the ASCII table. `@`, `€`, `{`, `[`, `]`, `}`, `\`, `~`, `|`, `µ`, `²`, and `³` are printed on the keycaps but are not mapped by the driver. The old firmware therefore cannot enter them.
5. **No control codes** are defined for Tab (7), Backspace (79), Delete (98), or the cursor and function keys: `keys_getc` returns `0` for them. The new firmware must define suitable key codes itself.
6. **Names in `keys.h`** follow the US layout, not the German key legends (`KEY_MINUS` = `ß`, `KEY_EQUAL` = `´`, `KEY_LEFT_BRACKET` = `Ü`, `KEY_RIGHT_BRACKET` = `+`, `KEY_SEMICOLON` = `Ö`, `KEY_APOSTROPH` = `Ä`, `KEY_SLASH` = `-`). `keys.h` has no constants for Return, Caps Lock, Alt, AltGr, Shift, or Ctrl (scan codes 78, 71, 53, 52, 95, 94, 106, 110).
7. **Ghosting:** Without diodes, pressing three keys at three corners of a rectangle in the matrix makes the fourth corner appear pressed. Because Shift and Ctrl each occupy dedicated rows, this rarely affects ordinary combinations such as Shift + letter: the ghost position would be the other Shift key or an empty position. The only exception is pressing both Shift keys together with a key in column 6 or 7, which creates a ghost at the adjacent column in the same row—an unlikely practical case.
8. **Scanning method:** The old firmware actively drives every inactive row high while one row is low. If two keys in the same column are pressed, they connect a high row to the low row: current flows through both contacts and the column assumes an intermediate voltage. A cleaner approach is to configure only the row being scanned as an output driven low and leave all other rows as high-impedance inputs through the DDR register. This is a proposal for the new driver, not a previously observed fault.
9. **Debouncing** in the old firmware uses two scans 20 ms apart in a blocking busy loop. A better design would scan on a 100 Hz tick (10 ms) using a state machine, ring buffer, and auto-repeat.
