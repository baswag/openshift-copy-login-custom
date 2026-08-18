<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>OpenShift API Token</title>
    <style>
      body {
        font-family: sans-serif;
        font-size: 14px;
        margin: 2em 2%;
        background-color: #f9f9f9;
      }
      h2 {
        font-size: 1.4em;
      }
      h3 {
        font-size: 1em;
        margin: 1.5em 0 0;
      }
      code,
      pre {
        font-family: Menlo, Monaco, Consolas, monospace;
      }
      code {
        font-weight: 300;
        font-size: 1.5em;
        margin-bottom: 1em;
        display: inline-block;
        color: #646464;
      }
      pre {
        padding-left: 1em;
        border-radius: 5px;
        color: #003d6e;
        background-color: #eaedf0;
        padding: 1.5em 0 1.5em 4.5em;
        white-space: normal;
        text-indent: -2em;
      }
      a {
        color: #00f;
        text-decoration: none;
      }
      a:hover {
        text-decoration: underline;
      }
      @media (min-width: 768px) {
        .nowrap {
          white-space: nowrap;
        }
      }
    </style>
  </head>
  <body>
    <div id="content">Signing you in&hellip;</div>

    <script>
      (function () {
        var CUSTOM_API_URL = "{{ include `token-display.customApiUrl` . }}";
        var OAUTH_SERVER_URL = "{{ include `token-display.oauthServerUrl` . }}";
        var CLIENT_ID = "{{ .Values.oauthClientId }}";
        var contentEl = document.getElementById("content");

        function selfURL() {
          return window.location.href.split("#")[0];
        }

        function escapeHtml(s) {
          var div = document.createElement("div");
          div.textContent = s;
          return div.innerHTML;
        }

        function parseHash(hash) {
          var params = {};
          hash
            .replace(/^#/, "")
            .split("&")
            .forEach(function (kv) {
              if (!kv) return;
              var i = kv.indexOf("=");
              if (i === -1) return;
              params[decodeURIComponent(kv.slice(0, i))] = decodeURIComponent(
                kv.slice(i + 1).replace(/\+/g, "%20")
              );
            });
          return params;
        }

        function renderError(msg) {
          contentEl.innerHTML =
            "<h2>Login failed</h2>" +
            "<pre>" + escapeHtml(msg) + "</pre>" +
            '<br><br><a href="' + escapeHtml(selfURL()) + '">Try again</a>';
        }

        function renderToken(token) {
          var loginCmd =
            "oc login " +
            '<span class="nowrap">--token=' + escapeHtml(token) + "</span> " +
            '<span class="nowrap">--server=' + escapeHtml(CUSTOM_API_URL) + "</span>";
          var curlCmd =
            "curl " +
            '<span class="nowrap">-H "Authorization: Bearer ' + escapeHtml(token) + '"</span> ' +
            '<span class="nowrap">"' + escapeHtml(CUSTOM_API_URL) + '/apis/user.openshift.io/v1/users/~"</span>';

          contentEl.innerHTML =
            "<h2>Your API token is</h2>" +
            "<code>" + escapeHtml(token) + "</code>" +
            "<h2>Log in with this token</h2>" +
            "<pre>" + loginCmd + "</pre>" +
            "<h3>Use this token directly against the API</h3>" +
            "<pre>" + curlCmd + "</pre>" +
            '<br><br><a href="#" id="reauth">Request another token</a>';

          document.getElementById("reauth").addEventListener("click", function (e) {
            e.preventDefault();
            contentEl.innerHTML = "Signing you in&hellip;";
            startLogin();
          });
        }

        function startLogin() {
          // No discovery fetch() here on purpose: OAUTH_SERVER_URL is
          // already known and reachable from the browser (it's what the
          // built-in "Copy login command" flow uses too), and a fetch to
          // the API server's /.well-known/oauth-authorization-server would
          // need CORS headers it generally doesn't send. A top-level
          // navigation isn't subject to CORS at all.
          var url =
            OAUTH_SERVER_URL + "/oauth/authorize" +
            "?client_id=" + encodeURIComponent(CLIENT_ID) +
            "&response_type=token" +
            "&redirect_uri=" + encodeURIComponent(selfURL());
          window.location.replace(url);
        }

        function main() {
          var hash = window.location.hash;
          if (hash.indexOf("access_token=") !== -1 || hash.indexOf("error=") !== -1) {
            var params = parseHash(hash);
            history.replaceState(null, "", selfURL());
            if (params.error) {
              renderError(params.error_description || params.error);
            } else if (params.access_token) {
              renderToken(params.access_token);
            } else {
              renderError("Unexpected OAuth response");
            }
          } else {
            startLogin();
          }
        }

        main();
      })();
    </script>
  </body>
</html>
