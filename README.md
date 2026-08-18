# Custom API URL Token Display Page

OpenShift's built-in "Copy login command" page always shows the API server's
internal `masterPublicURL`, which can differ from the load-balanced URL users
actually need. Both URLs accept the same bearer tokens - only the displayed URL
is wrong. This project deploys a small in-cluster page that does the same OAuth
login flow but prints a configurable, load-balanced API URL in the generated
`oc login` / `curl` commands instead.

It also adds an item to the web console's user-menu dropdown (top right) linking
to the new page, alongside the existing (unmodifiable) "Copy login command" entry.

The page is served under the console's *own* hostname at the `/token-display`
path (e.g. `https://console-openshift-console.apps.<domain>/token-display/`),
rather than a separate subdomain. OpenShift supports multiple `Route` objects
sharing one host as long as their paths don't overlap and none of them uses
`passthrough` TLS termination - the console's route uses `reencrypt`, so this
works. The catch: **the default route admission policy only allows a route to
add a path to an already-claimed host if it's in the *same namespace* as the
route that first claimed it.** The console's `console` Route lives in
`openshift-console`, so this chart's `Deployment`/`Service`/`Route`/`ConfigMap`
are installed into `openshift-console` too, alongside it - not into their own
project (the chart hard-fails at render time if you try to install it anywhere
else - see `templates/_helpers.tpl`). That namespace is normally restricted to
cluster-admins and reconciled by the console-operator; the operator only manages
resources it owns by name (`console`, `downloads`, etc.), so uniquely-named
`token-display-*` resources should be left alone, but this hasn't been verified
against a live cluster - watch for it being pruned after an upgrade and
re-install if so.

## How it works

- `chart/files/index.html.tpl` is a single static page, kept as a plain file
  (not inlined into a YAML manifest) so it's easy to edit. It's a Go template:
  Helm's `tpl` function renders it against the chart's values at
  `helm template`/`install` time (see `templates/configmap-html.yaml`), baking
  in `customApiUrl` and `oauthClientId` directly - the ConfigMap that reaches
  the cluster already contains the finished HTML/JS, no runtime substitution.
