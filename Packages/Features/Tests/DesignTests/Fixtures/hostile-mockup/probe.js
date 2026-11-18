// Runs the network and bridge probes of the hostile mockup and records the outcome in <body data-result>.
// "blocked" means the request failed (rule list or CSP); anything else is a failure the test reports.
(async () => {
  const base = "http://127.0.0.1:__PORT__";
  const r = {};
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
