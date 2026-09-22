# BASIC Command Set

Microsoft BASIC-M6502 V1.1, adapted for the HomeComputer 6502 (`REALIO=6`). The source is Microsoft's MIT-licensed file; the copyright notice is included in the source code under `src/msbasic/`. This page describes the command set actually included in this firmware.

The console consists of the 4×40 LCD and the keyboard. After startup, the banner, copyright notice, and `BYTES FREE` appear, followed by the input line. There is no ready prompt. If the last line is still open, the cursor advances one line before the next input. There are no `MEMORY SIZE` or `WIDTH` prompts. Program memory occupies `$0440`–`$7EFF`. A hex monitor that BASIC does not use runs in parallel on the ACIA; see [monitor.md](monitor.md). The monitor command `*BASIC` hands the serial line to BASIC. The keyboard and LCD then remain inactive until `QUIT`, the end of `tools/terminal/mame-basic.sh` or `serial-basic.sh`, or a `#1` device selection.

Keywords are converted to uppercase while entering them, except inside quotation marks, in `DATA`, and after `REM`.

## Program and Direct Mode

A numbered line is stored. Reusing the same number replaces the old line; entering only a number deletes it. A line without a number is executed immediately.

The editor holds one line of up to 120 characters and writes it at the cursor's current position. The rest of the screen remains unchanged. On the LCD, the line wraps after 40 characters; on the serial console, it wraps at the column count configured by `TERM`. Left and Right move one character, Up and Down one line. Backspace deletes before the cursor, Delete deletes under it. Home and End jump to the beginning or just past the last character. Insert enables overwrite mode; the LCD then blinks. Escape discards the line. Enter completes it and advances to the next line. On the terminal these are the corresponding ANSI keys (arrows, Home, End, Delete, Insert); Backspace may send either BS or DEL.

Caps Lock latches as on a PC: press it once to enable uppercase letters and again to disable them. Holding it down does not toggle repeatedly, and the key itself produces no character. It is off after power-on and reset. It affects only the letters A–Z. Shift reverses it: with Caps Lock enabled, Shift+A produces `a`. Digits and punctuation depend only on Shift. There is no indicator; the LED remains available for `LED ON`/`OFF` and `LIST`. The firmware reads Caps Lock on every keyboard poll: during input, between two BASIC statements, and in `KEY`.

Pressing Up on an empty input line retrieves the last program line, and Down retrieves the first, exactly as `LIST` would print it. Further Up moves to the previous line and further Down to the next. If the line contains only a number, Up and Down retrieve exactly that program line if it exists; browsing then continues from there. If the number does not exist, the text remains unchanged. Browsing remains active only while the line has not been modified since it was loaded. Enter submits the text as if it had been typed: the same number replaces the line, another number creates a new one, and the old line remains. `INPUT` uses the same line editor without browsing the program.

Multiple statements on one line are separated by `:`.

```
10 PRINT "HELLO"
20 GOTO 10
RUN
```

`INPUT` and `DEF FN` are not allowed in direct mode (`ILLEGAL DIRECT`).

## Statements

### `CLEAR`

Deletes variables, arrays, strings, and the stack. The program remains intact.

### `CONT`

Continues after `STOP` or Break. This is not possible after the program has been modified (`CAN'T CONTINUE`).

### `DATA` constant `,` …

Constants for `READ`. Unquoted strings end at the comma.

### `DEF FN` name `(` argument `) =` expression

User-defined function with one argument. The name has a form such as `FNA`. Program mode only.

### `DIM` name `(` bound `)` …

Array declaration. Without `DIM`, the bound is 10. A second `DIM` for the same name produces `REDIM'D ARRAY`. Integer arrays use `%`, string arrays use `$`.

### `END`

Ends the program. Unlike `STOP`, it does so without `BREAK`.

### `FOR` variable `=` start `TO` end [`STEP` increment]

Loop. `NEXT` without a name closes the innermost loop. `NEXT` with the wrong variable produces `NEXT WITHOUT FOR`.

### `GOTO` line

Jumps to a line. An unknown line produces `UNDEF'D STATEMENT`. `GO TO` is equivalent.

### `GOSUB` line / `RETURN`

Calls a subroutine. `RETURN` without `GOSUB` produces `RETURN WITHOUT GOSUB`.

