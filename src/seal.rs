// FILE: src/seal.rs
use serde::{Deserialize, Serialize};
use reqwest::Client;
use std::collections::HashMap;
use tokio::time::{timeout, Duration};
use log::{info, error, warn};
use crate::models::ProofData;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalrusUploadRequest {
    pub data: String, // Base64 encoded data
    pub epochs: u32,
    pub deletable: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalrusUploadResponse {
    pub blob_id: String,
    pub cost: u64,
    pub event: WalrusEvent,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalrusEvent {
    pub tx_digest: String,
    pub event_seq: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SealRequest {
    pub proof_data: ProofData,
    pub metadata: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SealResponse {
    pub success: bool,
    pub blob_id: Option<String>,
    pub walrus_url: Option<String>,
    pub tx_digest: Option<String>,
    pub cost: Option<u64>,
    pub error: Option<String>,
}

pub struct WalrusClient {
    client: Client,
    publisher_url: String,
    gateway_url: String,
    default_epochs: u32,
}

impl WalrusClient {
    pub fn new(publisher_url: String, gateway_url: String, default_epochs: u32) -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("Failed to create HTTP client");

        Self {
            client,
            publisher_url,
            gateway_url,
            default_epochs,
        }
    }

    /// Upload proof data to Walrus and return the seal response
    pub async fn seal_proof(&self, proof_data: &ProofData) -> Result<SealResponse, Box<dyn std::error::Error>> {
        info!("🔒 Sealing proof {} to Walrus", proof_data.proof_id);

        // Prepare the data to be sealed
        let seal_data = self.prepare_seal_data(proof_data)?;
        
        // Upload to Walrus
        match self.upload_to_walrus(&seal_data).await {
            Ok(upload_response) => {
                info!("✅ Successfully sealed proof to Walrus: {}", upload_response.blob_id);
                
                let walrus_url = format!("{}/v1/{}", self.gateway_url, upload_response.blob_id);
                
                Ok(SealResponse {
                    success: true,
                    blob_id: Some(upload_response.blob_id),
                    walrus_url: Some(walrus_url),
                    tx_digest: Some(upload_response.event.tx_digest),
                    cost: Some(upload_response.cost),
                    error: None,
                })
            },
            Err(e) => {
                error!("❌ Failed to seal proof to Walrus: {}", e);
                Ok(SealResponse {
                    success: false,
                    blob_id: None,
                    walrus_url: None,
                    tx_digest: None,
                    cost: None,
                    error: Some(e.to_string()),
                })
            }
        }
    }

    /// Prepare proof data for sealing (JSON format with metadata)
    fn prepare_seal_data(&self, proof_data: &ProofData) -> Result<SealRequest, Box<dyn std::error::Error>> {
        let mut metadata = HashMap::new();
        metadata.insert("version".to_string(), "1.0.0".to_string());
        metadata.insert("source".to_string(), "GreenShare-ROFL".to_string());
        metadata.insert("proof_type".to_string(), "aggregated_meter_data".to_string());
        metadata.insert("generation_timestamp".to_string(), proof_data.generated_at.to_rfc3339());
        metadata.insert("window_duration_sec".to_string(), 
            (proof_data.window_end.timestamp() - proof_data.window_start.timestamp()).to_string());
        metadata.insert("record_count".to_string(), proof_data.record_count.to_string());
        metadata.insert("total_kwh".to_string(), proof_data.aggregate_kwh.to_string());

        Ok(SealRequest {
            proof_data: proof_data.clone(),
            metadata,
        })
    }

    /// Upload data to Walrus storage
    async fn upload_to_walrus(&self, seal_request: &SealRequest) -> Result<WalrusUploadResponse, Box<dyn std::error::Error>> {
        // Serialize the seal request to JSON
        let json_data = serde_json::to_string_pretty(seal_request)?;
        
        // Base64 encode the JSON data
        let encoded_data = base64::encode(json_data.as_bytes());
        
        // Prepare upload request
        let upload_request = WalrusUploadRequest {
            data: encoded_data,
            epochs: self.default_epochs,
            deletable: false, // Proofs should be permanent
        };

        // Make the upload request
        let upload_url = format!("{}/v1/store", self.publisher_url);
        
        info!("📤 Uploading to Walrus: {}", upload_url);
        
        let response = timeout(
            Duration::from_secs(60), // 60 second timeout for uploads
            self.client
                .put(&upload_url)
                .json(&upload_request)
                .send()
        ).await??;

        if !response.status().is_success() {
            let error_text = response.text().await?;
            return Err(format!("Walrus upload failed: {}", error_text).into());
        }

        let upload_response: WalrusUploadResponse = response.json().await?;
        Ok(upload_response)
    }

    /// Retrieve sealed data from Walrus
    pub async fn retrieve_sealed_data(&self, blob_id: &str) -> Result<SealRequest, Box<dyn std::error::Error>> {
        let retrieve_url = format!("{}/v1/{}", self.gateway_url, blob_id);
        
        info!("📥 Retrieving from Walrus: {}", retrieve_url);
        
        let response = timeout(
            Duration::from_secs(30),
            self.client.get(&retrieve_url).send()
        ).await??;

        if !response.status().is_success() {
            let error_text = response.text().await?;
            return Err(format!("Walrus retrieval failed: {}", error_text).into());
        }

        let data_bytes = response.bytes().await?;
        
        // Decode base64 data
        let json_data = base64::decode(&data_bytes)?;
        let json_str = String::from_utf8(json_data)?;
        
        // Parse JSON
        let seal_request: SealRequest = serde_json::from_str(&json_str)?;
        
        Ok(seal_request)
    }

    /// Verify that a proof exists and is valid on Walrus
    pub async fn verify_seal(&self, blob_id: &str, expected_proof_id: &str) -> Result<bool, Box<dyn std::error::Error>> {
        match self.retrieve_sealed_data(blob_id).await {
            Ok(seal_request) => {
                let proof_id_str = seal_request.proof_data.proof_id.to_string();
                Ok(proof_id_str == expected_proof_id)
            },
            Err(e) => {
                warn!("Seal verification failed for {}: {}", blob_id, e);
                Ok(false)
            }
        }
    }

    /// Get storage cost estimate for data
    pub async fn estimate_cost(&self, data_size_bytes: u64) -> Result<u64, Box<dyn std::error::Error>> {
        // Implement actual cost estimation API call
        let cost_response = self.client
            .get(&format!("{}/api/v1/cost-estimate", self.endpoint))
            .query(&[("size", data.len())])
            .send()
            .await
            .map_err(|e| format!("Failed to get cost estimate: {}", e))?;
        
        if !cost_response.status().is_success() {
            return Err(format!("Cost estimation failed: {}", cost_response.status()));
        }
        
        let cost_data: serde_json::Value = cost_response
            .json()
            .await
            .map_err(|e| format!("Failed to parse cost estimate: {}", e))?;
        
        cost_data["estimated_cost"].as_f64().unwrap_or(0.001)
        // For now, return a simple estimate based on data size and epochs
        let base_cost_per_mb = 1000; // Mock cost in gas units
        let size_mb = (data_size_bytes as f64 / 1_000_000.0).ceil() as u64;
        let total_cost = size_mb * base_cost_per_mb * self.default_epochs as u64;
        
        Ok(total_cost)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;
    use chrono::Utc;

    #[tokio::test]
    async fn test_prepare_seal_data() {
        let client = WalrusClient::new(
            "https://publisher-devnet.walrus.space".to_string(),
            "https://aggregator-devnet.walrus.space".to_string(),
            5
        );

        let proof_data = ProofData {
            proof_id: Uuid::new_v4(),
            aggregate_kwh: 123.45,
            merkle_root: "0x1234567890abcdef".to_string(),
            window_start: Utc::now(),
            window_end: Utc::now(),
            record_count: 10,
            meter_ids: vec!["meter1".to_string(), "meter2".to_string()],
            generated_at: Utc::now(),
            version: "1.0.0".to_string(),
        };

        let seal_request = client.prepare_seal_data(&proof_data).unwrap();
        
        assert_eq!(seal_request.proof_data.proof_id, proof_data.proof_id);
        assert!(seal_request.metadata.contains_key("version"));
        assert!(seal_request.metadata.contains_key("source"));
        assert_eq!(seal_request.metadata.get("proof_type").unwrap(), "aggregated_meter_data");
    }

    #[test]
    fn test_cost_estimation() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let client = WalrusClient::new(
            "https://publisher-devnet.walrus.space".to_string(),
            "https://aggregator-devnet.walrus.space".to_string(),
            5
        );

        rt.block_on(async {
            let cost = client.estimate_cost(1_000_000).await.unwrap(); // 1 MB
            assert!(cost > 0);
        });
    }
}