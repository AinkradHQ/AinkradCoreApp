// A worker (own network stack for fetch) trying to reach the canary.
fetch("http://127.0.0.1:__PORT__/worker-fetch").then(() => postMessage("reached"), () => postMessage("blocked"));
