const page = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Sites Worker</title>
    <style>
      :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
      html { -webkit-font-smoothing: antialiased; -moz-osx-font-smoothing: grayscale; }
      body { display: grid; min-height: 100vh; margin: 0; place-items: center; }
      main { max-width: 36rem; padding: 2rem; text-align: center; }
      button { cursor: pointer; font: inherit; padding: .7rem 1rem; }
    </style>
  </head>
  <body>
    <main>
      <h1>Sites Worker ESM starter</h1>
      <p>This page needs no framework build.</p>
      <button id="counter" type="button">Clicks: 0</button>
    </main>
    <script>
      const button = document.querySelector("#counter");
      let count = 0;
      button.addEventListener("click", () => {
        count += 1;
        button.textContent = "Clicks: " + count;
      });
    </script>
  </body>
</html>`;

export default {
  async fetch(request, env, ctx) {
    void env;
    void ctx;

    if (new URL(request.url).pathname !== "/") {
      return new Response("Not found", { status: 404 });
    }

    return new Response(page, {
      headers: { "content-type": "text/html; charset=utf-8" },
    });
  },
};
