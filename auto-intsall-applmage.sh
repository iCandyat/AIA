#!/bin/bash

# 检查是否输入了AppImage文件路径
if [ $# -eq 0 ]; then
    echo "错误：请提供AppImage文件路径"
    echo "用法: $0 /path/to/your.AppImage"
    exit 1
fi

APPIMAGE="$1"
SCRIPT_NAME=$(basename "$0")
TEMP_ROOT="/tmp/appimage-helper"
DESKTOP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor"

# 检查文件是否存在
if [ ! -f "$APPIMAGE" ]; then
    echo "错误：文件 $APPIMAGE 不存在"
    exit 1
fi

# 获取应用基本信息
APP_NAME=$(basename "$APPIMAGE" | sed 's/\.AppImage//i')
OPT_DIR="/opt/$APP_NAME"
TEMP_DIR="$TEMP_ROOT/$APP_NAME"

# 清理旧临时目录
cleanup() {
    rm -rf "$TEMP_ROOT"
    echo "已清理临时文件"
}
trap cleanup EXIT

# 创建必要目录
mkdir -p "$TEMP_DIR" || exit 1

echo "▌ 正在处理: $APP_NAME"

# 步骤1: 添加执行权限
echo "▌ 添加执行权限..."
chmod +x "$APPIMAGE" || exit 1

# 步骤2: 解压AppImage
echo "▌ 解压AppImage文件..."
if ! "$APPIMAGE" --appimage-extract &>/dev/null; then
    echo "检测到旧格式AppImage，使用unsquashfs解压..."
    unsquashfs -f -d "$TEMP_DIR" "$APPIMAGE" || exit 1
else
    mv squashfs-root "$TEMP_DIR" || exit 1
fi

# 步骤3: 准备安装目录
echo "▌ 创建安装目录: $OPT_DIR"
sudo rm -rf "$OPT_DIR"  # 删除旧版本
sudo mkdir -p "$OPT_DIR" || exit 1

# 步骤4: 移动文件到/opt
echo "▌ 安装应用到系统目录..."
sudo mv "$TEMP_DIR"/* "$OPT_DIR" || exit 1

# 步骤5: 查找并处理.desktop文件
echo "▌ 处理桌面快捷方式..."
DESKTOP_FILE=$(find "$OPT_DIR" -type f -name "*.desktop" | head -n 1)

if [ -n "$DESKTOP_FILE" ]; then
    # 备份原始desktop文件
    cp "$DESKTOP_FILE" "$DESKTOP_FILE.bak"

    # 修改Exec和Icon路径
    sudo sed -i \
        -e "s|Exec=.*|Exec=$OPT_DIR/AppRun|" \
        -e "s|Icon=.*|Icon=$APP_NAME|" \
        "$DESKTOP_FILE"

    # 移动desktop文件
    DESKTOP_NAME=$(basename "$DESKTOP_FILE")
    sudo mv "$DESKTOP_FILE" "$DESKTOP_DIR/$APP_NAME.desktop" || exit 1
    
    echo "▌ 桌面快捷方式已安装: $DESKTOP_DIR/$APP_NAME.desktop"
else
    echo "警告: 未找到.desktop文件"
fi

# 步骤6: 处理图标文件
echo "▌ 处理图标文件..."
find "$OPT_DIR" -type f \( -name "*.png" -o -name "*.svg" -o -name "*.xpm" \) | while read -r ICON_FILE; do
    ICON_SIZE=$(identify -format "%wx%h" "$ICON_FILE" 2>/dev/null)
    ICON_TYPE=""
    
    case "$ICON_SIZE" in
        "256x256") ICON_TYPE="256x256" ;;
        "128x128") ICON_TYPE="128x128" ;;
        "64x64")   ICON_TYPE="64x64" ;;
        "48x48")   ICON_TYPE="48x48" ;;
        "32x32")   ICON_TYPE="32x32" ;;
        "16x16")   ICON_TYPE="16x16" ;;
        *)          ICON_TYPE="scalable" ;;
    esac

    TARGET_ICON_DIR="$ICON_DIR/$ICON_TYPE/apps"
    sudo mkdir -p "$TARGET_ICON_DIR"
    sudo cp "$ICON_FILE" "$TARGET_ICON_DIR/$APP_NAME.${ICON_FILE##*.}" || exit 1
done

echo "▌ 操作完成！应用已安装到 $OPT_DIR"