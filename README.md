# Roadbook

Motorcycle day trips that start and end wherever you are, rendered from a single
HTML file. No API keys, no backend.

- **Style**: Pico CSS with its `--pico-*` variables rewritten into two themes —
  topographic sheet by day, highway sign by night.
- **Trips**: one `<article data-route>` each, with coordinates on the `<li>` elements.
  The script reads the page; there is no parallel list to keep in sync.
- **Page script**: plain JavaScript. No framework — nothing here talks to a server.
- **Map**: OpenFreeMap vector basemaps, drawn by MapLibre GL inside Leaflet through
  `maplibre-gl-leaflet`. Liberty by day; Fiord at night, repainted layer by layer from
  the night palette so the map matches the card around it. No key.
- **Route**: navigation blue in both themes, on a wider edge in the page colour. The
  theme's accent goes on the Google Maps button instead.
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

`main.exs` turns a Google Maps directions link into the trip's `<article>`. It needs
Elixir; it fetches its one dependency on first run.

```bash
elixir main.exs "https://maps.app.goo.gl/…" --name "Pico do Lobo Guará"
```

It writes `<slug>.geojson` and `<slug>.html` (`--out DIR` puts them elsewhere). Paste the
`<article>` into `index.html`, before the footer. To fix an icon, a city label or the
blurb, edit the GeoJSON and rebuild the HTML from it:

```bash
elixir main.exs --from-json pico-do-lobo-guara.geojson
```

How it reads the link:

- Named places become stops, with a Lucide icon guessed from the name and the city
  from Nominatim (one request a second, no key).
- A bare coordinate at either end is wherever you were when you drew the route. It's
  dropped: the site puts your live position there at tap time.
- Bare coordinates in between are pins dropped to pull the route onto a road. They stay
  as vias, `<li class="via">`, named after the road under them.
- The GeoJSON's `source` link is rebuilt from the kept points, so it never carries your
  home coordinates or Google's tracking parameters.

By hand: each stop is an `<li>` carrying `data-lat`, `data-lon` and `data-search` — what
Google Maps looks up — plus a Lucide icon name in its pin. Coordinates in `data-search`
always land, and Maps still labels them with the place; a name works only if Maps' own
search finds it (it can't find "Pico Do Lobo Guará", so that route came up empty). The
two `<li class="me">` elements are you; leave them alone.

When the list grows past a screen or two, that's the moment to move each `<article>`
into its own file and load it on demand — htmx would earn its place then, not before.

## Worth knowing

- A Google Maps link opened in a mobile **browser** takes three intermediate stops; the
  app takes nine. Do Bambu às Águas has eight and Pico do Lobo Guará five, so open them
  in the app. Maps treats every via as a stop, with its own arrival prompt.
- OpenFreeMap's public instance is free, with no keys and no request limits. Styles,
  tiles and fonts all come from it, as does the attribution it requires.
- MapLibre adds about 275 KB (gzipped) of JavaScript to the page.
- The OSRM demo server is public and unguaranteed. If it goes down the page draws
  straight lines between stops and says so, rather than showing a wrong number.
