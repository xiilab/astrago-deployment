import curses
import os
import pathlib
import re
import subprocess
from datetime import datetime, timezone, timedelta
from pathlib import Path

import yaml

ESCAPE_CODE = -1
REGEX_NODE_NAME = r'^[a-zA-Z0-9-]+$'
REGEX_IP_ADDRESS = r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$'
REGEX_PATH = r'^\/(?:[a-zA-Z0-9_-]+\/?)*$'

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


class DataManager:
    def __init__(self):
        self.nodes = []
        self.nfs_server = {
            'ip': '',
            'path': ''
        }
        self.save_nodes_file = 'nodes.yaml'
        self.save_nfs_server_file = 'nfs-servers.yaml'
        # Load nodes from inventory file if it exists
        if os.path.exists(self.save_nodes_file):
            with open(self.save_nodes_file, 'r') as f:
                self.nodes = yaml.safe_load(f)

        if os.path.exists(self.save_nfs_server_file):
            with open(self.save_nfs_server_file, 'r') as f:
                self.nfs_server = yaml.safe_load(f)

    def _save_to_nodes(self):
        with open(self.save_nodes_file, 'w') as f:
            yaml.dump(self.nodes, f, default_flow_style=False)

    def _save_to_nfs(self):
        with open(self.save_nfs_server_file, 'w') as f:
            yaml.dump(self.nfs_server, f, default_flow_style=False)

    def set_nfs_server(self, ip, path):
        self.nfs_server['ip'] = ip
        self.nfs_server['path'] = path
        self._save_to_nfs()

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

    def __str__(self):
        return yaml.dump(self.nodes, default_flow_style=False)


class CommandRunner:

    def __init__(self, data_manager):
        self.data_manager = data_manager
        self.kubespray_inventory_path = Path.joinpath(Path.cwd(), 'kubespray/inventory/mycluster/astrago.yaml')
        self.nfs_inventory_path = '/tmp/nfs_inventory'
        self.gpu_inventory_path = '/tmp/gpu_inventory'
        self.ansible_extra_values = 'reset_confirmation=yes ansible_ssh_timeout=30 ansible_user={username}' \
                                    ' ansible_password={password} ansible_become_pass={password}'

    def _save_kubespray_inventory(self):
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
                'access_ip': node['ip']  # Assuming access_ip is the same as ip for simplicity
            }

            # Add node to appropriate group based on roles
            roles = node['role'].split(',')
            for role in roles:
                if role == 'kube-master':
                    inventory['all']['children']['kube-master']['hosts'][node['name']] = None
                elif role == 'kube-node':
                    inventory['all']['children']['kube-node']['hosts'][node['name']] = None

            # Add node to etcd group if applicable
            if node['etcd'] == 'Y':
                inventory['all']['children']['etcd']['hosts'][node['name']] = None
        with open(self.kubespray_inventory_path, 'w') as f:
            yaml.dump(inventory, f, default_flow_style=False)

    def run_kubespray_install(self, username, password):
        self._save_kubespray_inventory()
        return self._run_command(["ansible-playbook",
                                  "-i", self.kubespray_inventory_path,
                                  "--become", "--become-user=root",
                                  "cluster.yml",
                                  "--extra-vars",
                                  self.ansible_extra_values.format(
                                      username=username,
                                      password=password)],
                                 cwd='kubespray')

    def run_kubespray_reset(self, username, password):
        self._save_kubespray_inventory()
        return self._run_command(["ansible-playbook",
                                  "-i", self.kubespray_inventory_path,
                                  "--become", "--become-user=root",
                                  "reset.yml",
                                  "--extra-vars",
                                  self.ansible_extra_values.format(
                                      username=username,
                                      password=password)],
                                 cwd='kubespray')

    def _run_command(self, cmd, cwd="."):
        return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, cwd=cwd)

    def run_install_astrago(self, connected_url):
        with open('environments/prod/values.yaml') as f:
            helmfile_env = yaml.load(f, Loader=yaml.FullLoader)
            helmfile_env['externalIP'] = connected_url
            helmfile_env['nfs']['server'] = self.data_manager.nfs_server['ip']
            helmfile_env['nfs']['basePath'] = self.data_manager.nfs_server['path']

        os.makedirs('environments/astrago', exist_ok=True)
        with open('environments/astrago/values.yaml', 'w') as file:
            yaml.dump(helmfile_env, file, default_flow_style=False, sort_keys=False)

        return self._run_command(["helmfile", "-e", "astrago", "sync"])

    def run_uninstall_astrago(self):
        return self._run_command(["helmfile", "-e", "astrago", "destroy"])

    def _save_nfs_inventory(self):
        inventory = {
            'all': {
                'vars': {},
                'hosts': {}
            }
        }
        inventory['all']['vars']['nfs_exports'] = [
            "{} *(rw,sync,no_subtree_check,no_root_squash)".format(self.data_manager.nfs_server['path'])]
        inventory['all']['hosts']['nfs-server'] = {
            'access_ip': self.data_manager.nfs_server['ip'],
            'ansible_host': self.data_manager.nfs_server['ip'],
            'ip': self.data_manager.nfs_server['ip'],
            'ansible_user': 'root'
        }
        with open(self.nfs_inventory_path, 'w') as f:
            yaml.dump(inventory, f, default_flow_style=False)

    def run_install_nfs(self, username, password):
        self._save_nfs_inventory()
        return self._run_command(["ansible-playbook", "-i", self.nfs_inventory_path,
                                  "--become", "--become-user=root",
                                  "ansible/install-nfs.yml",
                                  "--extra-vars",
                                  self.ansible_extra_values.format(
                                      username=username,
                                      password=password)])

    def _save_gpudriver_inventory(self):
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
                'access_ip': node['ip']  # Assuming access_ip is the same as ip for simplicity
            }

        with open(self.gpu_inventory_path, 'w') as f:
            yaml.dump(inventory, f, default_flow_style=False)

    def run_install_gpudriver(self, username, password):
        self._save_gpudriver_inventory()
        return self._run_command(
            ["ansible-playbook", "-i", self.gpu_inventory_path,
             "--become", "--become-user=root",
             "ansible/install-gpu-driver.yml",
             "--extra-vars",
             self.ansible_extra_values.format(
                 username=username,
                 password=password)])


