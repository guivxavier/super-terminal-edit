// O que o hub.ps1 devolve em /api/state (os amostradores st-monitor-sample.ps1 + tailscale status)
export interface Proc { n: string; c: number; m: number }
export interface Sample {
  host: string
  cpu: number
  gpu: number | null
  temp: number | null
  ramUsed: number
  ramTotal: number
  cpuName: string
  gpuName: string | null
  up: number // horas
  procs: Proc[]
}
export interface Pc { name: string; self: boolean; err: string | null; d: Sample | null; hist: number[]; stale: boolean }
export interface Node { host: string; os: string; online: boolean; ip: string; self: boolean; seen: string }
export interface Theme { [k: string]: string }
export interface State { time: string; pcs: Pc[]; tailnet: { name: string; nodes: Node[] } | null; theme: Theme | null }
