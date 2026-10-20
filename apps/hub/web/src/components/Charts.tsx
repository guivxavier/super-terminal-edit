import { level } from '../format'

// Anel de percentagem (CPU / GPU / RAM)
export function Ring({ value, label, detail }: { value: number | null; label: string; detail?: string }) {
  const r = 30, c = 2 * Math.PI * r
  const v = value == null ? 0 : Math.max(0, Math.min(100, value))
  return (
    <div className={`ring ${value == null ? 'na' : level(v)}`}>
      <svg viewBox="0 0 76 76" aria-hidden>
        <circle className="track" cx="38" cy="38" r={r} />
        <circle className="arc" cx="38" cy="38" r={r} strokeDasharray={c} strokeDashoffset={c * (1 - v / 100)} transform="rotate(-90 38 38)" />
      </svg>
      <div className="ring-in">
        <b>{value == null ? '–' : Math.round(v)}<small>{value == null ? '' : '%'}</small></b>
      </div>
      <div className="ring-lbl">{label}</div>
      {detail && <div className="ring-detail">{detail}</div>}
    </div>
  )
}

// Grafico de area do historico (0..100), da direita para a esquerda; varias series
export function Spark({ series, points = 90 }: { series: { data: number[]; cls: string; name: string }[]; points?: number }) {
  const w = 300, h = 56
  const step = w / (points - 1)
  const path = (d: number[]) => {
    const n = d.length
    return d.map((v, i) => `${(w - (n - 1 - i) * step).toFixed(1)},${(h - 2 - (Math.min(100, v) / 100) * (h - 6)).toFixed(1)}`)
  }
  return (
    <div className="spark">
      <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" aria-hidden>
        {[25, 50, 75].map(g => <line key={g} className="grid" x1="0" x2={w} y1={h - 2 - (g / 100) * (h - 6)} y2={h - 2 - (g / 100) * (h - 6)} />)}
        {series.map(s => {
          if (s.data.length < 2) return null
          const pts = path(s.data)
          const first = pts[0].split(',')[0]
          return (
            <g key={s.name} className={s.cls}>
              <polygon className="area" points={`${first},${h} ${pts.join(' ')} ${w},${h}`} />
              <polyline className="line" points={pts.join(' ')} vectorEffect="non-scaling-stroke" />
            </g>
          )
        })}
      </svg>
      <div className="legend">
        {series.map(s => <span key={s.name} className={s.cls}><i />{s.name}</span>)}
        <span className="muted">last {Math.round((points * 2) / 60)} min</span>
      </div>
    </div>
  )
}
