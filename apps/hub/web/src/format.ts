export const bytes = (b: number) => (b >= 1073741824 ? `${(b / 1073741824).toFixed(1)} GB` : `${Math.round(b / 1048576)} MB`)
export const level = (v: number) => (v >= 85 ? 'hi' : v >= 60 ? 'mid' : 'lo')
export const tempLevel = (t: number) => (t >= 85 ? 'hi' : t >= 70 ? 'mid' : 'lo')
export const uptime = (h: number) => (h >= 48 ? `${Math.floor(h / 24)} days` : h >= 1 ? `${h} h` : 'just started')
export const ago = (ms: number) => {
  const s = Math.max(0, Math.round(ms / 1000))
  return s < 3 ? 'just now' : s < 60 ? `${s} s ago` : `${Math.floor(s / 60)} min ago`
}
export const isLaptop = (name: string) => /lap|book|note/i.test(name)
// "AMD Ryzen 5 5600H with Radeon Graphics" -> "Ryzen 5 5600H"; "NVIDIA GeForce RTX 2060 SUPER" -> "RTX 2060 SUPER"
export const shortCpu = (s: string) => s.replace(/^(AMD|Intel\(R\)|Intel)\s+/i, '').replace(/\s+with .*$/i, '').replace(/\s*(CPU|Processor)\b.*$/i, '').trim()
export const shortGpu = (s: string) => s.replace(/^(NVIDIA|AMD|Intel\(R\))\s+/i, '').replace(/^GeForce\s+/i, '').replace(/\(TM\)|\(R\)/g, '').replace(/\s+/g, ' ').trim()
