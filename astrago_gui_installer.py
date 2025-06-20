import curses
import os
import pathlib
import re
import subprocess
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

import yaml

ESCAPE_CODE = -1
REGEX_NODE_NAME = r'^[a-zA-Z0-9-]+$'
REGEX_IP_ADDRESS = r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$'
REGEX_PATH = r'^\/(?:[a-zA-Z0-9_-]+\/?)*$'
REGEX_URL = r'^https?://[^\s/$.?#].[^\s]*$|^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(:[0-9]+)?$'

# 환경 변수에서 설치 모드 가져오기
INSTALLATION_MODE = os.environ.get('ASTRAGO_INSTALLATION_MODE', 'online')

class DataManager:
    def __init__(self):
        self.nodes = []
        self.nfs_server = {
            'ip': '',
            'path': ''
        }
        self.environment_config = {
            'externalIP': '',
            'nfs': {
                'server': '',
                'basePath': ''
            },
            'offline': {
                'registry': '',
                'httpServer': ''
            }
        }
        self.save_nodes_file = 'nodes.yaml'
        self.save_nfs_server_file = 'nfs-servers.yaml'
        self.environment_name = 'astrago'
        
        # Load existing data
        self._load_data()

    def _load_data(self):
        # Load nodes from inventory file if it exists
        if os.path.exists(self.save_nodes_file):
            with open(self.save_nodes_file, 'r', encoding='utf-8') as f:
                self.nodes = yaml.safe_load(f) or []

        # Load NFS server config
        if os.path.exists(self.save_nfs_server_file):
            with open(self.save_nfs_server_file, 'r', encoding='utf-8') as f:
                self.nfs_server = yaml.safe_load(f) or {'ip': '', 'path': ''}

        # Load environment config
        env_file = f'environments/{self.environment_name}/values.yaml'
        if os.path.exists(env_file):
            with open(env_file, 'r', encoding='utf-8') as f:
                config = yaml.safe_load(f) or {}
                self.environment_config.update(config)

    def _save_to_nodes(self):
        with open(self.save_nodes_file, 'w', encoding='utf-8') as f:
            yaml.dump(self.nodes, f, default_flow_style=False, allow_unicode=True)

    def _save_to_nfs(self):
        with open(self.save_nfs_server_file, 'w', encoding='utf-8') as f:
            yaml.dump(self.nfs_server, f, default_flow_style=False, allow_unicode=True)

    def _save_environment_config(self):
        env_dir = f'environments/{self.environment_name}'
        os.makedirs(env_dir, exist_ok=True)
        
        env_file = f'{env_dir}/values.yaml'
        with open(env_file, 'w', encoding='utf-8') as f:
            yaml.dump(self.environment_config, f, default_flow_style=False, allow_unicode=True)

    def set_nfs_server(self, ip, path):
        self.nfs_server['ip'] = ip
        self.nfs_server['path'] = path
        self.environment_config['nfs']['server'] = ip
        self.environment_config['nfs']['basePath'] = path
        self._save_to_nfs()
        self._save_environment_config()

    def set_external_ip(self, ip):
        self.environment_config['externalIP'] = ip
        self._save_environment_config()

    def set_offline_config(self, registry, http_server):
        self.environment_config['offline']['registry'] = registry
        self.environment_config['offline']['httpServer'] = http_server
        self._save_environment_config()

    def get_environment_status(self):
        """환경 설정 상태를 반환"""
        status = {
            'configured': False,
            'external_ip': self.environment_config.get('externalIP', ''),
            'nfs_server': self.environment_config.get('nfs', {}).get('server', ''),
            'nfs_path': self.environment_config.get('nfs', {}).get('basePath', ''),
            'offline_registry': self.environment_config.get('offline', {}).get('registry', ''),
            'offline_http': self.environment_config.get('offline', {}).get('httpServer', ''),
            'nodes_count': len(self.nodes)
        }
        
        # 기본 설정이 완료되었는지 확인
        status['configured'] = bool(
            status['external_ip'] and 
            status['nfs_server'] and 
            status['nfs_path'] and
            status['nodes_count'] > 0
        )
        
        return status

    def add_node(self, name, ip, role, etcd):
        self.nodes.append({
            'name': name,
            'ip': ip,
            'role': role,
            'etcd': etcd
        })
        self._save_to_nodes()

    def remove_node(self, index):
        if 0 <= index < len(self.nodes):
            del self.nodes[index]
            self._save_to_nodes()

    def edit_node(self, index, name, ip, role, etcd):
        if 0 <= index < len(self.nodes):
            self.nodes[index]['name'] = name
            self.nodes[index]['ip'] = ip
            self.nodes[index]['role'] = role
            self.nodes[index]['etcd'] = etcd
            self._save_to_nodes()

    def list_nodes(self):
        return self.nodes

    def validate_ip(self, ip):
        """IP 주소 유효성 검사"""
        return bool(re.match(REGEX_IP_ADDRESS, ip))

    def validate_url(self, url):
        """URL 유효성 검사"""
        return bool(re.match(REGEX_URL, url))

    def validate_node_name(self, name):
        """노드 이름 유효성 검사 (Kubernetes 표준)"""
        if not name or len(name) > 63:
            return False
        return bool(re.match(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$', name))

    def validate_path(self, path):
        """경로 유효성 검사"""
        return bool(re.match(REGEX_PATH, path))


class CommandRunner:
    def __init__(self, data_manager):
        self.data_manager = data_manager
        self.current_dir = Path.cwd()
        self.kubespray_inventory_path = self.current_dir / 'kubespray/inventory/mycluster/astrago.yaml'
        self.nfs_inventory_path = '/tmp/nfs_inventory'
        self.gpu_inventory_path = '/tmp/gpu_inventory'
        self.ansible_extra_values = 'reset_confirmation=yes ansible_ssh_timeout=30 ansible_user={username}' \
                                    ' ansible_password={password} ansible_become_pass={password}'

    def _save_kubespray_inventory(self):
        """Kubespray 인벤토리 파일 생성"""
        inventory = {
            'all': {
                'children': {
                    'calico-rr': {'hosts': {}},
                    'etcd': {'hosts': {}},
                    'k8s-cluster': {
                        'children': {
                            'kube-master': {'hosts': {}},
                            'kube-node': {'hosts': {}}
                        }
                    },
                    'kube-master': {'hosts': {}},
                    'kube-node': {'hosts': {}}
                },
                'hosts': {}
            }
        }

        for node in self.data_manager.nodes:
            inventory['all']['hosts'][node['name']] = {
                'ansible_host': node['ip'],
                'ip': node['ip'],
                'access_ip': node['ip']
            }

            # Add node to appropriate group based on roles
            roles = node['role'].split(',')
            for role in roles:
                role = role.strip()
                if role == 'kube-master':
                    inventory['all']['children']['kube-master']['hosts'][node['name']] = None
                elif role == 'kube-node':
                    inventory['all']['children']['kube-node']['hosts'][node['name']] = None

            # Add node to etcd group if applicable
            if node['etcd'] == 'Y':
                inventory['all']['children']['etcd']['hosts'][node['name']] = None

        # Ensure directory exists
        os.makedirs(self.kubespray_inventory_path.parent, exist_ok=True)
        
        with open(self.kubespray_inventory_path, 'w', encoding='utf-8') as f:
            yaml.dump(inventory, f, default_flow_style=False, allow_unicode=True)

    def _apply_offline_settings(self):
        """오프라인 설정 적용"""
        if INSTALLATION_MODE != 'offline':
            return

        offline_config_dir = self.current_dir / 'kubespray/inventory/mycluster/group_vars/all'
        offline_config_file = offline_config_dir / 'offline.yml'
        
        # Create directory if it doesn't exist
        os.makedirs(offline_config_dir, exist_ok=True)
        
        # Get offline settings
        offline_config = self.data_manager.environment_config.get('offline', {})
        registry_host = offline_config.get('registry', '')
        http_server = offline_config.get('httpServer', '')
        
        if registry_host and http_server:
            offline_content = f"""# Offline configuration for kubespray
http_server: "{http_server}"
registry_host: "{registry_host}"

# Insecure registries for containerd
containerd_registries_mirrors:
  - prefix: "{{{{ registry_host }}}}"
    mirrors:
      - host: "http://{{{{ registry_host }}}}"
        capabilities: ["pull", "resolve"]
        skip_verify: true

files_repo: "{{{{ http_server }}}}/files"
yum_repo: "{{{{ http_server }}}}/rpms"
ubuntu_repo: "{{{{ http_server }}}}/debs"

# Registry overrides
kube_image_repo: "{{{{ registry_host }}}}"
gcr_image_repo: "{{{{ registry_host }}}}"
docker_image_repo: "{{{{ registry_host }}}}"
quay_image_repo: "{{{{ registry_host }}}}"
"""
            
            with open(offline_config_file, 'w', encoding='utf-8') as f:
                f.write(offline_content)

    def _run_command(self, cmd, cwd=None):
        """명령어 실행"""
        if cwd is None:
            cwd = self.current_dir
        return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, 
                              text=True, cwd=cwd, encoding='utf-8')

    def run_prepare_offline_packages(self):
        """오프라인 패키지 준비"""
        if INSTALLATION_MODE != 'offline':
            return None
            
        airgap_dir = self.current_dir / 'airgap/kubespray-offline'
        if not airgap_dir.exists():
            return None
            
        download_script = airgap_dir / 'download-all.sh'
        if not download_script.exists():
            return None
            
        return self._run_command(['bash', str(download_script)], cwd=airgap_dir)

    def run_kubespray_install(self, username, password):
        """Kubernetes 클러스터 설치"""
        self._save_kubespray_inventory()
        self._apply_offline_settings()
        
        if INSTALLATION_MODE == 'offline':
            # 오프라인 모드에서는 기존 airgap 스크립트 사용
            airgap_script = self.current_dir / 'airgap/deploy_kubernetes.sh'
            if airgap_script.exists():
                return self._run_command(['bash', str(airgap_script)], cwd=self.current_dir / 'airgap')
        
        # 온라인 모드 또는 오프라인 스크립트가 없는 경우
        kubespray_dir = self.current_dir / 'kubespray'
        cmd = [
            "ansible-playbook",
            "-i", str(self.kubespray_inventory_path),
            "--become", "--become-user=root",
            "cluster.yml",
            "--extra-vars",
            self.ansible_extra_values.format(username=username, password=password)
        ]
        
        if INSTALLATION_MODE == 'offline':
            # 오프라인 저장소 설정 먼저 실행
            offline_repo_cmd = [
                "ansible-playbook",
                "-i", str(self.kubespray_inventory_path),
                "--become", "--become-user=root",
                str(self.current_dir / "ansible/offline-repo.yml"),
                "--extra-vars",
                self.ansible_extra_values.format(username=username, password=password)
            ]
            # 여기서는 첫 번째 명령어만 반환 (UI에서 순차적으로 실행해야 함)
            return self._run_command(offline_repo_cmd, cwd=kubespray_dir)
        
        return self._run_command(cmd, cwd=kubespray_dir)

    def run_kubespray_reset(self, username, password):
        """Kubernetes 클러스터 리셋"""
        self._save_kubespray_inventory()
        return self._run_command([
            "ansible-playbook",
            "-i", str(self.kubespray_inventory_path),
            "--become", "--become-user=root",
            "reset.yml",
            "--extra-vars",
            self.ansible_extra_values.format(username=username, password=password)
        ], cwd=self.current_dir / 'kubespray')

    def run_install_astrago(self, app_name=None):
        """Astrago 애플리케이션 설치"""
        cmd = ["helmfile", "-e", self.data_manager.environment_name]
        if app_name:
            cmd.extend(["-l", f"app={app_name}"])
        cmd.append("sync")
        
        return self._run_command(cmd)

    def run_uninstall_astrago(self, app_name=None):
        """Astrago 애플리케이션 제거"""
        cmd = ["helmfile", "-e", self.data_manager.environment_name]
        if app_name:
            cmd.extend(["-l", f"app={app_name}"])
        cmd.append("destroy")
        
        return self._run_command(cmd)

    def run_status_check(self):
        """시스템 상태 확인"""
        cmd = ["helmfile", "-e", self.data_manager.environment_name, "list"]
        return self._run_command(cmd)

    def _save_nfs_inventory(self):
        """NFS 인벤토리 파일 생성"""
        inventory = {
            'all': {
                'vars': {
                    'nfs_exports': [
                        f"{self.data_manager.nfs_server['path']} *(rw,sync,no_subtree_check,no_root_squash)"
                    ]
                },
                'hosts': {
                    'nfs-server': {
                        'access_ip': self.data_manager.nfs_server['ip'],
                        'ansible_host': self.data_manager.nfs_server['ip'],
                        'ip': self.data_manager.nfs_server['ip'],
                        'ansible_user': 'root'
                    }
                }
            }
        }
        
        with open(self.nfs_inventory_path, 'w', encoding='utf-8') as f:
            yaml.dump(inventory, f, default_flow_style=False, allow_unicode=True)

    def run_install_nfs(self, username, password):
        """NFS 서버 설치"""
        self._save_nfs_inventory()
        return self._run_command([
            "ansible-playbook", "-i", self.nfs_inventory_path,
            "--become", "--become-user=root",
            "ansible/install-nfs.yml",
            "--extra-vars",
            self.ansible_extra_values.format(username=username, password=password)
        ])

    def _save_gpudriver_inventory(self):
        """GPU 드라이버 인벤토리 파일 생성"""
        inventory = {
            'all': {
                'vars': {
                    "nvidia_driver_branch": "535",
                    "nvidia_driver_package_state": "present"
                },
                'hosts': {}
            }
        }
        
        for node in self.data_manager.list_nodes():
            inventory['all']['hosts'][node['name']] = {
                'ansible_host': node['ip'],
                'ip': node['ip'],
                'access_ip': node['ip']
            }

        with open(self.gpu_inventory_path, 'w', encoding='utf-8') as f:
            yaml.dump(inventory, f, default_flow_style=False, allow_unicode=True)

    def run_install_gpudriver(self, username, password):
        """GPU 드라이버 설치"""
        self._save_gpudriver_inventory()
        return self._run_command([
            "ansible-playbook", "-i", self.gpu_inventory_path,
            "--become", "--become-user=root",
            "ansible/install-gpu-driver.yml",
            "--extra-vars",
            self.ansible_extra_values.format(username=username, password=password)
        ])


class AstragoInstaller:
    def __init__(self):
        self.data_manager = DataManager()
        self.command_runner = CommandRunner(self.data_manager)
        self.stdscr = None
        self.installation_mode = INSTALLATION_MODE

    def read_and_display_output(self, process):
        """명령어 출력을 실시간으로 표시"""
        if process is None:
            self.stdscr.addstr(0, 0, "명령어를 실행할 수 없습니다.")
            self.stdscr.addstr(1, 0, "아무 키나 눌러 메뉴로 돌아가세요")
            self.stdscr.refresh()
            curses.flushinp()
            self.stdscr.getch()
            return

        output_lines = []
        while True:
            output = process.stdout.readline()
            if output == '' and process.poll() is not None:
                break
            if output:
                output_lines.append(output.strip())
                max_lines = self.stdscr.getmaxyx()[0] - 2
                if len(output_lines) > max_lines:
                    output_lines = output_lines[-max_lines:]
                self.stdscr.erase()
                _, w = self.stdscr.getmaxyx()
                for idx, line in enumerate(output_lines):
                    try:
                        self.stdscr.addstr(idx, 0, line[:w - 1], curses.color_pair(2))
                    except curses.error:
                        pass
                self.stdscr.refresh()
        
        process.stdout.close()
        process.wait()
        
        # Display completion message
        output_lines.append("")
        if process.returncode == 0:
            output_lines.append("✅ 작업이 성공적으로 완료되었습니다!")
        else:
            output_lines.append("❌ 작업 중 오류가 발생했습니다.")
        output_lines.append("아무 키나 눌러 메뉴로 돌아가세요")
        
        h, w = self.stdscr.getmaxyx()
        for idx, line in enumerate(output_lines[-h + 1:]):
            try:
                color = curses.color_pair(1) if "✅" in line else curses.color_pair(3) if "❌" in line else curses.color_pair(2)
                self.stdscr.addstr(idx, 0, line[:w - 1], color)
            except curses.error:
                pass
        self.stdscr.refresh()
        curses.flushinp()
        self.stdscr.getch()

    def print_banner(self):
        """배너 출력"""
        self.stdscr.clear()
        
        # 모드에 따른 배너 선택
        if self.installation_mode == 'offline':
            title = [
                " ▄▄▄        ██████ ▄▄▄█████▓ ██▀███   ▄▄▄        ▄████  ▒█████   ",
                "▒████▄    ▒██    ▒ ▓  ██▒ ▓▒▓██ ▒ ██▒▒████▄     ██▒ ▀█▒▒██▒  ██▒ ",
                "▒██  ▀█▄  ░ ▓██▄   ▒ ▓██░ ▒░▓██ ░▄█ ▒▒██  ▀█▄  ▒██░▄▄▄░▒██░  ██▒ ",
                "░██▄▄▄▄██   ▒   ██▒░ ▓██▓ ░ ▒██▀▀█▄  ░██▄▄▄▄██ ░▓█  ██▓▒██   ██░ ",
                " ▓█   ▓██▒▒██████▒▒  ▒██▒ ░ ░██▓ ▒██▒ ▓█   ▓██▒░▒▓███▀▒░ ████▓▒░ ",
                " ▒▒   ▓▒█░▒ ▒▓▒ ▒ ░  ▒ ░░   ░ ▒▓ ░▒▓░ ▒▒   ▓▒█░ ░▒   ▒ ░ ▒░▒░▒░  ",
                "  ▒   ▒▒ ░░ ░▒  ░ ░    ░      ░▒ ░ ▒░  ▒   ▒▒ ░  ░   ░   ░ ▒ ▒░  ",
                "  ░   ▒   ░  ░  ░    ░        ░░   ░   ░   ▒   ░ ░   ░ ░ ░ ░ ▒   ",
                "      ░  ░      ░              ░           ░  ░      ░     ░ ░   ",
                "                                   🔒 OFFLINE MODE 🔒              ",
            ]
        else:
            title = [
                "    ___         __                         ",
                "   /   |  _____/ /__________ _____ _____   ",
                "  / /| | / ___/ __/ ___/ __ `/ __ `/ __ \\ ",
                " / ___ |(__  ) /_/ /  / /_/ / /_/ / /_/ /  ",
                "/_/  |_/____/\\__/_/   \\__,_/\\__, /\\____/   ",
                "                           /____/          ",
                "        🌐 ONLINE MODE 🌐                 ",
            ]

        h, w = self.stdscr.getmaxyx()
        for idx, line in enumerate(title):
            line = line[:w - 1]
            x = max(0, w // 2 - len(line) // 2)
            y = h // 2 - len(title) // 2 + idx - 8
            if 0 <= y < h and 0 <= x < w:
                try:
                    color = curses.color_pair(4) if self.installation_mode == 'offline' else curses.color_pair(2)
                    self.stdscr.addstr(y, x, line[:w], color)
                except curses.error:
                    pass
        
        # Current time display
        now_utc = datetime.now(timezone.utc)
        now_kst = now_utc + timedelta(hours=9)
        time_str = f"현재 시간: {now_kst.strftime('%Y-%m-%d %H:%M:%S KST')}"
        try:
            self.stdscr.addstr(h - 3, 2, time_str, curses.color_pair(2))
        except curses.error:
            pass
            
        self.stdscr.refresh()

    def print_menu(self, menu, selected_row_idx):
        """메뉴 출력"""
        self.stdscr.clear()
        self.print_banner()
        
        h, w = self.stdscr.getmaxyx()
        menu_start_y = h // 2 + 2
        
        # 상태 정보 표시
        status = self.data_manager.get_environment_status()
        status_y = menu_start_y - 3
        
        status_color = curses.color_pair(1) if status['configured'] else curses.color_pair(3)
        status_text = f"환경 설정 상태: {'✅ 완료' if status['configured'] else '❌ 미완료'}"
        
        try:
            x = w // 2 - len(status_text) // 2
            self.stdscr.addstr(status_y, x, status_text, status_color)
            
            # 추가 상태 정보
            if status['configured']:
                info_text = f"노드: {status['nodes_count']}개 | 모드: {self.installation_mode.upper()}"
                x = w // 2 - len(info_text) // 2
                self.stdscr.addstr(status_y + 1, x, info_text, curses.color_pair(2))
        except curses.error:
            pass
        
        # 메뉴 항목 표시
        max_menu_width = max(len(item) for item in menu)
        x = w // 2 - max_menu_width // 2
        
        for idx, row in enumerate(menu):
            y = menu_start_y + idx
            if 0 <= y < h - 2 and 0 <= x < w:
                try:
                    if idx == selected_row_idx:
                        self.stdscr.attron(curses.color_pair(1))
                        self.stdscr.addstr(y, x, f"► {row}".ljust(max_menu_width + 2)[:w])
                        self.stdscr.attroff(curses.color_pair(1))
                    else:
                        self.stdscr.addstr(y, x, f"  {row}"[:w])
                except curses.error:
                    pass
        
        # 하단 도움말
        help_text = "↑↓: 이동 | Enter: 선택 | ESC: 종료"
        try:
            self.stdscr.addstr(h - 2, 2, help_text, curses.color_pair(2))
        except curses.error:
            pass
            
        self.stdscr.refresh()

    def print_table(self, y, x, header, data, selected_index=-1):
        """테이블 출력"""
        h, w = self.stdscr.getmaxyx()
        
        # 헤더와 데이터 너비 계산
        header_widths = [len(str(col)) for col in header]
        data_widths = []
        
        for row in data:
            row_widths = [len(str(value)) for value in row]
            data_widths.append(row_widths)

        if data_widths:
            max_widths = [max(header_widths[i], *[row[i] for row in data_widths]) for i in range(len(header))]
        else:
            max_widths = header_widths[:]

        # 화면 너비에 맞게 조정
        total_width = sum(max_widths) + len(header) + 1
        if total_width > w - x:
            scale_factor = (w - x - len(header) - 1) / total_width
            max_widths = [max(8, int(width * scale_factor)) for width in max_widths]

        # 테이블 그리기
        try:
            # 상단 경계선
            line = '+' + '+'.join(['-' * width for width in max_widths]) + '+'
            self.stdscr.addstr(y, x, line[:w-x])
            y += 1
            
            # 헤더
            header_row = '|' + '|'.join([str(header[i]).center(max_widths[i]) for i in range(len(header))]) + '|'
            self.stdscr.addstr(y, x, header_row[:w-x], curses.color_pair(1))
            y += 1
            
            # 헤더 하단 경계선
            self.stdscr.addstr(y, x, line[:w-x])
            y += 1

            # 데이터 행
            for idx, row in enumerate(data):
                if y >= h - 2:
                    break
                    
                data_row = '|' + '|'.join([str(row[i]).ljust(max_widths[i])[:max_widths[i]] for i in range(len(row))]) + '|'
                color = curses.color_pair(1) if selected_index == idx else 0
                self.stdscr.addstr(y, x, data_row[:w-x], color)
                y += 1

            # 하단 경계선
            if y < h - 1:
                self.stdscr.addstr(y, x, line[:w-x])
                
        except curses.error:
            pass
            
        self.stdscr.refresh()

    def print_status_info(self):
        """상태 정보 출력"""
        self.stdscr.clear()
        h, w = self.stdscr.getmaxyx()
        
        try:
            self.stdscr.addstr(0, 0, "🔍 ASTRAGO 시스템 상태", curses.color_pair(1))
            self.stdscr.addstr(1, 0, "=" * min(50, w-1))
            
            status = self.data_manager.get_environment_status()
            y = 3
            
            # 기본 정보
            self.stdscr.addstr(y, 0, f"설치 모드: {self.installation_mode.upper()}")
            y += 1
            self.stdscr.addstr(y, 0, f"환경 이름: {self.data_manager.environment_name}")
            y += 2
            
            # 환경 설정 상태
            config_status = "✅ 완료" if status['configured'] else "❌ 미완료"
            self.stdscr.addstr(y, 0, f"환경 설정 상태: {config_status}")
            y += 1
            
            if status['external_ip']:
                self.stdscr.addstr(y, 0, f"외부 IP: {status['external_ip']}")
                y += 1
            
            if status['nfs_server']:
                self.stdscr.addstr(y, 0, f"NFS 서버: {status['nfs_server']}")
                y += 1
                self.stdscr.addstr(y, 0, f"NFS 경로: {status['nfs_path']}")
                y += 1
            
            if self.installation_mode == 'offline':
                if status['offline_registry']:
                    self.stdscr.addstr(y, 0, f"오프라인 레지스트리: {status['offline_registry']}")
                    y += 1
                if status['offline_http']:
                    self.stdscr.addstr(y, 0, f"오프라인 HTTP 서버: {status['offline_http']}")
                    y += 1
            
            self.stdscr.addstr(y, 0, f"등록된 노드 수: {status['nodes_count']}")
            y += 2
            
            # Kubernetes 클러스터 상태 확인
            try:
                import subprocess
                result = subprocess.run(['kubectl', 'cluster-info'], 
                                     capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    self.stdscr.addstr(y, 0, "Kubernetes 클러스터: ✅ 접근 가능", curses.color_pair(1))
                else:
                    self.stdscr.addstr(y, 0, "Kubernetes 클러스터: ❌ 접근 불가", curses.color_pair(3))
            except:
                self.stdscr.addstr(y, 0, "Kubernetes 클러스터: ❓ 상태 확인 불가")
            
            y += 2
            self.stdscr.addstr(y, 0, "아무 키나 눌러 메뉴로 돌아가세요", curses.color_pair(2))
            
        except curses.error:
            pass
            
        self.stdscr.refresh()
        curses.flushinp()
        self.stdscr.getch()

    def print_nfs_server_table(self, y, x):
        """NFS 서버 테이블 출력"""
        header = ["NFS IP 주소", "NFS 기본 경로"]
        data = [(
            self.data_manager.nfs_server['ip'] or '미설정',
            self.data_manager.nfs_server['path'] or '미설정'
        )]
        self.print_table(y, x, header, data)

    def print_nodes_table(self, y, x, selected_index=-1):
        """노드 테이블 출력"""
        header = ["번호", "노드 이름", "IP 주소", "역할", "Etcd"]
        data = []
        for idx, row in enumerate(self.data_manager.nodes):
            data.append((
                str(idx + 1),
                row['name'],
                row['ip'],
                row['role'],
                row['etcd']
            ))
        self.print_table(y, x, header, data, selected_index)

    def configure_environment(self):
        """환경 설정"""
        self.stdscr.clear()
        
        try:
            self.stdscr.addstr(0, 0, "🔧 환경 설정", curses.color_pair(1))
            self.stdscr.addstr(1, 0, "=" * 50)
            
            y = 3
            self.stdscr.addstr(y, 0, "기본 설정을 구성합니다...")
            y += 2
            
            # 외부 IP 설정
            external_ip = self.make_query(y, 0, "외부 IP 주소: ", 
                                        default_value=self.data_manager.environment_config.get('externalIP', ''),
                                        validation_func=self.data_manager.validate_ip)
            if external_ip == ESCAPE_CODE:
                return
            
            y += 1
            # NFS 서버 설정
            nfs_ip = self.make_query(y, 0, "NFS 서버 IP: ", 
                                   default_value=self.data_manager.nfs_server.get('ip', ''),
                                   validation_func=self.data_manager.validate_ip)
            if nfs_ip == ESCAPE_CODE:
                return
            
            y += 1
            nfs_path = self.make_query(y, 0, "NFS 기본 경로: ", 
                                     default_value=self.data_manager.nfs_server.get('path', ''),
                                     validation_func=self.data_manager.validate_path)
            if nfs_path == ESCAPE_CODE:
                return
            
            # 오프라인 모드인 경우 추가 설정
            if self.installation_mode == 'offline':
                y += 2
                self.stdscr.addstr(y, 0, "오프라인 설정:")
                y += 1
                
                offline_registry = self.make_query(y, 0, "오프라인 레지스트리 (예: 10.61.3.8:35000): ",
                                                 default_value=self.data_manager.environment_config.get('offline', {}).get('registry', ''))
                if offline_registry == ESCAPE_CODE:
                    return
                
                y += 1
                offline_http = self.make_query(y, 0, "HTTP 서버 (예: http://10.61.3.8): ",
                                             default_value=self.data_manager.environment_config.get('offline', {}).get('httpServer', ''),
                                             validation_func=self.data_manager.validate_url)
                if offline_http == ESCAPE_CODE:
                    return
                
                # 오프라인 설정 저장
                self.data_manager.set_offline_config(offline_registry, offline_http)
            
            # 설정 저장
            self.data_manager.set_external_ip(external_ip)
            self.data_manager.set_nfs_server(nfs_ip, nfs_path)
            
            y += 2
            self.stdscr.addstr(y, 0, "✅ 환경 설정이 완료되었습니다!", curses.color_pair(1))
            y += 1
            self.stdscr.addstr(y, 0, "아무 키나 눌러 계속하세요", curses.color_pair(2))
            
        except curses.error:
            pass
            
        self.stdscr.refresh()
        curses.flushinp()
        self.stdscr.getch()

    def prepare_offline_packages(self):
        """오프라인 패키지 준비"""
        if self.installation_mode != 'offline':
            self.stdscr.clear()
            self.stdscr.addstr(0, 0, "❌ 오프라인 모드에서만 사용 가능한 기능입니다.", curses.color_pair(3))
            self.stdscr.addstr(2, 0, "아무 키나 눌러 메뉴로 돌아가세요")
            self.stdscr.refresh()
            curses.flushinp()
            self.stdscr.getch()
            return

        self.stdscr.clear()
        self.stdscr.addstr(0, 0, "📦 오프라인 패키지 준비")
        self.stdscr.addstr(1, 0, "오프라인 설치에 필요한 패키지들을 다운로드합니다...")
        self.stdscr.addstr(3, 0, "계속하시겠습니까? [y/N]: ")
        self.stdscr.refresh()
        
        key = self.stdscr.getch()
        if key not in [ord('y'), ord('Y')]:
            return
        
        process = self.command_runner.run_prepare_offline_packages()
        if process:
            self.read_and_display_output(process)
        else:
            self.stdscr.clear()
            self.stdscr.addstr(0, 0, "❌ 오프라인 패키지 준비 스크립트를 찾을 수 없습니다.", curses.color_pair(3))
            self.stdscr.addstr(2, 0, "아무 키나 눌러 메뉴로 돌아가세요")
            self.stdscr.refresh()
            curses.flushinp()
            self.stdscr.getch()

    def remove_node(self):
        """노드 제거"""
        if not self.data_manager.nodes:
            self.stdscr.clear()
            self.stdscr.addstr(0, 0, "제거할 노드가 없습니다.")
            self.stdscr.addstr(2, 0, "아무 키나 눌러 메뉴로 돌아가세요")
            self.stdscr.refresh()
            curses.flushinp()
            self.stdscr.getch()
            return

        selected_index = 0
        while True:
            self.stdscr.clear()
            self.stdscr.addstr(0, 0, "🗑️ 노드 제거", curses.color_pair(3))
            self.stdscr.addstr(1, 0, "Enter: 선택한 노드 제거 | ↑↓: 이동 | ESC: 뒤로가기")
            self.print_nodes_table(3, 0, selected_index)
            
            key = self.stdscr.getch()

            if key == curses.KEY_DOWN and selected_index < len(self.data_manager.nodes) - 1:
                selected_index += 1
            elif key == curses.KEY_UP and selected_index > 0:
                selected_index -= 1
            elif key == curses.KEY_ENTER or key in [10, 13]:
                # 확인 메시지
                node_name = self.data_manager.nodes[selected_index]['name']
                self.stdscr.addstr(2, 0, f"정말로 '{node_name}' 노드를 제거하시겠습니까? [y/N]: ", curses.color_pair(3))
                self.stdscr.refresh()
                confirm = self.stdscr.getch()
                if confirm in [ord('y'), ord('Y')]:
                    self.data_manager.remove_node(selected_index)
                    if selected_index >= len(self.data_manager.nodes) and selected_index > 0:
                        selected_index -= 1
                    if not self.data_manager.nodes:
                        break
            elif key == curses.KEY_BACKSPACE or key == 27:
                break

    def input_node(self, node=None):
        """노드 입력/편집"""
        if node is None:
            node = {
                'name': '',
                'ip': '',
                'role': 'kube-master,kube-node',
                'etcd': 'Y'
            }
        
        self.stdscr.clear()
        self.stdscr.addstr(0, 0, "➕ 노드 정보 입력" if not node.get('name') else "✏️ 노드 정보 수정", curses.color_pair(1))
        
        # 노드 이름 입력
        name = self.make_query(2, 0, f"노드 이름 [{node['name']}]: ", 
                             default_value=node['name'], 
                             validation_func=self.data_manager.validate_node_name)
        if name == ESCAPE_CODE:
            return ESCAPE_CODE

        # IP 주소 입력
        ip = self.make_query(3, 0, f"IP 주소 [{node['ip']}]: ", 
                           default_value=node['ip'],
                           validation_func=self.data_manager.validate_ip)
        if ip == ESCAPE_CODE:
            return ESCAPE_CODE

        # 역할 선택
        role = self.select_checkbox(4, 0, "역할: ", ["kube-master", "kube-node"], node['role'].split(','))
        if role == ESCAPE_CODE:
            return ESCAPE_CODE

        # etcd 참여 여부
        etcd = self.select_YN(5, 0, "Etcd 클러스터 참여", node['etcd'])
        if etcd == ESCAPE_CODE:
            return ESCAPE_CODE

        return {
            'name': name,
            'ip': ip,
            'role': role,
            'etcd': etcd
        }

    def add_node(self):
        """노드 추가"""
        node = self.input_node()
        if node == ESCAPE_CODE:
            return
        
        # 중복 검사
        for existing_node in self.data_manager.nodes:
            if existing_node['name'] == node['name']:
                self.show_message("❌ 이미 존재하는 노드 이름입니다.", curses.color_pair(3))
                return
            if existing_node['ip'] == node['ip']:
                self.show_message("❌ 이미 존재하는 IP 주소입니다.", curses.color_pair(3))
                return
        
        self.data_manager.add_node(node['name'], node['ip'], node['role'], node['etcd'])
        self.show_message("✅ 노드가 성공적으로 추가되었습니다!", curses.color_pair(1))

    def edit_node(self):
        """노드 편집"""
        if not self.data_manager.nodes:
            self.show_message("편집할 노드가 없습니다.")
            return

        selected_index = 0
        while True:
            self.stdscr.clear()
            self.stdscr.addstr(0, 0, "✏️ 노드 편집", curses.color_pair(1))
            self.stdscr.addstr(1, 0, "Enter: 선택한 노드 편집 | ↑↓: 이동 | ESC: 뒤로가기")
            self.print_nodes_table(3, 0, selected_index)

            key = self.stdscr.getch()

            if key == curses.KEY_DOWN and selected_index < len(self.data_manager.nodes) - 1:
                selected_index += 1
            elif key == curses.KEY_UP and selected_index > 0:
                selected_index -= 1
            elif key == curses.KEY_ENTER or key in [10, 13]:
                selected_node = self.data_manager.nodes[selected_index]
                node = self.input_node(selected_node)
                if node != ESCAPE_CODE:
                    self.data_manager.edit_node(selected_index, node['name'], node['ip'], node['role'], node['etcd'])
                    self.show_message("✅ 노드 정보가 업데이트되었습니다!", curses.color_pair(1))
            elif key == curses.KEY_BACKSPACE or key == 27:
                break

    def show_message(self, message, color=0):
        """메시지 표시"""
        self.stdscr.clear()
        h, w = self.stdscr.getmaxyx()
        x = max(0, w // 2 - len(message) // 2)
        y = h // 2
        
        try:
            self.stdscr.addstr(y, x, message, color)
            self.stdscr.addstr(y + 2, x - 10, "아무 키나 눌러 계속하세요", curses.color_pair(2))
        except curses.error:
            pass
            
        self.stdscr.refresh()
        curses.flushinp()
        self.stdscr.getch()

    def select_YN(self, y, x, query, selected_option='Y'):
        """Y/N 선택"""
        options = ['Y', 'N']
        try:
            option_idx = options.index(selected_option)
        except ValueError:
            option_idx = 0
            
        while True:
            try:
                self.stdscr.addstr(y, x, f"{query}: ")
                self.stdscr.addstr(y, x + len(query) + 2, f"◀ {options[option_idx]} ▶", curses.color_pair(2))
            except curses.error:
                pass
                
            key = self.stdscr.getch()

            if key == curses.KEY_RIGHT:
                option_idx = (option_idx + 1) % len(options)
            elif key == curses.KEY_LEFT:
                option_idx = (option_idx - 1) % len(options)
            elif key in [10, 13]:  # Enter key
                return options[option_idx]
            elif key == curses.KEY_BACKSPACE or key == 27:
                return ESCAPE_CODE
        
        return options[option_idx]

    def select_checkbox(self, y, x, query, options, default_check=[]):
        """체크박스 선택"""
        selected_roles = [option in default_check for option in options]
        role_idx = 0
        
        while True:
            try:
                self.stdscr.addstr(y, x, query)
                for idx, option in enumerate(options):
                    checkbox = "[V]" if selected_roles[idx] else "[ ]"
                    color = curses.color_pair(2) if idx == role_idx else 0
                    self.stdscr.addstr(y, x + len(query) + idx * 20, f"{checkbox} {option}", color)
            except curses.error:
                pass

            key = self.stdscr.getch()
            
            if key == curses.KEY_RIGHT:
                role_idx = (role_idx + 1) % len(options)
            elif key == curses.KEY_LEFT:
                role_idx = (role_idx - 1) % len(options)
            elif key == ord(' '):
                selected_roles[role_idx] = not selected_roles[role_idx]
            elif key in [10, 13]:  # Enter key
                if any(selected_roles):
                    break
            elif key == curses.KEY_BACKSPACE or key == 27:
                return ESCAPE_CODE
                
        return ",".join([options[i] for i in range(len(options)) if selected_roles[i]])

    def make_query(self, y, x, query, default_value=None, validation_func=None, password_mode=False):
        """사용자 입력 받기 (비밀번호 모드 추가)"""
        h, w = self.stdscr.getmaxyx()
        input_line = []
        
        while True:
            try:
                if y < h and x + len(query) < w:
                    self.stdscr.addstr(y, x, query)
                self.stdscr.clrtoeol()
                
                if password_mode:
                    display_text = '*' * len(input_line)
                else:
                    display_text = ''.join(input_line)
                    
                self.stdscr.addstr(y, x + len(query), display_text, curses.color_pair(2))
            except curses.error:
                pass
                
            key = self.stdscr.getch()
            
            if 32 <= key <= 126:  # 출력 가능한 문자
                input_line.append(chr(key))
            elif key in (curses.KEY_BACKSPACE, 127, 8):
                if input_line:
                    input_line.pop()
            elif key == curses.KEY_ENTER or key in [10, 13]:
                text = ''.join(input_line)
                if text:
                    if not validation_func or validation_func(text):
                        return text
                    else:
                        # 유효성 검사 실패 메시지
                        try:
                            self.stdscr.addstr(y + 1, x, "❌ 잘못된 형식입니다. 다시 입력해주세요.", curses.color_pair(3))
                        except curses.error:
                            pass
                        self.stdscr.refresh()
                        curses.napms(1500)  # 1.5초 대기
                        try:
                            self.stdscr.addstr(y + 1, x, " " * 50)  # 메시지 지우기
                        except curses.error:
                            pass
                elif default_value is not None:
                    if not validation_func or validation_func(default_value):
                        return default_value
            elif key == 27:  # ESC
                return ESCAPE_CODE

        return ''.join(input_line)

    def install_astrago(self):
        """Astrago 애플리케이션 설치"""
        status = self.data_manager.get_environment_status()
        if not status['configured']:
            self.show_message("❌ 먼저 환경 설정을 완료해주세요.", curses.color_pair(3))
            return

        self.stdscr.clear()
        self.stdscr.addstr(0, 0, "🚀 Astrago 애플리케이션 설치", curses.color_pair(1))
        self.stdscr.addstr(1, 0, "=" * 50)
        
        # 현재 환경 정보 표시
        y = 3
        self.stdscr.addstr(y, 0, f"외부 IP: {status['external_ip']}")
        y += 1
        self.stdscr.addstr(y, 0, f"NFS 서버: {status['nfs_server']}")
        y += 1
        self.stdscr.addstr(y, 0, f"NFS 경로: {status['nfs_path']}")
        y += 1
        
        if self.installation_mode == 'offline':
            self.stdscr.addstr(y, 0, f"오프라인 레지스트리: {status['offline_registry']}")
            y += 1
            self.stdscr.addstr(y, 0, f"HTTP 서버: {status['offline_http']}")
            y += 1
        
        y += 1
        self.stdscr.addstr(y, 0, "설치를 시작하시겠습니까? [y/N]: ")
        self.stdscr.refresh()
        
        key = self.stdscr.getch()
        if key not in [ord('y'), ord('Y')]:
            return
        
        process = self.command_runner.run_install_astrago()
        self.read_and_display_output(process)

    def uninstall_astrago(self):
        """Astrago 애플리케이션 제거"""
        self.stdscr.clear()
        self.stdscr.addstr(0, 0, "🗑️ Astrago 애플리케이션 제거", curses.color_pair(3))
        self.stdscr.addstr(2, 0, "⚠️  모든 Astrago 애플리케이션이 제거됩니다!", curses.color_pair(3))
        self.stdscr.addstr(3, 0, "정말로 제거하시겠습니까? [y/N]: ")
        self.stdscr.refresh()
        
        key = self.stdscr.getch()
        if key not in [ord('y'), ord('Y')]:
            return
        
        process = self.command_runner.run_uninstall_astrago()
        self.read_and_display_output(process)

    def manage_individual_apps(self):
        """개별 애플리케이션 관리"""
        apps = [
            "csi-driver-nfs", "gpu-operator", "gpu-process-exporter",
            "loki-stack", "prometheus", "keycloak", "astrago", 
            "harbor", "mpi-operator", "flux"
        ]
        
        selected_app = 0
        action_menu = ["설치", "제거", "뒤로가기"]
        
        while True:
            self.stdscr.clear()
            self.stdscr.addstr(0, 0, "📦 개별 애플리케이션 관리", curses.color_pair(1))
            self.stdscr.addstr(1, 0, "설치/제거할 애플리케이션을 선택하세요")
            
            # 애플리케이션 목록 표시
            for idx, app in enumerate(apps):
                y = 3 + idx
                if y < self.stdscr.getmaxyx()[0] - 2:
                    prefix = "► " if idx == selected_app else "  "
                    color = curses.color_pair(1) if idx == selected_app else 0
                    self.stdscr.addstr(y, 0, f"{prefix}{app}", color)
            
            self.stdscr.addstr(self.stdscr.getmaxyx()[0] - 2, 0, "↑↓: 이동 | Enter: 선택 | ESC: 뒤로가기")
            self.stdscr.refresh()
            
            key = self.stdscr.getch()
            
            if key == curses.KEY_UP and selected_app > 0:
                selected_app -= 1
            elif key == curses.KEY_DOWN and selected_app < len(apps) - 1:
                selected_app += 1
            elif key == curses.KEY_ENTER or key in [10, 13]:
                # 액션 선택
                app_name = apps[selected_app]
                action = self.select_action_menu(action_menu, f"{app_name} 관리")
                
                if action == 0:  # 설치
                    process = self.command_runner.run_install_astrago(app_name)
                    self.read_and_display_output(process)
                elif action == 1:  # 제거
                    self.stdscr.clear()
                    self.stdscr.addstr(0, 0, f"'{app_name}' 애플리케이션을 제거하시겠습니까? [y/N]: ")
                    self.stdscr.refresh()
                    confirm = self.stdscr.getch()
                    if confirm in [ord('y'), ord('Y')]:
                        process = self.command_runner.run_uninstall_astrago(app_name)
                        self.read_and_display_output(process)
                elif action == 2:  # 뒤로가기
                    continue
            elif key == 27:  # ESC
                break

    def select_action_menu(self, actions, title):
        """액션 메뉴 선택"""
        selected = 0
        
        while True:
            self.stdscr.clear()
            self.stdscr.addstr(0, 0, title, curses.color_pair(1))
            
            for idx, action in enumerate(actions):
                y = 2 + idx
                prefix = "► " if idx == selected else "  "
                color = curses.color_pair(1) if idx == selected else 0
                self.stdscr.addstr(y, 0, f"{prefix}{action}", color)
            
            self.stdscr.refresh()
            key = self.stdscr.getch()
            
            if key == curses.KEY_UP and selected > 0:
                selected -= 1
            elif key == curses.KEY_DOWN and selected < len(actions) - 1:
                selected += 1
            elif key == curses.KEY_ENTER or key in [10, 13]:
                return selected
            elif key == 27:  # ESC
                return len(actions) - 1  # 마지막 항목 (뒤로가기) 반환

    def install_ansible_query(self, title, install_method, show_table_func=None):
        """SSH 기반 설치 쿼리"""
        self.stdscr.clear()
        self.stdscr.addstr(0, 0, title, curses.color_pair(1))
        
        if show_table_func:
            show_table_func(3, 0)
            y_start = 8
        else:
            y_start = 2
        
        self.stdscr.addstr(y_start, 0, "계속하시겠습니까? [y/N]: ")
        self.stdscr.refresh()
        
        key = self.stdscr.getch()
        if key not in [ord('y'), ord('Y')]:
            return
        
        # SSH 정보 입력
        username = self.make_query(y_start + 2, 0, "SSH 사용자명: ")
        if username == ESCAPE_CODE:
            return
        
        password = self.make_query(y_start + 3, 0, "SSH 비밀번호: ", password_mode=True)
        if password == ESCAPE_CODE:
            return
        
        process = install_method(username, password)
        self.read_and_display_output(process)

    def install_nfs(self):
        """NFS 서버 설치"""
        if not self.data_manager.nfs_server['ip'] or not self.data_manager.nfs_server['path']:
            self.show_message("❌ 먼저 NFS 서버 설정을 완료해주세요.", curses.color_pair(3))
            return
            
        self.install_ansible_query(
            "🗂️ NFS 서버 설치",
            self.command_runner.run_install_nfs,
            self.print_nfs_server_table
        )

    def install_gpu_driver(self):
        """GPU 드라이버 설치"""
        if not self.data_manager.nodes:
            self.show_message("❌ 먼저 노드를 추가해주세요.", curses.color_pair(3))
            return
            
        self.install_ansible_query(
            "🎮 GPU 드라이버 설치 (시스템이 재부팅됩니다)",
            self.command_runner.run_install_gpudriver,
            self.print_nodes_table
        )

    def install_kubernetes(self):
        """Kubernetes 클러스터 설치"""
        if not self.data_manager.nodes:
            self.show_message("❌ 먼저 노드를 추가해주세요.", curses.color_pair(3))
            return
            
        self.install_ansible_query(
            "☸️ Kubernetes 클러스터 설치",
            self.command_runner.run_kubespray_install,
            self.print_nodes_table
        )
        
        # kubeconfig 복사
        origin_config_path = pathlib.Path("kubespray/inventory/mycluster/artifacts/admin.conf")
        if origin_config_path.exists():
            kubeconfig_path = pathlib.Path.home() / '.kube' / 'config'
            kubeconfig_path.parent.mkdir(parents=True, exist_ok=True)
            kubeconfig_path.write_bytes(origin_config_path.read_bytes())
            self.show_message("✅ Kubeconfig가 복사되었습니다!", curses.color_pair(1))

    def reset_kubernetes(self):
        """Kubernetes 클러스터 리셋"""
        if not self.data_manager.nodes:
            self.show_message("❌ 리셋할 클러스터가 없습니다.", curses.color_pair(3))
            return
            
        self.install_ansible_query(
            "🔄 Kubernetes 클러스터 리셋",
            self.command_runner.run_kubespray_reset,
            self.print_nodes_table
        )

    def setting_node_menu(self):
        """노드 설정 메뉴"""
        menu = ["노드 추가", "노드 제거", "노드 편집", "뒤로가기"]
        handlers = {
            0: self.add_node,
            1: self.remove_node,
            2: self.edit_node
        }
        self.navigate_sub_menu(menu, handlers, self.print_nodes_table)

    def setting_nfs_menu(self):
        """NFS 설정 메뉴"""
        menu = ["NFS 서버 설정", "NFS 서버 설치 (선택사항)", "뒤로가기"]
        handlers = {
            0: self.configure_environment,
            1: self.install_nfs
        }
        self.navigate_sub_menu(menu, handlers, self.print_nfs_server_table)

    def install_astrago_menu(self):
        """Astrago 설치 메뉴"""
        if self.installation_mode == 'offline':
            menu = [
                "환경 설정", 
                "오프라인 패키지 준비",
                "Astrago 설치", 
                "Astrago 제거", 
                "개별 애플리케이션 관리",
                "뒤로가기"
            ]
            handlers = {
                0: self.configure_environment,
                1: self.prepare_offline_packages,
                2: self.install_astrago,
                3: self.uninstall_astrago,
                4: self.manage_individual_apps
            }
        else:
            menu = [
                "환경 설정",
                "Astrago 설치", 
                "Astrago 제거", 
                "개별 애플리케이션 관리",
                "뒤로가기"
            ]
            handlers = {
                0: self.configure_environment,
                1: self.install_astrago,
                2: self.uninstall_astrago,
                3: self.manage_individual_apps
            }
        
        self.navigate_menu(menu, handlers)

    def install_kubernetes_menu(self):
        """Kubernetes 설치 메뉴"""
        menu = [
            "노드 설정", 
            "Kubernetes 설치", 
            "Kubernetes 리셋", 
            "GPU 드라이버 설치 (선택사항)",
            "뒤로가기"
        ]
        handlers = {
            0: self.setting_node_menu,
            1: self.install_kubernetes,
            2: self.reset_kubernetes,
            3: self.install_gpu_driver
        }
        self.navigate_menu(menu, handlers)

    def navigate_sub_menu(self, menu, handlers, table_handler=None):
        """서브 메뉴 네비게이션"""
        current_row = 0
        while True:
            self.stdscr.clear()
            
            # 메뉴 제목 표시
            menu_title = menu[0].split()[0] + " 관리"
            self.stdscr.addstr(0, 0, menu_title, curses.color_pair(1))
            
            # 메뉴 항목 표시
            for idx, item in enumerate(menu):
                y = 2 + idx
                prefix = "► " if idx == current_row else "  "
                color = curses.color_pair(1) if idx == current_row else 0
                self.stdscr.addstr(y, 0, f"{prefix}{item}", color)
            
            # 테이블 표시
            if table_handler:
                table_y = 2 + len(menu) + 1
                table_handler(table_y, 0)
            
            # 도움말
            help_y = self.stdscr.getmaxyx()[0] - 2
            self.stdscr.addstr(help_y, 0, "↑↓: 이동 | Enter: 선택 | ESC: 뒤로가기")
            
            self.stdscr.refresh()
            
            key = self.stdscr.getch()
            
            if key == curses.KEY_UP and current_row > 0:
                current_row -= 1
            elif key == curses.KEY_DOWN and current_row < len(menu) - 1:
                current_row += 1
            elif key in range(49, 49 + len(menu)):  # 숫자 키
                current_row = key - 48 - 1
                if current_row in handlers:
                    handlers[current_row]()
                if current_row == len(menu) - 1:  # 뒤로가기
                    break
            elif key == curses.KEY_ENTER or key in [10, 13]:
                if current_row in handlers:
                    handlers[current_row]()
                if current_row == len(menu) - 1:  # 뒤로가기
                    break
            elif key == curses.KEY_BACKSPACE or key == 27:
                break

    def navigate_menu(self, menu, handlers):
        """메인 메뉴 네비게이션"""
        current_row = 0
        self.print_menu(menu, current_row)
        
        while True:
            key = self.stdscr.getch()
            
            if key == curses.KEY_UP and current_row > 0:
                current_row -= 1
            elif key == curses.KEY_DOWN and current_row < len(menu) - 1:
                current_row += 1
            elif key in range(49, 49 + len(menu)):  # 숫자 키
                current_row = key - 49 - 1
                if current_row in handlers:
                    handlers[current_row]()
                if current_row == len(menu) - 1:  # 종료/뒤로가기
                    break
            elif key == curses.KEY_ENTER or key in [10, 13]:
                if current_row in handlers:
                    handlers[current_row]()
                if current_row == len(menu) - 1:  # 종료/뒤로가기
                    break
            elif key == curses.KEY_BACKSPACE or key == 27:
                break
            
            self.print_menu(menu, current_row)

    def main(self, stdscr):
        """메인 함수"""
        self.stdscr = stdscr
        
        # 색상 설정
        curses.echo()
        curses.set_escdelay(1)
        curses.curs_set(0)
        
        # 색상 쌍 정의
        curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_GREEN)  # 선택된 항목
        curses.init_pair(2, curses.COLOR_GREEN, curses.COLOR_BLACK)  # 일반 텍스트
        curses.init_pair(3, curses.COLOR_RED, curses.COLOR_BLACK)    # 오류 메시지
        curses.init_pair(4, curses.COLOR_YELLOW, curses.COLOR_BLACK) # 오프라인 모드
        
        # 메인 메뉴
        main_menu = [
            "Kubernetes 클러스터",
            "Astrago 애플리케이션",
            "시스템 상태 확인",
            "종료"
        ]
        
        handlers = {
            0: self.install_kubernetes_menu,
            1: self.install_astrago_menu,
            2: self.print_status_info
        }
        
        try:
            self.navigate_menu(main_menu, handlers)
        except KeyboardInterrupt:
            pass
        except Exception as e:
            self.stdscr.clear()
            self.stdscr.addstr(0, 0, f"오류가 발생했습니다: {str(e)}", curses.color_pair(3))
            self.stdscr.addstr(2, 0, "아무 키나 눌러 종료하세요")
            self.stdscr.refresh()
            self.stdscr.getch()


if __name__ == "__main__":
    try:
        curses.wrapper(AstragoInstaller().main)
    except KeyboardInterrupt:
        print("\n프로그램이 사용자에 의해 종료되었습니다.")
    except Exception as e:
        print(f"\n오류가 발생했습니다: {e}")
        sys.exit(1)
