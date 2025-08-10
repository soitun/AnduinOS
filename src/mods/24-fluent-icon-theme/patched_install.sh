#!/usr/bin/env bash
# 重构版：跨颜色最大化去重 + 同色系内继续复用
# 接口与 README 一致

set -euo pipefail

#==========================
# 默认安装路径（root 安装到全局）
#==========================
if [ "${UID}" -eq 0 ]; then
  DEST_DIR="/usr/share/icons"
else
  DEST_DIR="${HOME}/.local/share/icons"
fi

# 源目录 = 脚本所在目录
readonly SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# 颜色 & 亮度变体
readonly COLOR_VARIANTS=("standard" "green" "grey" "orange" "pink" "purple" "red" "yellow" "teal")
readonly BRIGHT_VARIANTS=("" "light" "dark")

readonly DEFAULT_NAME="Fluent"

#==========================
# 打印帮助
#==========================
usage() {
  cat << EOF
Usage: $0 [OPTION] | [COLOR VARIANTS]...

OPTIONS:
  -a, --all                Install all color folder versions
  -d, --dest               Specify theme destination directory (Default: $HOME/.local/share/icons)
  -n, --name               Specify theme name (Default: Fluent)
  -h, --help               Show this help

COLOR VARIANTS:
  standard                 Standard color folder version
  green                    Green color folder version
  grey                     Grey color folder version
  orange                   Orange color folder version
  pink                     Pink color folder version
  purple                   Purple color folder version
  red                      Red color folder version
  yellow                   Yellow color folder version
  teal                     Teal color folder version

  By default, only the standard one is selected.
EOF
}

#==========================
# 小工具
#==========================
die() { echo "ERROR: $*" >&2; exit 1; }

# 带权限与模式的安装
install_file() {
  # $1 mode  $2 src  $3 dest
  install -m"$1" "$2" "$3"
}

ensure_dir() {
  install -d "$1"
}

safe_rm_dir() {
  local d="$1"
  if [ -d "$d" ] || [ -L "$d" ]; then
    rm -rf --one-file-system "$d"
  fi
}

# 创建相对符号链接（若已存在则替换）
rel_link() {
  local target="$1"
  local linkpath="$2"
  safe_rm_dir "$linkpath"
  ln -sr "$target" "$linkpath"
}

# 将 dir_src 的内容“合入” dir_dst（同名覆盖）
merge_copy() {
  local dir_src="$1"
  local dir_dst="$2"
  [ -d "$dir_src" ] || return 0
  ensure_dir "$dir_dst"
  cp -rT "$dir_src" "$dir_dst" 2>/dev/null || {
    # 对于老 busybox 等不支持 -T 的情况，退化实现
    cp -r "$dir_src/." "$dir_dst/"
  }
}

# sed 就地改色（若无匹配文件不失败）
safe_sed_replace() {
  local from="$1" to="$2" pattern="$3"
  # pattern 是 shell 展开后的文件列表
  # 若无文件匹配，不执行 sed
  shopt -s nullglob
  local files=( $pattern )
  shopt -u nullglob
  [ "${#files[@]}" -eq 0 ] && return 0
  sed -i "s/${from//\//\\/}/${to//\//\\/}/g" "${files[@]}"
}

#==========================
# 共享基座（隐藏目录，不暴露为主题）
#==========================
# 三个共享基座名（放在 DEST_DIR 下）
SHARED_BASE=""
SHARED_LIGHT_BASE=""
SHARED_DARK_BASE=""

init_shared_names() {
  SHARED_BASE="${DEST_DIR}/.${NAME}-base"
  SHARED_LIGHT_BASE="${DEST_DIR}/.${NAME}-light-base"
  SHARED_DARK_BASE="${DEST_DIR}/.${NAME}-dark-base"
}

# 构建标准亮度的共享基座（等价于原“标准亮度安装但不含 index.theme”）
build_shared_base() {
  if [ -d "${SHARED_BASE}" ]; then
    return
  fi
  echo "Preparing shared base: ${SHARED_BASE}"
  ensure_dir "${SHARED_BASE}"
  # 1) 复制 src 的整个主题树
  for d in 16 22 24 32 256 scalable symbolic; do
    merge_copy "${SRC_DIR}/src/${d}" "${SHARED_BASE}/${d}"
  done
  # 2) 合并 links（把链接别名结构叠加到相同目录下）
  for d in 16 22 24 32 256 scalable symbolic; do
    merge_copy "${SRC_DIR}/links/${d}" "${SHARED_BASE}/${d}"
  done
}

