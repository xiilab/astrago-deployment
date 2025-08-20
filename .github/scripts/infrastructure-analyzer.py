#!/usr/bin/env python3
"""
AstraGo Infrastructure Analyzer
Analyzes infrastructure changes in astrago-deployment repository
"""

import os
import yaml
import re
import json
from pathlib import Path
from typing import Dict, List, Any, Tuple

class AstraGoInfrastructureAnalyzer:
    def __init__(self):
        self.changed_files = os.environ.get('CHANGED_FILES', '').split()
        self.pr_number = os.environ.get('PR_NUMBER', 'unknown')
        self.analysis_results = {
            'warnings': [],
            'improvements': [],
            'resource_impact': {},
            'cost_analysis': {},
            'security_checks': [],
            'best_practices': []
        }
        
        # AstraGo specific patterns and limits
        self.astrago_patterns = {
            'gpu_node_limits': {'max_gpus_per_node': 8, 'recommended_memory_per_gpu': '16Gi'},
            'keycloak_limits': {'min_memory': '1Gi', 'recommended_replicas': 2},
            'harbor_limits': {'min_memory': '2Gi', 'min_storage': '50Gi'},
            'astrago_limits': {'min_memory': '4Gi', 'min_cpu': '2000m'},
            'default_ports': {
                'keycloak': 30001,
                'astrago': 30080, 
                'harbor': 30002,
                'prometheus': 30003
            }
        }

    def load_yaml_safe(self, file_path: str) -> Dict[str, Any]:
        """Safely load YAML file with error handling"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                
            # Handle Helm templating in .gotmpl files
            if file_path.endswith('.gotmpl'):
                # Simple templating removal for analysis
                content = re.sub(r'\{\{.*?\}\}', '""', content)
                
            return yaml.safe_load(content) or {}
        except Exception as e:
            print(f"Warning: Could not parse {file_path}: {e}")
            return {}

    def analyze_resource_impact(self, yaml_data: Dict, file_path: str):
        """Analyze resource impact of changes"""
        
        # Check GPU configurations
        self.check_gpu_configuration(yaml_data, file_path)
        
        # Check memory and CPU settings
        self.check_resource_limits(yaml_data, file_path)
        
        # Check storage configurations
        self.check_storage_configuration(yaml_data, file_path)

    def check_gpu_configuration(self, yaml_data: Dict, file_path: str):
        """Check GPU-related configurations"""
        def search_gpu_config(obj, path=""):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    current_path = f"{path}.{key}" if path else key
                    
                    if key == "nvidia.com/gpu":
                        gpu_count = int(value) if str(value).isdigit() else 0
                        if gpu_count > 4:
                            self.analysis_results['warnings'].append({
                                'type': 'GPU_OVERALLOCATION',
                                'file': file_path,
                                'message': f'⚠️ GPU 요청량이 높습니다 ({gpu_count}개). 클러스터 용량을 확인하세요.',
                                'suggestion': '일반적으로 노드당 2-4개 GPU가 안정적입니다.'
                            })
                        elif gpu_count == 0:
                            self.analysis_results['warnings'].append({
                                'type': 'GPU_ZERO_REQUEST',
                                'file': file_path,
                                'message': '⚠️ GPU 요청이 0입니다. ML 워크로드에서는 적절한 GPU 리소스가 필요합니다.'
                            })
                    
                    elif key == "gpu-operator" or key == "gpuOperator":
                        self.analysis_results['best_practices'].append({
                            'type': 'GPU_OPERATOR_CONFIG',
                            'file': file_path,
                            'message': '✅ GPU Operator 설정이 감지되었습니다.',
                            'suggestion': 'DCGM 메트릭 수집이 활성화되었는지 확인하세요.'
                        })
                    
                    search_gpu_config(value, current_path)
                    
            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    search_gpu_config(item, f"{path}[{i}]")
        
        search_gpu_config(yaml_data)

    def check_resource_limits(self, yaml_data: Dict, file_path: str):
        """Check CPU and Memory resource limits"""
        def search_resources(obj, path=""):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    current_path = f"{path}.{key}" if path else key
                    
                    if key == "resources" and isinstance(value, dict):
                        limits = value.get('limits', {})
                        requests = value.get('requests', {})
                        
                        # Memory checks
                        memory_limit = limits.get('memory', '')
                        memory_request = requests.get('memory', '')
                        
                        if 'keycloak' in file_path.lower():
                            if self.parse_memory(memory_limit) < self.parse_memory('1Gi'):
                                self.analysis_results['warnings'].append({
                                    'type': 'KEYCLOAK_LOW_MEMORY',
                                    'file': file_path,
                                    'message': f'⚠️ Keycloak 메모리 제한이 낮습니다 ({memory_limit})',
                                    'suggestion': '최소 1Gi 이상 권장합니다. OOMKilled 방지를 위해 2Gi가 더 안정적입니다.'
                                })
                        
                        elif 'harbor' in file_path.lower():
                            if self.parse_memory(memory_limit) < self.parse_memory('2Gi'):
                                self.analysis_results['warnings'].append({
                                    'type': 'HARBOR_LOW_MEMORY',
                                    'file': file_path,
                                    'message': f'⚠️ Harbor 메모리 제한이 낮습니다 ({memory_limit})',
                                    'suggestion': '최소 2Gi 이상 권장합니다.'
                                })
                        
                        elif 'astrago' in file_path.lower():
                            if self.parse_memory(memory_limit) < self.parse_memory('4Gi'):
                                self.analysis_results['improvements'].append({
                                    'type': 'ASTRAGO_MEMORY_OPTIMIZATION',
                                    'file': file_path,
                                    'message': f'💡 AstraGo 메모리를 최적화할 수 있습니다 ({memory_limit})',
                                    'suggestion': 'ML 워크로드 특성상 4Gi 이상이 권장됩니다.'
                                })
                    
                    search_resources(value, current_path)
                    
            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    search_resources(item, f"{path}[{i}]")
        
        search_resources(yaml_data)

    def check_storage_configuration(self, yaml_data: Dict, file_path: str):
        """Check storage configurations"""
        def search_storage(obj, path=""):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    if key in ['storage', 'size'] and isinstance(value, str):
                        size_gb = self.parse_storage_size(value)
                        
                        if 'harbor' in file_path.lower() and size_gb < 50:
                            self.analysis_results['warnings'].append({
                                'type': 'HARBOR_LOW_STORAGE',
                                'file': file_path,
                                'message': f'⚠️ Harbor 스토리지가 부족할 수 있습니다 ({value})',
                                'suggestion': '컨테이너 이미지 저장을 위해 최소 50Gi 권장합니다.'
                            })
                        
                        elif 'nfs' in file_path.lower() or 'csi' in file_path.lower():
                            self.analysis_results['best_practices'].append({
                                'type': 'NFS_STORAGE_CONFIG',
                                'file': file_path,
                                'message': f'✅ 공유 스토리지 설정 감지: {value}',
                                'suggestion': '백업 정책과 용량 모니터링을 설정하세요.'
                            })
                    
                    if isinstance(value, (dict, list)):
                        search_storage(value, f"{path}.{key}")
            
            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    search_storage(item, f"{path}[{i}]")
        
        search_storage(yaml_data)

    def check_security_best_practices(self, yaml_data: Dict, file_path: str):
        """Check security configurations"""
        security_issues = []
        
        # Check for hardcoded passwords (basic check)
        yaml_str = yaml.dump(yaml_data)
        if re.search(r'password:\s*[\'"]?[a-zA-Z0-9]{1,20}[\'"]?', yaml_str, re.IGNORECASE):
            security_issues.append({
                'type': 'HARDCODED_PASSWORD',
                'file': file_path,
                'message': '🔒 하드코딩된 패스워드가 감지되었을 수 있습니다.',
                'suggestion': 'Kubernetes Secret을 사용하여 민감한 정보를 관리하세요.'
            })
        
        # Check for missing security contexts
        def check_security_context(obj):
            if isinstance(obj, dict):
                if 'containers' in obj:
                    for container in obj['containers']:
                        if isinstance(container, dict) and 'securityContext' not in container:
                            security_issues.append({
                                'type': 'MISSING_SECURITY_CONTEXT',
                                'file': file_path,
                                'message': '🔒 컨테이너에 보안 컨텍스트가 없습니다.',
                                'suggestion': 'runAsNonRoot, readOnlyRootFilesystem 등을 설정하세요.'
                            })
                
                for value in obj.values():
                    if isinstance(value, (dict, list)):
                        check_security_context(value)
        
        check_security_context(yaml_data)
        self.analysis_results['security_checks'].extend(security_issues)

    def estimate_cost_impact(self):
        """Estimate cost impact of changes"""
        # Simple cost estimation based on resource changes
        cpu_cost_per_hour = 0.048  # USD per vCPU hour
        memory_cost_per_hour = 0.006  # USD per GB hour
        gpu_cost_per_hour = 0.90   # USD per GPU hour
        
        estimated_monthly_cost = 0
        
        # This is a simplified calculation
        # In a real scenario, you'd compare before/after configurations
        
        cost_summary = {
            'estimated_monthly_increase': estimated_monthly_cost,
            'recommendations': [
                '💰 비용 최적화를 위해 리소스 requests/limits를 정확히 설정하세요.',
                '📊 실제 사용량 모니터링 후 리소스를 조정하세요.',
                '⚡ GPU 사용량이 낮을 때는 스케일 다운을 고려하세요.'
            ]
        }
        
        self.analysis_results['cost_analysis'] = cost_summary

    def parse_memory(self, memory_str: str) -> int:
        """Parse memory string to bytes"""
        if not memory_str:
            return 0
        
        memory_str = str(memory_str).strip()
        
        # Convert to bytes
        multipliers = {
            'Ki': 1024,
            'Mi': 1024**2,  
            'Gi': 1024**3,
            'Ti': 1024**4,
            'K': 1000,
            'M': 1000**2,
            'G': 1000**3,
            'T': 1000**4
        }
        
        for suffix, multiplier in multipliers.items():
            if memory_str.endswith(suffix):
                number = memory_str[:-len(suffix)]
                try:
                    return int(float(number) * multiplier)
                except ValueError:
                    return 0
        
        # If no suffix, assume bytes
        try:
            return int(memory_str)
        except ValueError:
            return 0

    def parse_storage_size(self, storage_str: str) -> int:
        """Parse storage string to GB"""
        if not storage_str:
            return 0
        
        storage_str = str(storage_str).strip()
        
        # Convert to GB
        if storage_str.endswith('Gi'):
            return int(float(storage_str[:-2]))
        elif storage_str.endswith('G'):
            return int(float(storage_str[:-1]))
        elif storage_str.endswith('Ti'):
            return int(float(storage_str[:-2]) * 1024)
        elif storage_str.endswith('T'):
            return int(float(storage_str[:-1]) * 1000)
        
        return 0

    def generate_report(self) -> str:
        """Generate markdown report"""
        report = []
        
        # Header
        report.append("# 🏗️ AstraGo Infrastructure Review")
        report.append("")
        report.append(f"**PR #{self.pr_number}** - Infrastructure Analysis Report")
        report.append("")
        
        # Summary
        total_issues = len(self.analysis_results['warnings'])
        total_improvements = len(self.analysis_results['improvements'])
        total_security = len(self.analysis_results['security_checks'])
        
        if total_issues == 0 and total_improvements == 0 and total_security == 0:
            report.append("✅ **모든 검사를 통과했습니다!** 인프라 설정이 우수합니다.")
            report.append("")
        else:
            report.append("## 📊 검사 결과 요약")
            report.append("")
            report.append(f"- ⚠️  경고사항: **{total_issues}개**")
            report.append(f"- 💡 개선사항: **{total_improvements}개**") 
            report.append(f"- 🔒 보안 점검: **{total_security}개**")
            report.append("")
        
        # Warnings
        if self.analysis_results['warnings']:
            report.append("## ⚠️ 경고사항")
            report.append("")
            for warning in self.analysis_results['warnings']:
                report.append(f"### {warning['message']}")
                report.append(f"**파일:** `{warning['file']}`")
                if 'suggestion' in warning:
                    report.append(f"**권장사항:** {warning['suggestion']}")
                report.append("")
        
        # Improvements
        if self.analysis_results['improvements']:
            report.append("## 💡 개선사항")
            report.append("")
            for improvement in self.analysis_results['improvements']:
                report.append(f"### {improvement['message']}")
                report.append(f"**파일:** `{improvement['file']}`")
                if 'suggestion' in improvement:
                    report.append(f"**제안:** {improvement['suggestion']}")
                report.append("")
        
        # Security Checks
        if self.analysis_results['security_checks']:
            report.append("## 🔒 보안 점검")
            report.append("")
            for security in self.analysis_results['security_checks']:
                report.append(f"### {security['message']}")
                report.append(f"**파일:** `{security['file']}`")
                if 'suggestion' in security:
                    report.append(f"**권장사항:** {security['suggestion']}")
                report.append("")
        
        # Best Practices
        if self.analysis_results['best_practices']:
            report.append("## ✅ 모범사례")
            report.append("")
            for practice in self.analysis_results['best_practices']:
                report.append(f"- {practice['message']}")
                if 'suggestion' in practice:
                    report.append(f"  - {practice['suggestion']}")
            report.append("")
        
        # Cost Analysis
        if self.analysis_results['cost_analysis'].get('recommendations'):
            report.append("## 💰 비용 최적화 권장사항")
            report.append("")
            for rec in self.analysis_results['cost_analysis']['recommendations']:
                report.append(f"- {rec}")
            report.append("")
        
        # Footer
        report.append("---")
        report.append("🤖 *이 리뷰는 AstraGo Infrastructure Analyzer에 의해 자동 생성되었습니다.*")
        report.append("")
        report.append("💬 **질문이나 제안사항이 있으시면 댓글로 알려주세요!**")
        
        return "\n".join(report)

    def analyze_all_files(self):
        """Analyze all changed files"""
        print(f"Analyzing {len(self.changed_files)} changed files...")
        
        for file_path in self.changed_files:
            if not os.path.exists(file_path):
                continue
                
            print(f"Analyzing: {file_path}")
            
            # Load and analyze YAML
            yaml_data = self.load_yaml_safe(file_path)
            if yaml_data:
                self.analyze_resource_impact(yaml_data, file_path)
                self.check_security_best_practices(yaml_data, file_path)
        
        # Generate cost analysis
        self.estimate_cost_impact()
        
        # Generate and save report
        report = self.generate_report()
        
        # Save to temp file for GitHub Action to read
        with open('/tmp/infrastructure-analysis.md', 'w', encoding='utf-8') as f:
            f.write(report)
        
        print("Analysis completed!")
        print("=" * 50)
        print(report)

if __name__ == "__main__":
    analyzer = AstraGoInfrastructureAnalyzer()
    analyzer.analyze_all_files()