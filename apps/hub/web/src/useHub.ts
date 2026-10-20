import { useEffect, useRef, useState } from 'react'
import type { State } from './types'

const EVERY = 2000
const KEEP = 90 // pontos de historico (3 min)

export interface Hub {
  state: State | null
  error: string | null
  lastOk: number | null
  // historico do lado do browser (o hub so guarda o do CPU): por PC
  gpuHist: Record<string, number[]>
  ramHist: Record<string, number[]>
}

// Pergunta ao hub a cada 2 s. Um pedido de cada vez; erros nao apagam o ultimo estado bom.
export function useHub(): Hub {
  const [hub, setHub] = useState<Hub>({ state: null, error: null, lastOk: null, gpuHist: {}, ramHist: {} })
  const hist = useRef({ gpu: {} as Record<string, number[]>, ram: {} as Record<string, number[]> })

  useEffect(() => {
    let alive = true
    let timer: number | undefined
    const push = (m: Record<string, number[]>, k: string, v: number) => {
      const a = (m[k] ??= [])
      a.push(v)
      if (a.length > KEEP) a.splice(0, a.length - KEEP)
    }
    const tick = async () => {
      const ctl = new AbortController()
      const to = window.setTimeout(() => ctl.abort(), 6000)
      try {
        const r = await fetch('/api/state', { cache: 'no-store', signal: ctl.signal })
        if (!r.ok) throw new Error(`hub answered ${r.status}`)
        const s = (await r.json()) as State
        for (const p of s.pcs ?? []) {
          if (!p.d) continue
          if (p.d.gpu != null) push(hist.current.gpu, p.name, p.d.gpu)
          if (p.d.ramTotal) push(hist.current.ram, p.name, (100 * p.d.ramUsed) / p.d.ramTotal)
        }
        if (alive) setHub({ state: s, error: null, lastOk: Date.now(), gpuHist: { ...hist.current.gpu }, ramHist: { ...hist.current.ram } })
      } catch (e) {
        if (alive) setHub(h => ({ ...h, error: e instanceof Error && e.name !== 'AbortError' ? e.message : 'hub not answering' }))
      } finally {
        window.clearTimeout(to)
        if (alive) timer = window.setTimeout(tick, document.hidden ? EVERY * 3 : EVERY)
      }
    }
    tick()
    return () => { alive = false; window.clearTimeout(timer) }
  }, [])

  return hub
}

// "agora" que avanca sozinho (para "updated 3 s ago")
export function useNow(every = 1000) {
  const [now, setNow] = useState(Date.now())
  useEffect(() => { const t = window.setInterval(() => setNow(Date.now()), every); return () => window.clearInterval(t) }, [every])
  return now
}
