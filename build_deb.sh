#!/usr/bin/env bash
#
# LingJian-pinyin .deb 打包脚本
# 适用于 Ubuntu 22.04 ~ 26.04
#
# 构建 Fcitx5 输入法 addon + 可选的独立 UI Demo
#
# 用法:
#   chmod +x build_deb.sh
#   ./build_deb.sh              # 默认 Release 构建
#   ./build_deb.sh --skip-deps  # 跳过安装构建依赖
#   ./build_deb.sh --clean      # 清理之前的构建产物后重新构建
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PKG_NAME="lingjian-pinyin"
readonly PKG_VERSION="0.1.0"
readonly PKG_ARCH="$(dpkg --print-architecture)"
readonly PKG_MAINTAINER="LingJian Pinyin Team <lingjian-pinyin@example.com>"
readonly PKG_DESCRIPTION="灵键拼音输入法 - 基于 Fcitx5 的轻量级中文拼音输入法"
readonly PKG_HOMEPAGE="https://github.com/LingJian-pinyin/LingJian-pinyin"

readonly BUILD_DIR="${SCRIPT_DIR}/build-release"
readonly DEB_ROOT="${SCRIPT_DIR}/deb-package"
readonly DEB_FILE="${SCRIPT_DIR}/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb"

readonly INSTALL_PREFIX="/usr"
readonly LIB_DIR="${INSTALL_PREFIX}/lib/${PKG_NAME}"
readonly DATA_DIR="${LIB_DIR}/data"
readonly BIN_DIR="${INSTALL_PREFIX}/bin"
readonly SHARE_DIR="${INSTALL_PREFIX}/share"
readonly DESKTOP_DIR="${SHARE_DIR}/applications"
readonly ICON_DIR="${SHARE_DIR}/icons/hicolor/128x128/apps"
readonly DOC_DIR="${SHARE_DIR}/doc/${PKG_NAME}"

SKIP_DEPS=false
CLEAN_BUILD=false

for arg in "$@"; do
    case "$arg" in
        --skip-deps)  SKIP_DEPS=true  ;;
        --clean)      CLEAN_BUILD=true ;;
        -h|--help)
            echo "用法: $0 [--skip-deps] [--clean] [-h|--help]"
            echo "  --skip-deps  跳过安装构建依赖"
            echo "  --clean      清理之前的构建产物后重新构建"
            exit 0
            ;;
        *)
            echo "未知参数: $arg"
            exit 1
            ;;
    esac
done

