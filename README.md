# Caderno de estradas

Motorcycle day trips that start and end wherever you are, rendered from a plain
HTML file. No API keys, no backend.

- **Traçado**: servidor de demonstração do OSRM, chamado pelo navegador.
- **Mapa**: tiles do OpenStreetMap — funcionam em `http`/`https`, não em `file://`.
- **Botão**: monta o link do Google Maps na hora, com a sua posição no começo e no fim.

## Publicar no GitHub Pages

1. Crie o repositório `caderno-de-estradas`. Precisa ser **público**: no plano
   gratuito o Pages só publica a partir de repositório público.
2. Suba o `index.html` — pelo site dá para arrastar em **Add file → Upload files**.
3. **Settings → Pages → Build and deployment**: source `Deploy from a branch`,
   branch `main`, pasta `/ (root)`. Salve.
4. Em um ou dois minutos: `https://SEU-USUARIO.github.io/caderno-de-estradas/`.

Pelo terminal:

```bash
git init && git add . && git commit -m "primeira rota"
git branch -M main
git remote add origin git@github.com:SEU-USUARIO/caderno-de-estradas.git
git push -u origin main
```

Para manter o código privado, Cloudflare Pages e Netlify publicam de repositório
privado no plano gratuito.

## Ver antes de publicar

```bash
python3 -m http.server 8000   # http://localhost:8000
```

A localização do navegador exige contexto seguro, então `localhost` ou `https`
funcionam, `file://` não.

## Adicionar uma rota

Edite o array `ROTAS` no topo do `<script>`. Cada parada precisa de `nome`,
`cidade`, `lat`, `lon` e, de preferência, `busca` — o texto que o Google Maps
entende. Liste só as paradas do caminho: o começo e o fim são a sua localização.

## Limites que valem lembrar

- Um link do Google Maps aberto no **navegador** do celular aceita três paradas
  intermediárias; no aplicativo, nove. A rota fechada tem oito, então abra pelo app.
- Os tiles do OpenStreetMap são de servidores mantidos por voluntários. A política
  de uso cobre páginas pessoais de baixo tráfego, que é o caso aqui.
- O OSRM de demonstração é público e sem garantia. Se ele cair, a página liga as
  paradas em linha reta e avisa, em vez de mostrar número errado.
