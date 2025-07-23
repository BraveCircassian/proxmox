from proxmoxer import ProxmoxAPI
import csv
from datetime import datetime

# Конфигурация подключения
PROXMOX_HOST = "1.1.1.1" # Хост подключения
PROXMOX_USER = "root@pam" # Пользователь
USE_TOKEN = True # True если использовать токен, false если через пароль. 

if USE_TOKEN:
    TOKEN_NAME = "token-name" # Название токена
    TOKEN_VALUE = "token-value" # Ключ токена
else:
    PASSWORD = "your-password"

def format_size(size_bytes):
    """Конвертация байт в ГБ"""
    return round(size_bytes / (1024**3), 2)

def save_to_csv(data, filename="proxmox_resources.csv"):
    """Сохранение данных в CSV файл"""
    with open(filename, mode='a', newline='') as file:
        writer = csv.writer(file, delimiter=';')
        if file.tell() == 0:  # Записываем заголовки только если файл пустой
            writer.writerow([
                "Дата",
                "Нода",
                "Процессор",
                "Физические ядра",
                "Логические ядра",
                "Использовано ядер ВМ",
                "Доступно ядер",
                "Всего RAM (GB)",
                "Использовано RAM ВМ (GB)",
                "Доступно RAM (GB)",
                "Загрузка CPU (%)",
                "Рекомендуемый лимит"
            ])
        writer.writerow(data)

def get_node_resources(proxmox, node_name):
    """Сбор и сохранение информации о ресурсах"""
    try:
        node_info = proxmox.nodes(node_name).get("status")
        cpu_info = node_info["cpuinfo"]
        
        physical_cores = int(cpu_info["cores"])
        threads_per_core = 2 if "ht" in cpu_info["model"].lower() else 1
        logical_cores = physical_cores * threads_per_core
        total_ram = node_info["memory"]["total"]
        
        # Сбор данных по ВМ
        vms = proxmox.nodes(node_name).qemu.get()
        used_cores = sum(
            int(vm_config.get("cores", 1))
            for vm in vms
            if vm["status"] == "running"
            for vm_config in [proxmox.nodes(node_name).qemu(vm["vmid"]).config.get()]
            if str(vm_config.get("cores", 1)).isdigit()
        )
        
        used_ram = sum(
            int(vm_config.get("memory", 512)) * 1024 * 1024
            for vm in vms
            if vm["status"] == "running"
            for vm_config in [proxmox.nodes(node_name).qemu(vm["vmid"]).config.get()]
            if str(vm_config.get("memory", 512)).replace('M', '').isdigit()
        )
        
        # Подготовка данных для CSV
        csv_data = [
            datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            node_name,
            cpu_info["model"],
            physical_cores,
            logical_cores,
            used_cores,
            max(0, logical_cores - used_cores),
            format_size(total_ram),
            format_size(used_ram),
            format_size(max(0, total_ram - used_ram)),
            round(float(node_info["cpu"]) * 100, 1),
            round(physical_cores * 1.5)
        ]
        
        # Сохранение в файл
        save_to_csv(csv_data)
        
        # Вывод в консоль для информации
        print(f"\nДанные по ноде {node_name} сохранены в CSV")
        print(f"  Процессор: {cpu_info['model']}")
        print(f"  Использовано ядер: {used_cores}/{logical_cores}")
        print(f"  Использовано RAM: {format_size(used_ram)}/{format_size(total_ram)} GB")
        
    except Exception as e:
        print(f"Ошибка обработки ноды {node_name}: {str(e)}")

def main():
    try:
        proxmox = ProxmoxAPI(
            PROXMOX_HOST,
            user=PROXMOX_USER,
            token_name=TOKEN_NAME if USE_TOKEN else None,
            token_value=TOKEN_VALUE if USE_TOKEN else None,
            password=None if USE_TOKEN else PASSWORD,
            verify_ssl=False
        )
        
        nodes = proxmox.nodes.get()
        print(f"Начинаем сбор данных для {len(nodes)} нод...")
        
        for node in nodes:
            get_node_resources(proxmox, node["node"])
            
        print("\nГотово! Данные сохранены в файл 'proxmox_resources.csv'")
        print("Можно открыть этот файл в Excel для анализа")
        
    except Exception as e:
        print(f"Критическая ошибка: {str(e)}")

if __name__ == "__main__":
    main()