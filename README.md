# cx-space-action

A GitHub Action that deploys a static site directory to [CDW CX Space](https://control.cdwcx.space) using the `cxs` CLI.

It installs the CLI, authenticates with your API key, optionally creates the site if it doesn't exist, deploys your build output, and (optionally) applies an access policy.

> Runs on `ubuntu-latest` and `macos-latest` runners.

## Usage

```yaml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: |
          npm ci
          npm run build

      - name: Deploy to CX Space
        id: cxs
        uses: cdw-ai-icx/cx-space-action@v1
        with:
          api-key: ${{ secrets.CXS_API_KEY }}
          site: customer-demo
          directory: ./dist

      - run: echo "Deployed to ${{ steps.cxs.outputs.url }}"
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `api-key` | yes | — | CX Space API key (starts with `cxs_`). Always pass via a secret. |
| `site` | yes | — | Site selector: slug, slug-username, full host, or site id. |
| `directory` | no | `.` | Directory to deploy (your build output). |
| `create` | no | `true` | Create the site if it doesn't already exist. |
| `include-username` | no | `true` | Include your username in the domain when creating (`slug-username.cdwcx.space`). Set `false` for `slug.cdwcx.space`. Only affects creation. |
| `cxs-dev` | no | `false` | Target the dev environment (`*.dev.cdwcx.space`). Requires a dev API key. |
| `access` | no | — | Access mode(s): `public`, `sso`, `email`, `password` (comma-separated). **Only applied when set** — otherwise the existing policy is left untouched. |
| `access-password` | no | — | Password for `password` mode. Pass via a secret. |
| `access-domains` | no | — | Allowed email domains for `sso`/`email` mode (comma- or space-separated). |
| `access-emails` | no | — | Allowed emails for `sso`/`email` mode (comma- or space-separated). |
| `access-timeout` | no | — | Session timeout in minutes for the access policy. |

## Outputs

| Output | Description |
|--------|-------------|
| `url` | Full `https://` URL of the deployed site. |
| `host` | Host of the deployed site. |
| `file-count` | Number of files deployed. |
| `duration-ms` | Deploy duration in milliseconds. |

## Examples

### Deploy with SSO access restricted to a domain

```yaml
- uses: cdw-ai-icx/cx-space-action@v1
  with:
    api-key: ${{ secrets.CXS_API_KEY }}
    site: internal-dashboard
    directory: ./dist
    access: sso
    access-domains: cdw.com
    access-timeout: 480
```

### Password-protected site

```yaml
- uses: cdw-ai-icx/cx-space-action@v1
  with:
    api-key: ${{ secrets.CXS_API_KEY }}
    site: client-preview
    directory: ./build
    access: password
    access-password: ${{ secrets.SITE_PASSWORD }}
```

### Deploy to the dev environment

```yaml
- uses: cdw-ai-icx/cx-space-action@v1
  with:
    api-key: ${{ secrets.CXS_DEV_API_KEY }}
    site: my-test
    directory: ./dist
    cxs-dev: true
```

## Notes

- The API key must match the environment: a prod key for prod, a dev key when `cxs-dev: true`.
- Generate an API key at [control.cdwcx.space](https://control.cdwcx.space) → Profile.
- Site existence is detected by matching the `site` selector against your owned and shared sites.
- Access controls are only applied when the `access` input is set, so manual changes made in Mission Control are preserved across deploys.

## License

MIT
