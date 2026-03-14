#!/usr/bin/env bash

# Проверяем, передан ли аргумент
if [ $# -eq 0 ]; then
    echo "Ошибка: не указан файл"
    echo "Использование: $0 <файл>"
    exit 1
fi

file="$1"

# Проверяем, существует ли файл
if [ ! -f "$file" ]; then
    echo "Ошибка: файл '$file' не найден"
    exit 1
fi

# Выполняем exiftool
exiftool -overwrite_original \
         -FileModifyDate="1970:01:01 9:00:00" \
         -Artist="Неизвестный" \
         -Keywords="anon" \
         -Rating=3 \
         -Copyright="Phoin (c) 2021" \
         -Title="unsigned" \
         -Creator="Fantom" \
         -CreateDate="1970:01:01 9:00:00" \
         -DateTimeOriginal="1970:01:01 9:00:00" \
         "$file"

# Проверяем результат выполнения
if [ $? -eq 0 ]; then
    echo "Метаданные файла '$file' успешно обновлены"
else
    echo "Ошибка при обновлении метаданных"
    exit 1
fi
