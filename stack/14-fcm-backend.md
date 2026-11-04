# FCM backend (incomplete)

This branch currently provides registration and preference storage only. It does
not send notifications; the `push-on-assign` function, recipient authorization,
anti-spam claim, FCM integration, and their tests remain to be implemented. Do
not deploy or merge this partial work as an active push feature.

Authenticated clients call `register_fcm_token(p_token, p_platform)` with
`android`, `ios`, or `web`; registration transfers that token to the current
identity without changing its preference. `unregister_fcm_token(p_token)` only
removes the caller's token. `set_push_enabled(p_enabled)` sets the caller's
preference. The caller may read its own `notification_preferences` row; a
missing row means enabled. Direct client token writes are disabled. Registration
serializes competing transfers of the same token; pre-existing duplicate tokens
are reconciled when that token is registered again.

A future sender must enforce disabled preferences and all release gates in
trusted code, use the verified `caller` helper from `_shared/invites.ts`, and
avoid disclosing tokens or recipients. No Firebase project, service-account
secret, hosted configuration, or delivery infrastructure was changed here.