### `IF` expression `THEN` statement
### `IF` expression `THEN` line
### `IF` expression `GOTO` line

Any numeric value other than 0 is true. `THEN` is followed by a statement or line number.

### `INPUT` [`"` text `";`] variable `,` …

Reads a line and assigns its values to the variables. If too few values are entered, it prompts again with `??`. Program mode only.

`INPUT #1,` reads the keyboard; `INPUT #2,` reads the serial interface. `#2` is valid only while the monitor has handed over the line with `*BASIC`; otherwise it produces `ILLEGAL QUANTITY`. Without `#n`, the active device is used: the LCD, or the serial interface after `*BASIC`.

### `LED ON`
### `LED OFF`

Turns the LED on VIA1 PA7 on or off. See below.

### `LET` variable `=` expression

Assignment. `LET` may be omitted: `A=1` is equivalent.

### `LIST` [from] [`-` [to]]

Prints the program. Forms include `LIST 100`, `LIST 100-200`, `LIST -200`, and `LIST 100-`. The screen is not cleared. On the LCD, three more text lines are shown, followed by `MORE - PRESS A KEY` and the LED at the top right while more output remains. A BASIC line longer than 40 characters occupies the next screen line and may wrap in the middle of the text at a page boundary. Pressing a key continues below it. Break or Ctrl+C aborts. When BASIC is using the serial interface, `LIST` scrolls without waiting for a key.

### `NEW`

Deletes the program and variables.

### `NEXT` [variable] [`,` variable …]

Closes a `FOR` loop.

### `ON` expression `GOTO` line `,` line …
### `ON` expression `GOSUB` line `,` line …

The expression is converted to an integer from 1 through n. 1 selects the first line. 0 or a value that is too large does nothing.

### `POKE` address `,` value

Writes a byte (0…255) to an address (0…65535). Values outside these ranges produce `ILLEGAL QUANTITY`.

### `PRINT` [expression] [`;` | `,`] …

Produces output. `;` continues immediately after the preceding output; `,` advances to the next tabular column (width 10). `?` is shorthand for `PRINT`.

`PRINT #1,` writes to the LCD; `PRINT #2,` writes to the serial interface. The same rule as for `INPUT` applies: without `#n`, the active device is used, and `#2` is valid only after `*BASIC`. Lines wrap after 40 characters on the LCD and according to `TERM` on the serial interface (initially 80).

`TAB(` column `)` and `SPC(` count `)` may be used in the `PRINT` list.

### `READ` variable `,` …

Reads the next `DATA` constant. When there is no more data, it produces `OUT OF DATA`.

### `REM` text

Comment through the end of the line. A colon does not terminate `REM`.

### `RESTORE`

Causes the next `READ` to start again at the first `DATA` statement.

### `RUN` [line]

Deletes the variables and starts at the beginning of the program or at the specified line.

### `STOP`

Stops and reports `BREAK` with the line number. `CONT` resumes execution.

### `SYS` address

Jumps to an address (0…65535). `RTS` returns to BASIC. Values outside the range produce `ILLEGAL QUANTITY`.

Programs loaded from a `.prg` file use this to call machine code. Built-in entry points, specified as the address followed by `JSR`, are:

| Address | Meaning |
| --- | --- |
| `$FF80` | Clear the screen |
| `$FF83` | Cursor: A = row 0…3, X = column 0…39 |
| `$FF86` | Write the character in A at the cursor position. The LCD counter advances; the column maintained by the driver does not. |
| `$FF89` | Underline: A = 0 off, otherwise on |
| `$FF8C` | Key in A, or 0. X and Y are preserved. Arrow keys are `$11` left, `$12` right, `$13` up, `$14` down. |
| `$FF8F` | Wait A milliseconds |
| `$FF92` | Silence the SID |
| `$FF95` | Effect, A = 1…9 as for `EFFECT` |

`examples/raid.s65` uses these entry points. `examples/build.sh` creates `raid.prg`. Then use `LOAD "raid"` and `RUN`. Up and Down dodge the walls; `Q` returns to BASIC.

### `SLEEP` seconds

Waits. The time is a floating-point value in seconds: `SLEEP 1` waits one second, and `SLEEP 0.1` waits 100 milliseconds. `SLEEP 0` returns immediately. Negative values or values of 8388.608 seconds and above produce `ILLEGAL QUANTITY`. Break or Ctrl+C aborts the wait.

