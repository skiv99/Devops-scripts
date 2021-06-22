# README
## Описание примера скрипта деплоя
## Описание
Скрипт для деплоя микросервисов на виртуальные машины с помощью docker.
Сделан на основе GitlabCI и bash
Основным принципом является управление из yaml файла .\cicd-files\preprod.yaml и preprod.yaml
```json
service-name-111:
  port: 8888
  memory_start: 1g
  service_enable: true
  node_available:
    node1: false
    node2: true
    node3: true
    node4: true
  imagetag: [masked]
```
В .yaml указывается имя сервиса, порт на котором он запущен, параметры старта docker контейнера, версия тега


## Шаги выполниения

- Логин в docker regestry
- Скачивание необходимого образа на сервер
- Разрегестрирование сервиса в service discovery
- В случае если сервис является gateway происходит вывод сервера из балансировщика nginx путем запуска playbook ansible 
- Остановка и удаление существующего контейнера
- Создание контейнера с помощю docker run
- Проверка успешности деплоя сервиса 
