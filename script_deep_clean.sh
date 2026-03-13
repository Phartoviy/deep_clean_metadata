#!/usr/bin/env bash
set -Eeuo pipefail

TARGET="${1:-}"
FIXED_DATE="1970-09-01 00:00:00"

if [[ -z "$TARGET" ]]; then
  echo "Использование:"
  echo "  $0 <файл_или_папка>"
  exit 1
fi

if [[ ! -e "$TARGET" ]]; then
  echo "Ошибка: '$TARGET' не существует"
  exit 1
fi

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

log() {
  printf '[*] %s\n' "$*"
}

warn() {
  printf '[!] %s\n' "$*" >&2
}

cleanup_tmp() {
  [[ -n "${TMPDIR_CREATED:-}" && -d "${TMPDIR_CREATED:-}" ]] && rm -rf "$TMPDIR_CREATED"
}
trap cleanup_tmp EXIT

apply_timestamps() {
  local f="$1"
  touch -a -m -d "$FIXED_DATE" "$f" 2>/dev/null || true
}

clean_with_mat2() {
  local file="$1"
  local dir base ext cleaned

  have_cmd mat2 || return 1

  dir="$(dirname "$file")"
  base="$(basename "$file")"

  # MAT2 обычно создаёт очищенный файл рядом, не всегда in-place
  if mat2 "$file" >/dev/null 2>&1; then
    ext="${base##*.}"
    cleaned="${file%.*}.cleaned.${ext}"

    if [[ -f "$cleaned" ]]; then
      mv -f "$cleaned" "$file"
      return 0
    fi

    # запасной поиск на случай нестандартного имени
    cleaned="$(find "$dir" -maxdepth 1 -type f -name "$(basename "${file%.*}").cleaned.*" | head -n 1 || true)"
    if [[ -n "$cleaned" && -f "$cleaned" ]]; then
      mv -f "$cleaned" "$file"
      return 0
    fi

    # если MAT2 отработал, но нового файла не нашли
    return 0
  fi

  return 1
}

clean_with_exiftool() {
  local file="$1"

  have_cmd exiftool || return 1

  # Удаляем максимум известных тегов и служебных блоков
  exiftool -overwrite_original \
    -all= \
    -XMP:All= \
    -EXIF:All= \
    -IPTC:All= \
    -ICC_Profile:All= \
    -MakerNotes:All= \
    -Photoshop:All= \
    -Comment= \
    "$file" >/dev/null 2>&1 || return 1

  return 0
}

rewrite_plaintext() {
  local file="$1"
  local mime="$2"
  local perms owner group tmp

  case "$mime" in
    text/*|application/json|application/xml|application/javascript)
      perms="$(stat -c '%a' "$file" 2>/dev/null || echo "")"
      owner="$(stat -c '%u' "$file" 2>/dev/null || echo "")"
      group="$(stat -c '%g' "$file" 2>/dev/null || echo "")"

      TMPDIR_CREATED="$(mktemp -d)"
      tmp="$TMPDIR_CREATED/$(basename "$file")"

      cat "$file" > "$tmp"
      mv -f "$tmp" "$file"

      [[ -n "$perms" ]] && chmod "$perms" "$file" 2>/dev/null || true
      [[ -n "$owner" && -n "$group" ]] && chown "$owner:$group" "$file" 2>/dev/null || true
      ;;
  esac
}

remove_xattrs() {
  local file="$1"

  if have_cmd setfattr; then
    local attrs
    attrs="$(getfattr --absolute-names -d "$file" 2>/dev/null | awk -F= '/^# file: /{next} /^[^#].*=/{print $1}' || true)"
    if [[ -n "$attrs" ]]; then
      while IFS= read -r attr; do
        [[ -n "$attr" ]] && setfattr -x "$attr" "$file" 2>/dev/null || true
      done <<< "$attrs"
    fi
  fi
}

clean_one_file() {
  local file="$1"
  local mime perms owner group

  [[ -f "$file" ]] || return 0

  mime="$(file --mime-type -b "$file" 2>/dev/null || echo application/octet-stream)"
  perms="$(stat -c '%a' "$file" 2>/dev/null || echo "")"
  owner="$(stat -c '%u' "$file" 2>/dev/null || echo "")"
  group="$(stat -c '%g' "$file" 2>/dev/null || echo "")"

  log "Обрабатываю: $file"
  log "MIME: $mime"

  # 1) MAT2 — лучший для документов/анонимизации, если формат поддерживается
  if have_cmd mat2; then
    if clean_with_mat2 "$file"; then
      log "MAT2: выполнено"
    else
      warn "MAT2: пропущен или формат не поддерживается"
    fi
  else
    warn "MAT2 не найден"
  fi

  # 2) ExifTool — добиваем встроенные теги, если умеет этот формат
  if have_cmd exiftool; then
    if clean_with_exiftool "$file"; then
      log "ExifTool: выполнено"
    else
      warn "ExifTool: не смог обработать или формат не поддерживается"
    fi
  else
    warn "ExifTool не найден"
  fi

  # 3) Для текстовых файлов — переписываем содержимое в новый inode
  rewrite_plaintext "$file" "$mime"

  # 4) Пробуем убрать extended attributes файловой системы
  remove_xattrs "$file"

  # 5) Возвращаем права/владельца по возможности
  [[ -n "$perms" ]] && chmod "$perms" "$file" 2>/dev/null || true
  [[ -n "$owner" && -n "$group" ]] && chown "$owner:$group" "$file" 2>/dev/null || true

  # 6) Ставим фиксированную дату
  apply_timestamps "$file"

  log "Готово: $file"
  echo
}

export FIXED_DATE
export -f have_cmd log warn apply_timestamps clean_with_mat2 clean_with_exiftool rewrite_plaintext remove_xattrs clean_one_file cleanup_tmp

if [[ -f "$TARGET" ]]; then
  clean_one_file "$TARGET"
else
  find "$TARGET" -type f -print0 | while IFS= read -r -d '' f; do
    clean_one_file "$f"
  done
fi

echo "Завершено."
echo "Проверка:"
echo "  stat \"$TARGET\""
if have_cmd exiftool; then
  echo "  exiftool \"$TARGET\""
fi
