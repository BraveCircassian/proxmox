from proxmoxer import ProxmoxAPI
import csv
from datetime import datetime

# Конфигурация подключения
PROXMOX_HOST = "1.1.1.1"  # IP вашего Proxmox
PROXMOX_USER = "root@pam"        # Пользователь
TOKEN_NAME = "token_name"   # Имя токена
TOKEN_VALUE = "token_key" # Секретный ключ
OUTPUT_FILE = "vm_notes_export.csv" # Имя файла для выгрузки

def main():
    # Подключаемся к Proxmox API
    proxmox = ProxmoxAPI(
        PROXMOX_HOST,
        user=PROXMOX_USER,
        token_name=TOKEN_NAME,
        token_value=TOKEN_VALUE,
        verify_ssl=False
    )

    # Создаем CSV файл
    with open(OUTPUT_FILE, mode='w', newline='', encoding='utf-8') as file:
        writer = csv.writer(file, delimiter=';')
        # Заголовки CSV
        writer.writerow([
            "Дата выгрузки",
            "Нода",
            "ID ВМ",
            "Имя ВМ",
            "Статус",
            "Заметки (Notes)"
        ])

        # Получаем список всех нод
        nodes = proxmox.nodes.get()
        print(f"Найдено нод: {len(nodes)}")

        total_vms = 0
        processed_vms = 0

        for node in nodes:
            node_name = node['node']
            print(f"\nОбработка ноды: {node_name}")

            # Получаем все ВМ на ноде
            vms = proxmox.nodes(node_name).qemu.get()
            total_vms += len(vms)
            print(f"Найдено ВМ: {len(vms)}")

            for vm in vms:
                try:
                    # Получаем конфигурацию ВМ (включая notes)
                    config = proxmox.nodes(node_name).qemu(vm['vmid']).config.get()
                    
                    # Извлекаем заметки (поле 'description' в API)
                    notes = config.get('description', '').strip()
                    
                    # Записываем данные в CSV
                    writer.writerow([
                        datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                        node_name,
                        vm['vmid'],
                        vm.get('name', 'N/A'),
                        vm['status'],
                        notes.replace('\n', ' ')  # Убираем переносы строк
                    ])
                    
                    processed_vms += 1
                    if processed_vms % 10 == 0:
                        print(f"Обработано ВМ: {processed_vms}/{total_vms}")

                except Exception as e:
                    print(f"Ошибка при обработке ВМ {vm['vmid']}: {str(e)}")
                    continue

    print(f"\nГотово! Данные сохранены в файл: {OUTPUT_FILE}")
    print(f"Всего обработано ВМ: {processed_vms} из {total_vms}")

if __name__ == "__main__":
    main()