### `WAIT` address `,` mask [`,` XOR]

Reads the address, combines the value with XOR, and waits until `(byte XOR XOR) AND mask` is nonzero. Without XOR, 0 is used.

## LED

The LED is at the top right and lights automatically for one second after a reset. `LED ON` and `LED OFF` then control it persistently. The first of these commands stops the reset timer; otherwise the light would turn off again after that second.

```
10 LED ON
20 SLEEP 0.5
30 LED OFF
40 SLEEP 0.5
50 GOTO 10
```

`LED` without `ON` or `OFF` is a syntax error, as is `OFF` on its own. `ON` and `OFF` are reserved words, so `OFF` cannot be used as a variable name.

## Display

After startup, the display is on and the cursor is the display's nonblinking underline. Rows and columns are numbered from 0. `POS(0)` returns the column; `LOCATE` sets it along with the row.

These commands optionally accept `#1` (LCD) or `#2` (serial) first: `CLS #1`, `LOCATE #2, 0, 0`, `CURSOR #2 ON`. Without `#n`, the active device is used. The serial interface emits ANSI sequences (`ESC [ 2 J`, cursor position, cursor on/off). `BLINK` and `DISPLAY` have no effect there. The logical dimensions are independent of the host window.

### `CLS`

Clears the screen and moves the cursor to 0,0.

### `LOCATE` row `,` column

Sets the cursor position. On the LCD, rows are 0–3 and columns 0–39. On the serial interface, rows range from 0 through the number of `TERM` rows minus 1, and columns from 0 through the number of `TERM` columns minus 1. Values outside these ranges produce `ILLEGAL QUANTITY`.

### `TERM` [columns [`,` rows]]

Sets the logical dimensions of the serial console. The initial size is 80 columns by 24 rows. `TERM 80,24` sets both; `TERM 40` sets only the columns. Without an argument, the command prints the current values. The terminal window must be at least this large; the firmware does not query it.

### `QUIT`

Returns the serial line to the hex monitor (`MON 6502` and `*`) and switches the console back to the LCD and keyboard. `tools/terminal/mame-basic.sh` and `serial-basic.sh` send this when PicoCom exits. Without a preceding `*BASIC`, it is a syntax error.

### `CURSOR ON` / `CURSOR OFF`
### `CURSOR BLINK ON` / `CURSOR BLINK OFF`

`ON` enables the underline; `OFF` disables it. `BLINK ON` makes the character at the cursor position blink, and `BLINK OFF` disables blinking. The underline and blinking are independent. `BLINK` on its own is a syntax error. `BLINK` is a reserved word.

### `DISPLAY ON` / `DISPLAY OFF`

Turns the display panel on or off. The text remains stored.

## Sound

The SID plays in the background. None of these commands pause the program. It provides three voices and can play three melodies simultaneously, one per voice. `PLAY 0` stops all voices. `PLAY n OFF` stops only voice n. Values outside the valid range produce `ILLEGAL QUANTITY`.

After startup, the volume is 15 and the tempo is 8 sixteenth notes per second. Instrument 0 is assigned to each voice until a note loads another instrument.

| No. | Sound | Waveform |
| --- | --- | --- |
| 0 | Organ, sustained | Triangle |
| 1 | Piano, short attack | Sawtooth |
| 2 | Bass, sustained | Pulse |
| 3 | Noise, sustained | Noise |
| 4–7 | Same as 0 | Triangle |

`ENVELOPE` changes only the envelope. The waveform remains unchanged until `WAVE` or the next note using an instrument sets it.

### `VOL` level

Volume 0–15.

### `TEMPO` n

Sixteenth notes per second, 1–50. The default is 8, or about one eighth of a second per sixteenth note. This applies to `SOUND` and note lengths, but not to `EFFECT`.

### `ENVELOPE` n `,` attack `,` decay `,` sustain `,` release

Instrument 0–7. Each level is 0–15. The next note that uses this instrument adopts the new envelope.

### `WAVE` voice `,` form [ `,` pulse ]

Voice 1–3. Form 0 is triangle, 1 sawtooth, 2 pulse, and 3 noise. Pulse is 0–4095 and is audible only with form 2; if omitted, the pulse width remains unchanged. The command takes effect immediately. The next note reloads the waveform and pulse width from its instrument.

