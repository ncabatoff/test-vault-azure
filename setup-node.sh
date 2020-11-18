#!/usr/bin/env bash

set -x

echo "Installing azure cli"
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

echo "Installing jq and Vault package"
curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
apt-get update
apt-get install -y jq vault=${vault_version}

echo "Configuring system time"
timedatectl set-timezone UTC

echo "Overwriting Vault binary"
# we install the package to get things like the vault user and systemd configuration,
# but we're going to use our own binary:
az storage blob download --connection-string "${connection_string}" -n "${binary_blob}" -c "${binary_container}" -f /tmp/vault.gz
gunzip -f /tmp/vault.gz
cp /tmp/vault /usr/bin/vault
/sbin/setcap cap_ipc_lock=+ep /usr/bin/vault

myip=$(curl -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2017-08-01&format=text")

cat << EOF > /etc/vault.d/vault.hcl
disable_performance_standby = true
ui = true
log_level = "trace"

storage "raft" {
  path    = "/opt/vault/data"
  retry_join {
    auto_join = "provider=azure subscription_id=${subscription_id} resource_group=${resource_group} vm_scale_set=${scale_set}"
    auto_join_scheme = "http"
    auto_join_port = 8200
  }
}

cluster_addr = "http://$myip:8201"
api_addr = "http://0.0.0.0:8200"

listener "tcp" {
 address     = "0.0.0.0:8200"
 tls_disable = 1
 telemetry {
   unauthenticated_metrics_access = "true"
 }
}
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
}
EOF

mkdir -p -m 700 /opt/vault/data
chown -R vault:vault /etc/vault.d/* /opt/vault
chmod -R 640 /etc/vault.d/*

echo "start Vault service"

systemctl enable vault
systemctl start vault

echo "Setup Vault profile"
cat <<PROFILE | sudo tee /etc/profile.d/vault.sh
export VAULT_ADDR="http://127.0.0.1:8200"
PROFILE

