# Cowbell for Herdr

See which of your [Herdr](https://github.com/herdrdev/herdr) workspaces have dev servers running, without switching to them.

A herder knows where the herd is by its cowbells. Cowbell does the same for the servers in your Herdr workspaces.

Each server running in a workspace adds a colored dot next to that workspace's name in the sidebar:

```text
● api · ●● · ○
feat/auth · ↑2
● frontend · ●
main
● docs · ○
main
```

| Dot | Meaning |
| --- | --- |
| 🟢 green | A process in the pane is listening on a TCP port, including servers started through overmind or foreman |
| 🟡 yellow | The pane was serving before; a command is still running but nothing is listening (restarting, rebuilding, or all overmind processes stopped) |
| ○ hollow | A server ran in this pane before and it's back at the shell prompt (stopped or crashed). Stays until the pane is closed, so you can see where your servers live. |

Each dot is one pane. Two servers running and one stopped shows as `●● · ○`.

## Install

```bash
herdr plugin install mustafaergul/herdr-cowbell
```

The poller starts automatically the next time the Herdr server starts. To start it right away:

```bash
herdr plugin action invoke mustafaergul.cowbell.restart
```

### Show the dots in the sidebar (required)

Herdr doesn't let plugins change the sidebar layout, so this one-time step is needed. The plugin only reports the values. Your sidebar config decides where they go and what color they are. Add this to `~/.config/herdr/config.toml`:

```toml
[ui.sidebar.spaces]
rows = [
  ["state_icon", "workspace",
    { token = "$srv_up",   fg = "#a6e3a1" },
    { token = "$srv_wait", fg = "#f9e2af" },
    { token = "$srv_down", fg = "#f38ba8" }],
  ["branch", "git_status"],
]
```

Then reload:

```bash
herdr server reload-config
```

Use any `#RGB` or `#RRGGBB` color, or move the tokens to their own row. The dots appear in the expanded desktop sidebar only.

## Process managers and puma-dev

[Overmind](https://github.com/DarthSim/overmind) runs each Procfile process under its own detached tmux server, so those servers aren't children of your pane. Cowbell handles this. When a pane's foreground process is a known process manager (`overmind`, `foreman`, `hivemind`, or `honcho`), any listening server whose working directory is that pane's directory, or a folder under it, counts toward that pane. One `overmind start` pane shows as one dot, however many web processes it runs.

This also covers [puma-dev](https://github.com/puma/puma-dev) in proxy mode, where files in `~/.puma-dev` contain a port number (for example `myapp` → `5500`). puma-dev only forwards `myapp.test` to that port, and Cowbell detects whatever is listening there.

## Requirements

- Herdr 0.9.0 or newer
- macOS or Linux
- `bash`, `jq`, `lsof`, and `ps` on your `PATH`

## How it works

A Herdr startup hook launches a small background loop. Every few seconds the loop:

1. Lists the panes with `herdr pane list`, skipping panes that run a coding agent.
2. Gets each pane's shell pid with `herdr pane process-info`, then finds all of that shell's child processes.
3. Checks those processes against the TCP ports in the `LISTEN` state reported by `lsof`.
4. For panes running a process manager, matches the remaining listeners by working directory.
5. Writes the dot counts to each workspace with `herdr workspace report-metadata` as the tokens `srv_up`, `srv_wait`, and `srv_down`.

Tokens are written with a 15 second expiry, so the dots disappear on their own if the loop stops. Only panes that have listened on a port at least once can show a yellow dot or a hollow circle, so editors, test runners, and other long-running commands don't add noise.

## Configuration

Set these environment variables in the environment of the Herdr server:

| Variable | Default | Description |
| --- | --- | --- |
| `COWBELL_INTERVAL` | `5` | Seconds between scans |
| `COWBELL_TTL_MS` | `15000` | How long reported dots last without a refresh |
| `COWBELL_DOT` | `●` | Symbol for running and restarting servers |
| `COWBELL_DOT_DOWN` | `○` | Symbol for panes whose server has stopped |
| `COWBELL_LAUNCHERS` | `overmind foreman hivemind honcho` | Space-separated process names treated as process managers |

## Troubleshooting

Check that the poller is running:

```bash
pgrep -fl loop.sh
```

Inspect what the plugin reported for a workspace:

```bash
herdr workspace get <workspace_id> | jq '.result.workspace.tokens'
```

Preview one scan without writing anything:

```bash
DRY_RUN=1 ./scan.sh
```

The loop writes its output to `loop.log` in the plugin's state directory. Startup and action runs are listed by:

```bash
herdr plugin log list --plugin mustafaergul.cowbell
```

## Known limitations

- Herdr puts ` · ` between adjacent sidebar tokens, so mixed statuses render as `●● · ○`.
- Cowbell remembers server panes by pane id. Live handoffs keep that memory, but a full Herdr restart can renumber panes, so hollow circles start over after one.
- Panes running a coding agent are skipped, so servers that agents start themselves aren't counted.
- `lsof` only sees processes owned by your user. Servers running in Docker containers aren't detected, including Docker services inside a Procfile.
- puma-dev in app mode (symlinks in `~/.puma-dev` pointing at app folders) isn't detected, because puma-dev starts those apps on demand with no pane to attach them to.
- If two panes run a process manager in the same directory (for example `overmind start` and `overmind connect web`), both count.
- Changes take one or two scan cycles to show, roughly 5–10 seconds.
- A scan calls `herdr pane process-info` once per pane, so very large sessions take a couple of seconds per scan.

## Uninstall

```bash
herdr plugin uninstall mustafaergul.cowbell
```

Then remove the `$srv_*` tokens from your sidebar config.

## License

[MIT](LICENSE)
