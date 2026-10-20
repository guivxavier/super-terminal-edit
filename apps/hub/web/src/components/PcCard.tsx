import { useState } from 'react'
import type { Pc } from '../types'
import { bytes, isLaptop, level, shortCpu, shortGpu, tempLevel, uptime } from '../format'
import { Ring, Spark } from './Charts'
import { Clock, Desktop, Laptop, Thermo, Warn } from './Icons'

type Sort = 'cpu' | 'mem'

export function PcCard({ pc, gpuHist, ramHist }: { pc: Pc; gpuHist: number[]; ramHist: number[] }) {
  const [sort, setSort] = useState<Sort>('cpu')
  const d = pc.d
  const online = !!d && !pc.stale
  const Icon = isLaptop(pc.name) ? Laptop : Desktop
  const status = online ? 'online' : pc.err ? (pc.err === 'offline' ? 'offline' : 'problem') : 'connecting'

  return (
    <article className={`card ${pc.self ? 'is-hub' : ''} ${status}`}>
      <header className="card-head">
        <div className="pc-name">
          <span className="pc-icon"><Icon size={22} /></span>
          <div>
            <h3>{pc.name}</h3>
            {d && <p className="hw">{shortCpu(d.cpuName)}{d.gpuName ? ` · ${shortGpu(d.gpuName)}` : ''}</p>}
          </div>
        </div>
        <div className="badges">
          {pc.self && <span className="tag">hub</span>}
          <span className={`status ${status}`}><i />{status}</span>
        </div>
      </header>

      {!d ? (
        <div className="empty">
          {pc.err ? (
            <><Warn /><div><b>{pc.err === 'offline' ? 'This PC is offline' : 'No data from this PC'}</b><p>{pc.err === 'offline' ? `wake it with: wake ${pc.name}` : pc.err}</p></div></>
          ) : (
            <><span className="spinner" /><div><b>Connecting…</b><p>first sample takes a few seconds</p></div></>
          )}
        </div>
      ) : (
        <>
          <div className="rings">
            <Ring value={d.cpu} label="CPU" />
            <Ring value={d.gpu} label="GPU" />
            <Ring value={d.ramTotal ? (100 * d.ramUsed) / d.ramTotal : 0} label="RAM" detail={`${bytes(d.ramUsed)} / ${bytes(d.ramTotal)}`} />
          </div>

          <div className="facts">
            <span className={d.temp != null ? `temp ${tempLevel(d.temp)}` : 'muted'}><Thermo />{d.temp != null ? `${Math.round(d.temp)}°C` : 'no sensor'}</span>
            <span><Clock />up {uptime(d.up)}</span>
          </div>

          <Spark series={[
            { name: 'CPU', cls: 's-cpu', data: pc.hist },
            ...(gpuHist.length ? [{ name: 'GPU', cls: 's-gpu', data: gpuHist }] : []),
            { name: 'RAM', cls: 's-ram', data: ramHist },
          ]} />

          <table className="procs">
            <thead>
              <tr>
                <th>process</th>
                <th className={`num sortable ${sort === 'cpu' ? 'on' : ''}`} onClick={() => setSort('cpu')}>cpu</th>
                <th className={`num sortable ${sort === 'mem' ? 'on' : ''}`} onClick={() => setSort('mem')}>memory</th>
              </tr>
            </thead>
            <tbody>
              {[...d.procs].sort((a, b) => (sort === 'cpu' ? b.c - a.c || b.m - a.m : b.m - a.m)).slice(0, 6).map(p => (
                <tr key={p.n}>
                  <td title={p.n}>{p.n}</td>
                  <td className={`num ${level(p.c * 2)}`}>{p.c.toFixed(1)}%</td>
                  <td className="num muted">{bytes(p.m)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </article>
  )
}