### `SOUND` voice `,` frequency `,` duration [ `,` instrument ]

Starts a note and returns immediately. Frequency is a SID register value from 0–65535, not hertz. Middle C is 4389 ($1125, 261.6 Hz). Duration is 1–255 sixteenth notes and therefore depends on `TEMPO`. Without an instrument, the voice's current waveform remains unchanged. A melody already playing on that voice is replaced.

### `TUNE` slot `,` note-string

Slot 1–3 corresponds to the voice. The string may contain at most 47 characters. It is stored exactly as written; playback is case-insensitive.

Spaces are skipped. `O` followed by a digit 0–7 sets the octave, `I` followed by a digit 0–7 sets the instrument, and `L` followed by a digit 1–8 sets the length in sixteenth notes. All three settings persist. The initial values are octave 4, instrument 0, and length 4. `R` is a rest; the following digit specifies only the length of that rest. Notes are `A` through `G`, optionally followed by `#` and an octave from 0–7. `C3` is C in octave 3 and `C4` is C in octave 4. The digit is not the length. Without a digit, the last octave is used. `L` sets the length. For lengths, `0` counts as 1 and values from `9` upward count as 8. `#` after `B` becomes `C` in the next octave. An invalid character stops only that voice.

```
TUNE 1,"I0L4C4D4E4F4G4L2A4G4"
PLAY 1
```

### `PLAY` slot [ `ON` | `OFF` ] [ `,` … ]

Starts the stored melody in the background. `ON` repeats it until `PLAY 0` or `PLAY` slot `OFF`. Without `ON`, it plays once. `OFF` stops only that voice. `PLAY 0` stops all voices. `PLAY 0,1` stops all voices and then starts slot 1. An empty slot remains silent. `PLAY 1 ON,2` repeats slot 1 and plays slot 2 once.

### `EFFECT` n

`1` gunshot, `2` explosion, `3` laser, `4` jump, `5` coin, `6` extra, `7` error, `8` siren, `9` falling bomb. Effects always use voice 3; the other two continue playing. Pitch advances in 1/50-second steps, independently of the tempo.

## Functions

One pair of parentheses and one argument, except for `MID$`, which accepts two or three arguments. `LEFT$`, `RIGHT$`, and `MID$` expect a string and a number.

| Function | Result |
| --- | --- |
| `ABS(x)` | Absolute value |
| `ASC(s$)` | Character code of the first character |
| `ATN(x)` | Arctangent |
| `CHR$(n)` | Character with code n |
| `COS(x)` | Cosine; argument in radians |
| `EXP(x)` | e raised to x |
| `FRE(x)` | Free bytes; the value of x is not used |
| `INT(x)` | Greatest integer ≤ x |
| `KEY(x)` | Pressed key, or 0 if none. The value of x is not used. Arrows: 17 left, 18 right, 19 up, 20 down. Letters are returned as when typing: uppercase with Caps Lock enabled (65 rather than 97 for A). Caps Lock alone returns 0. |
| `LEFT$(s$,n)` | First n characters |
| `LEN(s$)` | Length |
| `LOG(x)` | Natural logarithm |
| `MID$(s$,start[,n])` | Substring; start begins at 1 |
| `PEEK(address)` | Byte read from the address |
| `POS(x)` | Cursor column; the value of x is not used |
| `RIGHT$(s$,n)` | Last n characters |
| `RND(x)` | Random number from 0…1. x>0 draws the next value, x<0 sets the seed, and x=0 repeats the last value. |
| `SGN(x)` | −1, 0, or 1 |
| `SIN(x)` | Sine; argument in radians |
| `SQR(x)` | Square root |
| `STR$(x)` | Number as a string |
| `TAN(x)` | Tangent; argument in radians |
| `USR(x)` | Calls a machine-language routine. The `JMP` is at address 10, with the target address in bytes 11 (low) and 12 (high). Without this setup, the result is `FC`. |
| `VAL(s$)` | Number at the beginning of the string |

## Operators

Numbers are floating point with about nine significant digits. Variables without a suffix are floating point; `%` variables are integers from −32768 to 32767; `$` variables are strings. A name consists of one letter or one letter followed by one character.

Arithmetic: `+` `-` `*` `/` `^`. Unary signs: `-` and `+`. Comparison: `=` `<` `>` and the combinations `<=` `>=` `<>`. Logic: `AND` `OR` `NOT`, bitwise on the integer value. Strings can be concatenated with `+` and compared with `=` `<` `>`.