log_info()  { echo -e "\033[1;32m[INFO]\033[0m  $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; }

check_ubuntu_version() {
    if [[ ! -f /etc/os-release ]]; then
        log_warn "无法检测操作系统版本，继续构建..."
        return
    fi

    source /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        log_warn "当前系统不是 Ubuntu (${ID:-unknown})，脚本可能仍然可用"
    fi

    local ver="${VERSION_ID:-0}"
    local major="${ver%%.*}"
    if (( major < 22 )); then
        log_warn "Ubuntu ${ver} 版本低于 22.04，Qt6 / Fcitx5 可能不可用"
    fi
}

install_build_deps() {
    if $SKIP_DEPS; then
        log_info "跳过安装构建依赖 (--skip-deps)"
        return
    fi

    local deps=(
        build-essential
        cmake
        g++
        dpkg-dev
        qt6-base-dev
        libgl1-mesa-dev
        fcitx5
        libfcitx5core-dev
        libfcitx5utils-dev
        fcitx5-modules-dev
    )

    local missing=()
    for pkg in "${deps[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_info "所有构建依赖已安装，跳过"
        return
    fi

    log_info "安装缺失的构建依赖: ${missing[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends "${missing[@]}"
}

build_project() {
    if $CLEAN_BUILD && [[ -d "$BUILD_DIR" ]]; then
        log_info "清理旧构建目录: ${BUILD_DIR}"
        rm -rf "$BUILD_DIR"
    fi

    log_info "开始构建项目 (Release)..."
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    cmake "$SCRIPT_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-O2" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DBUILD_UI=ON \
        -DBUILD_FCITX5=ON \
        -Wno-dev

    cmake --build . -- -j"$(nproc)"

    log_info "构建完成"
    cd "$SCRIPT_DIR"
}

prepare_deb_tree() {
    log_info "准备 .deb 打包目录..."

    rm -rf "$DEB_ROOT"
    mkdir -p "${DEB_ROOT}/DEBIAN"
    mkdir -p "${DEB_ROOT}${BIN_DIR}"
    mkdir -p "${DEB_ROOT}${LIB_DIR}"
    mkdir -p "${DEB_ROOT}${DATA_DIR}/skins"
    mkdir -p "${DEB_ROOT}${DESKTOP_DIR}"
    mkdir -p "${DEB_ROOT}${ICON_DIR}"
    mkdir -p "${DEB_ROOT}${DOC_DIR}"
}

detect_qt6_depends() {
    local binary="${BUILD_DIR}/src/ui/lingjian_ui"
    local qt_deps=""

    if [[ ! -f "$binary" ]]; then
        echo "libqt6widgets6 (>= 6.2), libqt6gui6 (>= 6.2), libqt6core6 (>= 6.2)"
        return
    fi

    if command -v dpkg-shlibdeps &>/dev/null && command -v objdump &>/dev/null; then
        local libs
        libs=$(ldd "$binary" 2>/dev/null | grep -oP '/\S+' || true)

        local qt6_packages=""
        for lib in $libs; do
            local pkg
            pkg=$(dpkg -S "$lib" 2>/dev/null | head -1 | cut -d: -f1 || true)
            if [[ -n "$pkg" && "$pkg" == *qt6* ]]; then
                qt6_packages="${qt6_packages:+${qt6_packages}, }${pkg}"
            fi
        done

        if [[ -n "$qt6_packages" ]]; then
            echo "$qt6_packages"
            return
        fi
    fi

    echo "libqt6widgets6 (>= 6.2), libqt6gui6 (>= 6.2), libqt6core6 (>= 6.2)"
}

write_control_file() {
    log_info "生成 DEBIAN/control..."

    local qt_deps
    qt_deps=$(detect_qt6_depends)

    cat > "${DEB_ROOT}/DEBIAN/control" << CTRL
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Section: utils
Priority: optional
Architecture: ${PKG_ARCH}
Depends: fcitx5 (>= 5.0), ${qt_deps}, unzip
Recommends: fcitx5-frontend-gtk3, fcitx5-frontend-gtk4, fcitx5-frontend-qt5, fcitx5-frontend-qt6, fcitx5-config-qt
Maintainer: ${PKG_MAINTAINER}
Homepage: ${PKG_HOMEPAGE}
Description: ${PKG_DESCRIPTION}
 灵键拼音是一款基于 Fcitx5 框架的中文拼音输入法，
 具有整句输入、Beam Search 解码、语言模型评分、
 主题皮肤定制等功能。支持 X11 和 Wayland 桌面环境。
 .
 Fcitx5 框架天然支持 X11（通过 XIM 协议）和 Wayland
 （通过 zwp_input_method_v2 协议），输入法引擎无需
 针对不同显示服务器做特殊适配。安装 fcitx5-frontend-gtk3、
 fcitx5-frontend-qt5 等前端模块后，可在各类应用中使用。
CTRL
}

write_postinst() {
    cat > "${DEB_ROOT}/DEBIAN/postinst" << 'POSTINST'
#!/bin/bash
set -e

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database -q /usr/share/applications 2>/dev/null || true
fi

if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
fi

# 重新加载 fcitx5 addon 列表
if command -v fcitx5-remote &>/dev/null; then
    fcitx5-remote -r 2>/dev/null || true
fi

echo ""
echo "=== 灵键拼音安装完成 ==="
echo ""
echo "请按以下步骤启用输入法："
echo "  1. 确保 fcitx5 已设为默认输入法框架"
echo "  2. 打开 fcitx5-configtool（或系统设置 → 输入法）"
echo "  3. 在输入法列表中添加「灵键拼音」"
echo "  4. 注销并重新登录，或运行: fcitx5-remote -r"
echo ""

exit 0
POSTINST
    chmod 0755 "${DEB_ROOT}/DEBIAN/postinst"
}

write_postrm() {
    cat > "${DEB_ROOT}/DEBIAN/postrm" << 'POSTRM'
#!/bin/bash
set -e

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database -q /usr/share/applications 2>/dev/null || true
fi

if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
fi

if command -v fcitx5-remote &>/dev/null; then
    fcitx5-remote -r 2>/dev/null || true
fi

exit 0
POSTRM
    chmod 0755 "${DEB_ROOT}/DEBIAN/postrm"
}

install_files() {
    log_info "安装文件到打包目录..."

    # 安装 fcitx5 addon（通过 cmake --install）
    log_info "安装 fcitx5 addon 文件..."
    DESTDIR="${DEB_ROOT}" cmake --install "$BUILD_DIR" --component Unspecified 2>/dev/null \
        || DESTDIR="${DEB_ROOT}" cmake --install "$BUILD_DIR" 2>/dev/null \
        || log_warn "cmake install 失败，尝试手动安装 fcitx5 文件..."

    # 手动安装兜底（如果 cmake install 失败）
    if [[ ! -f "${DEB_ROOT}/usr/lib/"*"/fcitx5/lingjian.so" ]] 2>/dev/null; then
        install_fcitx5_manually
    fi

    # 安装独立 UI（如果存在）
    if [[ -f "${BUILD_DIR}/src/ui/lingjian_ui" ]]; then
        install -m 0755 "${BUILD_DIR}/src/ui/lingjian_ui" "${DEB_ROOT}${LIB_DIR}/lingjian_ui"

        cat > "${DEB_ROOT}${BIN_DIR}/${PKG_NAME}" << WRAPPER
#!/bin/bash
exec "${LIB_DIR}/lingjian_ui" "\$@"
WRAPPER
        chmod 0755 "${DEB_ROOT}${BIN_DIR}/${PKG_NAME}"
    fi

    if [[ -f "${SCRIPT_DIR}/data/pinyin_dict.txt" ]]; then
        install -m 0644 "${SCRIPT_DIR}/data/pinyin_dict.txt" "${DEB_ROOT}${DATA_DIR}/pinyin_dict.txt"
    fi

    if [[ -d "${SCRIPT_DIR}/data/skins" ]]; then
        cp -r "${SCRIPT_DIR}/data/skins/"* "${DEB_ROOT}${DATA_DIR}/skins/"
    fi

    if [[ -f "${SCRIPT_DIR}/README.md" ]]; then
        install -m 0644 "${SCRIPT_DIR}/README.md" "${DEB_ROOT}${DOC_DIR}/README.md"
    fi

    write_desktop_file
    generate_icon
}

install_fcitx5_manually() {
    log_info "手动安装 fcitx5 addon 文件..."

    local fcitx5_addon_dir
    fcitx5_addon_dir=$(pkg-config --variable=addondir fcitx5 2>/dev/null || echo "/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)/fcitx5")
    local fcitx5_data_dir
    fcitx5_data_dir=$(pkg-config --variable=pkgdatadir fcitx5 2>/dev/null || echo "/usr/share/fcitx5")

    mkdir -p "${DEB_ROOT}${fcitx5_addon_dir}"
    mkdir -p "${DEB_ROOT}${fcitx5_data_dir}/addon"
    mkdir -p "${DEB_ROOT}${fcitx5_data_dir}/inputmethod"
    mkdir -p "${DEB_ROOT}${fcitx5_data_dir}/lingjian"

    if [[ -f "${BUILD_DIR}/src/fcitx/lingjian.so" ]]; then
        install -m 0644 "${BUILD_DIR}/src/fcitx/lingjian.so" "${DEB_ROOT}${fcitx5_addon_dir}/lingjian.so"
    fi

    if [[ -f "${BUILD_DIR}/src/fcitx/lingjian-addon.conf" ]]; then
        install -m 0644 "${BUILD_DIR}/src/fcitx/lingjian-addon.conf" "${DEB_ROOT}${fcitx5_data_dir}/addon/lingjian.conf"
    fi

    if [[ -f "${BUILD_DIR}/src/fcitx/lingjian-im.conf" ]]; then
        install -m 0644 "${BUILD_DIR}/src/fcitx/lingjian-im.conf" "${DEB_ROOT}${fcitx5_data_dir}/inputmethod/lingjian.conf"
    fi

    if [[ -f "${SCRIPT_DIR}/data/pinyin_dict.txt" ]]; then
        install -m 0644 "${SCRIPT_DIR}/data/pinyin_dict.txt" "${DEB_ROOT}${fcitx5_data_dir}/lingjian/pinyin_dict.txt"
    fi
}

write_desktop_file() {
    log_info "生成 .desktop 文件..."

    cat > "${DEB_ROOT}${DESKTOP_DIR}/${PKG_NAME}.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=灵键拼音
Name[en]=LingJian Pinyin
GenericName=Chinese Pinyin Input Method
GenericName[zh_CN]=中文拼音输入法
Comment=轻量级中文拼音输入法 (Fcitx5)
Comment[en]=Lightweight Chinese Pinyin Input Method (Fcitx5)
Exec=${PKG_NAME}
Icon=${PKG_NAME}
Terminal=false
Categories=Utility;TextEditor;
Keywords=pinyin;input;chinese;输入法;拼音;fcitx5;
StartupNotify=true
DESKTOP
}

generate_icon() {
    log_info "生成应用图标 (SVG → PNG)..."

    local svg_file="${DEB_ROOT}${ICON_DIR}/${PKG_NAME}.svg"
    mkdir -p "$(dirname "$svg_file")"

    cat > "$svg_file" << 'SVGICON'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#4F8EF7"/>
      <stop offset="100%" style="stop-color:#2563EB"/>
    </linearGradient>
  </defs>
  <rect width="128" height="128" rx="24" fill="url(#bg)"/>
  <text x="64" y="78" font-family="sans-serif" font-size="52" font-weight="bold"
        fill="white" text-anchor="middle">灵</text>
  <text x="64" y="110" font-family="sans-serif" font-size="18"
        fill="rgba(255,255,255,0.85)" text-anchor="middle">PINYIN</text>
</svg>
SVGICON

    if command -v rsvg-convert &>/dev/null; then
        rsvg-convert -w 128 -h 128 "$svg_file" > "${DEB_ROOT}${ICON_DIR}/${PKG_NAME}.png"
        rm -f "$svg_file"
        log_info "已通过 rsvg-convert 生成 PNG 图标"
    elif command -v convert &>/dev/null; then
        convert -background none -resize 128x128 "$svg_file" "${DEB_ROOT}${ICON_DIR}/${PKG_NAME}.png"
        rm -f "$svg_file"
        log_info "已通过 ImageMagick 生成 PNG 图标"
    else
        local svg_icon_dir="${SHARE_DIR}/icons/hicolor/scalable/apps"
        mkdir -p "${DEB_ROOT}${svg_icon_dir}"
        mv "$svg_file" "${DEB_ROOT}${svg_icon_dir}/${PKG_NAME}.svg"
        rmdir "${DEB_ROOT}${ICON_DIR}" 2>/dev/null || true
        log_warn "未找到 SVG 转换工具，将使用 SVG 格式图标"
    fi
}

build_deb() {
    log_info "构建 .deb 包..."

    find "$DEB_ROOT" -type d -exec chmod 0755 {} +
    find "$DEB_ROOT" -type f -not -path "*/DEBIAN/*" -exec chmod 0644 {} +

    # 设置可执行权限
    if [[ -f "${DEB_ROOT}${LIB_DIR}/lingjian_ui" ]]; then
        chmod 0755 "${DEB_ROOT}${LIB_DIR}/lingjian_ui"
    fi
    if [[ -f "${DEB_ROOT}${BIN_DIR}/${PKG_NAME}" ]]; then
        chmod 0755 "${DEB_ROOT}${BIN_DIR}/${PKG_NAME}"
    fi

    fakeroot dpkg-deb --build "$DEB_ROOT" "$DEB_FILE" 2>/dev/null \
        || dpkg-deb --build "$DEB_ROOT" "$DEB_FILE"

    if [[ -f "$DEB_FILE" ]]; then
        log_info "打包成功!"
        echo ""
        echo "========================================"
        echo "  .deb 文件: ${DEB_FILE}"
        echo "  文件大小: $(du -h "$DEB_FILE" | cut -f1)"
        echo "========================================"
        echo ""
        echo "安装命令:"
        echo "  sudo dpkg -i ${DEB_FILE}"
        echo "  sudo apt-get install -f   # 修复依赖（如有需要）"
        echo ""
        echo "启用输入法："
        echo "  1. fcitx5-configtool → 添加「灵键拼音」"
        echo "  2. 或运行: fcitx5-remote -r"
        echo ""
        echo "卸载命令:"
        echo "  sudo dpkg -r ${PKG_NAME}"
        echo ""

        if command -v lintian &>/dev/null; then
            log_info "运行 lintian 检查..."
            lintian "$DEB_FILE" || true
        fi
    else
        log_error "打包失败: ${DEB_FILE} 未生成"
        exit 1
    fi
}

cleanup() {
    log_info "清理临时打包目录..."
    rm -rf "$DEB_ROOT"
}

main() {
    log_info "====== 灵键拼音 .deb 打包脚本 ======"
    log_info "包名: ${PKG_NAME}  版本: ${PKG_VERSION}  架构: ${PKG_ARCH}"
    echo ""

    check_ubuntu_version
    install_build_deps
    build_project
    prepare_deb_tree
    write_control_file
    write_postinst
    write_postrm
    install_files
    build_deb
    cleanup

    log_info "全部完成!"
}

main
