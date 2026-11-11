// rust_core/src/vault_crypto/mod.rs
use aes::cipher::{block_padding::Pkcs7, BlockDecryptMut, BlockEncryptMut, KeyIvInit};
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use obfstr::obfstr;
use zeroize::Zeroize;

type Aes256CbcDec = cbc::Decryptor<aes::Aes256>;
type Aes256CbcEnc = cbc::Encryptor<aes::Aes256>;

pub struct VaultCrypto;

impl VaultCrypto {
    /// 獲取編譯期打碎之 DoH 網域清單 (零明文常數，打碎於機器指令中)
    pub fn get_doh_endpoints() -> Vec<String> {
        vec![
            obfstr!("https://cloudflare-dns.com/dns-query").to_string(),
            obfstr!("https://dns.google/resolve").to_string(),
            obfstr!("https://doh.pub/dns-query").to_string(),
            obfstr!("https://dns.alidns.com/resolve").to_string(),
        ]
    }

    /// 獲取阿里雲香港 OSS 動態設定檔 URL
    pub fn get_oss_url() -> String {
        obfstr!("https://thjsq999.oss-ap-southeast-1.aliyuncs.com/web-config.json").to_string()
    }

    /// 獲取 DoH 查詢設定網域 (Primary / Secondary)
    pub fn get_config_domains() -> Vec<String> {
        vec![
            obfstr!("thjsqaes32.spsr86.cv").to_string(),
            obfstr!("novaclash.spsr86.cv").to_string(),
        ]
    }

    /// 獲取預設 API 兜底主機清單
    pub fn get_fallback_domains() -> Vec<String> {
        vec![
            obfstr!("https://8.218.176.238:3389").to_string(),
            obfstr!("https://8.218.176.238:8443").to_string(),
            obfstr!("https://8.219.196.216:3389").to_string(),
            obfstr!("https://0n21.com").to_string(),
        ]
    }

    /// 獲取本地核心防窺探 Secret
    pub fn get_core_secret() -> String {
        obfstr!("tianhe_sec_99a8b7c6d5e4").to_string()
    }

    /// 解密 Base64 編碼的 AES-256-CBC 密文
    /// 遵循 PKCS7 Padding，解密完成後立即將金鑰、IV 與工作緩衝區強制 zeroize 清零！
    pub fn decrypt_cbc(ciphertext_base64: &str) -> Result<String, String> {
        let mut key_bytes = obfstr!("5xfWh681lPHNamV89fKFuqZxQyAaBnjs").as_bytes().to_vec();
        let mut iv_bytes = obfstr!("s303Khc0kIFZtVeX").as_bytes().to_vec();

        // 1. 去除引號、空白與換行
        let sanitized = ciphertext_base64
            .trim()
            .trim_matches('"')
            .trim_matches('\'')
            .replace(['"', '\'', ' ', '\n', '\r'], "");

        if sanitized.is_empty() {
            return Err("密文字串為空".to_string());
        }

        // 2. Base64 解碼
        let mut raw_data = BASE64.decode(sanitized).map_err(|e| format!("Base64 解碼失敗: {}", e))?;

        // 3. AES-256-CBC 解密
        let cipher = Aes256CbcDec::new_from_slices(&key_bytes, &iv_bytes)
            .map_err(|e| format!("AES 實例化失敗: {}", e))?;

        let decrypted_bytes = cipher
            .decrypt_padded_mut::<Pkcs7>(&mut raw_data)
            .map_err(|e| format!("PKCS7 解密失敗: {}", e))?;

        let result = String::from_utf8(decrypted_bytes.to_vec())
            .map_err(|e| format!("UTF-8 解析失敗: {}", e))?;

        // 4. 物理記憶體清零 (防記憶體傾印 Dump)
        key_bytes.zeroize();
        iv_bytes.zeroize();
        raw_data.zeroize();

        Ok(result)
    }

    /// 加密明文字串為 Base64 (供單元測試與配置發布使用)
    pub fn encrypt_cbc(plaintext: &str) -> Result<String, String> {
        let mut key_bytes = obfstr!("5xfWh681lPHNamV89fKFuqZxQyAaBnjs").as_bytes().to_vec();
        let mut iv_bytes = obfstr!("s303Khc0kIFZtVeX").as_bytes().to_vec();

        let pt_bytes = plaintext.as_bytes();
        let buf_len = pt_bytes.len() + 16;
        let mut buf = vec![0u8; buf_len];
        buf[..pt_bytes.len()].copy_from_slice(pt_bytes);

        let cipher = Aes256CbcEnc::new_from_slices(&key_bytes, &iv_bytes)
            .map_err(|e| format!("AES Enc 實例化失敗: {}", e))?;

        let ct = cipher
            .encrypt_padded_mut::<Pkcs7>(&mut buf, pt_bytes.len())
            .map_err(|e| format!("PKCS7 加密失敗: {}", e))?;

        let encoded = BASE64.encode(ct);

        key_bytes.zeroize();
        iv_bytes.zeroize();
        buf.zeroize();

        Ok(encoded)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vault_crypto_roundtrip() {
        let sample = r#"{"api_domain":"https://api.v2board.com","latest_version":"3.4.0","min_version":"3.0.0"}"#;
        let encrypted = VaultCrypto::encrypt_cbc(sample).expect("Encryption should succeed");
        assert!(!encrypted.is_empty());

        let decrypted = VaultCrypto::decrypt_cbc(&encrypted).expect("Decryption should succeed");
        assert_eq!(sample, decrypted);
    }

    #[test]
    fn test_vault_crypto_constants() {
        let doh = VaultCrypto::get_doh_endpoints();
        assert_eq!(doh.len(), 4);
        assert!(doh[0].contains("cloudflare-dns.com"));

        let secret = VaultCrypto::get_core_secret();
        assert_eq!(secret, "tianhe_sec_99a8b7c6d5e4");

        let oss = VaultCrypto::get_oss_url();
        assert!(oss.contains("thjsq999.oss-ap-southeast-1.aliyuncs.com"));
    }
}