Precedence, highest first: `^`, unary signs, `*` `/`, `+` `-`, comparisons, `NOT`, `AND`, `OR`.

## Error Messages

Messages have the form `TEXT ERROR` and, in a program, `IN` followed by the line number.

| Message | Meaning |
| --- | --- |
| `NEXT WITHOUT FOR` | `NEXT` without `FOR` |
| `SYNTAX` | Syntax error |
| `RETURN WITHOUT GOSUB` | `RETURN` without `GOSUB` |
| `OUT OF DATA` | No more `DATA` |
| `ILLEGAL QUANTITY` | Invalid value |
| `OVERFLOW` | Overflow |
| `OUT OF MEMORY` | Memory full |
| `UNDEF'D STATEMENT` | Unknown line |
| `BAD SUBSCRIPT` | Array index out of range |
| `REDIM'D ARRAY` | Array already dimensioned |
| `DIVISION BY ZERO` | Division by zero |
| `ILLEGAL DIRECT` | Not allowed in direct mode |
| `TYPE MISMATCH` | String and number mixed |
| `STRING TOO LONG` | String longer than 255 characters |
| `FORMULA TOO COMPLEX` | String expression nested too deeply |
| `CAN'T CONTINUE` | `CONT` is not possible |
| `UNDEF'D FUNCTION` | `FN` function not defined |
| `NO DISK` | `DIR`, `LOAD`, `SAVE`, or `DELETE` without a connected drive |
| `FILE NOT FOUND` | `LOAD` or `DELETE`: the file is missing |
| `BAD LOAD` | Loading a `.prg` file: load address is not `$0441`, or the image does not fit in program memory |

Break or Ctrl+C aborts input or the program (`BREAK`).

## Disk Drive

`DIR`, `LOAD "name"`, `SAVE "name"`, and `DELETE "name"` communicate with the serial drive described in [monitor.md](monitor.md). `name` is a string of at most 16 characters. If the name contains no period, the host uses `name.prg` if that file exists, otherwise `name.bas`. The directory is selected when starting `tools/disk/disk.rb`, not in the BASIC command. In serial BASIC, `tools/terminal/mame-basic.sh` (emulator) and `serial-basic.sh` (default `/dev/ttyUSB0`) implement the same protocol; their default directory is also `examples`, and another directory may be given as the first argument. Without this proxy the command times out; serial BASIC does not produce `NO DISK` in this case.

`DIR` lists sizes and file names without clearing the screen. On the LCD it shows three files, then `MORE - PRESS A KEY` and the LED at the top right if more entries remain. A key continues output below; afterward the LED returns to its state before the wait. In serial BASIC the list runs through without `MORE`. Break or Ctrl+C aborts. At the end of the directory it prints `END OF DIRECTORY`. `SAVE` writes the program as text, one line per program line, with keywords in uppercase. If memory contains no program, it prints `NO PROGRAM` and writes nothing. `LOAD` and `SAVE` show a progress bar and percentage, followed by `LOADED` or `SAVED`. On the serial console the proxy draws the same bar. `LOAD` replaces the program with the file and returns to input. If the file is missing, the existing program remains and `FILE NOT FOUND` appears immediately. If the file is empty, the program remains and `EMPTY FILE` appears. A `.prg` file is a machine-language program in the C64 format: the first two bytes are the little-endian load address, followed by the bytes beginning at that address. The address is `$0441`, the first byte of the BASIC program. `$0440` remains the preceding zero byte. The image starts with a BASIC line containing `SYS`, followed by the machine code. `LOAD` sets the end of variables after the image so that `RUN` does not overwrite the code. `LIST` shows the `SYS` line and `RUN` starts it. If the image does not fit, program memory remains empty and `BAD LOAD` appears. `SAVE` writes only the BASIC lines as text, not the machine code. `DELETE "name"` deletes the file. If it is missing, `FILE NOT FOUND` also appears. If it exists, BASIC asks `DELETE? (Y/N)`. Only `Y` deletes it, followed by `DELETED`; any other key leaves the file intact. Without a drive, it prints `NO DISK`.

## Not Included in This Version

`GET`, `NULL`, `INPUT#`, `PRINT#`, `CMD`, `OPEN`, `CLOSE`.
