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

# ==========================================
# 🎨 Beautiful Color Definitions
# ==========================================
# Color pairs will be initialized in the main function
COLOR_GRADIENT1 = 1
COLOR_GRADIENT2 = 2  
COLOR_GRADIENT3 = 3
COLOR_GRADIENT4 = 4
COLOR_SUCCESS = 5
COLOR_ERROR = 6
COLOR_WARNING = 7
COLOR_INFO = 8
COLOR_SELECTED = 9
COLOR_BORDER = 10

# ==========================================
# 🎯 Beautiful Unicode Box Characters
# ==========================================
BOX_CHARS = {
    'top_left': '╔',
    'top_right': '╗', 
    'bottom_left': '╚',
    'bottom_right': '╝',
    'horizontal': '═',
    'vertical': '║',
    'section_top_left': '┌',
    'section_top_right': '┐',
    'section_bottom_left': '└', 
    'section_bottom_right': '┘',
    'section_horizontal': '─',
    'section_vertical': '│'
}

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
            self.stdscr.clear()
            self.stdscr.addstr(0, 0, "명령어를 실행할 수 없습니다.")
            self.stdscr.addstr(1, 0, "아무 키나 눌러 메뉴로 돌아가세요")
            self.stdscr.refresh()
            curses.flushinp()
            self.stdscr.getch()
            return

        self.stdscr.clear()
        h, w = self.stdscr.getmaxyx()
        output_lines = []
        
        # 상단 제목 박스
        title_width = min(w - 4, 70)
        title_x = (w - title_width) // 2
        self.print_beautiful_box(0, title_x, title_width, 3, "🔄 Installation Progress", COLOR_GRADIENT1)
        
        # 출력 영역
        output_start_y = 4
        max_lines = h - output_start_y - 3

        while True:
            output = process.stdout.readline()
            if output == '' and process.poll() is not None:
                break
            if output:
                output_lines.append(output.strip())
                if len(output_lines) > max_lines:
                    output_lines = output_lines[-max_lines:]
                
                # 출력 영역 지우기
                for i in range(output_start_y, h - 2):
                    if i < h and w > 1:
                        try:
                            self.stdscr.addstr(i, 0, " " * (w - 1))
                        except curses.error:
                            pass
                
                # 출력 표시
                for idx, line in enumerate(output_lines):
                    if output_start_y + idx < h - 2:
                        display_line = line[:w - 1]
                        # 로그 레벨에 따른 색상
                        if "ERROR" in line or "Failed" in line:
                            color = COLOR_ERROR
                        elif "WARNING" in line or "WARN" in line:
                            color = COLOR_WARNING
                        elif "SUCCESS" in line or "Completed" in line:
                            color = COLOR_SUCCESS
                        else:
                            color = COLOR_INFO
                        
                        try:
                            self.stdscr.addstr(output_start_y + idx, 0, display_line, curses.color_pair(color))
                        except curses.error:
                            pass
                
                self.stdscr.refresh()
        
        process.stdout.close()
        process.wait()
        
        # 완료 메시지
        completion_y = h - 2
        if completion_y > 0:
            completion_msg = "🎉 Installation completed! Press any key to return to the menu"
            msg_x = max(0, (w - len(completion_msg)) // 2)
            try:
                self.stdscr.addstr(completion_y, msg_x, completion_msg, curses.color_pair(COLOR_SUCCESS) | curses.A_BOLD)
            except curses.error:
                pass
        
        self.stdscr.refresh()
        curses.flushinp()
        self.stdscr.getch()

    def print_beautiful_box(self, y, x, width, height, title="", color_pair=COLOR_GRADIENT1):
        """아름다운 박스를 그립니다"""
        h, w = self.stdscr.getmaxyx()
        
        # 박스 그리기
        if y < h and x < w:
            # 상단
            self.stdscr.addstr(y, x, BOX_CHARS['top_left'], curses.color_pair(color_pair))
            for i in range(1, width-1):
                if x + i < w:
                    self.stdscr.addstr(y, x + i, BOX_CHARS['horizontal'], curses.color_pair(color_pair))
            if x + width - 1 < w:
                self.stdscr.addstr(y, x + width - 1, BOX_CHARS['top_right'], curses.color_pair(color_pair))
            
            # 중간 라인들
            for j in range(1, height-1):
                if y + j < h:
                    if x < w:
                        self.stdscr.addstr(y + j, x, BOX_CHARS['vertical'], curses.color_pair(color_pair))
                    if x + width - 1 < w:
                        self.stdscr.addstr(y + j, x + width - 1, BOX_CHARS['vertical'], curses.color_pair(color_pair))
            
            # 하단
            if y + height - 1 < h:
                if x < w:
                    self.stdscr.addstr(y + height - 1, x, BOX_CHARS['bottom_left'], curses.color_pair(color_pair))
                for i in range(1, width-1):
                    if x + i < w:
                        self.stdscr.addstr(y + height - 1, x + i, BOX_CHARS['horizontal'], curses.color_pair(color_pair))
                if x + width - 1 < w:
                    self.stdscr.addstr(y + height - 1, x + width - 1, BOX_CHARS['bottom_right'], curses.color_pair(color_pair))
        
        # 제목 추가
        if title and len(title) < width - 4:
            title_x = x + (width - len(title)) // 2
            if title_x < w and y < h:
                self.stdscr.addstr(y, title_x, f" {title} ", curses.color_pair(color_pair) | curses.A_BOLD)

    def print_banner(self):
        """배너 출력"""
        self.stdscr.clear()
        title = [
            "    ___         __                         ",
            "   /   |  _____/ /__________ _____ _____   ",
            "  / /| | / ___/ __/ ___/ __ `/ __ `/ __ \\ ",
            " / ___ |(__  ) /_/ /  / /_/ / /_/ / /_/ /  ",
            "/_/  |_/____/\\__/_/   \\__,_/\\__, /\\____/   ",
            "                           /____/          ",
        ]
        now_utc = datetime.now(timezone.utc)
        now_kst = now_utc + timedelta(hours=9)
        current_hour = now_kst.hour
        if current_hour >= 21:
            title = [
                " ▄▄▄        ██████ ▄▄▄█████▓ ██▀███   ▄▄▄        ▄████  ▒█████  ",
                "▒████▄    ▒██    ▒ ▓  ██▒ ▓▒▓██ ▒ ██▒▒████▄     ██▒ ▀█▒▒██▒  ██▒",
                "▒██  ▀█▄  ░ ▓██▄   ▒ ▓██░ ▒░▓██ ░▄█ ▒▒██  ▀█▄  ▒██░▄▄▄░▒██░  ██▒",
                "░██▄▄▄▄██   ▒   ██▒░ ▓██▓ ░ ▒██▀▀█▄  ░██▄▄▄▄██ ░▓█  ██▓▒██   ██░",
                " ▓█   ▓██▒▒██████▒▒  ▒██▒ ░ ░██▓ ▒██▒ ▓█   ▓██▒░▒▓███▀▒░ ████▓▒░",
                " ▒▒   ▓▒█░▒ ▒▓▒ ▒ ░  ▒ ░░   ░ ▒▓ ░▒▓░ ▒▒   ▓▒█░ ░▒   ▒ ░ ▒░▒░▒░ ",
                "  ▒   ▒▒ ░░ ░▒  ░ ░    ░      ░▒ ░ ▒░  ▒   ▒▒ ░  ░   ░   ░ ▒ ▒░ ",
                "  ░   ▒   ░  ░  ░    ░        ░░   ░   ░   ▒   ░ ░   ░ ░ ░ ░ ▒  ",
                "  ░  ░      ░              ░           ░  ░      ░     ░ ░      ",
            ]

        h, w = self.stdscr.getmaxyx()
        for idx, line in enumerate(title):
            line = line[:w - 1]
            x = w // 2 - len(line) // 2
            y = h // 2 - len(title) // 2 + idx - 10
            if 0 <= y < h and 0 <= x < w:
                self.stdscr.addstr(y, x, line[:w], curses.color_pair(2))
        self.stdscr.refresh()

    def print_menu(self, menu, selected_row_idx):
        """메뉴 출력"""
        self.stdscr.clear()
        self.print_banner()
        
        h, w = self.stdscr.getmaxyx()
        x = w // 2 - len(max(menu, key=len)) // 2
        for idx, row in enumerate(menu):
            y = h // 2 - len(menu) // 2 + idx
            if 0 <= y < h and 0 <= x < w:
                if idx == selected_row_idx:
                    self.stdscr.attron(curses.color_pair(1))
                    self.stdscr.addstr(y, x, row[:w])
                    self.stdscr.attroff(curses.color_pair(1))
                else:
                    self.stdscr.addstr(y, x, row[:w])
        self.stdscr.refresh()

    def print_table(self, y, x, header, data, selected_index=-1):
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

        total_width = sum(max_widths) + len(header) - 1
        if total_width > w:
            for i in range(len(max_widths)):
                max_widths[i] = max(1, max_widths[i] * (w - len(header) + 1) // total_width)

        line = '+'.join(['-' * width for width in max_widths])

        self.stdscr.addstr(y, x, '+' + line + '+')
        y += 1
        self.stdscr.addstr(y, x, '|' + '|'.join(header[i].center(max_widths[i]) for i in range(len(header))) + '|')
        y += 1
        self.stdscr.addstr(y, x, '+' + line + '+')

        for idx, row in enumerate(data):
            new_row = [str(col).center(max_widths[i]) for i, col in enumerate(row)]
            y += 1
            if y < h - 2:
                if selected_index == idx:
                    self.stdscr.addstr(y, x, '|' + '|'.join(new_row) + '|', curses.color_pair(1))
                else:
                    self.stdscr.addstr(y, x, '|' + '|'.join(new_row) + '|')

        y += 1
        if y < h:
            self.stdscr.addstr(y, x, '+' + line + '+')
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

    def print_sub_menu(self, menu, selected_row_idx):
        h, w = self.stdscr.getmaxyx()
        for idx, row in enumerate(menu):
            if len(row) > w:
                row = row[:w - 1]
            x = 0
            y = idx
            if y < h:
                if idx == selected_row_idx:
                    self.stdscr.attron(curses.color_pair(1))
                    self.stdscr.addstr(y, x, row)
                    self.stdscr.attroff(curses.color_pair(1))
                else:
                    self.stdscr.addstr(y, x, row)
        self.stdscr.refresh()

    def make_query(self, y, x, query, default_value=None, valid_regex=None, validation_func=None, password_mode=False):
        """사용자 입력을 받는 함수"""
        h, w = self.stdscr.getmaxyx()
        input_line = []
        error_msg = ""
        
        while True:
            # 화면 지우기
            try:
                if y < h and x + len(query) < w:
                    self.stdscr.addstr(y, x, query)
                self.stdscr.clrtoeol()
                
                # 입력 내용 표시 (패스워드 모드면 * 표시)
                display_text = '*' * len(input_line) if password_mode else ''.join(input_line)
                if y < h and x + len(query) + len(display_text) < w:
                    self.stdscr.addstr(y, x + len(query), display_text, curses.color_pair(COLOR_INFO))
                
                # 커서 표시
                if y < h and x + len(query) + len(display_text) < w:
                    self.stdscr.addstr(y, x + len(query) + len(display_text), "█", curses.color_pair(COLOR_SELECTED))
                
                # 오류 메시지 표시
                if error_msg and y + 1 < h:
                    self.stdscr.addstr(y + 1, x, error_msg, curses.color_pair(COLOR_ERROR))
                
            except curses.error:
                pass
            
            key = self.stdscr.getch()
            
            # 문자 입력
            if 33 <= key <= 126:
                input_line.append(chr(key))
                error_msg = ""
            
            # 백스페이스
            elif key in (curses.KEY_BACKSPACE, 127, 8):
                if input_line:
                    input_line.pop()
                error_msg = ""
            
            # 엔터
            elif key == curses.KEY_ENTER or key in [10, 13]:
                user_input = ''.join(input_line)
                
                # 입력이 있는 경우 유효성 검사
                if user_input:
                    valid = True
                    
                    # 정규식 검사
                    if valid_regex and not re.fullmatch(valid_regex, user_input):
                        valid = False
                        error_msg = "❌ 잘못된 형식입니다"
                    
                    # 함수 검사
                    elif validation_func and not validation_func(user_input):
                        valid = False
                        error_msg = "❌ 유효하지 않은 값입니다"
                    
                    if valid:
                        return user_input
                
                # 입력이 없는 경우 기본값 반환
                elif default_value is not None:
                    return default_value
                else:
                    error_msg = "❌ 값을 입력해주세요"
            
            # ESC
            elif key == 27:
                return ESCAPE_CODE

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
        menu = ["1. ➕ Add Node", "2. ➖ Remove Node", "3. ✏️ Edit Node", "4. 🔙 Back"]
        self.navigate_sub_menu(menu, {
            0: self.add_node,
            1: self.remove_node,
            2: self.edit_node
        }, self.print_nodes_table)

    def set_nfs_query(self):
        """NFS 서버 설정"""
        self.stdscr.clear()
        self.stdscr.addstr(0, 0, "🗄️ NFS 서버 설정", curses.color_pair(COLOR_GRADIENT1))
        self.stdscr.addstr(1, 0, "=" * 50)
        
        # 현재 설정 표시
        y = 3
        current_ip = self.data_manager.nfs_server.get('ip', '')
        current_path = self.data_manager.nfs_server.get('path', '')
        
        self.stdscr.addstr(y, 0, f"현재 NFS IP: {current_ip or '미설정'}")
        y += 1
        self.stdscr.addstr(y, 0, f"현재 NFS 경로: {current_path or '미설정'}")
        y += 2
        
        # NFS IP 입력
        nfs_ip = self.make_query(y, 0, "NFS 서버 IP 주소: ", 
                               default_value=current_ip,
                               validation_func=self.data_manager.validate_ip)
        if nfs_ip == ESCAPE_CODE:
            return
        
        y += 1
        # NFS 경로 입력
        nfs_path = self.make_query(y, 0, "NFS 기본 경로: ", 
                                 default_value=current_path,
                                 validation_func=self.data_manager.validate_path)
        if nfs_path == ESCAPE_CODE:
            return
        
        # 설정 저장
        self.data_manager.set_nfs_server(nfs_ip, nfs_path)
        
        y += 2
        self.stdscr.addstr(y, 0, "✅ NFS 서버 설정이 저장되었습니다!", curses.color_pair(COLOR_SUCCESS))
        y += 1
        self.stdscr.addstr(y, 0, "아무 키나 눌러 계속하세요")
        
        self.stdscr.refresh()
        curses.flushinp()
        self.stdscr.getch()

    def setting_nfs_menu(self):
        """NFS 설정 메뉴"""
        menu = ["1. ⚙️ Setting NFS Server", "2. 📦 Install NFS Server(Optional)", "3. 🔙 Back"]
        self.navigate_sub_menu(menu, {
            0: self.set_nfs_query,
            1: self.install_nfs
        }, self.print_nfs_server_table)

    def print_status_info(self):
        """시스템 상태 정보 표시"""
        self.stdscr.clear()
        h, w = self.stdscr.getmaxyx()
        
        # 제목
        title = "📊 시스템 상태 정보"
        self.stdscr.addstr(0, 0, title, curses.color_pair(COLOR_GRADIENT1) | curses.A_BOLD)
        self.stdscr.addstr(1, 0, "=" * 60)
        
        y = 3
        status = self.data_manager.get_environment_status()
        
        # 환경 설정 상태
        self.stdscr.addstr(y, 0, "🔧 환경 설정:", curses.color_pair(COLOR_GRADIENT2))
        y += 1
        
        config_status = "✅ 완료" if status['configured'] else "❌ 미완료"
        config_color = COLOR_SUCCESS if status['configured'] else COLOR_ERROR
        self.stdscr.addstr(y, 2, f"설정 상태: {config_status}", curses.color_pair(config_color))
        y += 1
        
        self.stdscr.addstr(y, 2, f"외부 IP: {status['external_ip'] or '미설정'}")
        y += 1
        self.stdscr.addstr(y, 2, f"NFS 서버: {status['nfs_server'] or '미설정'}")
        y += 1
        self.stdscr.addstr(y, 2, f"NFS 경로: {status['nfs_path'] or '미설정'}")
        y += 2
        
        # 노드 정보
        self.stdscr.addstr(y, 0, "🖥️ 노드 정보:", curses.color_pair(COLOR_GRADIENT2))
        y += 1
        self.stdscr.addstr(y, 2, f"등록된 노드 수: {status['nodes_count']}")
        y += 2
        
        # 설치 모드
        self.stdscr.addstr(y, 0, "🔧 설치 모드:", curses.color_pair(COLOR_GRADIENT2))
        y += 1
        mode_text = "오프라인" if self.installation_mode == 'offline' else "온라인"
        self.stdscr.addstr(y, 2, f"현재 모드: {mode_text}")
        y += 1
        
        if self.installation_mode == 'offline':
            self.stdscr.addstr(y, 2, f"오프라인 레지스트리: {status['offline_registry'] or '미설정'}")
            y += 1
            self.stdscr.addstr(y, 2, f"HTTP 서버: {status['offline_http'] or '미설정'}")
            y += 2
        
        # 도움말
        help_y = h - 3
        self.stdscr.addstr(help_y, 0, "아무 키나 눌러 메뉴로 돌아가세요", curses.color_pair(COLOR_INFO))
        
        self.stdscr.refresh()
        curses.flushinp()
        self.stdscr.getch()

    def install_astrago_menu(self):
        """Astrago 설치 메뉴"""
        menu = ["1. 🗄️ Set NFS Server", "2. 🚀 Install Astrago", "3. 🗑️ Uninstall Astrago", "4. 🔙 Back"]
        self.navigate_menu(menu, {
            0: self.setting_nfs_menu,
            1: self.install_astrago,
            2: self.uninstall_astrago
        })

    def install_kubernetes_menu(self):
        """Kubernetes 설치 메뉴"""
        menu = ["1. 🖥️ Set Nodes", "2. ☸️ Install Kubernetes", "3. 🔄 Reset Kubernetes", "4. 🎮 Install GPU Driver (Optional)",
                "5. 🔙 Back"]
        self.navigate_menu(menu, {
            0: self.setting_node_menu,
            1: self.install_kubernetes,
            2: self.reset_kubernetes,
            3: self.install_gpu_driver
        })

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
        
        # ==========================================
        # 🎨 Beautiful Color Initialization
        # ==========================================
        curses.start_color()
        curses.use_default_colors()
        
        # 그라데이션 색상 정의 (run_gui_installer.sh와 통일)
        curses.init_pair(COLOR_GRADIENT1, 129, -1)  # Purple
        curses.init_pair(COLOR_GRADIENT2, 135, -1)  # Light Purple
        curses.init_pair(COLOR_GRADIENT3, 141, -1)  # Pink
        curses.init_pair(COLOR_GRADIENT4, 147, -1)  # Light Pink
        curses.init_pair(COLOR_SUCCESS, curses.COLOR_GREEN, -1)
        curses.init_pair(COLOR_ERROR, curses.COLOR_RED, -1)
        curses.init_pair(COLOR_WARNING, curses.COLOR_YELLOW, -1)
        curses.init_pair(COLOR_INFO, curses.COLOR_CYAN, -1)
        curses.init_pair(COLOR_SELECTED, curses.COLOR_BLACK, curses.COLOR_GREEN)
        curses.init_pair(COLOR_BORDER, curses.COLOR_BLUE, -1)
        
        # 기본 설정
        curses.echo()
        curses.set_escdelay(1)
        curses.curs_set(0)
        
        # 호환성을 위한 기본 색상 쌍
        curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_GREEN)
        curses.init_pair(2, curses.COLOR_GREEN, curses.COLOR_BLACK)
        curses.init_pair(3, curses.COLOR_RED, curses.COLOR_BLACK)
        
        main_menu = ["1. 🏗️ Kubernetes Infrastructure",
                     "2. 🚀 Astrago Platform", 
                     "3. ⚙️ Environment Settings",
                     "4. 📊 System Status",
                     "5. ❌ Close"]
        
        try:
            self.navigate_menu(main_menu, {
                0: self.install_kubernetes_menu,
                1: self.install_astrago_menu,
                2: self.configure_environment,
                3: self.print_status_info
            })
        except KeyboardInterrupt:
            pass
        except Exception as e:
            self.stdscr.clear()
            self.stdscr.addstr(0, 0, f"오류가 발생했습니다: {str(e)}", curses.color_pair(COLOR_ERROR))
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
