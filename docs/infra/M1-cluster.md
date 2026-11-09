# M1 — kubeadm 클러스터 직접 구축

노트북(VMware Workstation)의 VM 3대에 kubeadm으로 쿠버네티스 클러스터를 구축한다.
깨끗한 Ubuntu 상태에서 스크립트만으로 다시 만들 수 있게 했다.

## 구성

| 노드 | 역할 | IP | 사양 |
|---|---|---|---|
| k8s-cp1 | control-plane | 192.168.125.10 | 2 vCPU · 4 GB · 40 GB |
| k8s-w1 | worker | 192.168.125.11 | 2 vCPU · 4 GB · 40 GB |
| k8s-w2 | worker | 192.168.125.12 | 2 vCPU · 4 GB · 40 GB |

| 항목 | 값 |
|---|---|
| 가상화·네트워크 | VMware Workstation, NAT(VMnet8) `192.168.125.0/24`, 게이트웨이·DNS `.2` |
| OS | Ubuntu Server 24.04 LTS (LVM 미사용, 고정 IP는 netplan) |
| 컨테이너 런타임 | containerd 2.2 (Ubuntu 패키지), cgroup 드라이버 systemd |
| 쿠버네티스 | v1.37 (kubeadm·kubelet·kubectl, `apt-mark hold`로 고정) |
| CNI | Calico v3.33 (operator 방식) |
| 파드 대역 | `10.244.0.0/16` — Calico 기본값 `192.168.0.0/16`은 노드 대역과 겹쳐서 바꿈 |

## 구축 순서

전제: VM 3대에 Ubuntu 설치, 고정 IP, 서로 다른 hostname·machine-id·SSH 호스트 키.

```bash
# 1) 3대 모두: 노드 준비 (swap 해제, 커널 모듈·sysctl, containerd, kubeadm 설치)
scp scripts/node-prep.sh <user>@<node-ip>:~/
ssh -t <user>@<node-ip> 'sudo bash node-prep.sh'

# 2) cp1: 클러스터 초기화 (init, kubectl 설정, Calico, Ready 대기, join 명령 출력)
scp scripts/cluster-init.sh <user>@192.168.125.10:~/
ssh -t <user>@192.168.125.10 'bash cluster-init.sh'

# 3) worker 2대: 2)에서 출력된 join 명령을 sudo로 실행
sudo kubeadm join 192.168.125.10:6443 --token ... --discovery-token-ca-cert-hash sha256:...
```

두 스크립트 모두 다시 실행해도 결과가 같다(이미 된 단계는 건너뛴다).

## 재구축 결과

VM 3대를 OS만 설치된 스냅샷으로 되돌린 뒤 위 순서로 다시 구축했다.
3노드 `Ready`까지 약 19분 걸렸다(이번 실행 중 발견한 스크립트 오류 수정·재실행 시간 포함).

## 구축하며 만난 문제

| 증상 | 원인 | 조치 |
|---|---|---|
| Calico 설치가 `kubeadm configuration is missing required podSubnet field`로 멈춤 | `kubeadm init`을 손으로 입력하다 `--pod-network-cidr`이 빠짐 | `kubeadm reset` 후 재-init. 스크립트에 init 옵션을 고정하고, init 직후 podSubnet을 검사하도록 함 |
| 노트북 망을 옮긴 뒤 이미지 pull이 `lookup registry.k8s.io ... i/o timeout` | VM의 DNS는 VMware NAT(`.2`)를 거치는데, NAT 서비스가 이전 망의 DNS를 계속 사용 | Windows에서 `VMware NAT Service` 재시작 |
| 재구축 중 `node-prep.sh`가 `Could not get lock /var/lib/dpkg/lock-frontend`로 실패 | 재부팅 직후 Ubuntu 자동 업데이트가 apt 잠금을 잡고 있음 | 모든 apt 호출에 `-o DPkg::Lock::Timeout=600`을 줘서 잠금이 풀릴 때까지 대기 |
| VM 콘솔에 `rcu_preempt detected stalls` 반복, SSH 끊김 | VM의 vCPU가 호스트에서 실행 시간을 받지 못함(노트북 절전 중 VM을 켜 둔 것이 유력) | VM 리셋. 작업 후 VM을 끄거나 일시 정지 |
