# LittleManComputer CLI – Command Hierarchy Draft

## Root Command `lmc`
- **Abstract**: "Little Man Computer command-line interface"
- **Discussion**: Provides assembly, execution, inspection, and persistence tools backed by CoreLittleManComputer.
- **Usage**: `lmc [global-options] <subcommand>`

### Global Options
- `--workspace <path>` / `-w`: Override workspace directory (default `~/.lmc`).
- `--color <auto|always|never>`: Control colour output (default `auto`).
- `--verbosity <quiet|info|debug>` / `-v`: Increase logging detail.
- `--plain`: Shortcut for `--color never --verbosity quiet` (friendly for pipelines).
- `--version`: Emit CLI + Core snapshot schema versions and exit.

---

## Subcommands

### `assemble`
- **Abstract**: Assemble Little Man Computer source into a program snapshot.
- **Usage**: `lmc assemble [--input <file>] [--output <file>] [--format <json|text>]`
- **Options**:
  - `--input <file>` / `-i`: Path to `.lmc` source; omit to read from stdin.
  - `--output <file>` / `-o`: Write compiled program JSON to file; omit for stdout.
  - `--format <json|text>`: Output JSON snapshot (default) or human-readable summary.
  - `--label-style <numeric|symbolic>`: Choose numbering style when emitting assembly.
- **Exit Codes**: `0` success; `1` assembly diagnostics emitted; `3` filesystem error.

### `run`
- **Abstract**: Execute a program snapshot and stream terminal updates.
- **Usage**: `lmc run <program> [--input <values>] [--speed <hz>] [--max-cycles <count>] [--break <addr> ...]`
- **Options**:
  - `--input <values>` / `-I`: Comma-separated inbox values or `stdin` to stream.
  - `--speed <hz>` / `-s`: Target cycles-per-second for continuous run (default 2.0).
  - `--max-cycles <count>`: Stop after given instruction count.
  - `--break <addr>`: Add mailbox breakpoints; repeatable.
  - `--plain-state`: Emit plain text state snapshots instead of live grid.
- **Exit Codes**: `0` clean halt; `2` runtime error; `3` filesystem error.

### `repl`
- **Abstract**: Launch interactive session for loading, running, and inspecting programs.
- **Usage**: `lmc repl [--welcome <file>]`
- **Options**:
  - `--welcome <file>`: Display file contents before prompt (tips, examples).
  - `--script <file>`: Preload and execute a command script before interactive control.

### `disassemble`
- **Abstract**: Convert a program snapshot back into assembly text.
- **Usage**: `lmc disassemble <program> [--output <file>] [--annotate]`
- **Options**:
  - `--output <file>` / `-o`: Write assembly to file; omit for stdout.
  - `--annotate`: Include mailbox comments, addresses, and metadata in the listing.

### `snapshot`
- **Abstract**: Manage persisted program and state snapshots in the workspace.
- **Usage**: `lmc snapshot <store|list|remove> [options]`
- **Subcommands**:
  - `store`: Assemble and store under a logical name (`--name`, `--source`).
  - `list`: Show stored snapshots with timestamps and metadata.
  - `remove`: Delete snapshots by name; confirm before destructive action.

### `state`
- **Abstract**: Inspect program state at rest or after execution.
- **Usage**: `lmc state <program> [--json] [--trace <count>] [--mailbox <addr>]`
- **Options**:
  - `--json`: Emit a single JSON payload for machine consumption.
  - `--trace <count>`: Tail length for recent instruction trace (default 10).
  - `--mailbox <addr>`: Focus on a single mailbox when printing in plain mode.

### `exec`
- **Abstract**: Convenience shortcut to assemble and immediately run inline code.
- **Usage**: `lmc exec "code" [run-options]`
- **Notes**: Equivalent to pipe `assemble` into `run`; surfaces diagnostics inline.

---

## Exit Code Convention
- `0`: Success.
- `1`: Assembly / input validation failure.
- `2`: Runtime failure (engine error, halted by guard).
- `3`: Filesystem or environment error.
- `130`: Interrupted by user (SIGINT).

## Next Steps
- Flesh out ArgumentParser command tree matching this layout.
- Map each command to service layer types (AssemblyService, ExecutionService, SnapshotService).
- Determine tests per command (`CommandTests`).
