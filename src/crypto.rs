// FILE: src/crypto.rs
use secp256k1::{PublicKey, Signature, Message, Secp256k1, ecdsa::RecoverableSignature};
use sha2::{Sha256, Digest};
use sha3::Keccak256;
use hex;
use crate::models::MeterRecord;

pub struct CryptoService {
    secp: Secp256k1<secp256k1::All>,
}

impl CryptoService {
    pub fn new() -> Self {
        Self {
            secp: Secp256k1::new(),
        }
    }

    /// Create deterministic message hash for meter record (compatible with TypeScript version)
    pub fn create_message_hash(&self, record: &MeterRecord) -> Result<[u8; 32], Box<dyn std::error::Error>> {
        // Create the same JSON structure as TypeScript version
        let message = serde_json::json!({
            "meter_id": record.meter_id,
            "timestamp": record.timestamp,
            "kwh_delta": record.kwh_delta,
            "nonce": record.nonce
        });
        
        let message_str = serde_json::to_string(&message)?;
        let mut hasher = Sha256::new();
        hasher.update(message_str.as_bytes());
        Ok(hasher.finalize().into())
    }

    /// Create keccak256 hash of record for Merkle tree
    pub fn create_record_hash(&self, record: &MeterRecord) -> Result<String, Box<dyn std::error::Error>> {
        let message = serde_json::json!({
            "meter_id": record.meter_id,
            "timestamp": record.timestamp,
            "kwh_delta": record.kwh_delta,
            "nonce": record.nonce
        });
        
        let message_str = serde_json::to_string(&message)?;
        let mut hasher = Keccak256::new();
        hasher.update(message_str.as_bytes());
        let hash = hasher.finalize();
        Ok(hex::encode(hash))
    }

    /// Verify ECDSA signature against meter record
    pub fn verify_signature(&self, record: &MeterRecord, signature_hex: &str) -> Result<bool, Box<dyn std::error::Error>> {
        // Create message hash
        let message_hash = self.create_message_hash(record)?;
        let message = Message::from_slice(&message_hash)?;

        // Parse signature (format: 0x + 64 bytes r + 64 bytes s + 2 bytes v)
        let sig_hex = signature_hex.strip_prefix("0x").unwrap_or(signature_hex);
        
        if sig_hex.len() != 130 {
            return Ok(false);
        }

        let r_hex = &sig_hex[0..64];
        let s_hex = &sig_hex[64..128];
        let v_hex = &sig_hex[128..130];

        let r_bytes = hex::decode(r_hex)?;
        let s_bytes = hex::decode(s_hex)?;
        let recovery_id = u8::from_str_radix(v_hex, 16)?;

        // Create recoverable signature
        let mut sig_bytes = [0u8; 64];
        sig_bytes[0..32].copy_from_slice(&r_bytes);
        sig_bytes[32..64].copy_from_slice(&s_bytes);

        let recovery_id = secp256k1::ecdsa::RecoveryId::from_i32(recovery_id as i32)?;
        let recoverable_sig = RecoverableSignature::from_compact(&sig_bytes, recovery_id)?;

        // Recover public key and verify
        match self.secp.recover_ecdsa(&message, &recoverable_sig) {
            Ok(_public_key) => {
                // Convert to non-recoverable signature for verification
                let (_, signature) = recoverable_sig.serialize_compact();
                let sig = Signature::from_compact(&signature)?;
                
                // Recover public key again for verification
                let public_key = self.secp.recover_ecdsa(&message, &recoverable_sig)?;
                
                // Verify signature
                match self.secp.verify_ecdsa(&message, &sig, &public_key) {
                    Ok(_) => Ok(true),
                    Err(_) => Ok(false),
                }
            }
            Err(_) => Ok(false),
        }
    }

    /// Extract public key from signature and record
    pub fn recover_public_key(&self, record: &MeterRecord, signature_hex: &str) -> Result<String, Box<dyn std::error::Error>> {
        let message_hash = self.create_message_hash(record)?;
        let message = Message::from_slice(&message_hash)?;

        let sig_hex = signature_hex.strip_prefix("0x").unwrap_or(signature_hex);
        
        if sig_hex.len() != 130 {
            return Err("Invalid signature length".into());
        }

        let r_hex = &sig_hex[0..64];
        let s_hex = &sig_hex[64..128];
        let v_hex = &sig_hex[128..130];

        let r_bytes = hex::decode(r_hex)?;
        let s_bytes = hex::decode(s_hex)?;
        let recovery_id = u8::from_str_radix(v_hex, 16)?;

        let mut sig_bytes = [0u8; 64];
        sig_bytes[0..32].copy_from_slice(&r_bytes);
        sig_bytes[32..64].copy_from_slice(&s_bytes);

        let recovery_id = secp256k1::ecdsa::RecoveryId::from_i32(recovery_id as i32)?;
        let recoverable_sig = RecoverableSignature::from_compact(&sig_bytes, recovery_id)?;

        let public_key = self.secp.recover_ecdsa(&message, &recoverable_sig)?;
        Ok(hex::encode(public_key.serialize_uncompressed()))
    }

    /// Detect outliers using statistical analysis
    pub fn detect_outliers(&self, kwh_values: &[f64], threshold_multiplier: f64) -> Vec<bool> {
        if kwh_values.len() < 3 {
            return vec![false; kwh_values.len()];
        }

        // Calculate mean and standard deviation
        let mean = kwh_values.iter().sum::<f64>() / kwh_values.len() as f64;
        let variance = kwh_values.iter()
            .map(|x| (x - mean).powi(2))
            .sum::<f64>() / kwh_values.len() as f64;
        let std_dev = variance.sqrt();

        // Mark outliers (values beyond threshold * std_dev from mean)
        let threshold = threshold_multiplier * std_dev;
        kwh_values.iter()
            .map(|&value| (value - mean).abs() > threshold)
            .collect()
    }
}

impl Default for CryptoService {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_hash_consistency() {
        let crypto = CryptoService::new();
        let record = MeterRecord {
            meter_id: "test_meter".to_string(),
            timestamp: 1640995200000,
            kwh_delta: 1.234,
            nonce: "test_nonce".to_string(),
        };

        let hash1 = crypto.create_message_hash(&record).unwrap();
        let hash2 = crypto.create_message_hash(&record).unwrap();
        
        assert_eq!(hash1, hash2);
    }

    #[test]
    fn test_record_hash() {
        let crypto = CryptoService::new();
        let record = MeterRecord {
            meter_id: "test_meter".to_string(),
            timestamp: 1640995200000,
            kwh_delta: 1.234,
            nonce: "test_nonce".to_string(),
        };

        let hash = crypto.create_record_hash(&record).unwrap();
        assert_eq!(hash.len(), 64); // keccak256 produces 32 bytes = 64 hex chars
    }

    #[test]
    fn test_outlier_detection() {
        let crypto = CryptoService::new();
        let values = vec![1.0, 1.1, 1.2, 10.0, 1.3]; // 10.0 is an outlier
        let outliers = crypto.detect_outliers(&values, 2.0);
        
        assert_eq!(outliers.len(), 5);
        assert!(outliers[3]); // 10.0 should be marked as outlier
    }
}