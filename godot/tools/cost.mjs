// Measures what the Godot client costs beside a coding agent: the CPU and the memory of its process, in each state of its window
//.
//
//   node tools/cost.mjs --scenario multi --state focus                # one measurement
//   node tools/cost.mjs --matrix                                      # every scenario in every state (about 7 minutes)
//   node tools/cost.mjs --scenario replay --state unfocused --seconds 40 --json
//   node tools/cost.mjs --matrix --app <path to an exported app>     # measure a release export
//
// Scenarios:  idle    the bridge is up, the client is connected, no events (an agent that waits for its user)
//             replay  the bridge replays the Claude Code example session again and again (one agent that works)
//             multi   the scene `multi`, six agents in one room (demo mode, no bridge)
//             arenas  the scene `arenas`, nine agents in three arenas
//             ten     the scene `ten`, 157 agents in 40 arenas
//             raw     --project <folder>: any other Godot project, with no options (a baseline: for example an empty scene)
// States:     focus      the window has the focus (the client draws as fast as the screen allows)
//             unfocused  another window has the focus (the client draws at 30 frames a second)
//             minimized  the window is minimized (the client does not draw)
//
// It starts the client (the window build of the editor), waits for it to start, puts the window in the state, waits for the state to
// hold, and reads the CPU time and the memory of the process once a second. The CPU is in percent of ONE core (100 is one core).
// It needs a window, and on Windows PowerShell for the state of the window and the sampling. Linux and macOS samplers are written,
// but they were not run; the states unfocused and minimized are done on Windows only.

