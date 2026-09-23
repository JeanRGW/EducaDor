"""Create the first platform gestor from a trusted operator machine only.

Usage: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... APP_ORIGIN=... \
  python3 scripts/bootstrap_gestor.py email@example.com 'Full Name'
"""

import json
import os
import sys
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def request(path: str, *, method: str = "GET", body: dict | None = None):
    url = os.environ["SUPABASE_URL"].rstrip("/") + path
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
    payload = json.dumps(body).encode() if body is not None else None
    with urlopen(Request(url, data=payload, headers=headers, method=method)) as response:
        return json.load(response)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: bootstrap_gestor.py EMAIL 'FULL NAME'")
    email, name = sys.argv[1].strip().lower(), sys.argv[2].strip()
    if not email or not name:
        raise SystemExit("Email and full name are required")
    existing = request("/rest/v1/platform_gestors?select=user_id&limit=1")
    if existing:
        raise SystemExit("A platform gestor already exists. Invite others from the app.")

    redirect = os.environ["APP_ORIGIN"].rstrip("/") + "/set-password"
    link_data = request(
        "/auth/v1/admin/generate_link?" + urlencode({"redirect_to": redirect}),
        method="POST", body={"type": "invite", "email": email},
    )
    user = link_data["user"]
    request("/rest/v1/profiles", method="POST", body={
        "id": user["id"], "full_name": name, "email": email,
        "needs_password": True,
    })
    request("/rest/v1/platform_gestors", method="POST", body={"user_id": user["id"]})
    # Only release the bearer link AFTER both grants have succeeded.
    print("Share this short-lived link privately with the first gestor:")
    print(link_data["action_link"])


if __name__ == "__main__":
    main()
