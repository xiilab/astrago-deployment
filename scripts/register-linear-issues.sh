#!/bin/bash
# Linear Issue Registration Script for BE-384 Helmfile Refactoring

# Linear API Key를 환경 변수로 설정해주세요
# export LINEAR_API_KEY="lin_api_xxxxx"

if [ -z "$LINEAR_API_KEY" ]; then
    echo "❌ LINEAR_API_KEY 환경 변수가 설정되지 않았습니다."
    echo "사용법: export LINEAR_API_KEY='your-api-key'"
    exit 1
fi

# GraphQL endpoint
LINEAR_API="https://api.linear.app/graphql"

echo "🚀 Linear 이슈 등록 시작..."

# Function to create issue
create_issue() {
    local title="$1"
    local description="$2"
    local labels="$3"
    local estimate="$4"
    local priority="$5"
    
    echo "📝 등록 중: $title"
    
    # GraphQL mutation
    response=$(curl -s -X POST "$LINEAR_API" \
        -H "Authorization: $LINEAR_API_KEY" \
        -H "Content-Type: application/json" \
        -d @- <<EOF
{
    "query": "mutation CreateIssue(\$title: String!, \$description: String!) {
        issueCreate(input: {
            title: \$title,
            description: \$description,
            priority: $priority,
            estimate: $estimate
        }) {
            success
            issue {
                id
                identifier
                title
                url
            }
        }
    }",
    "variables": {
        "title": "$title",
        "description": "$description"
    }
}
EOF
)
    
    # Parse response
    if echo "$response" | grep -q '"success":true'; then
        identifier=$(echo "$response" | grep -o '"identifier":"[^"]*' | cut -d'"' -f4)
        url=$(echo "$response" | grep -o '"url":"[^"]*' | cut -d'"' -f4)
        echo "✅ 성공: $identifier - $url"
    else
        echo "❌ 실패: $response"
    fi
    
    echo ""
}

# BE-384-1: Create new helmfile directory structure
create_issue \
    "[BE-384-1] Create new helmfile directory structure" \
    "## Objective\nCreate the foundation directory structure for helmfile refactoring to centralize all helmfile-related files.\n\n## Background\nCurrent helmfile files are scattered across the project root and applications/ subdirectories, making management complex.\n\n## Tasks\n- [ ] Create helmfile/ root directory\n- [ ] Create helmfile/charts/external/ for downloaded external charts\n- [ ] Create helmfile/charts/custom/ for custom charts\n- [ ] Create helmfile/charts/patches/ for Kustomize patches\n- [ ] Create helmfile/values/common/ for shared values\n- [ ] Create helmfile/values/templates/ for Go templates\n- [ ] Create helmfile/environments/{dev,stage,prod}/ for environment configs\n\n## Acceptance Criteria\n- [ ] Directory structure matches the specification\n- [ ] No existing files are affected\n- [ ] Structure supports offline deployment requirements\n\n## Definition of Done\n- [ ] All directories created\n- [ ] README.md added explaining structure\n- [ ] Verified in development environment" \
    "infrastructure,refactoring,phase-1" \
    "1" \
    "1"

# BE-384-2: Develop external charts download script
create_issue \
    "[BE-384-2] Develop external charts download script" \
    "## Objective\nDevelop automation script to download all external Helm charts for offline deployment support.\n\n## Background\nAstrago deployment must work in airgap environments where internet access is not available.\n\n## Tasks\n- [ ] Create scripts/sync-charts.sh script\n- [ ] Define chart inventory with versions\n- [ ] Implement versions.lock generation\n- [ ] Add checksum validation\n- [ ] Add error handling and rollback\n\n## Acceptance Criteria\n- [ ] Script downloads all required charts\n- [ ] Charts are stored with version in directory name\n- [ ] versions.lock file tracks all metadata\n- [ ] Checksum validation works\n- [ ] Script handles network failures gracefully\n\n## Definition of Done\n- [ ] Script tested on clean environment\n- [ ] All charts downloaded successfully\n- [ ] Documentation added to script\n- [ ] Error scenarios tested" \
    "automation,offline,phase-1" \
    "2" \
    "1"

# BE-384-3: Download and store external charts locally
create_issue \
    "[BE-384-3] Download and store external charts locally" \
    "## Objective\nExecute the download script to store all external charts locally for offline deployment.\n\n## Background\nAll external charts must be available locally to support airgap deployment scenarios.\n\n## Dependencies\n- BE-384-2 (Download script must be completed)\n\n## Tasks\n- [ ] Execute sync-charts.sh script\n- [ ] Verify all charts downloaded correctly\n- [ ] Validate versions.lock file\n- [ ] Check chart integrity with checksums\n- [ ] Test local chart access\n\n## Acceptance Criteria\n- [ ] All 6 external charts stored locally\n- [ ] Directory naming follows pattern: chart-name-version\n- [ ] versions.lock file complete and accurate\n- [ ] All checksums valid\n- [ ] No external dependencies remain\n\n## Definition of Done\n- [ ] Charts accessible without internet\n- [ ] File sizes reasonable for distribution\n- [ ] Backup strategy documented" \
    "offline,charts,phase-1" \
    "1" \
    "1"

echo "✅ Linear 이슈 등록 완료!"
echo ""
echo "📋 등록된 이슈:"
echo "1. BE-384-1: Create new helmfile directory structure (1 day)"
echo "2. BE-384-2: Develop external charts download script (2 days)"
echo "3. BE-384-3: Download and store external charts locally (1 day)"
echo ""
echo "⚠️  참고사항:"
echo "- Team을 Back-end로 설정해야 합니다"
echo "- Status를 Triage로 변경해야 합니다"
echo "- Reporter를 m.kwon으로 설정해야 합니다"
echo "- 위 설정은 Linear 웹 인터페이스에서 수동으로 조정이 필요할 수 있습니다"