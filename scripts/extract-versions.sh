#!/bin/bash
# Astrago Deployment - 오픈소스 버전 자동 추출 스크립트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FILE="${OUTPUT_FILE:-$PROJECT_ROOT/VERSIONS_REPORT.md}"

echo "=== Astrago Deployment 버전 정보 추출 중... ==="
echo ""

# 출력 파일 초기화
cat > "$OUTPUT_FILE" << 'EOF'
# Astrago Deployment - 오픈소스 버전 보고서

**생성일:** $(date '+%Y-%m-%d %H:%M:%S')

---

## 📦 **1. Kubernetes & Container Runtime**

EOF

# 1. Kubernetes 버전 (Kubespray)
echo "1️⃣ Kubernetes 버전 추출 중..."
K8S_VERSION=$(grep "^kube_version:" "$PROJECT_ROOT/kubespray/inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml" 2>/dev/null | awk '{print $2}' || echo "Not found")
cat >> "$OUTPUT_FILE" << EOF

### **Kubernetes**
- **버전**: \`$K8S_VERSION\`
- **관리 도구**: Kubespray (Ansible)
- **설정 파일**: \`kubespray/inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml\`

EOF

# Container Runtime
CONTAINERD_VERSION=$(grep "^containerd_version:" "$PROJECT_ROOT/kubespray/inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml" 2>/dev/null | awk '{print $2}' || echo "Not found")
cat >> "$OUTPUT_FILE" << EOF
### **Container Runtime**
- **런타임**: containerd
- **버전**: \`$CONTAINERD_VERSION\`

EOF

# 2. Helm Charts 버전
echo "2️⃣ Helm Chart 버전 추출 중..."
cat >> "$OUTPUT_FILE" << 'EOF'

---

## 📊 **2. Application Helm Charts**

EOF

# 각 애플리케이션별 Chart 버전 추출
for app_dir in "$PROJECT_ROOT/applications"/*/; do
    app_name=$(basename "$app_dir")
    
    # Chart.yaml에서 버전 추출
    chart_yaml="$app_dir/*/Chart.yaml"
    if [ -f $chart_yaml 2>/dev/null ]; then
        chart_version=$(grep "^version:" $chart_yaml 2>/dev/null | head -1 | awk '{print $2}')
        app_version=$(grep "^appVersion:" $chart_yaml 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"')
        
        if [ -n "$chart_version" ]; then
            cat >> "$OUTPUT_FILE" << EOF

### **$app_name**
- **Chart 버전**: \`$chart_version\`
- **App 버전**: \`${app_version:-N/A}\`
- **경로**: \`applications/$app_name/\`

EOF
        fi
    fi
done

# 3. GPU Operator
echo "3️⃣ GPU Operator 버전 추출 중..."
cat >> "$OUTPUT_FILE" << 'EOF'

---

## 🎮 **3. GPU & ML Infrastructure**

EOF

GPU_OPERATOR_VERSION=$(grep "version:" "$PROJECT_ROOT/applications/gpu-operator/custom-gpu-operator/Chart.yaml" 2>/dev/null | awk '{print $2}' || echo "Not found")
DRIVER_VERSION=$(grep "version:" "$PROJECT_ROOT/environments/prod/values.yaml" 2>/dev/null | grep -A1 "driver:" | tail -1 | awk '{print $2}' | tr -d '"' || echo "Not found")

cat >> "$OUTPUT_FILE" << EOF
### **NVIDIA GPU Operator**
- **Chart 버전**: \`$GPU_OPERATOR_VERSION\`
- **Driver 버전**: \`$DRIVER_VERSION\`
- **설정 파일**: \`applications/gpu-operator/\`

EOF

# 4. Ingress Controller
echo "4️⃣ Ingress Controller 버전 추출 중..."
cat >> "$OUTPUT_FILE" << 'EOF'

---

## 🌐 **4. Network & Ingress**

EOF

INGRESS_VERSION=$(grep "version:" "$PROJECT_ROOT/applications/ingress-nginx/ingress-nginx/Chart.yaml" 2>/dev/null | awk '{print $2}' || echo "Not found")
cat >> "$OUTPUT_FILE" << EOF
### **ingress-nginx**
- **Chart 버전**: \`$INGRESS_VERSION\`
- **경로**: \`applications/ingress-nginx/\`

EOF

# Calico
CALICO_VERSION=$(grep "calico_version:" "$PROJECT_ROOT/kubespray/inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml" 2>/dev/null | awk '{print $2}' || echo "Not found")
cat >> "$OUTPUT_FILE" << EOF
### **Calico (CNI)**
- **버전**: \`$CALICO_VERSION\`
- **플러그인 타입**: VXLAN

EOF

# 5. Monitoring Stack
echo "5️⃣ Monitoring Stack 버전 추출 중..."
cat >> "$OUTPUT_FILE" << 'EOF'

---

## 📈 **5. Monitoring & Observability**

EOF

PROMETHEUS_VERSION=$(grep "version:" "$PROJECT_ROOT/applications/prometheus/kube-prometheus-stack/Chart.yaml" 2>/dev/null | awk '{print $2}' || echo "Not found")
LOKI_VERSION=$(grep "version:" "$PROJECT_ROOT/applications/loki-stack/Chart.yaml" 2>/dev/null | awk '{print $2}' || echo "Not found")

cat >> "$OUTPUT_FILE" << EOF
### **Prometheus Stack**
- **Chart 버전**: \`$PROMETHEUS_VERSION\`
- **구성요소**: Prometheus, Grafana, Alertmanager, Node Exporter
- **경로**: \`applications/prometheus/\`

### **Loki Stack**
- **Chart 버전**: \`$LOKI_VERSION\`
- **구성요소**: Loki, Promtail
- **경로**: \`applications/loki-stack/\`

EOF

# 6. Storage
echo "6️⃣ Storage 버전 추출 중..."
cat >> "$OUTPUT_FILE" << 'EOF'

---

## 💾 **6. Storage**

EOF

NFS_CSI_VERSION=$(grep "version:" "$PROJECT_ROOT/applications/csi-driver-nfs/csi-driver-nfs/Chart.yaml" 2>/dev/null | awk '{print $2}' || echo "Not found")
cat >> "$OUTPUT_FILE" << EOF
### **NFS CSI Driver**
- **Chart 버전**: \`$NFS_CSI_VERSION\`
- **경로**: \`applications/csi-driver-nfs/\`

EOF

# 7. Authentication
echo "7️⃣ Authentication 버전 추출 중..."
cat >> "$OUTPUT_FILE" << 'EOF'

---

## 🔐 **7. Authentication & Security**

EOF

KEYCLOAK_VERSION=$(grep "version:" "$PROJECT_ROOT/applications/keycloak/keycloak/Chart.yaml" 2>/dev/null | awk '{print $2}' || echo "Not found")
cat >> "$OUTPUT_FILE" << EOF
### **Keycloak**
- **Chart 버전**: \`$KEYCLOAK_VERSION\`
- **경로**: \`applications/keycloak/\`

EOF

# 8. Registry
echo "8️⃣ Registry 버전 추출 중..."
cat >> "$OUTPUT_FILE" << 'EOF'

---

## 🐳 **8. Container Registry**

EOF

HARBOR_VERSION=$(grep "version:" "$PROJECT_ROOT/applications/harbor/harbor/Chart.yaml" 2>/dev/null | awk '{print $2}' || echo "Not found")
cat >> "$OUTPUT_FILE" << EOF
### **Harbor**
- **Chart 버전**: \`$HARBOR_VERSION\`
- **경로**: \`applications/harbor/\`

EOF

# 9. Astrago Application
echo "9️⃣ Astrago Application 버전 추출 중..."
cat >> "$OUTPUT_FILE" << 'EOF'

---

## 🚀 **9. Astrago Application**

EOF

ASTRAGO_CHART_VERSION=$(grep "version:" "$PROJECT_ROOT/applications/astrago/astrago/Chart.yaml" 2>/dev/null | awk '{print $2}' || echo "Not found")

# 컴포넌트 버전 (environments/prod/values.yaml에서)
CORE_TAG=$(grep "imageTag:" "$PROJECT_ROOT/environments/prod/values.yaml" 2>/dev/null | grep -A1 "core:" | tail -1 | awk '{print $2}' | tr -d '"' || echo "Not found")
BATCH_TAG=$(grep "imageTag:" "$PROJECT_ROOT/environments/prod/values.yaml" 2>/dev/null | grep -A1 "batch:" | tail -1 | awk '{print $2}' | tr -d '"' || echo "Not found")
MONITOR_TAG=$(grep "imageTag:" "$PROJECT_ROOT/environments/prod/values.yaml" 2>/dev/null | grep -A1 "monitor:" | tail -1 | awk '{print $2}' | tr -d '"' || echo "Not found")
FRONTEND_TAG=$(grep "imageTag:" "$PROJECT_ROOT/environments/prod/values.yaml" 2>/dev/null | grep -A1 "frontend:" | tail -1 | awk '{print $2}' | tr -d '"' || echo "Not found")

cat >> "$OUTPUT_FILE" << EOF
### **Astrago**
- **Chart 버전**: \`$ASTRAGO_CHART_VERSION\`
- **경로**: \`applications/astrago/\`

#### **컴포넌트 버전**
- **Core**: \`$CORE_TAG\`
- **Batch**: \`$BATCH_TAG\`
- **Monitor**: \`$MONITOR_TAG\`
- **Frontend**: \`$FRONTEND_TAG\`

EOF

# 10. 도구 및 유틸리티
echo "🔟 도구 버전 추출 중..."
cat >> "$OUTPUT_FILE" << 'EOF'

---

## 🛠️ **10. Tools & Utilities**

EOF

# Helm
if [ -f "$PROJECT_ROOT/tools/linux/helm" ]; then
    HELM_VERSION=$("$PROJECT_ROOT/tools/linux/helm" version --short 2>/dev/null | cut -d'+' -f1 || echo "Not found")
else
    HELM_VERSION=$(helm version --short 2>/dev/null | cut -d'+' -f1 || echo "Not installed")
fi

# Helmfile
if [ -f "$PROJECT_ROOT/tools/linux/helmfile" ]; then
    HELMFILE_VERSION=$("$PROJECT_ROOT/tools/linux/helmfile" version 2>/dev/null | grep "Version:" | awk '{print $2}' || echo "Not found")
else
    HELMFILE_VERSION=$(helmfile version 2>/dev/null | grep "Version:" | awk '{print $2}' || echo "Not installed")
fi

# kubectl
if [ -f "$PROJECT_ROOT/tools/linux/kubectl" ]; then
    KUBECTL_VERSION=$("$PROJECT_ROOT/tools/linux/kubectl" version --client --short 2>/dev/null | cut -d' ' -f3 || echo "Not found")
else
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | cut -d' ' -f3 || echo "Not installed")
fi

cat >> "$OUTPUT_FILE" << EOF
### **Deployment Tools**
- **Helm**: \`$HELM_VERSION\`
- **Helmfile**: \`$HELMFILE_VERSION\`
- **kubectl**: \`$KUBECTL_VERSION\`

EOF

# Python (Ansible)
PYTHON_VERSION=$(python3 --version 2>/dev/null | awk '{print $2}' || echo "Not installed")
ANSIBLE_VERSION=$(ansible --version 2>/dev/null | head -1 | awk '{print $3}' || echo "Not installed")

cat >> "$OUTPUT_FILE" << EOF
### **Ansible & Python**
- **Python**: \`$PYTHON_VERSION\`
- **Ansible**: \`$ANSIBLE_VERSION\`

EOF

# 11. 요약 테이블
echo "📊 요약 테이블 생성 중..."
cat >> "$OUTPUT_FILE" << 'EOF'

---

## 📊 **11. 핵심 버전 요약**

| 구분 | 컴포넌트 | 버전 |
|------|----------|------|
EOF

cat >> "$OUTPUT_FILE" << EOF
| **인프라** | Kubernetes | \`$K8S_VERSION\` |
| | containerd | \`$CONTAINERD_VERSION\` |
| | Calico (CNI) | \`$CALICO_VERSION\` |
| **GPU** | GPU Operator | \`$GPU_OPERATOR_VERSION\` |
| | NVIDIA Driver | \`$DRIVER_VERSION\` |
| **네트워크** | ingress-nginx | \`$INGRESS_VERSION\` |
| **모니터링** | Prometheus Stack | \`$PROMETHEUS_VERSION\` |
| | Loki Stack | \`$LOKI_VERSION\` |
| **스토리지** | NFS CSI Driver | \`$NFS_CSI_VERSION\` |
| **인증** | Keycloak | \`$KEYCLOAK_VERSION\` |
| **레지스트리** | Harbor | \`$HARBOR_VERSION\` |
| **애플리케이션** | Astrago Chart | \`$ASTRAGO_CHART_VERSION\` |
| **도구** | Helm | \`$HELM_VERSION\` |
| | Helmfile | \`$HELMFILE_VERSION\` |
| | kubectl | \`$KUBECTL_VERSION\` |
| | Python | \`$PYTHON_VERSION\` |
| | Ansible | \`$ANSIBLE_VERSION\` |

EOF

cat >> "$OUTPUT_FILE" << 'EOF'

---

## 📝 **12. 라이선스 정보**

대부분의 컴포넌트는 **Apache 2.0** 라이선스를 따릅니다:
- Kubernetes: Apache 2.0
- Helm: Apache 2.0
- Calico: Apache 2.0
- Prometheus: Apache 2.0
- Harbor: Apache 2.0
- Keycloak: Apache 2.0

**참고:** 상용 환경 사용 시 각 컴포넌트의 라이선스를 반드시 확인하시기 바랍니다.

---

**📅 생성일:** $(date '+%Y-%m-%d %H:%M:%S')  
**🔧 스크립트:** `scripts/extract-versions.sh`
EOF

echo ""
echo "✅ 버전 정보 추출 완료!"
echo "📄 보고서 위치: $OUTPUT_FILE"
echo ""
echo "보고서를 확인하세요:"
echo "  cat $OUTPUT_FILE"