- On load the page navigates straight to `<oauthServerUrl>/oauth/authorize`
  (implicit grant, `response_type=token`) - the cluster's OAuth server route,
  a separate route from the API server that's already reachable from users'
  browsers today (it's what the built-in "Copy login command" flow uses too).
  There's deliberately no discovery `fetch()` of
  `<customApiUrl>/.well-known/oauth-authorization-server`: that would be a
  cross-origin read, and the API server generally doesn't send the
  `Access-Control-Allow-Origin` header needed for the browser to allow it. A
  top-level navigation isn't subject to CORS at all, so this sidesteps the
  problem rather than working around it (e.g. via an in-cluster reverse
  proxy or a cluster-wide `APIServer` CORS config change). On the way back it
  reads the token from the URL fragment and renders the `oc login` / `curl`
  commands using `customApiUrl`.
- The page is served by `registry.access.redhat.com/hi/nginx:1.30.4` (Red Hat's
  hardened/minimal nginx build - no shell, no package manager, `ENTRYPOINT` is
  the `nginx` binary directly). That's exactly why the HTML is pre-rendered by
  Helm rather than substituted at container startup: this image has no shell
  to run an entrypoint/envsubst script even if we wanted one. The ConfigMap's
  `index.html` key is mounted straight onto the served path via `subPath`.
  Confirmed by inspecting the image: listens on 8080, serves
  `/usr/share/nginx/html` with the standard `index` directive, default UID
  65532 (arbitrary-UID/OpenShift-compatible), logs symlinked to
  stdout/stderr.
- A dedicated `OAuthClient` is required because the built-in `openshift-browser-client`'s
  redirect URI is fixed to OpenShift's own display page. `grantMethod: auto`
  keeps the flow to a single redirect with no consent screen.

## Deploy

1. Find the console's actual hostname:
   ```sh
   oc get route console -n openshift-console -o jsonpath='{.spec.host}'
   ```
   and decide the load-balanced API URL you want displayed.
2. Install, setting the two required values (the chart has no sensible
   defaults for these and will fail the render if either is missing):
   ```sh
   helm install token-display chart/ \
     --namespace openshift-console \
     --set customApiUrl=https://api.example.com:6443 \
     --set route.host=console-openshift-console.apps.example.com
   ```
   (`--namespace openshift-console` is required - the chart refuses to render
   for any other namespace, see "How it works" above.)
3. Check rollout:
   ```sh
   oc rollout status deployment/token-display -n openshift-console
   ```

To change anything later (the displayed URL, the page content, the image tag),
edit `chart/values.yaml` / `chart/files/index.html.tpl` and run:
```sh
helm upgrade token-display chart/ -n openshift-console \
  --set customApiUrl=... --set route.host=...
```
(or `-f your-values.yaml` if you keep the real values out of `--set`/shell
history, which you likely want for `customApiUrl`+`route.host` in a real repo).

See `chart/values.yaml` for the full set of configurable values (`oauthClientId`,
`route.path`, `image.repository`/`image.tag`/`image.pullPolicy`).

## Before relying on it: two pre-flight checks

The page does a cross-origin browser `fetch()` from the console's origin to
`customApiUrl` for OAuth discovery. Two independent things can break that,
and they look almost identical in the browser console but need different
fixes:

**1. TLS trust.** If the browser console shows *"CORS request did not
succeed"* with **status code `(null)`**, the browser never got an HTTP
response at all - most commonly because it doesn't trust `customApiUrl`'s TLS
certificate (this is the norm for local dev clusters like CRC, whose API
server cert is signed by a locally-generated CA that Firefox/Chrome don't
trust by default, since Firefox in particular uses its own cert store rather
than the OS one). Confirm by opening
`https://<customApiUrl>/.well-known/oauth-authorization-server` directly in
the same browser: an untrusted-certificate warning page confirms it. Click
through it once to add a permanent exception for that host+port and retry -
background `fetch()` calls will then succeed too. A real load-balanced
production URL normally carries a CA-trusted certificate and won't hit this.

**2. Missing CORS headers.** If instead you get a response with an actual
status code but reason *"CORSMissingAllowOrigin"* (or similar), the API
server responded fine but didn't send permissive CORS headers. Confirm with:
```sh
curl -sI -H "Origin: https://<console-host>" \
  "https://<customApiUrl>/.well-known/oauth-authorization-server" | grep -i access-control
```
If there's no `Access-Control-Allow-Origin`, you'll need to add an nginx
`location` block that proxies that one path server-side instead (a new
ConfigMap key + volume mount for a `conf.d` file - the hardened image has no
shell, but it doesn't need one to just load an extra static config file).

## Verify end-to-end

1. `oc get route token-display -n openshift-console -o jsonpath='{.spec.host}{.spec.path}'` -
   confirm it matches the registered `OAuthClient` redirect URI and `ConsoleLink` href
   (`helm get manifest token-display -n openshift-console` shows the actual
   applied resources).
2. Visit `https://<console-host>/token-display/` in a browser: expect a redirect
   to cluster login (or instant pass-through if already SSO'd), then a redirect
   back with `#access_token=...`, then the token / `oc login` / `curl` block
   rendering with a clean URL bar (no fragment left behind).
3. Run the shown `oc login` command locally - it should succeed against the
   configured `customApiUrl`.
4. Run the shown `curl` command - it should return your user identity JSON.
5. Try the same token against the cluster's real internal API URL too, to
   confirm token interchangeability (the whole premise of this page).
6. Click "Request another token" - with an existing SSO session this should
   silently re-mint a token with no login prompt.
7. In the web console, open the user menu (top right) and confirm the new
   entry appears alongside "Copy login command" and links to this page.
8. Negative test: temporarily break `oauthClientId` or reinstall with a wrong
   `route.host` and confirm the page renders a readable error instead of
   hanging.