# 构建 light 共享基座（只包含 16/22/24 的 panel；完成 #dedede -> #363636）
build_shared_light_base() {
  if [ -d "${SHARED_LIGHT_BASE}" ]; then
    return
  fi
  echo "Preparing shared light base: ${SHARED_LIGHT_BASE}"
  ensure_dir "${SHARED_LIGHT_BASE}"
  for sz in 16 22 24; do
    # 从 src 拷贝 panel
    if [ -d "${SRC_DIR}/src/${sz}/panel" ]; then
      merge_copy "${SRC_DIR}/src/${sz}/panel" "${SHARED_LIGHT_BASE}/${sz}/panel"
      # 改色：light 中变深（与原脚本一致）
      safe_sed_replace "#dedede" "#363636" "${SHARED_LIGHT_BASE}/${sz}/panel/*.svg"
    fi
    # 合并 links 的 panel（与原脚本一致）
    if [ -d "${SRC_DIR}/links/${sz}/panel" ]; then
      merge_copy "${SRC_DIR}/links/${sz}/panel" "${SHARED_LIGHT_BASE}/${sz}/panel"
      # links 下的 panel 不做 sed（保持与原逻辑一致）
    fi
  done
}

# 构建 dark 共享基座（复制并改色那批目录）
build_shared_dark_base() {
  if [ -d "${SHARED_DARK_BASE}" ]; then
    return
  fi
  echo "Preparing shared dark base: ${SHARED_DARK_BASE}"
  ensure_dir "${SHARED_DARK_BASE}"

  # 复制 src 指定目录
  merge_copy "${SRC_DIR}/src/16/actions"   "${SHARED_DARK_BASE}/16/actions"
  merge_copy "${SRC_DIR}/src/16/devices"   "${SHARED_DARK_BASE}/16/devices"
  merge_copy "${SRC_DIR}/src/16/places"    "${SHARED_DARK_BASE}/16/places"

  merge_copy "${SRC_DIR}/src/22/actions"   "${SHARED_DARK_BASE}/22/actions"
  merge_copy "${SRC_DIR}/src/22/categories" "${SHARED_DARK_BASE}/22/categories"
  merge_copy "${SRC_DIR}/src/22/devices"   "${SHARED_DARK_BASE}/22/devices"
  merge_copy "${SRC_DIR}/src/22/places"    "${SHARED_DARK_BASE}/22/places"

  merge_copy "${SRC_DIR}/src/24/actions"   "${SHARED_DARK_BASE}/24/actions"
  merge_copy "${SRC_DIR}/src/24/devices"   "${SHARED_DARK_BASE}/24/devices"
  merge_copy "${SRC_DIR}/src/24/places"    "${SHARED_DARK_BASE}/24/places"

  merge_copy "${SRC_DIR}/src/32/actions"   "${SHARED_DARK_BASE}/32/actions"
  merge_copy "${SRC_DIR}/src/32/devices"   "${SHARED_DARK_BASE}/32/devices"
  merge_copy "${SRC_DIR}/src/32/status"    "${SHARED_DARK_BASE}/32/status"

  # symbolic
  if [ -d "${SRC_DIR}/src/symbolic" ]; then
    ensure_dir "${SHARED_DARK_BASE}/symbolic"
    cp -r "${SRC_DIR}/src/symbolic/." "${SHARED_DARK_BASE}/symbolic/"
  fi

  # 改色：dark 中把 #363636 -> #dedede（与原脚本一致）
  safe_sed_replace "#363636" "#dedede" "${SHARED_DARK_BASE}/22/categories/*.svg"
  for sz in 16 22 24 32; do
    safe_sed_replace "#363636" "#dedede" "${SHARED_DARK_BASE}/${sz}/actions/*.svg"
  done
  safe_sed_replace "#363636" "#dedede" "${SHARED_DARK_BASE}/32/devices/*.svg"
  safe_sed_replace "#363636" "#dedede" "${SHARED_DARK_BASE}/32/status/*.svg"
  for sz in 16 22 24; do
    safe_sed_replace "#363636" "#dedede" "${SHARED_DARK_BASE}/${sz}/places/*.svg"
    safe_sed_replace "#363636" "#dedede" "${SHARED_DARK_BASE}/${sz}/devices/*.svg"
  done
  # symbolic 子目录
  for sub in actions apps categories devices emblems emotes mimetypes places status; do
    safe_sed_replace "#363636" "#dedede" "${SHARED_DARK_BASE}/symbolic/${sub}/*.svg"
  done

  # 合并 links 下相应目录（与原脚本一致）
  merge_copy "${SRC_DIR}/links/16/actions"   "${SHARED_DARK_BASE}/16/actions"
  merge_copy "${SRC_DIR}/links/16/devices"   "${SHARED_DARK_BASE}/16/devices"
  merge_copy "${SRC_DIR}/links/16/places"    "${SHARED_DARK_BASE}/16/places"

  merge_copy "${SRC_DIR}/links/22/actions"   "${SHARED_DARK_BASE}/22/actions"
  merge_copy "${SRC_DIR}/links/22/categories" "${SHARED_DARK_BASE}/22/categories"
  merge_copy "${SRC_DIR}/links/22/devices"   "${SHARED_DARK_BASE}/22/devices"
  merge_copy "${SRC_DIR}/links/22/places"    "${SHARED_DARK_BASE}/22/places"

  merge_copy "${SRC_DIR}/links/24/actions"   "${SHARED_DARK_BASE}/24/actions"
  merge_copy "${SRC_DIR}/links/24/devices"   "${SHARED_DARK_BASE}/24/devices"
  merge_copy "${SRC_DIR}/links/24/places"    "${SHARED_DARK_BASE}/24/places"

  merge_copy "${SRC_DIR}/links/32/actions"   "${SHARED_DARK_BASE}/32/actions"
  merge_copy "${SRC_DIR}/links/32/devices"   "${SHARED_DARK_BASE}/32/devices"
  merge_copy "${SRC_DIR}/links/32/status"    "${SHARED_DARK_BASE}/32/status"

  if [ -d "${SRC_DIR}/links/symbolic" ]; then
    merge_copy "${SRC_DIR}/links/symbolic"   "${SHARED_DARK_BASE}/symbolic"
  fi
}

