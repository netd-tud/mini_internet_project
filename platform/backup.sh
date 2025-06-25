#!/bin/bash

WORKING_DIR="/users/mini_internet_project/platform"
SCRIPT_ARGS=("-b" "-g" "3,4,5,6,7,8,9,10,11,12,13,14,23,24,25,26,27,28,29,30,31,32,33,34")
SOURCE_DIR="/users/mini_internet_project/students_config"
TARGET_DIR="/net/archive/mini_internet_configs-backup"

cd "$WORKING_DIR" || exit
./utils/save_and_restore/restart_mini_internet.sh "${SCRIPT_ARGS[@]}"
# Format YYYY-MM-DD_HH-MM-SS
CURRENT_DATETIME=$(date +"%Y-%m-%d_%H-%M-%S")
mkdir -p "$TARGET_DIR/$CURRENT_DATETIME"
echo "Folder $CURRENT_DATETIME created in $TARGET_DIR"
cp -r "$SOURCE_DIR" "$TARGET_DIR/$CURRENT_DATETIME"
echo "Copied $SOURCE_DIR into $TARGET_DIR/$CURRENT_DATETIME"