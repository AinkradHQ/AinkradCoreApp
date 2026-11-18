// Runs the network and bridge probes of the hostile mockup and records the outcome in <body data-result>.
// "blocked" means the request failed (rule list or CSP); anything else is a failure the test reports.
(async () => {
  const base = "http://127.0.0.1:__PORT__";
  const r = {};
  document.body.dataset.violations = "0";
  document.addEventListener("securitypolicyviolation", () => {
    document.body.dataset.violations = String(Number(document.body.dataset.violations) + 1);
  });
  // CSP active? script-src has no 'unsafe-eval', so eval must throw; without the header it works.
  try { eval("1"); r.eval = "allowed"; } catch (e) { r.eval = "blocked"; }
  const blocked = (p) => p.then(() => "reached", () => "blocked");
  r.fetch = await blocked(fetch(base + "/fetch"));
  r.fetchNoCors = await blocked(fetch(base + "/fetch-nocors", { mode: "no-cors" }));
  r.fetchPackage = await blocked(fetch("mockup://package/local.json")); // CSP connect-src 'none'
  r.xhr = await new Promise((ok) => {
    const x = new XMLHttpRequest();
    x.onload = () => ok("reached");
    x.onerror = () => ok("blocked");
    try { x.open("GET", base + "/xhr"); x.send(); } catch (e) { ok("blocked"); }
  });
  r.ws = await new Promise((ok) => {
    try {
      const w = new WebSocket("ws://127.0.0.1:__PORT__/ws");
      w.onopen = () => ok("reached");
      w.onerror = () => ok("blocked");
      w.onclose = () => ok("blocked");
    } catch (e) { ok("blocked"); }
  });
  r.beacon = navigator.sendBeacon ? (navigator.sendBeacon(base + "/beacon", "x") ? "queued" : "blocked") : "blocked";
  r.img = await new Promise((ok) => {
    const i = new Image();
    i.onload = () => ok("reached");
    i.onerror = () => ok("blocked");
    i.src = base + "/img2";
  });
  r.eventSource = await new Promise((ok) => {
    try {
      const e = new EventSource(base + "/eventsource");
      e.onopen = () => ok("reached");
      e.onerror = () => { e.close(); ok("blocked"); };
    } catch (e) { ok("blocked"); }
  });
  r.worker = await new Promise((ok) => {
    try {
      const w = new Worker("worker.js");
      w.onmessage = (m) => ok(m.data);
      w.onerror = () => ok("blocked");
      setTimeout(() => ok("timeout"), 3000);
    } catch (e) { ok("blocked"); }
  });
  r.fileFetch = await blocked(fetch("file:///etc/hosts"));
  r.otherFetch = await blocked(fetch("mockup://other/x.json"));
  r.dotsFetch = await blocked(fetch("mockup://package/%2e%2e/x"));
  // WebRTC: the constructors must be gone; if one survived, aim a TURN-over-TCP probe at the canary.
  r.rtc = typeof RTCPeerConnection;
  r.webkitRtc = typeof webkitRTCPeerConnection;
  r.rtcData = typeof RTCDataChannel;
  const Rtc = window.RTCPeerConnection || window.webkitRTCPeerConnection;
  if (Rtc) {
    try {
      const pc = new Rtc({ iceServers: [{ urls: "turn:127.0.0.1:__PORT__?transport=tcp", username: "a", credential: "b" }] });
      pc.createDataChannel("x");
      pc.setLocalDescription(await pc.createOffer());
    } catch (e) {}
  }
  // <base href> must not apply (CSP base-uri 'none'; without CSP the rules block the load): a relative image tests it.
  const base1 = document.createElement("base");
  base1.href = base + "/base/";
  document.head.appendChild(base1);
  const rel = new Image();
  rel.src = "relative.png";
  document.getElementById("pinger").click();
  // window.open('about:blank') + document.write must get no window at all.
  let w = null;
  try { w = window.open("about:blank"); if (w) w.document.write("<img src='" + base + "/write'>"); } catch (e) {}
  r.openBlank = w ? "opened" : "none";
  await new Promise((ok) => setTimeout(ok, 300));
  base1.remove();
  r.webkit = typeof window.webkit === "undefined" ? "none" : Object.keys(window.webkit.messageHandlers || {}).join(",") || "empty";
  r.handlers = (window.webkit && window.webkit.messageHandlers && Object.keys(window.webkit.messageHandlers).length) || 0;
  // Navigation attempts: none may leave the package.
  try { window.open(base + "/open"); } catch (e) {}
  document.getElementById("out").click();
  document.getElementById("blank").click();
  document.getElementById("up").click();
  try { document.getElementById("form").submit(); } catch (e) {}
  try { location.href = base + "/location"; } catch (e) {}
  document.body.dataset.result = JSON.stringify(r);
  document.body.dataset.done = "1";
})();