class AstragoInstaller:
    def __init__(self):
        self.data_manager = DataManager()
        self.command_runner = CommandRunner(self.data_manager)
        self.stdscr = None

    def read_and_display_output(self, process):
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
                    self.stdscr.addstr(i, 0, " " * (w - 1))
                
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
                        
                        self.stdscr.addstr(output_start_y + idx, 0, display_line, curses.color_pair(color))
                
                self.stdscr.refresh()
        
        process.stdout.close()
        process.wait()
        
        # 완료 메시지
        completion_y = h - 2
        if completion_y > 0:
            completion_msg = "🎉 Installation completed! Press any key to return to the menu"
            msg_x = (w - len(completion_msg)) // 2
            if msg_x >= 0:
                self.stdscr.addstr(completion_y, msg_x, completion_msg, curses.color_pair(COLOR_SUCCESS) | curses.A_BOLD)
        
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
        self.stdscr.clear()
        h, w = self.stdscr.getmaxyx()
        
        # 아름다운 박스로 둘러싸인 배너
        box_width = min(w - 4, 80)
        box_height = 12
        box_x = (w - box_width) // 2
        box_y = max(1, (h - box_height) // 2 - 8)
        
        # 외부 박스
        self.print_beautiful_box(box_y, box_x, box_width, box_height, "🚀 ASTRAGO GUI INSTALLER", COLOR_GRADIENT1)
        
        # 내부 제목
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
        
        # 시간에 따른 특별 디자인 (밤 시간)
        if current_hour >= 21 or current_hour <= 6:
            title = [
                "✨ A S T R A G O ✨",
                "「 AI Infrastructure Platform 」",
                "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
                "🌙 Night Mode Activated 🌙",
            ]
        
        # 제목 출력
        for idx, line in enumerate(title):
            line = line[:box_width - 6]
            title_x = box_x + (box_width - len(line)) // 2
            title_y = box_y + 2 + idx
            if 0 <= title_y < h and 0 <= title_x < w:
                color = COLOR_GRADIENT2 if idx % 2 == 0 else COLOR_GRADIENT3
                self.stdscr.addstr(title_y, title_x, line, curses.color_pair(color) | curses.A_BOLD)
        
        # 하단 정보
        info_y = box_y + box_height + 1
        if info_y < h:
            info_text = "🔥 Beautiful Installation Experience 🔥"
            info_x = (w - len(info_text)) // 2
            if 0 <= info_x < w:
                self.stdscr.addstr(info_y, info_x, info_text, curses.color_pair(COLOR_GRADIENT4) | curses.A_DIM)
        
        self.stdscr.refresh()

    def print_menu(self, menu, selected_row_idx):
        self.stdscr.clear()
        self.print_banner()
        h, w = self.stdscr.getmaxyx()
        
        # 메뉴 박스 설정
        menu_width = min(w - 8, 60)
        menu_height = len(menu) + 4
        menu_x = (w - menu_width) // 2
        menu_y = h // 2 + 2
        
        # 메뉴 박스 그리기
        self.print_beautiful_box(menu_y, menu_x, menu_width, menu_height, "📋 Main Menu", COLOR_GRADIENT2)
        
        # 메뉴 아이템 출력
        for idx, row in enumerate(menu):
            item_y = menu_y + 2 + idx
            item_x = menu_x + 3
            
            if 0 <= item_y < h and 0 <= item_x < w:
                # 메뉴 아이템 전체 배경
                menu_text = f"  {row}  "
                if len(menu_text) > menu_width - 6:
                    menu_text = menu_text[:menu_width - 6]
                
                if idx == selected_row_idx:
                    # 선택된 메뉴
                    self.stdscr.addstr(item_y, item_x, "▶", curses.color_pair(COLOR_SELECTED) | curses.A_BOLD)
                    self.stdscr.addstr(item_y, item_x + 2, menu_text, curses.color_pair(COLOR_SELECTED) | curses.A_BOLD)
                else:
                    # 일반 메뉴
                    icon = "🔹" if idx < len(menu) - 1 else "🚪"
                    self.stdscr.addstr(item_y, item_x, " ", curses.color_pair(COLOR_INFO))
                    self.stdscr.addstr(item_y, item_x + 2, menu_text, curses.color_pair(COLOR_INFO))
        
        # 하단 도움말
        help_y = menu_y + menu_height + 1
        if help_y < h:
            help_text = "↑↓ 이동 | Enter 선택 | ESC 종료"
            help_x = (w - len(help_text)) // 2
            if 0 <= help_x < w:
                self.stdscr.addstr(help_y, help_x, help_text, curses.color_pair(COLOR_INFO) | curses.A_DIM)
        
        self.stdscr.refresh()

    def print_table(self, y, x, header, data, selected_index=-1, title=""):
        h, w = self.stdscr.getmaxyx()
        header_widths = [len(col) for col in header]
        data_widths = [[len(str(value)) for value in row] for row in data]

        if data_widths:
            max_widths = [max(header_widths[i], *[row[i] for row in data_widths]) for i in range(len(header))]
        else:
            max_widths = header_widths[:]

        # 박스 그리기 문자 사용
        total_width = sum(max_widths) + len(header) * 3 + 1
        if total_width > w - 4:
            for i in range(len(max_widths)):
                max_widths[i] = max(1, max_widths[i] * (w - len(header) * 3 - 5) // sum(max_widths))

        # 상단 테두리
        top_line = BOX_CHARS['section_top_left']
        for i, width in enumerate(max_widths):
            top_line += BOX_CHARS['section_horizontal'] * (width + 2)
            if i < len(max_widths) - 1:
                top_line += '┬'
        top_line += BOX_CHARS['section_top_right']
        
        if y < h and x < w:
            self.stdscr.addstr(y, x, top_line[:w-x], curses.color_pair(COLOR_BORDER))
        
        # 헤더
        y += 1
        if y < h and x < w:
            header_line = BOX_CHARS['section_vertical']
            for i, col in enumerate(header):
                header_text = f" {col.center(max_widths[i])} "
                header_line += header_text
                if i < len(header) - 1:
                    header_line += BOX_CHARS['section_vertical']
            header_line += BOX_CHARS['section_vertical']
            self.stdscr.addstr(y, x, header_line[:w-x], curses.color_pair(COLOR_GRADIENT2) | curses.A_BOLD)
        
        # 헤더 구분선
        y += 1
        if y < h and x < w:
            mid_line = '├'
            for i, width in enumerate(max_widths):
                mid_line += BOX_CHARS['section_horizontal'] * (width + 2)
                if i < len(max_widths) - 1:
                    mid_line += '┼'
            mid_line += '┤'
            self.stdscr.addstr(y, x, mid_line[:w-x], curses.color_pair(COLOR_BORDER))

        # 데이터 행
        for idx, row in enumerate(data):
            y += 1
            if y < h - 2 and x < w:
                row_line = BOX_CHARS['section_vertical']
                for i, col in enumerate(row):
                    cell_text = f" {str(col).center(max_widths[i])} "
                    row_line += cell_text
                    if i < len(max_widths) - 1:
                        row_line += BOX_CHARS['section_vertical']
                row_line += BOX_CHARS['section_vertical']
                
                if selected_index == idx:
                    self.stdscr.addstr(y, x, row_line[:w-x], curses.color_pair(COLOR_SELECTED) | curses.A_BOLD)
                else:
                    self.stdscr.addstr(y, x, row_line[:w-x], curses.color_pair(COLOR_INFO))

        # 하단 테두리
        y += 1
        if y < h and x < w:
            bottom_line = BOX_CHARS['section_bottom_left']
            for i, width in enumerate(max_widths):
                bottom_line += BOX_CHARS['section_horizontal'] * (width + 2)
                if i < len(max_widths) - 1:
                    bottom_line += '┴'
            bottom_line += BOX_CHARS['section_bottom_right']
            self.stdscr.addstr(y, x, bottom_line[:w-x], curses.color_pair(COLOR_BORDER))
            
        self.stdscr.refresh()

    def print_nfs_server_table(self, y, x):
        header = ["NFS IP Address", "NFS Base Path"]
        data = [(
            self.data_manager.nfs_server['ip'],
            self.data_manager.nfs_server['path']
        )]
        self.print_table(y, x, header, data)

    def print_nodes_table(self, y, x, selected_index=-1):
        header = ["No", "Node Name", "IP Address", "Role", "Etcd"]
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

    def remove_node(self):
        selected_index = 0
        while True:
            self.stdscr.clear()
            self.stdscr.addstr("Press the enter to remove a node, Backspace key to go back")
            self.print_nodes_table(1, 0, selected_index)
            key = self.stdscr.getch()

            if key == curses.KEY_DOWN and selected_index < len(self.data_manager.nodes) - 1:
                selected_index += 1
            elif key == curses.KEY_UP and selected_index > 0:
                selected_index -= 1
            elif key == curses.KEY_ENTER or key in [10, 13]:
                self.data_manager.remove_node(selected_index)
                if selected_index >= 1:
                    selected_index -= 1
            elif key == curses.KEY_BACKSPACE or key == 27:
                break

    def input_node(self, node=None):
        if node is None:
            node = {
                'name': '',
                'ip': '',
                'role': '',
                'etcd': 'Y'
            }
        self.stdscr.clear()
        name = self.make_query(0, 0, f"Name[{node['name']}]: ", default_value=node['name'], valid_regex=REGEX_NODE_NAME)
        if name == ESCAPE_CODE:
            return ESCAPE_CODE
        ip = self.make_query(1, 0, f"IP Address[{node['ip']}]: ", default_value=node['ip'],
                             valid_regex=REGEX_IP_ADDRESS)
        if ip == ESCAPE_CODE:
            return ESCAPE_CODE
        role = self.select_checkbox(2, 0, f"Role: ", ["kube-master", "kube-node"], node['role'].split(','))
        if role == ESCAPE_CODE:
            return ESCAPE_CODE
        etcd = self.select_YN(3, 0, f"Etcd: ", node['etcd'])
        if etcd == ESCAPE_CODE:
            return ESCAPE_CODE
        return {
            'name': name,
            'ip': ip,
            'role': role,
            'etcd': etcd
        }

    def add_node(self):
        node = self.input_node()
        if node == ESCAPE_CODE:
            return None
        self.data_manager.add_node(node['name'], node['ip'], node['role'], node['etcd'])

    def edit_node(self):
        selected_index = 0
        while True:
            self.stdscr.clear()
            self.stdscr.addstr("Press the Enter to select a node to edit, Backspace to go back")

            self.print_nodes_table(1, 0, selected_index)
            key = self.stdscr.getch()

            if key == curses.KEY_DOWN and selected_index < len(self.data_manager.nodes) - 1:
                selected_index += 1
            elif key == curses.KEY_UP and selected_index > 0:
                selected_index -= 1
            elif key == curses.KEY_ENTER or key in [10, 13]:
                self.stdscr.clear()
                selected_node = self.data_manager.nodes[selected_index]
                node = self.input_node(selected_node)
                if node != ESCAPE_CODE:
                    self.data_manager.edit_node(selected_index, node['name'], node['ip'], node['role'], node['etcd'])
            elif key == curses.KEY_BACKSPACE or key == 27:
                break

    def select_YN(self, y, x, query, selected_option='Y'):
        options = ['Y', 'N']
        option_idx = options.index(selected_option)
        while True:
            self.stdscr.addstr(y, x, f"{query}: ")
            self.stdscr.addstr(y, x + len(query), f"◀ {options[option_idx]} ▶", curses.color_pair(2))
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
        selected_roles = [option in default_check for option in options]
        role_idx = 0
        while True:
            self.stdscr.addstr(y, x, query)
            for idx, option in enumerate(options):
                if selected_roles[idx]:
                    self.stdscr.addstr(y, x + len(query) + idx * 20, "[V] " + option,
                                       curses.color_pair(2) if idx == role_idx else 0)
                else:
                    self.stdscr.addstr(y, x + len(query) + idx * 20, "[ ] " + option,
                                       curses.color_pair(2) if idx == role_idx else 0)

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
        
        # 상단 제목 박스
        title_height = 4
        title_width = min(w - 4, 70)
        title_x = (w - title_width) // 2
        title_y = 1
        
        self.print_beautiful_box(title_y, title_x, title_width, title_height, "🔧 Configuration Menu", COLOR_GRADIENT3)
        
        # 메뉴 박스
        menu_width = min(w - 8, 60)
        menu_height = len(menu) + 4
        menu_x = 2
        menu_y = title_y + title_height + 1
        
        self.print_beautiful_box(menu_y, menu_x, menu_width, menu_height, "📝 Options", COLOR_GRADIENT2)
        
        # 메뉴 아이템들
        for idx, row in enumerate(menu):
            item_y = menu_y + 2 + idx
            item_x = menu_x + 3
            
            if item_y < h and item_x < w:
                # 메뉴 텍스트 준비
                if len(row) > menu_width - 8:
                    row = row[:menu_width - 8]
                
                if idx == selected_row_idx:
                    # 선택된 메뉴
                    self.stdscr.addstr(item_y, item_x, "▶", curses.color_pair(COLOR_SELECTED) | curses.A_BOLD)
                    self.stdscr.addstr(item_y, item_x + 2, f" {row} ", curses.color_pair(COLOR_SELECTED) | curses.A_BOLD)
                else:
                    # 일반 메뉴 - 아이콘 선택
                    if "Back" in row or "뒤로" in row:
                        icon = "🔙"
                    elif "Add" in row or "추가" in row:
                        icon = "➕"
                    elif "Remove" in row or "제거" in row:
                        icon = "➖"
                    elif "Edit" in row or "편집" in row:
                        icon = "✏️"
                    elif "Setting" in row or "설정" in row:
                        icon = "⚙️"
                    elif "Install" in row or "설치" in row:
                        icon = "📦"
                    else:
                        icon = "🔹"
                    
                    self.stdscr.addstr(item_y, item_x, icon, curses.color_pair(COLOR_INFO))
                    self.stdscr.addstr(item_y, item_x + 3, row, curses.color_pair(COLOR_INFO))
        
        # 하단 도움말
        help_y = menu_y + menu_height + 1
        if help_y < h:
            help_text = "↑↓ 이동 | Enter 선택 | Backspace 뒤로 | ESC 종료"
            self.stdscr.addstr(help_y, 2, help_text, curses.color_pair(COLOR_INFO) | curses.A_DIM)
        
        self.stdscr.refresh()

    def make_query(self, y, x, query, default_value=None, valid_regex=None):
        h, w = self.stdscr.getmaxyx()
        input_line = []
        
        # 입력 박스 디자인
        input_width = min(w - x - 4, 50)
        input_height = 5
        
        # 입력 박스 그리기
        self.print_beautiful_box(y, x, input_width, input_height, "📝 Input Required", COLOR_GRADIENT3)
        
        # 쿼리 텍스트
        query_y = y + 2
        query_x = x + 2
        if query_y < h and query_x < w:
            self.stdscr.addstr(query_y, query_x, query, curses.color_pair(COLOR_INFO) | curses.A_BOLD)
        
        # 입력 필드
        input_y = query_y + 1
        input_x = query_x
        input_field_width = input_width - 4
        
        while True:
            # 입력 필드 배경 지우기
            if input_y < h and input_x < w:
                self.stdscr.addstr(input_y, input_x, " " * input_field_width)
                
                # 입력된 텍스트 표시
                display_text = ''.join(input_line)
                if len(display_text) > input_field_width - 2:
                    display_text = display_text[-(input_field_width - 2):]
                
                # 입력 박스 스타일
                self.stdscr.addstr(input_y, input_x, "▶ ", curses.color_pair(COLOR_GRADIENT2))
                self.stdscr.addstr(input_y, input_x + 2, display_text, curses.color_pair(COLOR_SUCCESS) | curses.A_BOLD)
                self.stdscr.addstr(input_y, input_x + 2 + len(display_text), "█", curses.color_pair(COLOR_SELECTED))  # 커서
            
            key = self.stdscr.getch()
            
            if 33 <= key <= 126:  # 출력 가능한 문자
                input_line.append(chr(key))
            elif key in (curses.KEY_BACKSPACE, 127, 8):  # 백스페이스
                if input_line:
                    input_line.pop()
            elif key == curses.KEY_ENTER or key in [10, 13]:  # 엔터
                input_text = ''.join(input_line)
                if input_text:
                    if not valid_regex or re.fullmatch(valid_regex, input_text):
                        return input_text
                    else:
                        # 유효하지 않은 입력
                        error_y = input_y + 1
                        if error_y < h:
                            self.stdscr.addstr(error_y, input_x, "❌ Invalid format! Please try again.", curses.color_pair(COLOR_ERROR))
                            self.stdscr.refresh()
                            curses.napms(1500)  # 1.5초 대기
                else:
                    if default_value is not None:
                        return default_value
            elif key == 27:  # ESC
                return ESCAPE_CODE

        return ''.join(input_line)

    def install_astrago(self):
        self.stdscr.clear()
        nfs_server_ip = self.data_manager.nfs_server['ip']
        nfs_base_path = self.data_manager.nfs_server['path']

        if not nfs_server_ip or not nfs_base_path:
            self.stdscr.addstr(0, 0, "You have to set the NFS server")
            self.stdscr.addstr(1, 0, "Press any key to return to the menu")
            self.stdscr.getch()
            return None

        self.print_nfs_server_table(1, 0)

        connected_url = self.make_query(0, 0, "Enter Connected Url: ")
        if connected_url == ESCAPE_CODE:
            return None
        self.read_and_display_output(self.command_runner.run_install_astrago(connected_url))

    def uninstall_astrago(self):
        self.stdscr.clear()
        check_uninstall = self.make_query(0, 0, "Are you sure want to uninstall astrago? [y/N]: ", default_value='N')
        if check_uninstall == 'Y' or check_uninstall == 'y':
            self.read_and_display_output(self.command_runner.run_uninstall_astrago())

    def install_ansible_query(self, query, install_method, show_table):
        self.stdscr.clear()
        if show_table is not None:
            show_table(3, 0)
        check_install = self.make_query(0, 0, query, default_value='N')
        if check_install == 'Y' or check_install == 'y':
            username = self.make_query(1, 0, "Input SSH Username: ")
            if username == ESCAPE_CODE:
                return None
            password = self.make_query(2, 0, "Input SSH Password: ")
            if password == ESCAPE_CODE:
                return None
            self.read_and_display_output(install_method(username, password))

    def install_nfs(self):
        self.install_ansible_query("Are you sure want to install NFS-server? [y/N]: ",
                                   self.command_runner.run_install_nfs, self.print_nfs_server_table)

    def install_gpu_driver(self):
        self.install_ansible_query("Install the GPU driver? the system will reboot [y/N]: ",
                                   self.command_runner.run_install_gpudriver, self.print_nodes_table)

    def install_kubernetes(self):
        self.install_ansible_query("Check the Node Table. Install Kubernetes? [y/N]: ",
                                   self.command_runner.run_kubespray_install, self.print_nodes_table)
        origin_config_path = pathlib.Path(
            Path.joinpath(Path.cwd(), "kubespray/inventory/mycluster/artifacts/admin.conf"))
        if origin_config_path.exists():
            kubeconfig_path = pathlib.Path(Path.joinpath(Path.home(), '.kube', 'config'))
            kubeconfig_path.parent.mkdir(parents=True, exist_ok=True)
            kubeconfig_path.write_bytes(origin_config_path.read_bytes())

    def reset_kubernetes(self):
        self.install_ansible_query("Check the Node Table. Reset Kubernetes? [y/N]: ",
                                   self.command_runner.run_kubespray_reset, self.print_nodes_table)

    def setting_node_menu(self):
        self.stdscr.clear()
        menu = ["1. ➕ Add Node", "2. ➖ Remove Node", "3. ✏️ Edit Node", "4. 🔙 Back"]
        self.navigate_sub_menu(menu, {
            0: self.add_node,
            1: self.remove_node,
            2: self.edit_node
        }, self.print_nodes_table)

    def set_nfs_query(self):
        self.stdscr.clear()
        ip = self.data_manager.nfs_server['ip']
        path = self.data_manager.nfs_server['path']
        ip = self.make_query(0, 0, f"IP Address [{ip}]: ", default_value=ip, valid_regex=REGEX_IP_ADDRESS)
        if ip == ESCAPE_CODE:
            return None
        path = self.make_query(1, 0, f"Base Path [{path}]: ", default_value=path, valid_regex=REGEX_PATH)
        if path == ESCAPE_CODE:
            return None
        self.data_manager.set_nfs_server(ip, path)

    def setting_nfs_menu(self):
        self.stdscr.clear()
        menu = ["1. ⚙️ Setting NFS Server", "2. 📦 Install NFS Server(Optional)", "3. 🔙 Back"]
        self.navigate_sub_menu(menu, {
            0: self.set_nfs_query,
            1: self.install_nfs
        }, self.print_nfs_server_table)

    def install_astrago_menu(self):
        menu = ["1. 🗄️ Set NFS Server", "2. 🚀 Install Astrago", "3. 🗑️ Uninstall Astrago", "4. 🔙 Back"]
        self.navigate_menu(menu, {
            0: self.setting_nfs_menu,
            1: self.install_astrago,
            2: self.uninstall_astrago
        })

    def install_kubernetes_menu(self):
        menu = ["1. 🖥️ Set Nodes", "2. ☸️ Install Kubernetes", "3. 🔄 Reset Kubernetes", "4. 🎮 Install GPU Driver (Optional)",
                "5. 🔙 Back"]
        self.navigate_menu(menu, {
            0: self.setting_node_menu,
            1: self.install_kubernetes,
            2: self.reset_kubernetes,
            3: self.install_gpu_driver
        })

    def navigate_sub_menu(self, menu, handlers, table_handler=None):
        current_row = 0
        while True:
            self.stdscr.clear()
            self.print_sub_menu(menu, current_row)
            if table_handler is not None:
                table_handler(len(menu), 0)
            key = self.stdscr.getch()
            if key == curses.KEY_UP and current_row > 0:
                current_row -= 1
            elif key == curses.KEY_DOWN and current_row < len(menu) - 1:
                current_row += 1
            elif key in range(49, 49 + len(menu)):
                current_row = key - 48 - 1
                if current_row in handlers:
                    handlers[current_row]()
                if current_row == len(menu) - 1:
                    break
            elif key == curses.KEY_ENTER or key in [10, 13]:
                if current_row in handlers:
                    handlers[current_row]()
                if current_row == len(menu) - 1:
                    break
            elif key == curses.KEY_BACKSPACE or key == 27:
                break
                curses.KEY_CANCEL

    def navigate_menu(self, menu, handlers):
        current_row = 0
        self.print_menu(menu, current_row)
        while True:
            key = self.stdscr.getch()
            if key == curses.KEY_UP and current_row > 0:
                current_row -= 1
            elif key == curses.KEY_DOWN and current_row < len(menu) - 1:
                current_row += 1
            elif key in range(49, 49 + len(menu)):
                current_row = key - 48 - 1
                if current_row in handlers:
                    handlers[current_row]()
                if current_row == len(menu) - 1:
                    break
            elif key == curses.KEY_ENTER or key in [10, 13]:
                if current_row in handlers:
                    handlers[current_row]()
                if current_row == len(menu) - 1:
                    break
            elif key == curses.KEY_BACKSPACE or key == 27:
                break
            self.print_menu(menu, current_row)

    def main(self, stdscr):
        self.stdscr = stdscr
        
        # ==========================================
        # 🎨 Beautiful Color Initialization
        # ==========================================
        curses.start_color()
        curses.use_default_colors()
        
        # 그라데이션 색상 정의 (run_gui_installer.sh와 통일)
        curses.init_pair(COLOR_GRADIENT1, 129, -1)    # Purple gradient
        curses.init_pair(COLOR_GRADIENT2, 135, -1)    # Light purple gradient
        curses.init_pair(COLOR_GRADIENT3, 141, -1)    # Pink purple gradient
        curses.init_pair(COLOR_GRADIENT4, 147, -1)    # Light pink gradient
        
        # 기능별 색상
        curses.init_pair(COLOR_SUCCESS, curses.COLOR_GREEN, -1)      # 성공
        curses.init_pair(COLOR_ERROR, curses.COLOR_RED, -1)          # 오류
        curses.init_pair(COLOR_WARNING, curses.COLOR_YELLOW, -1)     # 경고
        curses.init_pair(COLOR_INFO, curses.COLOR_CYAN, -1)          # 정보
        curses.init_pair(COLOR_SELECTED, curses.COLOR_BLACK, curses.COLOR_GREEN)  # 선택
        curses.init_pair(COLOR_BORDER, curses.COLOR_BLUE, -1)        # 테두리
        
        # 터미널 설정
        curses.echo()
        curses.set_escdelay(1)
        curses.curs_set(0)  # 커서 숨기기
        
        # 메인 메뉴
        main_menu = [
            "1. 🏗️  Kubernetes Infrastructure",
            "2. 🚀 Astrago Platform", 
            "3. 🚪 Exit"
        ]
        
        self.navigate_menu(main_menu, {
            0: self.install_kubernetes_menu,
            1: self.install_astrago_menu
        })


if __name__ == "__main__":
    curses.wrapper(AstragoInstaller().main)
