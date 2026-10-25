#!/usr/bin/env bash
# Install only the broker. Do not rebuild, migrate or restart the API.
set -euo pipefail
app_dir="${1:-/home/ubuntu/apps/HuTube}"
config_source="${2:-$app_dir/deploy/rabbitmq/rabbitmq.conf}"
env_file="$app_dir/.env.ec2-api"
state_dir="$HOME/.config/dalitu/rabbitmq"
test -f "$env_file"
test -f "$config_source"
install -d -m 700 "$state_dir"
cp -p "$env_file" "$state_dir/env.ec2-api.before-$(date -u +%Y%m%dT%H%M%SZ)"
chmod 600 "$state_dir"/env.ec2-api.before-*
python3 - "$env_file" "$state_dir/broker.env" "$app_dir/.env.rabbitmq" <<'PY'
import os, secrets, sys
from pathlib import Path
env=Path(sys.argv[1]); text=env.read_text()
values={line.split('=',1)[0].strip():line.split('=',1)[1].strip().strip('\"\'')
        for line in text.splitlines() if '=' in line and not line.lstrip().startswith('#')}
user=values.get('RABBITMQ_USER') or 'dalitu'
password=values.get('RABBITMQ_PASSWORD') or secrets.token_urlsafe(32)
new={'RABBITMQ_USER':user,'RABBITMQ_PASSWORD':password,'RabbitMq__Enabled':'true',
     'RabbitMq__HostName':'rabbitmq','RabbitMq__UserName':user,'RabbitMq__Password':password,'RabbitMq__VirtualHost':'dalitu'}
lines=[line for line in text.splitlines() if line.split('=',1)[0].strip() not in new]
env.write_text('\n'.join(lines)+ '\n' + '\n'.join(f'{key}={value}' for key,value in new.items())+'\n')
os.chmod(env,0o600)
broker=Path(sys.argv[2]);broker.write_text(f'RABBITMQ_USER={user}\nRABBITMQ_PASSWORD={password}\n')
os.chmod(broker,0o600)
runtime=Path(sys.argv[3]);runtime.write_text(f'RABBITMQ_DEFAULT_USER={user}\nRABBITMQ_DEFAULT_PASS={password}\nRABBITMQ_DEFAULT_VHOST=dalitu\n')
os.chmod(runtime,0o600)
PY
install -m 644 "$config_source" "$state_dir/rabbitmq.conf"
cat > "$state_dir/compose.yml" <<'YAML'
services:
  rabbitmq:
    image: rabbitmq:4.3.6-management
    container_name: dalitu-rabbitmq
    hostname: dalitu-rabbitmq
    environment:
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASSWORD}
      RABBITMQ_DEFAULT_VHOST: dalitu
      RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS: "+S 2:2"
    ports:
      - "127.0.0.1:5672:5672"
      - "127.0.0.1:15672:15672"
    volumes:
      - rabbitmq-data:/var/lib/rabbitmq
      - ./rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf:ro
    mem_limit: 384m
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 15s
      timeout: 10s
      retries: 12
volumes:
  rabbitmq-data:
YAML
sudo -n docker compose -p hutube-ec2 --env-file "$state_dir/broker.env" -f "$state_dir/compose.yml" up -d --wait --wait-timeout 180 rabbitmq
sudo -n docker exec dalitu-rabbitmq rabbitmq-diagnostics -q check_running
sudo -n docker inspect --format '{{.Name}} {{.State.Health.Status}} {{.Config.Image}}' dalitu-rabbitmq
