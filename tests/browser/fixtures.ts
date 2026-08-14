import http from 'node:http'
import type { AddressInfo } from 'node:net'

export interface FixtureServer {
  baseUrl: string
  url: (path: string) => string
  close: () => Promise<void>
}

const FORM_PAGE = `<!doctype html><html><head><meta charset="utf-8"><title>Form</title></head>
<body>
  <h1>Form page</h1>
  <form>
    <label for="username">Username</label>
    <input id="username" name="username" type="text">
    <label for="password">Password</label>
    <input id="password" name="password" type="password">
    <label for="choice">Choice</label>
    <select id="choice" name="choice">
      <option value="one">One</option>
      <option value="two">Two</option>
      <option value="three">Three</option>
    </select>
    <label for="agree">I agree</label>
    <input id="agree" name="agree" type="checkbox">
    <button id="submit" type="button">Submit</button>
  </form>
  <a id="to-b" href="/nav-b">Go to B</a>
</body></html>`

const NAV_A = `<!doctype html><html><head><meta charset="utf-8"><title>Page A</title></head>
<body><h1>Page A</h1><a id="go" href="/nav-b">Go to B</a><button id="btn-a">Button A</button></body></html>`

const NAV_B = `<!doctype html><html><head><meta charset="utf-8"><title>Page B</title></head>
<body><h1>Page B</h1><p id="b-marker">You are on B</p></body></html>`

const FRAME_PAGE = `<!doctype html><html><head><meta charset="utf-8"><title>Frame</title></head>
<body><h2 id="frame-heading">Inside frame</h2><button id="frame-btn">Frame button</button></body></html>`

const FRAMES_PAGE = `<!doctype html><html><head><meta charset="utf-8"><title>Frames</title></head>
<body>
  <h1>Frames page</h1>
  <iframe id="the-frame" src="/frame.html" title="Child frame"></iframe>
  <div id="shadow-host"></div>
  <script>
    var host = document.getElementById('shadow-host')
    var root = host.attachShadow({ mode: 'open' })
    var btn = document.createElement('button')
    btn.textContent = 'Shadow button'
    root.appendChild(btn)
  </script>
</body></html>`

const SCROLL_PAGE = `<!doctype html><html><head><meta charset="utf-8"><title>Scroll</title></head>
<body>
  <h1 id="top">TOP MARKER</h1>
  <div style="height: 3000px"></div>
  <h2 id="bottom">BOTTOM MARKER</h2>
</body></html>`

const UPLOAD_PAGE = `<!doctype html><html><head><meta charset="utf-8"><title>Upload</title></head>
<body><h1>Upload page</h1><label for="file">Choose file</label>
<input id="file" type="file" aria-label="file upload"></body></html>`

const OCR_ONLY_PAGE = `<!doctype html><html><head><meta charset="utf-8"><title>OCR only</title>
<style>body{margin:0}#visual{position:absolute;left:20px;top:20px;width:120px;height:40px}</style></head>
<body><button id="visual" aria-hidden="true">Visual Submit</button><p id="status"></p>
<script>document.getElementById('visual').addEventListener('click',function(){document.getElementById('status').textContent='visual control clicked'})</script>
</body></html>`

const PAGES: Record<string, string> = {
  '/': FORM_PAGE,
  '/nav-a': NAV_A,
  '/nav-b': NAV_B,
  '/frame.html': FRAME_PAGE,
  '/frames.html': FRAMES_PAGE,
  '/scroll.html': SCROLL_PAGE,
  '/upload.html': UPLOAD_PAGE,
  '/ocr-only.html': OCR_ONLY_PAGE,
}

export async function startFixtureServer(): Promise<FixtureServer> {
  const server = http.createServer((req, res) => {
    const pathname = new URL(req.url ?? '/', 'http://localhost').pathname
    const body = PAGES[pathname]
    if (body === undefined) {
      res.writeHead(404, { 'content-type': 'text/plain' })
      res.end('not found')
      return
    }
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' })
    res.end(body)
  })
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
  const { port } = server.address() as AddressInfo
  const baseUrl = `http://127.0.0.1:${port}`
  return {
    baseUrl,
    url: (p) => `${baseUrl}${p}`,
    close: () =>
      new Promise<void>((resolve, reject) => {
        server.close((err) => (err ? reject(err) : resolve()))
      }),
  }
}
