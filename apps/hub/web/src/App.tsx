import { useEffect } from 'react'
import { useHub, useNow } from './useHub'
import { ago } from './format'
import { PcCard } from './components/PcCard'
import { Tailnet } from './components/Tailnet'
import { Lock, Warn } from './components/Icons'

const THEME_KEYS = ['bg', 'dark', 'surf', 'surf2', 'sel', 'line', 'comment', 'fg', 'white', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan']

export default function App() {
  const hub = useHub()
  const now = useNow()
  const s = hub.state

  // as cores do comando theme (theme.json do PC que serve o hub)
  useEffect(() => {
    const t = s?.theme
    if (!t) return
    for (const k of THEME_KEYS) if (/^#[0-9a-f]{6}$/i.test(t[k] ?? '')) document.documentElement.style.setProperty(`--${k}`, t[k])
    if (t.bg) document.querySelector('meta[name=theme-color]')?.setAttribute('content', t.bg)
  }, [s?.theme])

  const nodes = s?.tailnet?.nodes ?? []
  const pcs = s?.pcs ?? []
  const pcsOn = pcs.filter(p => p.d && !p.stale).length
  const lost = !!hub.error && !!hub.lastOk && now - hub.lastOk > 6000
  useEffect(() => { document.title = s ? `SuperTerminal Hub · ${pcsOn}/${pcs.length}` : 'SuperTerminal Hub' }, [s, pcsOn, pcs.length])

  return (
    <div className="page">
      <header className="top">
        <div className="brand">
          <span className="logo">&gt;_</span>
          <div>
            <h1>SuperTerminal <span>Hub</span></h1>
            <p className="muted">{s?.tailnet?.name ?? 'your tailnet'}</p>
          </div>
        </div>
        <div className="top-right">
          {s && <span className="pill">{pcsOn}/{pcs.length} PCs · {nodes.filter(n => n.online).length}/{nodes.length} devices</span>}
          <span className={`live ${lost || (hub.error && !hub.lastOk) ? 'down' : ''}`}><i />{hub.lastOk ? (lost ? `no answer · ${ago(now - hub.lastOk)}` : `live · ${ago(now - hub.lastOk)}`) : hub.error ? 'no answer' : 'connecting'}</span>
        </div>
      </header>

      {lost && <div className="banner"><Warn /> The hub stopped answering. Showing the last data from {ago(now - (hub.lastOk ?? now))}.</div>}

      <section>
        <h2>PCs</h2>
        {!s ? (
          <div className="grid">{[0, 1].map(i => <div key={i} className="card skeleton" />)}</div>
        ) : (
          <div className="grid">
            {pcs.map(p => <PcCard key={p.name} pc={p} gpuHist={hub.gpuHist[p.name] ?? []} ramHist={hub.ramHist[p.name] ?? []} />)}
          </div>
        )}
      </section>

      <section>
        <h2>Tailnet</h2>
        {s && <Tailnet nodes={nodes} />}
      </section>

      <footer className="muted">
        <Lock /> only reachable inside your tailnet · {location.protocol === 'https:' ? 'https' : 'http'} · updates every 2 s
      </footer>
    </div>
  )
}
