#!/usr/bin/env bash
# control-plane 초기화 스크립트 (k8s-cp1 전용)
#
# node-prep.sh가 끝난 cp1에서 실행한다.
# kubeadm init → kubectl 설정 → Calico 설치 → 노드 Ready 대기 → worker용 join 명령 출력
#
# 사용: bash cluster-init.sh   (sudo 없이. 필요한 곳에서만 sudo를 쓴다)

set -euo pipefail

CP_IP="192.168.125.10"
POD_CIDR="10.244.0.0/16"          # 노드 대역(192.168.125.0/24)과 겹치면 안 된다
K8S_VERSION="v1.37.2"             # 설치된 kubelet과 같은 버전
CALICO_VERSION="v3.33.0"
CALICO_URL="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests"

log() { echo; echo "==> $*"; }
die() { echo "오류: $*" >&2; exit 1; }

# kubectl 설정을 실행한 사용자 홈에 만들어야 하므로 root로 실행하지 않는다
[[ $EUID -ne 0 ]] || die "sudo 없이 일반 사용자로 실행 (bash $0)"

# ---------------------------------------------------------------------------
log "1. kubeadm init"
if [[ -f /etc/kubernetes/admin.conf ]]; then
  echo "  이미 초기화됨 (/etc/kubernetes/admin.conf 있음) — 건너뜀"
else
  sudo kubeadm init \
    --apiserver-advertise-address="$CP_IP" \
    --pod-network-cidr="$POD_CIDR" \
    --kubernetes-version="$K8S_VERSION"
fi

# ---------------------------------------------------------------------------
log "2. kubectl 설정 (~/.kube/config)"
mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
# 파드 대역이 실제로 들어갔는지 확인 (init 옵션 누락으로 Calico가 실패한 적이 있다)
kubectl -n kube-system get configmap kubeadm-config -o yaml | grep -q "podSubnet: ${POD_CIDR}" \
  || die "kubeadm 설정에 podSubnet ${POD_CIDR}이 없다"
echo "  podSubnet ${POD_CIDR} 확인"

# ---------------------------------------------------------------------------
log "3. Calico ${CALICO_VERSION} 설치 (operator 방식)"
# --server-side: 이미 있으면 갱신. 다시 실행해도 오류가 나지 않는다
kubectl apply --server-side --force-conflicts -f "${CALICO_URL}/v3_projectcalico_org.yaml" > /dev/null
kubectl apply --server-side --force-conflicts -f "${CALICO_URL}/tigera-operator.yaml" > /dev/null
tmp="$(mktemp)"
curl -fsSL "${CALICO_URL}/custom-resources.yaml" -o "$tmp"
sed -i "s#192.168.0.0/16#${POD_CIDR}#" "$tmp"         # Calico 기본 대역을 우리 파드 대역으로
grep -q "cidr: ${POD_CIDR}" "$tmp" || die "custom-resources.yaml의 cidr 변경 실패"
kubectl apply --server-side --force-conflicts -f "$tmp" > /dev/null
rm -f "$tmp"
echo "  적용 완료"

# ---------------------------------------------------------------------------
log "4. 노드 Ready 대기 (최대 10분)"
kubectl wait --for=condition=Ready "node/$(hostname)" --timeout=600s
kubectl -n kube-system rollout status deployment/coredns --timeout=300s

# ---------------------------------------------------------------------------
log "5. 결과"
kubectl get nodes -o wide
echo
echo "worker(k8s-w1, k8s-w2)에서 아래 명령을 sudo로 실행:"
echo "  sudo $(sudo kubeadm token create --print-join-command)"
