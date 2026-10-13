#cloud-config
users:
  - name: ${USER}
    ssh_authorized_keys:
      - ${SSH_KEY}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
ssh_pwauth: false
write_files:
  - path: /etc/systemd/resolved.conf.d/10-cloud-dns.conf
    permissions: '0644'
    content: |
      [Resolve]
      DNS=${DNS_SERVERS}
runcmd:
  - systemctl restart systemd-resolved
