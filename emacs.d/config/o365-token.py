#!/usr/bin/env python3
"""OAuth2 token helper for direct Microsoft (Outlook.com / Office365) XOAUTH2.

Used by 45_mail.org as the mbsync PassCmd for :oauth accounts.  Does the v2.0
device-code flow (works for personal Microsoft accounts incl. 2FA), keeps the
refresh token in the macOS Keychain, and prints a fresh access token.

Usage:
  o365-token.py authorize <id>   # one-time: device-code sign-in, store token
  o365-token.py token <id>       # print a fresh access token (PassCmd)

Stdlib only — runs with the system /usr/bin/python3.
"""
import sys, json, time, subprocess, urllib.parse, urllib.request, urllib.error

# Thunderbird's public client id — registered for personal Microsoft accounts
# and the Outlook IMAP/SMTP scopes; no app registration needed.
CLIENT_ID = "9e5f94bc-e8a4-4e73-b8be-63364c29d753"
TENANT = "common"
KC = "emacs-mail-oauth"          # Keychain generic-password service
SCOPE = ("https://outlook.office.com/IMAP.AccessAsUser.All "
         "https://outlook.office.com/SMTP.Send offline_access")
DEVICECODE = f"https://login.microsoftonline.com/{TENANT}/oauth2/v2.0/devicecode"
TOKEN = f"https://login.microsoftonline.com/{TENANT}/oauth2/v2.0/token"

acct = sys.argv[2] if len(sys.argv) > 2 else "outlook"


def post(url, data):
    req = urllib.request.Request(url, urllib.parse.urlencode(data).encode())
    try:
        return json.load(urllib.request.urlopen(req))
    except urllib.error.HTTPError as e:
        return json.load(e)


def kc_set(value):
    subprocess.run(["security", "add-generic-password", "-U",
                    "-s", KC, "-a", acct, "-w", value])


def kc_get():
    r = subprocess.run(["security", "find-generic-password",
                        "-s", KC, "-a", acct, "-w"],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def authorize():
    dc = post(DEVICECODE, {"client_id": CLIENT_ID, "scope": SCOPE})
    if "device_code" not in dc:
        print("ERR:", dc.get("error_description", dc), flush=True)
        sys.exit(1)
    print(dc["message"], flush=True)
    interval = dc.get("interval", 5)
    while True:
        time.sleep(interval)
        t = post(TOKEN, {
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "client_id": CLIENT_ID, "device_code": dc["device_code"]})
        if "refresh_token" in t:
            kc_set(t["refresh_token"])
            print("AUTHORIZED", flush=True)
            return
        err = t.get("error")
        if err == "authorization_pending":
            continue
        if err == "slow_down":
            interval += 5
            continue
        print("ERR:", t.get("error_description", t), flush=True)
        sys.exit(1)


def token():
    rt = kc_get()
    if not rt:
        sys.stderr.write(f"no refresh token for {acct}; run: authorize {acct}\n")
        sys.exit(1)
    t = post(TOKEN, {"grant_type": "refresh_token", "client_id": CLIENT_ID,
                     "scope": SCOPE, "refresh_token": rt})
    if "access_token" in t:
        if "refresh_token" in t:          # rotate if a new one was issued
            kc_set(t["refresh_token"])
        sys.stdout.write(t["access_token"])
        return
    sys.stderr.write("refresh failed: %s\n" % t.get("error_description", t))
    sys.exit(1)


mode = sys.argv[1] if len(sys.argv) > 1 else "token"
authorize() if mode == "authorize" else token()
