#!/usr/bin/env bash
# 쿠버네티스 노드 준비 스크립트 (control-plane·worker 공통)
#
# 깨끗한 Ubuntu 24.04(고정 IP 설정까지 끝난 상태)를 kubeadm init/join 직전 상태로 만든다.
# 여러 번 실행해도 결과가 같도록(멱등) 작성했다.
#
# 사용: sudo bash node-prep.sh

set -euo pipefail

K8S_MINOR="${K8S_MINOR:-v1.37}"          # 쿠버네티스 마이너 버전 (패치는 저장소의 최신)
NODES=(                                 # 클러스터 노드 목록: "IP 이름"
  "192.168.125.10 k8s-cp1"
  "192.168.125.11 k8s-w1"
  "192.168.125.12 k8s-w2"
)

# apt가 설치 중에 질문 창(보라색 화면 등)을 띄우지 않게 한다
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

log() { echo; echo "==> $*"; }
die() { echo "오류: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "root 권한이 필요하다. sudo bash $0 으로 실행"

# ---------------------------------------------------------------------------
log "A. 노드 이름 등록 (/etc/hosts)"
# Ubuntu가 넣은 '내 이름 = 127.0.1.1' 줄을 지운다. 남기면 내 이름이 실제 IP가 아닌 127.0.1.1로 풀린다
sed -i '/^127\.0\.1\.1/d' /etc/hosts
for entry in "${NODES[@]}"; do
  name="${entry#* }"                                  # "IP 이름"에서 이름만
  if grep -qE "[[:space:]]${name}$" /etc/hosts; then  # 이미 있으면 건너뛴다 (중복 방지)
    echo "  이미 있음: $entry"
  else
    echo "$entry" >> /etc/hosts
    echo "  추가: $entry"
  fi
done

# ---------------------------------------------------------------------------
log "B. swap 끄기"
swapoff -a                                    # 지금 끈다
sed -i -E '/\sswap\s/ s/^#?/#/' /etc/fstab    # 재부팅 후에도 꺼지게 (이미 주석이면 그대로)

# ---------------------------------------------------------------------------
log "C. 커널 모듈 (overlay, br_netfilter)"
cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay                              # 지금 켠다
modprobe br_netfilter                         # (부팅 때는 위 파일로 켜진다)

# ---------------------------------------------------------------------------
log "D. 커널 네트워크 설정 (sysctl)"
cat > /etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system > /dev/null                   # 지금 적용 (부팅 때는 위 파일로 적용된다)

# ---------------------------------------------------------------------------
log "E. containerd 설치·설정"
apt-get update -qq
apt-get install -y -qq containerd > /dev/null
mkdir -p /etc/containerd
# 설정 파일이 없거나 systemd cgroup이 아니면 기본값으로 새로 만들고 systemd로 바꾼다
if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml 2>/dev/null; then
  containerd config default > /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  echo "  config.toml 생성 (SystemdCgroup = true)"
else
  echo "  config.toml 이미 설정됨"
fi
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml || die "SystemdCgroup 설정 실패"
systemctl enable containerd > /dev/null 2>&1
systemctl restart containerd

# ---------------------------------------------------------------------------
log "F. kubeadm·kubelet·kubectl 설치 (${K8S_MINOR})"
apt-get install -y -qq curl gpg > /dev/null
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg   # --yes: 다시 실행할 때 덮어쓰기 질문 없이
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl > /dev/null

# ---------------------------------------------------------------------------
log "G. 버전 고정"
apt-mark hold kubelet kubeadm kubectl > /dev/null
systemctl enable kubelet > /dev/null 2>&1     # 시작은 kubeadm init/join이 한다

# ---------------------------------------------------------------------------
log "결과 확인"
fail=0
check() {  # check "설명" 명령...  → 명령이 성공하면 OK
  local desc="$1"; shift
  if "$@" > /dev/null 2>&1; then echo "  [OK]   $desc"; else echo "  [FAIL] $desc"; fail=1; fi
}
check "swap 꺼짐"                 bash -c '[[ -z "$(swapon --show)" ]]'
check "overlay 모듈"              bash -c 'lsmod | grep -q "^overlay"'
check "br_netfilter 모듈"         bash -c 'lsmod | grep -q "^br_netfilter"'
check "ip_forward = 1"            bash -c '[[ "$(sysctl -n net.ipv4.ip_forward)" == 1 ]]'
check "bridge-nf-call-iptables=1" bash -c '[[ "$(sysctl -n net.bridge.bridge-nf-call-iptables)" == 1 ]]'
check "containerd 실행 중"        systemctl is-active --quiet containerd
check "kubelet·kubeadm·kubectl 고정" bash -c '[[ "$(apt-mark showhold | grep -cE "^(kubelet|kubeadm|kubectl)$")" == 3 ]]'
echo "  containerd $(containerd --version | awk '{print $3}') / kubeadm $(kubeadm version -o short)"

[[ $fail -eq 0 ]] || die "확인 실패 항목이 있다"
log "완료: $(hostname) 준비 끝. 다음은 kubeadm init(control-plane) 또는 join(worker)"
