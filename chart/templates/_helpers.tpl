{{/*
Full external URL this page is reachable at, e.g.
https://console-openshift-console.apps.example.com/token-display/
Used as both the OAuthClient's redirectURI and the ConsoleLink's href, so the
two can never drift out of sync with each other or with the Route.
*/}}
{{- define "token-display.url" -}}
https://{{ required "route.host must be set (see values.yaml)" .Values.route.host }}{{ .Values.route.path }}/
{{- end -}}

{{/*
Validated customApiUrl: requires an explicit http(s) scheme. Without one, a
value like "api.crc.testing:6443" parses in the browser as a URL with scheme
"api.crc.testing" (matches the URI scheme grammar [a-zA-Z][a-zA-Z0-9+.-]*:),
not as a host:port - fetch() then fails same-origin/CORS checks with a
misleading "CORS request not http" error instead of a clear config error.
*/}}
{{- define "token-display.customApiUrl" -}}
{{- $url := required `customApiUrl must be set (see values.yaml)` .Values.customApiUrl -}}
{{- if not (regexMatch "^https?://" $url) -}}
{{- fail (printf "customApiUrl must include an explicit http:// or https:// scheme (got %q) - without one the browser misparses the host as a custom URI scheme and OAuth discovery fails with a confusing CORS error" $url) -}}
{{- end -}}
{{- $url -}}
{{- end -}}

{{/*
Validated oauthServerUrl: same explicit-scheme requirement as customApiUrl,
and for the same reason (a schemeless value misparses as a custom URI scheme
rather than a host:port).
*/}}
{{- define "token-display.oauthServerUrl" -}}
{{- $url := required `oauthServerUrl must be set (see values.yaml)` .Values.oauthServerUrl -}}
{{- if not (regexMatch "^https?://" $url) -}}
{{- fail (printf "oauthServerUrl must include an explicit http:// or https:// scheme (got %q)" $url) -}}
{{- end -}}
{{- $url -}}
{{- end -}}

{{/*
Hard-fail fast if this chart is installed outside the openshift-console
namespace: OpenShift's default route admission policy only allows a Route to
add a path to a hostname already claimed by another namespace's Route (the
console's own "console" Route) when both routes live in the SAME namespace.
Installing elsewhere would render fine but fail at apply time with a
confusing HostAlreadyClaimed error - catch it here instead.
*/}}
{{- define "token-display.namespaceCheck" -}}
{{- if ne .Release.Namespace "openshift-console" -}}
{{- fail (printf "this chart must be installed with --namespace openshift-console (got %q) - its Route needs to share the console's hostname, which OpenShift only allows for routes in the same namespace" .Release.Namespace) -}}
{{- end -}}
{{- end -}}
