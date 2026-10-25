#!/usr/bin/env bash
# Prepare credentials for the next API deployment; do not restart the API.
set -euo pipefail
credential="${1:?Pass the private service-account file path}"
app_dir="${2:-/home/ubuntu/apps/HuTube}"
destination="$HOME/.config/dalitu/firebase"
backup="$HOME/.config/dalitu/firebase-backups"
test -f "$credential"
test -f "$app_dir/.env.ec2-api"
project=$(python3 - "$credential" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d['type']=='service_account' and d['private_key'].startswith('-----BEGIN PRIVATE KEY-----')
assert d['project_id'].replace('-','').isalnum()
print(d['project_id'])
PY
)
api_uid=$(sudo -n docker exec hutube-ec2-api-1 id -u)
api_gid=$(sudo -n docker exec hutube-ec2-api-1 id -g)
[[ "$api_uid" =~ ^[0-9]+$ && "$api_gid" =~ ^[0-9]+$ ]]
install -d -m 700 "$backup"
cp -p "$app_dir/.env.ec2-api" "$backup/env.ec2-api.before-$(date -u +%Y%m%dT%H%M%SZ)"
chmod 600 "$backup"/env.ec2-api.before-*
sudo -n install -d -m 700 -o "$api_uid" -g "$api_gid" "$destination"
sudo -n install -m 400 -o "$api_uid" -g "$api_gid" "$credential" "$destination/service-account.json"
python3 - "$app_dir/.env.ec2-api" "$project" <<'PY'
import os,sys
from pathlib import Path
p=Path(sys.argv[1]);new={'Fcm__Enabled':'true','Fcm__ProjectId':sys.argv[2],
                        'Fcm__CredentialsPath':'/run/secrets/firebase/service-account.json'}
lines=[line for line in p.read_text().splitlines() if line.split('=',1)[0].strip() not in new]
p.write_text('\n'.join(lines)+'\n'+'\n'.join(f'{key}={value}' for key,value in new.items())+'\n')
os.chmod(p,0o600)
PY
printf 'FCM prepared for project %s; credential readable by API UID %s. API was not restarted.\n' "$project" "$api_uid"