#==========================
# 安装单主题（颜色 + 亮度）
#==========================
install_theme() {
  local color="$1"   # e.g. standard / green
  local bright="$2"  # "" / light / dark

  local colorprefix=""
  [ "$color" != "standard" ] && colorprefix="-$color"
  local brightprefix=""
  [ -n "$bright" ] && brightprefix="-$bright"

  local THEME_NAME="${NAME}${colorprefix}${brightprefix}"
  local THEME_DIR="${DEST_DIR}/${THEME_NAME}"

  # 构建到临时目录，再原子替换
  local TMP_DIR="${THEME_DIR}.tmp.$$"
  safe_rm_dir "${TMP_DIR}"
  ensure_dir "${TMP_DIR}"

  echo "Installing '${THEME_NAME}'..."

  # index.theme
  install_file 644 "${SRC_DIR}/src/index.theme" "${TMP_DIR}/index.theme"
  # 更新 name（把 '-' 换成空格保持原行为）
  sed -i "s/%NAME%/${THEME_NAME//-/ }/g" "${TMP_DIR}/index.theme"

  if [ -z "${bright}" ]; then
    #==========================
    # 标准亮度
    #==========================
    # 大部分目录链接到共享基座
    for d in 16 22 24 32 256 symbolic; do
      ensure_dir "${TMP_DIR}/${d%/*}"
      rel_link "${SHARED_BASE}/${d}" "${TMP_DIR}/${d}"
    done

    # scalable：标准色整目录链接；非标准色需要覆写 apps/places
    if [ "$color" = "standard" ]; then
      rel_link "${SHARED_BASE}/scalable" "${TMP_DIR}/scalable"
    else
      ensure_dir "${TMP_DIR}/scalable"
      # 其余子目录链接
      for sub in applets devices mimetypes; do
        [ -d "${SHARED_BASE}/scalable/${sub}" ] && rel_link "${SHARED_BASE}/scalable/${sub}" "${TMP_DIR}/scalable/${sub}"
      done
      # apps / places：拷贝基线再覆盖颜色差异
      for sub in apps places; do
        ensure_dir "${TMP_DIR}/scalable/${sub}"
        if [ -d "${SHARED_BASE}/scalable/${sub}" ]; then
          cp -r "${SHARED_BASE}/scalable/${sub}/." "${TMP_DIR}/scalable/${sub}/"
        fi
      done
      # 覆盖颜色差异
      local COLOR_DIR="${SRC_DIR}/colors/color-${color}"
      if [ -d "${COLOR_DIR}/places" ]; then
        install -m644 "${COLOR_DIR}/places/"*.svg "${TMP_DIR}/scalable/places" 2>/dev/null || true
      fi
      if [ -d "${COLOR_DIR}/apps" ]; then
        install -m644 "${COLOR_DIR}/apps/"*.svg "${TMP_DIR}/scalable/apps" 2>/dev/null || true
      fi
    fi

  elif [ "${bright}" = "light" ]; then
    #==========================
    # light 变体
    #==========================
    # 16/22/24/panel → 链接到共享 light 基座；其它目录链接到同色标准亮度
    local STD_THEME_DIR="${DEST_DIR}/${NAME}${colorprefix}"

    # 准备像素目录
    ensure_dir "${TMP_DIR}/16"
    ensure_dir "${TMP_DIR}/22"
    ensure_dir "${TMP_DIR}/24"

    # panel（由 light 基座提供改色后版本）
    rel_link "${SHARED_LIGHT_BASE}/16/panel" "${TMP_DIR}/16/panel"
    rel_link "${SHARED_LIGHT_BASE}/22/panel" "${TMP_DIR}/22/panel"
    rel_link "${SHARED_LIGHT_BASE}/24/panel" "${TMP_DIR}/24/panel"

    # 链接公共目录到标准同色
    rel_link "${STD_THEME_DIR}/scalable"     "${TMP_DIR}/scalable"
    rel_link "${STD_THEME_DIR}/32"           "${TMP_DIR}/32"
    rel_link "${STD_THEME_DIR}/256"          "${TMP_DIR}/256"
    rel_link "${STD_THEME_DIR}/16/actions"   "${TMP_DIR}/16/actions"
    rel_link "${STD_THEME_DIR}/16/devices"   "${TMP_DIR}/16/devices"
    rel_link "${STD_THEME_DIR}/16/mimetypes" "${TMP_DIR}/16/mimetypes"
    rel_link "${STD_THEME_DIR}/16/places"    "${TMP_DIR}/16/places"
    rel_link "${STD_THEME_DIR}/16/status"    "${TMP_DIR}/16/status"
    rel_link "${STD_THEME_DIR}/22/actions"   "${TMP_DIR}/22/actions"
    rel_link "${STD_THEME_DIR}/22/categories" "${TMP_DIR}/22/categories"
    rel_link "${STD_THEME_DIR}/22/devices"   "${TMP_DIR}/22/devices"
    rel_link "${STD_THEME_DIR}/22/emblems"   "${TMP_DIR}/22/emblems"
    rel_link "${STD_THEME_DIR}/22/mimetypes" "${TMP_DIR}/22/mimetypes"
    rel_link "${STD_THEME_DIR}/22/places"    "${TMP_DIR}/22/places"
    rel_link "${STD_THEME_DIR}/24/actions"   "${TMP_DIR}/24/actions"
    rel_link "${STD_THEME_DIR}/24/animations" "${TMP_DIR}/24/animations"
    rel_link "${STD_THEME_DIR}/24/devices"   "${TMP_DIR}/24/devices"
    rel_link "${STD_THEME_DIR}/24/places"    "${TMP_DIR}/24/places"
    rel_link "${STD_THEME_DIR}/symbolic"     "${TMP_DIR}/symbolic"

  elif [ "${bright}" = "dark" ]; then
    #==========================
    # dark 变体
    #==========================
    local STD_THEME_DIR="${DEST_DIR}/${NAME}${colorprefix}"

    # 需要“改色后专有”的目录 → 链接到共享 dark 基座
    for path in \
      "16/actions" "16/devices" "16/places" \
      "22/actions" "22/categories" "22/devices" "22/places" \
      "24/actions" "24/devices" "24/places" \
      "32/actions" "32/devices" "32/status" \
      "symbolic"
    do
      local src="${SHARED_DARK_BASE}/${path}"
      if [ -e "$src" ]; then
        ensure_dir "${TMP_DIR}/$(dirname "$path")"
        rel_link "$src" "${TMP_DIR}/${path}"
      fi
    done

    # 其它公共目录 → 链接到同色标准亮度
    rel_link "${STD_THEME_DIR}/scalable"       "${TMP_DIR}/scalable"
    rel_link "${STD_THEME_DIR}/16/mimetypes"   "${TMP_DIR}/16/mimetypes"
    rel_link "${STD_THEME_DIR}/16/status"      "${TMP_DIR}/16/status"
    rel_link "${STD_THEME_DIR}/16/panel"       "${TMP_DIR}/16/panel"
    rel_link "${STD_THEME_DIR}/22/emblems"     "${TMP_DIR}/22/emblems"
    rel_link "${STD_THEME_DIR}/22/mimetypes"   "${TMP_DIR}/22/mimetypes"
    rel_link "${STD_THEME_DIR}/22/panel"       "${TMP_DIR}/22/panel"
    rel_link "${STD_THEME_DIR}/24/animations"  "${TMP_DIR}/24/animations"
    rel_link "${STD_THEME_DIR}/24/panel"       "${TMP_DIR}/24/panel"
    rel_link "${STD_THEME_DIR}/32/categories"  "${TMP_DIR}/32/categories"
    rel_link "${STD_THEME_DIR}/256"            "${TMP_DIR}/256"
  fi

  # @2x / @3x 别名（保持原行为）
  for mult in 2 3; do
    rel_link "${TMP_DIR}/16"      "${TMP_DIR}/16@${mult}x"
    rel_link "${TMP_DIR}/22"      "${TMP_DIR}/22@${mult}x"
    rel_link "${TMP_DIR}/24"      "${TMP_DIR}/24@${mult}x"
    rel_link "${TMP_DIR}/32"      "${TMP_DIR}/32@${mult}x"
    rel_link "${TMP_DIR}/256"     "${TMP_DIR}/256@${mult}x"
    rel_link "${TMP_DIR}/scalable" "${TMP_DIR}/scalable@${mult}x"
  done

  # 原子替换
  safe_rm_dir "${THEME_DIR}"
  mv "${TMP_DIR}" "${THEME_DIR}"

  # 更新缓存（保守做法：每主题更新一次；如需统一延后，可改为收集列表后统一执行）
  gtk-update-icon-cache "${THEME_DIR}" >/dev/null 2>&1 || true
}

