#!/usr/bin/env elixir
#
# main.exs — turn a Google Maps directions link into two files:
#
#   <slug>.geojson   the trip, as GeoJSON (RFC 7946). Source of truth.
#   <slug>.html      the <article> section to paste into index.html.
#
# Usage
#   elixir main.exs "<maps link>" --name "Do Bambu às Águas"
#   elixir main.exs "<maps link>" --name "…" --slug my-trip --out ./trips
#   elixir main.exs "<maps link>" --name "…" --no-geocode
#   elixir main.exs --from-json trips/do-bambu-as-aguas.geojson
#
# The last form regenerates the HTML from an edited GeoJSON — that's the loop:
# generate once, fix the icons and city labels in JSON, regenerate.
#
# No API keys anywhere. Short-link expansion is a plain redirect, coordinates come
# out of the link itself, and city labels come from Nominatim, which asks only for
# a real User-Agent and no more than one request a second.
#
# A bare coordinate at either end of the link is dropped on purpose: that's wherever
# you happened to be, and the site supplies it at tap time. Bare coordinates in
# between are pins dropped to pull the route onto a road, so they stay, as vias.

Mix.install([{:jason, "~> 1.4"}])

defmodule Roadbook do
  @nominatim "https://nominatim.openstreetmap.org/reverse"
  @agent ~c"roadbook/1.0 (personal motorcycle route generator)"

  # Google's data blob: !1s<place id>!8m2!3d<lat>!4d<lon>, one group per named place.
  @place ~r/!1s(0x[0-9a-f]+:0x[0-9a-f]+)!8m2!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/
  @bare_coords ~r/^(-?\d+\.\d+),\s*(-?\d+\.\d+)$/

  # Cheap guesses, meant to be corrected in the GeoJSON afterwards.
  @icon_hints [
    {~r/caf[eé]|coffee|padaria/iu, "coffee"},
    {~r/posto|gas|shell|ipiranga|petrobras/iu, "fuel"},
    {~r/mirante|pico|morro|serra/iu, "mountain"},
    {~r/esta[cç][aã]o|ferrovi|trem/iu, "train-front"},
    {~r/fazenda|queijo|latic[ií]nio|atilatte/iu, "milk"},
    {~r/parque|bioparque|jardim|bosque/iu, "sprout"},
    {~r/bambu|floresta|mata|trilha/iu, "trees"},
    {~r/loja|empório|mercado|store/iu, "store"},
    {~r/cachoeira|represa|lago|rio/iu, "waves"},
    {~r/museu|igreja|capela|hist[oó]ric/iu, "landmark"},
    {~r/restaurante|pizza|almoço|bar\b/iu, "utensils"}
  ]

  def main(argv) do
    {opts, rest, _} =
      OptionParser.parse(argv,
        strict: [
          name: :string,
          slug: :string,
          blurb: :string,
          out: :string,
          geocode: :boolean,
          from_json: :string
        ]
      )

    out = Keyword.get(opts, :out, ".")
    File.mkdir_p!(out)

    case {Keyword.get(opts, :from_json), rest} do
      {nil, [url | _]} -> from_link(url, opts, out)
      {nil, []} -> abort("give me a Google Maps link, or --from-json <file>")
      {file, _} -> from_json(file, out)
    end
  end

  # ---------------------------------------------------------------- link mode

  defp from_link(url, opts, out) do
    start_http()

    final = expand(url)
    if final != url, do: log("expanded the short link")

    stops = parse_stops(final)
    if stops == [], do: abort("nothing between the start and the end of that link")

    log("#{length(stops)} points: #{stops |> Enum.map(&describe/1) |> Enum.join(", ")}")

    # Built from the parsed points, never the link itself: that starts and ends at
    # your door and carries Google's tracking parameters.
    source = source_link(stops)

    stops =
      if Keyword.get(opts, :geocode, true) do
        log("asking Nominatim for city and road labels (1 req/s)…")
        Enum.map(stops, &add_place/1)
      else
        stops
      end

    name = Keyword.get(opts, :name) || default_name(stops)
    slug = Keyword.get(opts, :slug) || slugify(name)

    trip = %{
      "slug" => slug,
      "name" => name,
      "blurb" => Keyword.get(opts, :blurb, ""),
      "source" => source,
      "generated" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    write(out, slug, trip, stops)
  end

  # ---------------------------------------------------------------- json mode

  defp from_json(file, out) do
    doc = file |> File.read!() |> Jason.decode!()
    trip = Map.fetch!(doc, "properties")
    stops = Enum.map(doc["features"], &feature_to_stop/1)
    write(out, trip["slug"], trip, stops)
  end

  defp feature_to_stop(%{"geometry" => %{"coordinates" => [lon, lat]}, "properties" => p}) do
    Map.merge(p, %{"lat" => lat, "lon" => lon})
  end

  # ---------------------------------------------------------------- expansion

  # Only short links need a round trip. A link that is already /maps/dir/ is
  # parsed straight away, which also means no network at all for that case.
  defp expand(url) do
    if URI.parse(url).host in ["maps.app.goo.gl", "goo.gl", "maps.google.com"] do
      expand(url, 5)
    else
      url
    end
  end

  defp expand(url, 0), do: url

  defp expand(url, hops) do
    case request(url, autoredirect: false) do
      {:redirect, location} -> expand(location, hops - 1)
      {:ok, _body} -> url
      {:error, reason} -> abort("could not follow the link: #{inspect(reason)}")
    end
  end

  # ---------------------------------------------------------------- parsing

  def parse_stops(url) do
    uri = URI.parse(url)
    segments = (uri.path || "") |> String.split("/", trim: true)

    data =
      Enum.find(segments, "", &String.starts_with?(&1, "data=")) <>
        "?" <> (uri.query || "")

    waypoints =
      segments
      |> Enum.drop_while(&(&1 != "dir"))
      |> Enum.drop(1)
      |> Enum.reject(&String.starts_with?(&1, "data="))
      |> Enum.map(&classify/1)
      |> drop_ends()

    coords =
      @place
      |> Regex.scan(data)
      |> Enum.map(fn [_, id, lat, lon] ->
        {id, String.to_float(lat), String.to_float(lon)}
      end)

    place(waypoints, coords)
  end

  defp classify(segment) do
    text = decode_segment(segment)

    case Regex.run(@bare_coords, text) do
      [_, lat, lon] -> {:via, String.to_float(lat), String.to_float(lon)}
      nil -> {:named, text}
    end
  end

  # Origin and destination are "where I was standing", not part of the trip.
  defp drop_ends(waypoints) do
    waypoints |> drop_bare_head() |> Enum.reverse() |> drop_bare_head() |> Enum.reverse()
  end

  defp drop_bare_head([{:via, _, _} | rest]), do: rest
  defp drop_bare_head(waypoints), do: waypoints

  # Google lists one coordinate group per named place, in order; vias carry their own
  # coordinates in the path. If the counts disagree the link shape has changed, so say
  # so rather than pairing blindly.
  defp place(waypoints, coords) do
    names = for {:named, name} <- waypoints, do: name

    if length(names) != length(coords) do
      abort("""
      #{length(names)} place names but #{length(coords)} coordinate groups.
      Google's link format probably changed. Names: #{Enum.join(names, ", ")}
      """)
    end

    {stops, []} = Enum.map_reduce(waypoints, coords, &to_stop/2)
    stops
  end

  # Google Maps gets coordinates, not the name: its text search can miss its own place
  # names ("Pico Do Lobo Guará" came back as not found), while coordinates always land and
  # Maps still labels them with the place.
  defp to_stop({:named, name}, [{id, lat, lon} | coords]) do
    stop = %{
      "city" => "",
      "gmaps_id" => id,
      "icon" => icon_for(name),
      "kind" => "stop",
      "lat" => lat,
      "lon" => lon,
      "name" => name,
      "search" => "#{lat},#{lon}"
    }

    {stop, coords}
  end

  defp to_stop({:via, lat, lon}, coords) do
    via = %{
      "city" => "",
      "icon" => "milestone",
      "kind" => "via",
      "lat" => lat,
      "lon" => lon,
      "name" => "Via",
      "search" => "#{lat},#{lon}"
    }

    {via, coords}
  end

  defp decode_segment(seg) do
    seg |> String.replace("+", " ") |> URI.decode()
  end

  defp describe(%{"kind" => "via", "search" => at}), do: "via #{at}"
  defp describe(%{"name" => name}), do: name

  # Same encoding as Google's own links: "+" for spaces, commas left bare.
  defp source_link(stops) do
    "https://www.google.com/maps/dir/" <>
      Enum.map_join(stops, "/", fn stop ->
        stop["search"] |> URI.encode_www_form() |> String.replace("%2C", ",")
      end)
  end

  defp icon_for(name) do
    Enum.find_value(@icon_hints, "map-pin", fn {re, icon} ->
      if Regex.match?(re, name), do: icon
    end)
  end

  # ---------------------------------------------------------------- geocoding

  # Street-level zoom: the address still names the city, and a via also gets its road.
  defp add_place(stop) do
    Process.sleep(1_100)

    query =
      URI.encode_query(%{
        "addressdetails" => 1,
        "format" => "jsonv2",
        "lat" => stop["lat"],
        "lon" => stop["lon"],
        "zoom" => 17
      })

    case request("#{@nominatim}?#{query}", []) do
      {:ok, body} -> label(stop, body |> Jason.decode!() |> Map.get("address", %{}))
      _ -> stop
    end
  end

  defp label(%{"kind" => "via"} = via, address) do
    %{via | "city" => city(address), "name" => road(address, via["name"])}
  end

  defp label(stop, address), do: %{stop | "city" => city(address)}

  defp city(address) do
    ["city", "town", "village", "municipality", "county"]
    |> Enum.find_value("", &Map.get(address, &1))
  end

  # Highways come back as "SP-095;SP-360" when two share the asphalt.
  defp road(%{"road" => road}, _fallback), do: String.replace(road, ";", " / ")
  defp road(_address, fallback), do: fallback

  # ---------------------------------------------------------------- output

  defp write(out, slug, trip, stops) do
    geojson = Path.join(out, "#{slug}.geojson")
    html = Path.join(out, "#{slug}.html")

    File.write!(geojson, Jason.encode!(to_geojson(trip, stops), pretty: true) <> "\n")
    File.write!(html, to_html(trip, stops))

    log("""

    wrote #{geojson}
    wrote #{html}

    Next: paste the <article> into index.html, then fix the icons and any city
    label that came back wrong. Edit the GeoJSON and re-run with --from-json to
    rebuild the HTML from it.
    """)
  end

  # A FeatureCollection of Points. The route line is not stored: the page asks
  # OSRM for it at load time, and that keeps this file about the places.
  # "properties" at the top level is a foreign member, which RFC 7946 allows.
  defp to_geojson(trip, stops) do
    %{
      "type" => "FeatureCollection",
      "properties" => trip,
      "features" =>
        Enum.map(stops, fn s ->
          %{
            "type" => "Feature",
            "geometry" => %{"type" => "Point", "coordinates" => [s["lon"], s["lat"]]},
            "properties" =>
              Map.take(s, ~w(city gmaps_id icon kind links name note photo search))
          }
        end)
    }
  end

  # The rows carry their full indentation: an interpolated string only gets the outer
  # template's indent on its first line, so the rest would land four columns short.
  defp to_html(trip, stops) do
    me = fn where ->
      """
              <li class="me"><span class="pin"><i data-lucide="crosshair"></i></span>
                #{name_html("Your location", where)}</li>
      """
      |> String.trim_trailing()
    end

    rows =
      Enum.map_join(stops, "\n\n", fn s ->
        """
                <li#{li_attrs(s)}>
                  <span class="pin"><i data-lucide="#{s["icon"]}"></i></span>
                  #{name_html(esc(s["name"]), esc(s["city"]))}</li>
        """
        |> String.trim_trailing()
      end)

    """
    <article class="route" id="#{trip["slug"]}" data-route>
      <header>
        <h2>#{esc(trip["name"])}</h2>
        <span class="stat" data-distance aria-live="polite"><i data-lucide="route"></i>measuring…</span>
        <span class="stat" data-duration hidden><i data-lucide="clock-4"></i>—</span>
      </header>

      <div class="body">
        <div class="map"></div>

        <div class="side">
          <p class="blurb">#{trip["blurb"] |> esc() |> wrap()}</p>

          <ol class="stops">
    #{me.("wherever you set off")}

    #{rows}

    #{me.("back to the same spot")}
          </ol>

          <div class="actions">
            <a role="button" href="#" target="_blank" rel="noopener" data-open>
              <i data-lucide="navigation"></i>Open in Google Maps</a>
            <button class="secondary outline" data-gpx disabled><i data-lucide="download"></i>Download GPX</button>
          </div>

          <p class="notice" role="status"></p>
        </div>
      </div>
    </article>
    """
  end

  # ---------------------------------------------------------------- plumbing

  defp start_http do
    :inets.start()
    :ssl.start()
  end

  defp request(url, opts) do
    headers = [{~c"user-agent", @agent}]

    # Verify the certificate chain. Without this :httpc happily talks to anyone.
    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    http_opts = [timeout: 15_000, ssl: ssl] ++ Keyword.take(opts, [:autoredirect])

    case :httpc.request(:get, {String.to_charlist(url), headers}, http_opts, body_format: :binary) do
      {:ok, {{_, status, _}, resp_headers, body}} when status in 200..299 ->
        _ = resp_headers
        {:ok, body}

      {:ok, {{_, status, _}, resp_headers, _}} when status in 300..399 ->
        location =
          Enum.find_value(resp_headers, fn {k, v} ->
            if to_string(k) |> String.downcase() == "location", do: to_string(v)
          end)

        if location, do: {:redirect, location}, else: {:error, {:no_location, status}}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Decompose, then drop the combining marks by codepoint. Doing this with a
  # regex character class chews through the bytes of multi-byte characters.
  def slugify(text) do
    text
    |> String.normalize(:nfd)
    |> String.to_charlist()
    |> Enum.reject(&(&1 in 0x0300..0x036F))
    |> List.to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp name_html(name, place),
    do: ~s(<span><span class="name">#{name}</span><small>#{place}</small></span>)

  # Wrapped like the hand-written trips: the first line follows the tag, the rest line up
  # under it, about 73 characters of text per line.
  defp wrap(text) do
    text
    |> String.split()
    |> Enum.reduce([], &fill_line/2)
    |> Enum.reverse()
    |> Enum.join("\n         ")
  end

  defp fill_line(word, []), do: [word]

  defp fill_line(word, [line | lines]) do
    case String.length(line) + 1 + String.length(word) do
      fits when fits <= 73 -> [line <> " " <> word | lines]
      _overflow -> [word, line | lines]
    end
  end

  defp li_attrs(s) do
    ~s(#{li_class(s)} data-lat="#{s["lat"]}" data-lon="#{s["lon"]}") <>
      ~s( data-search="#{esc(s["search"])}")
  end

  defp li_class(%{"kind" => "via"}), do: ~s( class="via")
  defp li_class(_stop), do: ""

  # Named stops only: a via is a road, not somewhere you'd call the trip after.
  defp default_name(stops) do
    case for(%{"kind" => "stop", "name" => name} <- stops, do: name) do
      [] -> "Untitled ride"
      [only] -> only
      [first | rest] -> "#{first} → #{List.last(rest)}"
    end
  end

  defp esc(nil), do: ""

  defp esc(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp log(message), do: IO.puts(:stderr, message)

  defp abort(message) do
    IO.puts(:stderr, "\n#{message}\n")
    System.halt(1)
  end
end

Roadbook.main(System.argv())
