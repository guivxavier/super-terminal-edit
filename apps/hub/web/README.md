# Hub page (React)

Source of `apps/hub/hub.html`. The build is a single HTML file (JS and CSS inlined), so the hub server
(`apps/hub/hub.ps1`) serves it as it is and nobody needs Node to install SuperTerminal.

```
npm install
npm run dev      # live reload; /api goes to the running hub (HUB=https://hub.<domain> to pick another)
npm run build    # then copy dist/index.html to ../hub.html
```
