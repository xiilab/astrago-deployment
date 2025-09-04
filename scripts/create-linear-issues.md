# Linear Sub-Issues for BE-384 Helmfile Refactoring

## Phase 1: Foundation (우선 등록)

### 🔹 BE-384-1: Create new helmfile directory structure

**Team**: Back-end  
**Status**: Triage  
**Reporter**: m.kwon  
**Priority**: High  
**Labels**: infrastructure, refactoring, phase-1  
**Estimate**: 1 day  

**Description**:
```
## Objective
Create the foundation directory structure for helmfile refactoring to centralize all helmfile-related files.

## Background
Current helmfile files are scattered across the project root and applications/ subdirectories, making management complex.

## Tasks
- [ ] Create helmfile/ root directory
- [ ] Create helmfile/charts/external/ for downloaded external charts
- [ ] Create helmfile/charts/custom/ for custom charts
- [ ] Create helmfile/charts/patches/ for Kustomize patches
- [ ] Create helmfile/values/common/ for shared values
- [ ] Create helmfile/values/templates/ for Go templates
- [ ] Create helmfile/environments/{dev,stage,prod}/ for environment configs

## Acceptance Criteria
- [ ] Directory structure matches the specification
- [ ] No existing files are affected
- [ ] Structure supports offline deployment requirements

## Definition of Done
- [ ] All directories created
- [ ] README.md added explaining structure
- [ ] Verified in development environment
```

---

### 🔹 BE-384-2: Develop external charts download script

**Team**: Back-end  
**Status**: Triage  
**Reporter**: m.kwon  
**Priority**: High  
**Labels**: automation, offline, phase-1  
**Estimate**: 2 days  

**Description**:
```
## Objective
Develop automation script to download all external Helm charts for offline deployment support.

## Background
Astrago deployment must work in airgap environments where internet access is not available.

## Tasks
- [ ] Create scripts/sync-charts.sh script
- [ ] Define chart inventory with versions:
  - GPU Operator v25.3.2
  - Prometheus Stack 45.7.1
  - Loki Stack 2.9.10
  - Keycloak 18.4.0
  - Harbor 1.13.1
  - MPI Operator 0.4.0
- [ ] Implement versions.lock generation
- [ ] Add checksum validation
- [ ] Add error handling and rollback

## Acceptance Criteria
- [ ] Script downloads all required charts
- [ ] Charts are stored with version in directory name
- [ ] versions.lock file tracks all metadata
- [ ] Checksum validation works
- [ ] Script handles network failures gracefully

## Definition of Done
- [ ] Script tested on clean environment
- [ ] All charts downloaded successfully
- [ ] Documentation added to script
- [ ] Error scenarios tested
```

---

### 🔹 BE-384-3: Download and store external charts locally

**Team**: Back-end  
**Status**: Triage  
**Reporter**: m.kwon  
**Priority**: High  
**Labels**: offline, charts, phase-1  
**Estimate**: 1 day  
**Dependencies**: BE-384-2  

**Description**:
```
## Objective
Execute the download script to store all external charts locally for offline deployment.

## Background
All external charts must be available locally to support airgap deployment scenarios.

## Dependencies
- BE-384-2 (Download script must be completed)

## Tasks
- [ ] Execute sync-charts.sh script
- [ ] Verify all charts downloaded correctly
- [ ] Validate versions.lock file
- [ ] Check chart integrity with checksums
- [ ] Test local chart access

## Acceptance Criteria
- [ ] All 6 external charts stored locally
- [ ] Directory naming follows pattern: chart-name-version
- [ ] versions.lock file complete and accurate
- [ ] All checksums valid
- [ ] No external dependencies remain

## Definition of Done
- [ ] Charts accessible without internet
- [ ] File sizes reasonable for distribution
- [ ] Backup strategy documented
```

---

## Phase 2: Core Implementation (나중에 등록)

### 🔹 BE-384-4: Create unified helmfile.yaml

**Team**: Back-end  
**Status**: Triage  
**Reporter**: m.kwon  
**Priority**: High  
**Labels**: core, helmfile, phase-2  
**Estimate**: 3 days  
**Dependencies**: BE-384-1, BE-384-3  