#==========================
# 参数解析
#==========================
NAME=""
colors=()

while [ $# -gt 0 ]; do
  case "$1" in
    -a|--all)
      colors=("${COLOR_VARIANTS[@]}")
      ;;
    -d|--dest)
      [ $# -ge 2 ] || die "Missing argument for $1"
      DEST_DIR="$2"
      shift
      ;;
    -n|--name)
      [ $# -ge 2 ] || die "Missing argument for $1"
      NAME="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      # 若是合法颜色名，加入列表；否则报错
      if [[ " ${COLOR_VARIANTS[*]} " == *" $1 "* ]]; then
        # 去重
        if [[ " ${colors[*]-} " != *" $1 "* ]]; then
          colors+=("$1")
        fi
      else
        die "Unrecognized installation option '$1'. Try '$0 --help'."
      fi
      ;;
  esac
  shift
done

: "${NAME:="${DEFAULT_NAME}"}"

# 默认仅安装 standard
if [ ${#colors[@]} -eq 0 ]; then
  colors=(standard)
fi

#==========================
# 预备共享基座（一次构建，终身复用）
#==========================
ensure_dir "${DEST_DIR}"
init_shared_names
build_shared_base
build_shared_light_base
build_shared_dark_base

#==========================
# 安装循环
#==========================
for color in "${colors[@]}"; do
  for bright in "${BRIGHT_VARIANTS[@]}"; do
    install_theme "${color}" "${bright}"
  done
done

echo "Done."
