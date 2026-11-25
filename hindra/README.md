# MacSync's website on Hindra

One container serves the website and counts installs. It's separate from the hindra.studio app, so
neither can break the other. Nothing here is deployed yet.

## 1. DNS

Point `macsync.hindra.studio` at the Coolify server, the same way `hindra.studio` is.

## 2. Coolify: a new application

| Setting | Value |
| --- | --- |
| Repository, branch | `https://github.com/onlymoein/macsync`, `main` |
| Build Pack | Dockerfile, at `/Dockerfile` |
| Domains | `https://macsync.hindra.studio` |
| Ports Exposes | `3000` (leave Port Mappings empty) |
| Health check | `GET /healthz`, port 3000, expect 200 |
| Persistent storage | a volume at `/data`. **Without it the count is lost on every deploy.** |
| Runtime variable `STATS_TOKEN` | a long random value: `openssl rand -hex 32` |
| Runtime variable `CLIENT_IP_HEADER` | `cf-connecting-ip` if Cloudflare proxies the name; otherwise leave out |
| Build variable `SITE_URL` | only for another address; the default is `https://macsync.hindra.studio/` |

Run one copy only: the count is a SQLite file in the volume. Back that volume up.
If Cloudflare proxies the name, its bot checks must not challenge `POST /api/count`: the app can't answer one.
Turn off proxy access logs for `/api/count` (Coolify's are off by default), since the site says no IP addresses are kept.

## 3. Check it

```bash
curl -sI https://macsync.hindra.studio/ | head -1
curl -s https://macsync.hindra.studio/robots.txt
curl -s -H "Authorization: Bearer $STATS_TOKEN" https://macsync.hindra.studio/api/installs
```

`uniqueInstalls` is the number of Macs ever counted; `activeLast30Days` is how many still use it.

## 4. Tell search engines

1. Set the default in `site/site.config.js` to `https://macsync.hindra.studio/`, run `npm run build` in `site/`
   and push, so the copy on GitHub Pages names this one as the original. **Keep GitHub Pages on**: the app
   reads its signed rules file from `onlymoein.github.io/macsync/rules.json`.
2. Change the website link on the GitHub repository and in `README.md`.
3. Add the site to Google Search Console and Bing Webmaster Tools, and submit `/sitemap.xml`.
   (Bing's index also feeds several AI assistants.)
4. Link to it from hindra.studio, for example as a project on the works page.

## What the count means

- The app's address for it is in `Sources/MacSyncCore/InstallCount.swift`. Change it there if the domain changes.
- Only versions with the counter report, and only once their owner has seen the notice and pressed OK.
  Macs that decline are never counted, so the real number is higher.
- Reinstalling keeps the Mac's number; erasing the Mac, or turning counting off and on, makes a new one.
