# Roadbook

Motorcycle day trips that start and end wherever you are, rendered from a single
HTML file. No API keys, no backend.

- **Style**: Pico CSS with its `--pico-*` variables rewritten into two themes —
  topographic sheet by day, highway sign by night.
- **Trips**: one `<article data-route>` each, with coordinates on the `<li>` elements.
  The script reads the page; there is no parallel list to keep in sync.
- **Script**: plain JavaScript. No framework — nothing here talks to a server.
- **Map**: OpenStreetMap in day mode, Esri Dark Gray Canvas at night. Neither needs a
  key; neither works over `file://`.
- **Routing**: the OSRM demo server, called from the browser.
- **Icons**: Lucide.
- **Theme**: follows the clock — dark from 18:00 to 06:00. Flipping the switch pins
  your choice in `localStorage`; the small "auto" link hands control back to the clock.
- **Button**: builds the Google Maps link at tap time, with your position at both ends.

Place names stay in Portuguese. Everything else is English.

## Publish on GitHub Pages

1. Create the `roadbook` repository. It has to be **public** — on the free plan Pages
   only builds from public repos.
2. Upload `index.html`, or drag it into **Add file → Upload files**.
3. **Settings → Pages → Build and deployment**: source `Deploy from a branch`,
   branch `main`, folder `/ (root)`. Save.
4. A minute or two later: `https://YOUR-USER.github.io/roadbook/`.

From the terminal:

```bash
git init && git add . && git commit -m "first trip"
git branch -M main
git remote add origin git@github.com:YOUR-USER/roadbook.git
git push -u origin main
```

To keep the source private, Cloudflare Pages and Netlify both deploy from a private
repo on their free tiers.

## Run it locally

```bash
python3 -m http.server 8000   # http://localhost:8000
```

Geolocation needs a secure context, so `localhost` or `https` work and `file://` does not.

## Add a trip

Copy the whole `<article class="route" data-route>`, change the `id`, the title, the
blurb and the stops. Each stop is an `<li>` carrying `data-lat`, `data-lon` and
`data-search` — the text Google Maps understands — plus a Lucide icon name in its pin.
The two `<li class="me">` elements are you; leave them alone.

When the list grows past a screen or two, that's the moment to move each `<article>`
into its own file and load it on demand — htmx would earn its place then, not before.

## Worth knowing

- A Google Maps link opened in a mobile **browser** takes three intermediate stops; the
  app takes nine. This trip has eight, so open it in the app.
- OpenStreetMap tiles come from volunteer-run servers. Their usage policy covers
  low-traffic personal pages, which this is.
- The OSRM demo server is public and unguaranteed. If it goes down the page draws
  straight lines between stops and says so, rather than showing a wrong number.
