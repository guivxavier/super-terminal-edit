import { useState } from 'react'
import type { Node } from '../types'
import { Copy, Linux, Windows } from './Icons'

export function Tailnet({ nodes }: { nodes: Node[] }) {
  const [copied, setCopied] = useState<string | null>(null)
  const copy = async (ip: string) => {
    try { await navigator.clipboard.writeText(ip); setCopied(ip); window.setTimeout(() => setCopied(c => (c === ip ? null : c)), 1500) } catch { /* sem permissao: nada */ }
  }
  const list = [...nodes].sort((a, b) => Number(b.online) - Number(a.online) || a.host.localeCompare(b.host))
  return (
    <div className="nodes">
      {list.map(n => (
        <div key={n.ip + n.host} className={`node ${n.online ? '' : 'off'}`}>
          <span className="os" title={n.os}>{n.os === 'windows' ? <Windows /> : <Linux />}</span>
          <span className="host">{n.host}{n.self && <span className="tag">hub</span>}</span>
          <span className={`status ${n.online ? 'online' : 'offline'}`}><i />{n.online ? 'online' : 'offline'}</span>
          <button className="ip" onClick={() => copy(n.ip)} title="copy the IP">
            {copied === n.ip ? 'copied' : n.ip}<Copy />
          </button>
        </div>
      ))}
    </div>
  )
}