**Description**:
```
## Objective
Create single helmfile.yaml containing all application releases organized by tiers.

## Background
Current structure has multiple helmfile.yaml files causing complexity. Unifying into single file improves maintainability.

## Dependencies
- BE-384-1 (Directory structure)
- BE-384-3 (Local charts available)

## Tasks
- [ ] Define Tier 1 - Infrastructure:
  - CSI Driver NFS
  - GPU Operator  
  - Flux
- [ ] Define Tier 2 - Monitoring:
  - Prometheus
  - Loki Stack
  - GPU Process Exporter
- [ ] Define Tier 3 - Security & Registry:
  - Keycloak
  - Harbor
  - MPI Operator
- [ ] Define Tier 4 - Applications:
  - Astrago
- [ ] Configure dependencies (needs field)
- [ ] Add labels and priorities
- [ ] Configure environment-specific values

## Acceptance Criteria
- [ ] Single helmfile.yaml contains all releases
- [ ] Tier-based organization clear
- [ ] Dependencies properly defined
- [ ] Environment-specific configurations work
- [ ] Local chart paths correct

## Definition of Done
- [ ] Helmfile syntax validation passes
- [ ] Template rendering works
- [ ] All charts reference local paths
- [ ] Dependencies tested
```

---

### 🔹 BE-384-5: Migrate environment configurations

**Team**: Back-end  
**Status**: Triage  
**Reporter**: m.kwon  
**Priority**: Medium  
**Labels**: configuration, environments, phase-2  
**Estimate**: 2 days  
**Dependencies**: BE-384-1  

**Description**:
```
## Objective
Migrate existing environment configurations to new structure with proper inheritance.

## Background
Current environment files need reorganization to support new unified helmfile structure.

## Dependencies
- BE-384-1 (Directory structure)

## Tasks
- [ ] Analyze existing environments/ structure
- [ ] Extract common configurations to values/common/defaults.yaml
- [ ] Create environment-specific overrides:
  - environments/dev/values.yaml
  - environments/stage/values.yaml
  - environments/prod/values.yaml
- [ ] Convert existing gotmpl files to new structure
- [ ] Update secret management approach

## Acceptance Criteria
- [ ] No configuration duplication
- [ ] Environment inheritance works properly
- [ ] All existing environment variables preserved
- [ ] Secret management secure
- [ ] Template rendering functional

## Definition of Done
- [ ] All environments render correctly
- [ ] No breaking changes to existing deployments
- [ ] Documentation updated
- [ ] Team reviewed configurations
```

---

### 🔹 BE-384-6: Migrate custom charts

**Team**: Back-end  
**Status**: Triage  
**Reporter**: m.kwon  
**Priority**: Medium  
**Labels**: charts, migration, phase-2  
**Estimate**: 2 days  
**Dependencies**: BE-384-1  

**Description**:
```
## Objective
Move all custom Helm charts from applications/ to helmfile/charts/custom/ structure.

## Background
Custom charts (astrago, csi-driver-nfs, etc.) need to be relocated and verified in new structure.

## Dependencies
- BE-384-1 (Directory structure)

## Tasks
- [ ] Migrate astrago chart
- [ ] Migrate csi-driver-nfs chart
- [ ] Migrate gpu-process-exporter chart
- [ ] Migrate flux chart
- [ ] Update Chart.yaml metadata
- [ ] Verify template compatibility
- [ ] Update values.yaml references

## Acceptance Criteria
- [ ] All custom charts in helmfile/charts/custom/
- [ ] Chart.yaml files valid
- [ ] Templates render correctly
- [ ] Values inheritance works
- [ ] No breaking changes

## Definition of Done
- [ ] Charts lint successfully
- [ ] Templates validated
- [ ] Dependency tracking works
- [ ] Documentation updated
```

---

## 등록 방법

### Option 1: Linear 웹 인터페이스
1. https://linear.app 접속
2. Back-end 팀 보드로 이동
3. New Issue 클릭
4. 위 내용 복사하여 붙여넣기
5. Status를 Triage로 설정

### Option 2: Linear API (API Key 필요)
```bash
# API Key 설정
export LINEAR_API_KEY="your-api-key"

# GraphQL 요청으로 이슈 생성
curl -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation CreateIssue($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { id identifier title } } }",
    "variables": {
      "input": {
        "teamId": "BACK-END-TEAM-ID",
        "title": "[BE-384-1] Create new helmfile directory structure",
        "description": "위 내용",
        "priority": 1,
        "labelIds": ["infrastructure-label-id", "refactoring-label-id"],
        "estimate": 1
      }
    }
  }'
```

### Option 3: Linear CLI (재설치 필요)
```bash
# Linear CLI 설치
npm install -g @linear/cli

# 로그인
linear login

# 이슈 생성
linear issue create \
  --team "Back-end" \
  --title "[BE-384-1] Create new helmfile directory structure" \
  --description "위 내용" \
  --priority high \
  --labels "infrastructure,refactoring,phase-1"
```