import { spawn, execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import net from 'node:net';
import { bridgeBinary } from '../../bridge/tools/bridge-binary.mjs';
import { GODOT_DIR, resolveGodot } from './godot-path.mjs';
import { windowBuild } from './startup.mjs';

export const SCENARIOS = ['idle', 'replay', 'multi', 'arenas', 'ten'];
export const STATES = ['focus', 'unfocused', 'minimized'];

/** Mean and peak of the CPU in percent of one core, from samples { t (ms), cpuMs }. The first sample is the start of the window. */
export function cpuPercent(samples) {
  const rates = [];
  for (let i = 1; i < samples.length; i += 1) {
    const wall = samples[i].t - samples[i - 1].t;
    if (wall > 0) rates.push(((samples[i].cpuMs - samples[i - 1].cpuMs) / wall) * 100);
  }
  const total = samples.length > 1 ? ((samples.at(-1).cpuMs - samples[0].cpuMs) / (samples.at(-1).t - samples[0].t)) * 100 : NaN;
  return { mean: total, peak: rates.length ? Math.max(...rates) : NaN, second_by_second: rates };
}

/** Mean and peak of the memory in MB from samples { memBytes }. */
export function memoryMb(samples) {
  const values = samples.map((s) => s.memBytes / (1024 * 1024));
  return { mean: values.reduce((a, b) => a + b, 0) / values.length, peak: Math.max(...values) };
}

/** True when the lines that the client wrote about its window say that the window is in the state (the last lines count). */
export function stateHolds(state, lines) {
  const last = (prefix) => lines.filter((line) => line.startsWith(prefix)).at(-1);
  const minimized = last('[live] minimized') === '[live] minimized true';
  const focus = last('[live] focus');
  if (state === 'minimized') return minimized;
  if (minimized) return false;
  if (state === 'unfocused') return focus === '[live] focus false';
  return focus === undefined || focus === '[live] focus true';
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

// ---------------------------------------------------------------- the process: CPU and memory

/** One reading of a process: { t (ms), cpuMs, memBytes }. */
function readProcess(pid) {
  if (process.platform === 'win32') {
    const out = execFileSync('powershell', ['-NoProfile', '-Command',
      `$p = Get-Process -Id ${pid}; [string]::Join(',', [DateTimeOffset]::Now.ToUnixTimeMilliseconds(), [int64]$p.TotalProcessorTime.TotalMilliseconds, $p.WorkingSet64)`], { encoding: 'utf8' });
    const [t, cpuMs, memBytes] = out.trim().split(',').map(Number);
    return { t, cpuMs, memBytes };
  }
  if (process.platform === 'linux') {
    const stat = readFileSync(`/proc/${pid}/stat`, 'utf8').split(' ');
    const ticks = Number(stat[13]) + Number(stat[14]);
    const rss = Number(readFileSync(`/proc/${pid}/statm`, 'utf8').split(' ')[1]) * 4096;
    return { t: Date.now(), cpuMs: (ticks * 1000) / 100, memBytes: rss };
  }
  const out = execFileSync('ps', ['-o', 'time=,rss=', '-p', String(pid)], { encoding: 'utf8' }).trim().split(/\s+/);
  const [m, s] = out[0].split(':');
  return { t: Date.now(), cpuMs: (Number(m) * 60 + Number(s)) * 1000, memBytes: Number(out[1]) * 1024 };
}

// ---------------------------------------------------------------- the state of the window (Windows)

const WIN32 = `Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
"@`;

/** Puts the window of a process in a state. Returns the pid of the foreground window afterwards, for a check. */
function setWindowState(pid, state) {
  if (process.platform !== 'win32') {
    if (state === 'focus') return;
    throw new Error('the states unfocused and minimized are done on Windows only');
  }
  const action = {
    focus: `[W]::ShowWindow($h, 9) | Out-Null; [W]::SetForegroundWindow($h) | Out-Null`,
    minimized: `[W]::ShowWindow($h, 6) | Out-Null`,
    // a press of the Alt key lets a background process take the foreground (the system's lock on the foreground window)
    unfocused: `[W]::ShowWindow($h, 9) | Out-Null; [W]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [W]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero); [W]::SetForegroundWindow([W]::GetShellWindow()) | Out-Null`,
  }[state];
  const script = `${WIN32}\n$h = (Get-Process -Id ${pid}).MainWindowHandle; ${action}; Start-Sleep -Milliseconds 300; $f = [W]::GetForegroundWindow(); $fp = 0; [W]::GetWindowThreadProcessId($f, [ref]$fp) | Out-Null; $fp`;
  return Number(execFileSync('powershell', ['-NoProfile', '-Command', script], { encoding: 'utf8' }).trim().split(/\s+/).pop());
}

// ---------------------------------------------------------------- one measurement

/**
 * Starts the client for a scenario, puts its window in a state, and measures. Returns { cpu, memory, log (the lines that the client
 * wrote about its window), foreground_ok }.
 */
export async function measure({ scenario, state, seconds = 30, warmup = 8, clientArgs = [], engineArgs = [], project = GODOT_DIR, app = '' }) {
  // app: an exported app (tools/export.mjs) in place of the editor that runs the project
  const godot = app || windowBuild(resolveGodot());
  const work = mkdtempSync(join(tmpdir(), 'agent-workshop-cost-'));
  const logFile = join(work, 'client.log');
  const children = [];
  let args = [...(app ? [] : ['--path', project]), '--log-file', logFile, ...engineArgs, '--', '--log-events', ...clientArgs];
  try {
    if (scenario === 'idle' || scenario === 'replay') {
      const port = await freePort();
      const bridgeBin = bridgeBinary();
      const bridge = spawn(bridgeBin, ['serve', '--port', String(port)], { stdio: 'ignore' });
      children.push(bridge);
      await sleep(1000);
      args = [...args, `--bridge=ws://127.0.0.1:${port}/ws`];
      if (scenario === 'replay') {
        const example = fileURLToPath(new URL('../../schema/examples/claude-code-transcript.jsonl', import.meta.url));
        // the same session again and again, at normal speed, until the measurement ends
        const loop = async () => {
          while (!loop.stopped) {
            await new Promise((resolve) => {
              const replay = spawn(bridgeBin, ['replay', example, '--speed', '1', '--url', `http://127.0.0.1:${port}`], { stdio: 'ignore' });
              children.push(replay);
              replay.on('exit', resolve);
            });
            await sleep(500);
          }
        };
        loop.stopped = false;
        children.push({ kill: () => { loop.stopped = true; } });
        setTimeout(() => loop(), 3000);
      }
    } else if (scenario !== 'raw') {
      args = [...args, `--demo=${scenario}`];
    }
    let client = spawn(godot, args, { stdio: 'ignore' });
    children.push(client);
    await sleep(warmup * 1000);
    // the client says in its log when its window changes (`--log-events`). The state must show there, or the measurement is not valid.
    const windowLog = () => (existsSync(logFile) ? readFileSync(logFile, 'utf8').split(/\r?\n/).filter((line) => line.startsWith('[live] focus') || line.startsWith('[live] minimized')) : []);
    let foreground = 0;
    let forced = false;
    for (let attempt = 0; attempt < 3 && !stateHolds(state, windowLog()); attempt += 1) {
      foreground = setWindowState(client.pid, state);
      await sleep(2000);
    }
    if (!stateHolds(state, windowLog()) && state === 'unfocused') {
      // the system keeps the foreground window (it does not let a background process take it): start the client again and tell it to
      // behave as a window without the focus. The cost is the same (the frame cap and the drawing); only the system's own handling of
      // a background window is not measured. The result says so.
      client.kill();
      await sleep(1000);
      forced = true;
      const again = spawn(godot, [...args, '--force-focus=false'], { stdio: 'ignore' });
      children.push(again);
      client = again;
      await sleep(warmup * 1000);
    } else if (!stateHolds(state, windowLog())) {
      throw new Error(`the window did not reach the state ${state}: ${windowLog().join('; ') || 'no change reported'}`);
    }
    await sleep(2000);
    const samples = [readProcess(client.pid)];
    for (let i = 0; i < seconds; i += 1) {
      await sleep(1000);
      samples.push(readProcess(client.pid));
    }
    const log = windowLog();
    if (!forced && !stateHolds(state, log)) throw new Error(`the window left the state ${state} during the measurement: ${log.join('; ')}`);
    return { scenario, state, seconds, cpu: cpuPercent(samples), memory: memoryMb(samples), window_log: log, forced_by_option: forced, foreground_pid: foreground, client_pid: client.pid };
  } finally {
    for (const child of children) child.kill();
    await sleep(500);
    rmSync(work, { recursive: true, force: true });
  }
}

async function main() {
  const args = process.argv.slice(2);
  const option = (name, fallback) => (args.includes(name) ? args[args.indexOf(name) + 1] : fallback);
  const seconds = Number(option('--seconds', 30));
  // --client-arg=--unfocused-fps=15 passes an option on to the client (repeat it for more)
  const clientArgs = args.filter((a) => a.startsWith('--client-arg=')).map((a) => a.slice('--client-arg='.length));
  // --engine-arg=--audio-driver --engine-arg=Dummy passes an argument to the engine itself, before the client's own (a run with a tune
  // that must not play through the speakers uses the dummy audio driver: the engine decodes and mixes, and sends nothing to a device)
  const engineArgs = args.filter((a) => a.startsWith('--engine-arg=')).map((a) => a.slice('--engine-arg='.length));
  const jobs = args.includes('--matrix')
    ? SCENARIOS.flatMap((scenario) => STATES.map((state) => ({ scenario, state })))
    : [{ scenario: option('--scenario', 'multi'), state: option('--state', 'focus') }];
  const results = [];
  for (const job of jobs) {
    const result = await measure({ ...job, seconds, clientArgs, engineArgs, project: option('--project', GODOT_DIR), app: option('--app', '') });
    results.push(result);
    if (!args.includes('--json')) {
      console.log(`${job.scenario.padEnd(7)} ${job.state.padEnd(9)} CPU ${result.cpu.mean.toFixed(1).padStart(5)} % mean, ${result.cpu.peak.toFixed(1).padStart(5)} % peak   memory ${result.memory.mean.toFixed(0)} MB mean, ${result.memory.peak.toFixed(0)} MB peak   window: ${result.forced_by_option ? 'forced by --force-focus=false (the system kept the foreground window)' : result.window_log.join('; ') || 'no change reported'}`);
    }
  }
  if (args.includes('--json')) console.log(JSON.stringify(results, null, 2));
  const out = option('--out', '');
  if (out) writeFileSync(out, JSON.stringify(results, null, 2));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await main();
