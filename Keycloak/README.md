# Keycloak

[Keycloak](https://www.keycloak.org/) a self-hosted open-source IDP.

Refs:
- [Docker Starting](https://www.keycloak.org/getting-started/getting-started-docker)
- [API Ref](https://www.keycloak.org/docs-api/latest/rest-api/index.html)
- [Local development with Keycloak](https://medium.com/norsk-helsenett/local-development-with-keycloak-and-blazor-server-695921705578)
- [Local development with Keycloak part 2](https://medium.com/norsk-helsenett/local-development-with-keycloak-part-2-3d4e95f324c0)

## Validation

To test the Keycloak setup, run this curl command from outside the container to check that the correct token is returned:

~~~bash
curl --request POST ^
    --url http://localhost:55001/realms/local-realm/protocol/openid-connect/token ^
    --header 'Content-Type: application/x-www-form-urlencoded' ^
    --data client_id=local-client ^
    --data username=<userid> ^
    --data password=<user-password> ^
    --data realm=local-realm ^
    --data grant_type=password
~~~

This command will return a JSON token, containing the following details:
```JSON
{
	"access_token": "eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJzdkFDZE9TWmFMREhOVjA5ckhhaVAwbWZMNUZTWVZNYnJvQ3pMVndXWEFNIn0.eyJleHAiOjE3ODgyODMxNDIsImlhdCI6MTc4ODI4Mjg0MiwianRpIjoib25ydHJvOjJmOTdiNjY0LTI2MTYtNzI2NS00NGFlLTIzMGQ0YzBlOTVkNiIsImlzcyI6Imh0dHA6Ly9sb2NhbGhvc3Q6NTUwMDEvcmVhbG1zL2xvY2FsLXJlYWxtIiwiYXVkIjoiYWNjb3VudCIsInN1YiI6IjVjOTlhNTNlLTQyNTEtNGQyZi04NGE4LTY3ODVjMmUxODQ4NyIsInR5cCI6IkJlYXJlciIsImF6cCI6ImxvY2FsLWNsaWVudCIsInNpZCI6IlRZTHhfVGI0RjQzNHdYYWVZT0dLNVpWLSIsImFjciI6IjEiLCJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsic3RhbmRhcmQtdXNlciIsIm9mZmxpbmVfYWNjZXNzIiwiZGVmYXVsdC1yb2xlcy1sb2NhbC1yZWFsbSIsInVtYV9hdXRob3JpemF0aW9uIl19LCJyZXNvdXJjZV9hY2Nlc3MiOnsiYWNjb3VudCI6eyJyb2xlcyI6WyJtYW5hZ2UtYWNjb3VudCIsIm1hbmFnZS1hY2NvdW50LWxpbmtzIiwidmlldy1wcm9maWxlIl19fSwic2NvcGUiOiJlbWFpbCBwcm9maWxlIGxvY2FsX3Njb3BlIiwiZW1haWxfdmVyaWZpZWQiOmZhbHNlLCJuYW1lIjoiSm9obiBBZG1pbiIsInByZWZlcnJlZF91c2VybmFtZSI6IndvcmtpbmdfYWRtaW5fdXNlciIsImdpdmVuX25hbWUiOiJKb2huIiwiZmFtaWx5X25hbWUiOiJBZG1pbiIsImVtYWlsIjoid29ya2luZ19hZG1pbl91c2VyQGxvY2FsLmNvbSJ9.ZsmEUMPtcJ51SQ-bidudu23MJxcSWqYwyJupxRCqTqVUuPd-ZzAjcrJpBO5B_hrza5f6xyD6ad0Zs2VqnQAc_PtA0IYYipeNfgF6g0qiMYqGSNvKn7UBtqpDjwe7ZFIRfZp71GH7eZJB3KCBu-MhFFJnRQkx0aGgM7lqA8dnyHvG8u-k2KO4zHusQrTEDzlyeLnpuU55HZpB1E5KzrlNuGpG4MLG5uFR5gSY0Uqv_vor-x3fqUwk9w0YVkBRmKv2rX9QILIfxflndx5cFKjXbtDJoT3wbclc3VPoyMPxMKYZtN4fe38BICuVR7WL3dHWUOxaP8SpA-_gdnv1cPaMDw",
	"expires_in": 300,
	"refresh_expires_in": 1800,
	"refresh_token": "eyJhbGciOiJIUzUxMiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJlNTE1ZTNiOC0zNDMxLTRiYjAtYjNjMy0zYmI3MzY4NGI4ZDAifQ.eyJleHAiOjE3ODgyODQ2NDIsImlhdCI6MTc4ODI4Mjg0MiwianRpIjoiM2FhNmU2ZDMtNzU2Zi0zODBkLTE3ZjUtMjVlZTJjYWRlZTY3IiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NTAwMS9yZWFsbXMvbG9jYWwtcmVhbG0iLCJhdWQiOiJodHRwOi8vbG9jYWxob3N0OjU1MDAxL3JlYWxtcy9sb2NhbC1yZWFsbSIsInN1YiI6IjVjOTlhNTNlLTQyNTEtNGQyZi04NGE4LTY3ODVjMmUxODQ4NyIsInR5cCI6IlJlZnJlc2giLCJhenAiOiJsb2NhbC1jbGllbnQiLCJzaWQiOiJUWUx4X1RiNEY0MzR3WGFlWU9HSzVaVi0iLCJzY29wZSI6ImVtYWlsIHByb2ZpbGUgcm9sZXMgd2ViLW9yaWdpbnMgYmFzaWMgbG9jYWxfc2NvcGUgYWNyIiwiYXVkX3giOiJhY2NvdW50IiwicHJvdiI6ImRlZmF1bHQifQ.bv4jJLFDCzrsPaZd5Kw9_dyNI5PkshV4cdm-IbPAcKKm_o4y7dw9pWfmDm2MVOUJoqLn6NwrnJsX8PeHUy8bvg",
	"token_type": "Bearer",
	"not-before-policy": 0,
	"session_state": "TYLx_Tb4F434wXaeYOGK5ZV-",
	"scope": "email profile local_scope"
}
```

The access_token, in the above token, is a [JWT](https://www.jwt.io/).  Using the decoder on the JWT site, results in the following:

Decoded Header:

```JSON
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "svACdOSZaLDHNV09rHaiP0mfL5FSYVMbroCzLVwWXAM"
}
```

Decoded Payload:

```JSON
{
  "exp": 1788283142,
  "iat": 1788282842,
  "jti": "onrtro:2f97b664-2616-7265-44ae-230d4c0e95d6",
  "iss": "http://localhost:55001/realms/local-realm",
  "aud": "account",
  "sub": "5c99a53e-4251-4d2f-84a8-6785c2e18487",
  "typ": "Bearer",
  "azp": "local-client",
  "sid": "TYLx_Tb4F434wXaeYOGK5ZV-",
  "acr": "1",
  "realm_access": {
    "roles": [
      "admin_role",
      "offline_access",
      "default-roles-local-realm",
      "uma_authorization"
    ]
  },
  "resource_access": {
    "account": {
      "roles": [
        "manage-account",
        "manage-account-links",
        "view-profile"
      ]
    }
  },
  "scope": "email profile client_scope",
  "email_verified": false,
  "name": "John Admin",
  "preferred_username": "working_admin_user",
  "given_name": "John",
  "family_name": "Admin",
  "email": "working_admin_user@local.com"
}
```

Most of the attributes above are explained in the JWT website, but a few attribuites that point to specific settings in Keycloak are as follows:
| Attribute | Keycloak Source |
| --- | --- |
| acr | Authentication Context Class Reference — reflects the authentication flow/level of assurance used at login (e.g. `1` for username/password), driven by the realm's configured authentication flows |
| azp | The ID of the client |
| iss | The realm's issuer URL, `<hostname>/realms/<realm-name>` — derived from the server's configured hostname/frontend URL and the realm that issued the token |
| scope | The client scopes evaluated for this client (Clients → Client scopes → Default/Optional); each scope's protocol mappers determine which claims get added to the token |
| sid | The Keycloak SSO session ID for the login session; shared by every token issued from that session, and what a Keycloak logout/session revocation invalidates |
| sub | The user's internal unique ID (UUID) as stored in Keycloak's user database — matches the user's `id` in the Admin Console / Admin REST API |
| typ | The token's type as assigned by Keycloak (`Bearer` for an access token, `Refresh` for a refresh token, `ID` for an ID token) — distinct from the `typ` in the JWT header, which is always `JWT` |
| realm_access.roles | The realm-level roles assigned to the user (Admin Console → Realm roles, or Users → Role mapping) |
| resource_access.\<clientId\>.roles | The client-level roles assigned to the user, scoped to a specific client (Clients → Roles, or Users → Role mapping filtered to that client) |
| preferred_username | The username of the authenticated Keycloak user account (Users → Username) |

A few relationships worth knowing between a generated token and its Keycloak configuration:
- **Claims come from client scopes.** Every claim beyond the core registered ones is added by a protocol mapper attached to a client scope assigned to the client (e.g. the `client_scope` created by [Docker-Keycloak-builder.bat](Docker-Keycloak-builder.bat) is why `client_scope` appears in `scope` above). Removing a default scope, or a mapper on it, removes the corresponding claim from future tokens.
- **Realm roles vs. client roles.** `realm_access` and `resource_access` mirror Keycloak's two-tier role model — realm roles apply across every client in the realm, while client roles (under `resource_access`) are scoped to one client and only appear for clients that have roles assigned.
- **azp and aud identify the client(s).** `azp` is always the client that requested the token; `aud` is the client(s) the token is valid for. They can differ (e.g. `aud: "account"` above) when an audience mapper targets a different client than the one that authenticated.
- **sid ties tokens to a session.** The access token and its paired refresh token share the same `sid`; any other token issued during that browser session (e.g. after a silent refresh) will carry the same value, and revoking that Keycloak session invalidates all of them together.
- **Lifetimes are realm/client settings, not JWT defaults.** `exp`/`iat` reflect the realm's Tokens → Access Token Lifespan setting, which can be overridden per client under Advanced → Fine Grain Token Lifespan.

## Usage

In a browser:
- [Admin Console](http://localhost:55001/admin)
- [Account Console](http://localhost:55001/realms/local-realm/account)
