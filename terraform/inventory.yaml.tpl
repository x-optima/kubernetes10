all:
  vars:
    ansible_user: ubuntu
    ansible_become: yes
    ansible_ssh_common_args: >-
      -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30
      -o ControlMaster=no -o ControlPath=none
  children:
    kube_control_plane:
      hosts:
        master:
    etcd:
      hosts:
        master:
    kube_node:
      hosts:
%{ for worker_index, worker_ip in workers }
        worker-${worker_index + 1}:
%{ endfor }
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
  hosts:
    master:
      ansible_host: ${master_ext}
      ip: ${master_int}
      access_ip: ${master_int}
%{ for worker_index, worker_ip in workers }
    worker-${worker_index + 1}:
      ansible_host: ${worker_ip}
      ip: ${worker_ip}
      access_ip: ${worker_ip}
      ansible_ssh_common_args: >-
        -o StrictHostKeyChecking=accept-new
        -o BatchMode=yes -o ConnectTimeout=30
        -o ControlMaster=no -o ControlPath=none
        -o ProxyCommand="ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=30 -o ControlMaster=no -o ControlPath=none -W %h:%p ubuntu@${master_ext}"
%{ endfor }