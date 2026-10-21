#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
================================================================================
天河網絡 (Tianhe Network) - AES-256 DNS TXT 配置加解密與金鑰產生器
================================================================================
功能說明：
1. 隨機生成安全高強度的 AES-256 金鑰 (32 字元 / 256-bit) 與 IV (16 字元 / 128-bit)
2. 將 V2Board 遠端配置 JSON 加密為 AES-256-CBC (PKCS7 Padding) Base64 密文（用於 Cloudflare DNS TXT 記錄）
3. 解密 DNS TXT 密文字串還原為格式化 JSON，校驗配置完整性
4. 支援命令行模式與互動式終端選單模式
================================================================================
"""

import sys
import os
import json
import base64
import secrets
import string
import argparse

# 預設金鑰常數（天河網絡專屬金鑰，與客戶端 AppConstants 嚴格對齊）
DEFAULT_KEY = "5xfWh681lPHNamV89fKFuqZxQyAaBnjs"  # 32 bytes
DEFAULT_IV  = "s303Khc0kIFZtVeX"                  # 16 bytes

# 標準天河網絡配置範本
SAMPLE_CONFIG = {
    "api_domain": "https://8.218.176.238:3389",
    "backup_api_domains": [
        "https://0n21.com",
        "https://api-backup.v2board-node.com"
    ],
    "hosts": "portal.0n23.li",
    "invite_link": "https://0n21.com/#/register?code=",
    "crisp_id": "b8b32705-d834-41b5-b6f5-6849fa0679d6",
    "app_name": "天河網絡",
    "latest_version": "1.0.0",
    "min_version": "1.0.0",
    "apk_url": "https://portal.0n23.li/d/android.apk",
    "exe_url": "https://portal.0n23.li/d/windows.zip",
    "changelog": "1. 全面升級深色科技主題\n2. 節點大洲分組 (亞洲/美洲/歐洲/其他)\n3. 支援系統語言自動跟隨"
}

def generate_key_and_iv():
    """生成 32-byte Key 和 16-byte IV (英數字元組合，方便填入程式碼)"""
    chars = string.ascii_letters + string.digits
    key = ''.join(secrets.choice(chars) for _ in range(32))
    iv = ''.join(secrets.choice(chars) for _ in range(16))
    return key, iv

def pkcs7_pad(data: bytes, block_size: int = 16) -> bytes:
    """PKCS7 填充"""
    pad_len = block_size - (len(data) % block_size)
    return data + bytes([pad_len] * pad_len)

def pkcs7_unpad(data: bytes) -> bytes:
    """PKCS7 去除填充"""
    if not data:
        raise ValueError("資料為空，無法去除填充")
    pad_len = data[-1]
    if pad_len < 1 or pad_len > 16:
        raise ValueError("無效的 PKCS7 填充長度")
    if data[-pad_len:] != bytes([pad_len] * pad_len):
        raise ValueError("PKCS7 填充校驗失敗")
    return data[:-pad_len]

# 嘗試使用 cryptography 庫，若無安裝則回退純 Python AES 實作或提示安裝
try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    from cryptography.hazmat.backends import default_backend

    def encrypt_aes_cbc(plain_text: str, key_str: str, iv_str: str) -> str:
        key_bytes = key_str.encode('utf-8')
        iv_bytes = iv_str.encode('utf-8')
        if len(key_bytes) != 32:
            raise ValueError(f"AES-256 金鑰必須為 32 位元組，當前為 {len(key_bytes)} 位元組")
        if len(iv_bytes) != 16:
            raise ValueError(f"AES IV 必須為 16 位元組，當前為 {len(iv_bytes)} 位元組")

        raw_data = plain_text.encode('utf-8')
        padded_data = pkcs7_pad(raw_data, 16)

        cipher = Cipher(algorithms.AES(key_bytes), modes.CBC(iv_bytes), backend=default_backend())
        encryptor = cipher.encryptor()
        encrypted_bytes = encryptor.update(padded_data) + encryptor.finalize()
        return base64.b64encode(encrypted_bytes).decode('utf-8')

    def decrypt_aes_cbc(cipher_b64: str, key_str: str, iv_str: str) -> str:
        key_bytes = key_str.encode('utf-8')
        iv_bytes = iv_str.encode('utf-8')
        if len(key_bytes) != 32:
            raise ValueError(f"AES-256 金鑰必須為 32 位元組，當前為 {len(key_bytes)} 位元組")
        if len(iv_bytes) != 16:
            raise ValueError(f"AES IV 必須為 16 位元組，當前為 {len(iv_bytes)} 位元組")

        # 清理 DNS TXT 可能夾帶的引號與換行
        clean_b64 = cipher_b64.strip().replace('"', '').replace('\n', '').replace(' ', '')
        encrypted_bytes = base64.b64decode(clean_b64)

        cipher = Cipher(algorithms.AES(key_bytes), modes.CBC(iv_bytes), backend=default_backend())
        decryptor = cipher.decryptor()
        padded_plain = decryptor.update(encrypted_bytes) + decryptor.finalize()
        plain_bytes = pkcs7_unpad(padded_plain)
        return plain_bytes.decode('utf-8')

except ImportError:
    # 備用純 Python / PyCryptodome 檢測
    try:
        from Crypto.Cipher import AES
        from Crypto.Util.Padding import pad, unpad

        def encrypt_aes_cbc(plain_text: str, key_str: str, iv_str: str) -> str:
            key_bytes = key_str.encode('utf-8')
            iv_bytes = iv_str.encode('utf-8')
            cipher = AES.new(key_bytes, AES.MODE_CBC, iv_bytes)
            padded = pad(plain_text.encode('utf-8'), 16)
            return base64.b64encode(cipher.encrypt(padded)).decode('utf-8')

        def decrypt_aes_cbc(cipher_b64: str, key_str: str, iv_str: str) -> str:
            key_bytes = key_str.encode('utf-8')
            iv_bytes = iv_str.encode('utf-8')
            clean_b64 = cipher_b64.strip().replace('"', '').replace('\n', '').replace(' ', '')
            encrypted_bytes = base64.b64decode(clean_b64)
            cipher = AES.new(key_bytes, AES.MODE_CBC, iv_bytes)
            decrypted = unpad(cipher.decrypt(encrypted_bytes), 16)
            return decrypted.decode('utf-8')
    except ImportError:
        def encrypt_aes_cbc(plain_text: str, key_str: str, iv_str: str) -> str:
            raise RuntimeError("請先安裝加密庫：pip install cryptography 或 pip install pycryptodome")
        def decrypt_aes_cbc(cipher_b64: str, key_str: str, iv_str: str) -> str:
            raise RuntimeError("請先安裝加密庫：pip install cryptography 或 pip install pycryptodome")


def interactive_menu():
    """終端互動選單模式"""
    print("\n" + "=" * 65)
    print("      天河網絡 (Tianhe Network) - AES-256 DNS TXT 配置小工具")
    print("=" * 65)
    print(" [1] 隨機生成新的 AES-256 Key (32字元) 與 IV (16字元)")
    print(" [2] 將 JSON 配置加密為 DNS TXT 密文 (Base64)")
    print(" [3] 解密 DNS TXT 密文並校驗 JSON")
    print(" [4] 匯出天河網絡標準配置範本為 JSON 檔案 (config_sample.json)")
    print(" [0] 退出程式")
    print("=" * 65)

    choice = input("請選擇操作功能 [0-4]: ").strip()

    if choice == "1":
        key, iv = generate_key_and_iv()
        print("\n[+] 生成成功！請妥善保存：")
        print(f"    AES Key (32 Bytes): {key}")
        print(f"    AES IV  (16 Bytes): {iv}")
        print("\n提示：請將此 Key 與 IV 替換至客戶端 lib/core/constants/app_constants.dart 中。")

    elif choice == "2":
        print(f"\n當前預設 Key: {DEFAULT_KEY}")
        print(f"當前預設 IV:  {DEFAULT_IV}")
        use_default = input("是否使用上述預設 Key 與 IV？[Y/n]: ").strip().lower()
        key = DEFAULT_KEY
        iv = DEFAULT_IV
        if use_default == 'n':
            key = input("請輸入 32 字元 Key: ").strip()
            iv = input("請輸入 16 字元 IV: ").strip()

        print("\n請選擇輸入來源：")
        print(" [1] 使用內建標準配置範本")
        print(" [2] 手動輸入/貼上 JSON 字串")
        print(" [3] 讀取本地 JSON 檔案")
        src_opt = input("請選擇 [1-3]: ").strip()

        json_str = ""
        if src_opt == "1":
            json_str = json.dumps(SAMPLE_CONFIG, ensure_ascii=False, indent=2)
            print(f"\n使用標準配置：\n{json_str}")
        elif src_opt == "2":
            print("請輸入單行或多行 JSON（輸入完畢請按 Enter 並按 Ctrl+Z / Ctrl+D 結束）：")
            lines = sys.stdin.read()
            json_str = lines.strip()
        elif src_opt == "3":
            fpath = input("請輸入 JSON 檔案路徑: ").strip()
            with open(fpath, 'r', encoding='utf-8') as f:
                json_str = f.read().strip()

        # 壓縮為單行 JSON 減少 TXT 體積
        try:
            parsed = json.loads(json_str)
            compact_json = json.dumps(parsed, ensure_ascii=False, separators=(',', ':'))
            ciphertext = encrypt_aes_cbc(compact_json, key, iv)
            print("\n" + "-" * 65)
            print("【加密成功！】請直接複製以下密文貼入 Cloudflare DNS TXT 記錄值：")
            print("-" * 65)
            print(ciphertext)
            print("-" * 65)
            print(f"密文字元長度: {len(ciphertext)} 字元 (標準 DNS TXT 支援單段 255 字元，多段自動拼接)")
        except Exception as e:
            print(f"\n[-] 加密失敗: {e}")

    elif choice == "3":
        print(f"\n當前預設 Key: {DEFAULT_KEY}")
        print(f"當前預設 IV:  {DEFAULT_IV}")
        use_default = input("是否使用上述預設 Key 與 IV？[Y/n]: ").strip().lower()
        key = DEFAULT_KEY
        iv = DEFAULT_IV
        if use_default == 'n':
            key = input("請輸入 32 字元 Key: ").strip()
            iv = input("請輸入 16 字元 IV: ").strip()

        cipher_input = input("\n請貼上 DNS TXT 密文字串: ").strip()
        try:
            decrypted = decrypt_aes_cbc(cipher_input, key, iv)
            print("\n" + "-" * 65)
            print("【解密成功！】還原之配置內容如下：")
            print("-" * 65)
            try:
                parsed = json.loads(decrypted)
                print(json.dumps(parsed, ensure_ascii=False, indent=2))
            except:
                print(decrypted)
            print("-" * 65)
        except Exception as e:
            print(f"\n[-] 解密失敗: {e}")

    elif choice == "4":
        out_file = "config_sample.json"
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(SAMPLE_CONFIG, f, ensure_ascii=False, indent=2)
        print(f"\n[+] 已成功導出範本檔案至: {os.path.abspath(out_file)}")

    elif choice == "0":
        sys.exit(0)

def main():
    parser = argparse.ArgumentParser(description="天河網絡 AES-256 DNS TXT 配置工具")
    parser.add_argument("--gen-keys", action="store_true", help="隨機產生 32-byte Key 與 16-byte IV")
    parser.add_argument("--encrypt", type=str, help="欲加密的明文 JSON 字串")
    parser.add_argument("--decrypt", type=str, help="欲解密的 Base64 TXT 密文字串")
    parser.add_argument("--key", type=str, default=DEFAULT_KEY, help="32-byte AES Key")
    parser.add_argument("--iv", type=str, default=DEFAULT_IV, help="16-byte AES IV")
    parser.add_argument("--file", type=str, help="欲加密的 JSON 檔案路徑")

    args = parser.parse_args()

    if args.gen_keys:
        k, i = generate_key_and_iv()
        print(f"Key: {k}")
        print(f"IV:  {i}")
        return

    if args.encrypt:
        print(encrypt_aes_cbc(args.encrypt, args.key, args.iv))
        return

    if args.file:
        with open(args.file, "r", encoding="utf-8") as f:
            content = f.read().strip()
        compact = json.dumps(json.loads(content), ensure_ascii=False, separators=(',', ':'))
        print(encrypt_aes_cbc(compact, args.key, args.iv))
        return

    if args.decrypt:
        print(decrypt_aes_cbc(args.decrypt, args.key, args.iv))
        return

    # 若無參數則啟動互動選單
    while True:
        interactive_menu()
        cont = input("\n是否繼續執行其他操作？[y/N]: ").strip().lower()
        if cont != 'y':
            break

if __name__ == "__main__":
    if hasattr(sys.stdout, 'reconfigure'):
        try:
            sys.stdout.reconfigure(encoding='utf-8')
        except Exception:
            pass
    main()
