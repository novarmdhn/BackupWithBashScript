#!/bin/bash

BACKUP_SRC="/Data/DataKTP"
BACKUP_DEST="/Data/DataBackup"
REMOTE_SERVER="root@serverb:/BackupServera"
TELEGRAM_TOKEN="7639188871:AAGKVCf3kCNud1JLirzb1wHT1ch245SPhT8"
TELEGRAM_CHAT_ID="1130838061"
RETENTION_DAYS=30
TIMESTAMP=$(date "+%Y-%m-%d_%H-%M")
LOG_FILE="/MyBackup/logs/backup-${TIMESTAMP}.log"
GPG_RECIPIENT="8737F58F544FB5AFC5C7F71EF2347B3283EFB4C7"

send_telegram_message() {
  local level="$1"
  local status="$2"
  local details="$3"
  local message="[- Server Saviour Backup Report -]

Level: ${level}
Date: ${TIMESTAMP}
Hostname: $(hostname)
IP Address: $(hostname -I | awk '{print $1}')
Bot Alarm: Backup ${status} ${details}"

  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="${message}" >/dev/null
}

compress_and_encrypt_backup() {
  local backup_file="servera_backup_$(date +%Y%m%d%H%M).tar.gz"
  local encrypted_file="${backup_file}.gpg"

  # Compress
  echo "[$TIMESTAMP] Compressing the backup directory..." >> "${LOG_FILE}"
  tar -czf "${BACKUP_SRC}/${backup_file}" -C "${BACKUP_SRC}" .

  if [ $? -ne 0 ]; then
    send_telegram_message "critical" "failed" "to compress the backup directory."
    exit 1
  fi

  # Encrypt
  echo "[$TIMESTAMP] Encrypting the backup file..." >> "${LOG_FILE}"
  gpg --yes --batch --trust-model always --recipient "${GPG_RECIPIENT}" --encrypt "${BACKUP_SRC}/${backup_file}"
  if [ $? -ne 0 ]; then
    send_telegram_message "critical" "failed" "to encrypt the backup file."
    exit 1
  fi

  # Move the encrypted file to /Data/DataBackup
  echo "[$TIMESTAMP] Moving encrypted file to backup directory..." >> "${LOG_FILE}"
  mv "${BACKUP_SRC}/${encrypted_file}" "${BACKUP_DEST}/"
  if [ $? -ne 0 ]; then
    send_telegram_message "critical" "failed" "to move encrypted file to ${BACKUP_DEST}."
    exit 1
  fi
  echo "[$TIMESTAMP] Backup successfully compressed, encrypted, and moved to ${BACKUP_DEST}/${encrypted_file}" >> "${LOG_FILE}"
}

transfer_backup() {
  local encrypted_file=$(find "${BACKUP_DEST}" -type f -name "*.gpg" | sort | tail -n 1)

  echo "[$TIMESTAMP] Transferring encrypted backup file to remote server..." >> "${LOG_FILE}"

  # Transfer the encrypted file
  if rsync -avz "${encrypted_file}" "${REMOTE_SERVER}"; then
    echo "[$TIMESTAMP] Transfer successful. Cleaning up local encrypted backup file..." >> "${LOG_FILE}"
    # Cleanup all files in BACKUP_SRC after transfer
    rm -rf "${BACKUP_SRC}/"*
    echo "[$TIMESTAMP] All files removed from local backup source." >> "${LOG_FILE}"
  else
    # Log and send error notification if the transfer fails
    send_telegram_message "critical" "failed" "to transfer backup to ${REMOTE_SERVER}."
    echo "[$TIMESTAMP] ERROR: Failed to transfer encrypted file to ${REMOTE_SERVER}" >> "${LOG_FILE}"
    exit 1
  fi
}

cleanup_remote_backups() {
  echo "Cleaning up old backups on remote server..." >> "${LOG_FILE}"
  ssh "${REMOTE_SERVER%%:*}" "find ${REMOTE_SERVER#*:} -type f -mtime +${RETENTION_DAYS} -exec rm -f {} \;"
  echo "${TIMESTAMP} Old backups cleaned on remote server." >> "${LOG_FILE}"
}

# === Proses Backup ===
echo "Starting backup process..." >> "${LOG_FILE}"
send_telegram_message "info" "started" "Backup process initiated."

# Step 1: Compress and encrypt backup
encrypted_file=$(compress_and_encrypt_backup)

# Step 2: Transfer encrypted backup to remote server
transfer_backup "${encrypted_file}"

# Step 3: Cleanup old backups on remote server
cleanup_remote_backups

# Step 4: Notify success
send_telegram_message "info" "completed successfully" "Backup process completed for ${TIMESTAMP}."
echo "Backup process completed successfully." >> "${LOG_FILE}"