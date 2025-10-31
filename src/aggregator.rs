// FILE: src/aggregator.rs
use chrono::{DateTime, Utc, Duration};
use log::{info, warn, error, debug};
use std::collections::HashMap;
use uuid::Uuid;
use tokio::fs;

use crate::config::Config;
use crate::models::{MeterRecord, VerifiedRecord, AggregationWindow, ProofData, WindowStatus};
use crate::crypto::CryptoService;
use crate::merkle::MerkleTree;

pub struct DataAggregator {
    config: Config,
    crypto: CryptoService,
    current_window: Option<AggregationWindow>,
    stats: AggregatorStats,
}

#[derive(Debug, Default)]
pub struct AggregatorStats {
    pub total_records_processed: usize,
    pub total_proofs_generated: usize,
    pub last_proof_generated: Option<DateTime<Utc>>,
    pub records_rejected_signature: usize,
    pub records_rejected_outlier: usize,
    pub records_rejected_duplicate: usize,
}

impl DataAggregator {
    pub fn new(config: Config) -> Self {
        Self {
            config,
            crypto: CryptoService::new(),
            current_window: None,
            stats: AggregatorStats::default(),
        }
    }

    /// Process incoming meter data
    pub async fn process_record(&mut self, record: MeterRecord, signature: String) 
        -> Result<Uuid, Box<dyn std::error::Error + Send + Sync>> {
        
        let receipt_id = Uuid::new_v4();
        debug!("Processing record for meter {} with receipt {}", record.meter_id, receipt_id);

        // Verify signature if enabled
        if self.config.enable_signature_verification {
            if !self.crypto.verify_signature(&record, &signature)? {
                self.stats.records_rejected_signature += 1;
                return Err("Invalid signature".into());
            }
        }

        // Create verified record
        let record_hash = self.crypto.create_record_hash(&record)?;
        let verified_record = VerifiedRecord {
            record: record.clone(),
            signature,
            verification_timestamp: Utc::now(),
            record_hash,
        };

        // Ensure we have a current window
        self.ensure_current_window()?;

        // Check for duplicate records (same meter_id and nonce)
        if let Some(ref window) = self.current_window {
            let is_duplicate = window.records.iter().any(|r| 
                r.record.meter_id == record.meter_id && r.record.nonce == record.nonce
            );
            
            if is_duplicate {
                self.stats.records_rejected_duplicate += 1;
                return Err("Duplicate record (same meter_id and nonce)".into());
            }
        }

        // Add to current window
        if let Some(ref mut window) = self.current_window {
            // Check window capacity
            if window.records.len() >= self.config.max_records_per_window {
                warn!("Window capacity exceeded, forcing aggregation");
                self.finalize_current_window().await?;
                self.ensure_current_window()?;
            }

            // Check if window has expired
            if Utc::now() >= window.window_end {
                info!("Window expired, finalizing aggregation");
                self.finalize_current_window().await?;
                self.ensure_current_window()?;
            }

            // Add record to current window
            if let Some(ref mut window) = self.current_window {
                window.records.push(verified_record);
                self.stats.total_records_processed += 1;
                
                debug!("Added record to window. Total records in window: {}", window.records.len());
            }
        }

        Ok(receipt_id)
    }

    /// Ensure we have a current aggregation window
    fn ensure_current_window(&mut self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        if self.current_window.is_none() || 
           (self.current_window.as_ref().unwrap().window_end <= Utc::now()) {
            self.start_new_window()?;
        }
        Ok(())
    }

    /// Start a new aggregation window
    fn start_new_window(&mut self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let now = Utc::now();
        let window_duration = Duration::seconds(self.config.agg_window_sec as i64);
        
        // Align window to hour boundaries for consistency
        let window_start = now
            .with_minute(0).unwrap()
            .with_second(0).unwrap()
            .with_nanosecond(0).unwrap();
        
        let window_end = window_start + window_duration;

        self.current_window = Some(AggregationWindow {
            window_start,
            window_end,
            records: Vec::new(),
        });

        info!("Started new aggregation window: {} to {}", window_start, window_end);
        Ok(())
    }

    /// Finalize current window and generate proof
    pub async fn finalize_current_window(&mut self) -> Result<Option<ProofData>, Box<dyn std::error::Error + Send + Sync>> {
        let window = match self.current_window.take() {
            Some(window) => window,
            None => return Ok(None),
        };

        if window.records.is_empty() {
            info!("No records in window, skipping proof generation");
            return Ok(None);
        }

        info!("Finalizing window with {} records", window.records.len());

        // Filter outliers
        let filtered_records = self.filter_outliers(window.records)?;
        info!("After outlier filtering: {} records", filtered_records.len());

        if filtered_records.is_empty() {
            warn!("All records filtered out as outliers");
            return Ok(None);
        }

        // Generate proof
        let proof = self.generate_proof(&window, filtered_records).await?;
        
        // Save proof to file
        self.save_proof(&proof).await?;
        
        self.stats.total_proofs_generated += 1;
        self.stats.last_proof_generated = Some(Utc::now());

        info!("Generated proof {} for window {} to {}", 
              proof.proof_id, proof.window_start, proof.window_end);

        Ok(Some(proof))
    }

    /// Filter outliers from records
    fn filter_outliers(&mut self, records: Vec<VerifiedRecord>) 
        -> Result<Vec<VerifiedRecord>, Box<dyn std::error::Error + Send + Sync>> {
        
        if records.len() < 3 {
            return Ok(records); // Not enough data for outlier detection
        }

        let kwh_values: Vec<f64> = records.iter().map(|r| r.record.kwh_delta).collect();
        let outlier_flags = self.crypto.detect_outliers(&kwh_values, self.config.outlier_threshold_multiplier);

        let filtered: Vec<VerifiedRecord> = records.into_iter()
            .zip(outlier_flags.iter())
            .filter_map(|(record, &is_outlier)| {
                if is_outlier {
                    self.stats.records_rejected_outlier += 1;
                    warn!("Filtered outlier: meter_id={}, kwh_delta={}", 
                          record.record.meter_id, record.record.kwh_delta);
                    None
                } else {
                    Some(record)
                }
            })
            .collect();

        Ok(filtered)
    }

    /// Generate cryptographic proof from aggregated data
    async fn generate_proof(&self, window: &AggregationWindow, records: Vec<VerifiedRecord>) 
        -> Result<ProofData, Box<dyn std::error::Error + Send + Sync>> {
        
        // Calculate aggregate kWh
        let aggregate_kwh: f64 = records.iter().map(|r| r.record.kwh_delta).sum();

        // Extract unique meter IDs
        let mut meter_ids: Vec<String> = records.iter()
            .map(|r| r.record.meter_id.clone())
            .collect();
        meter_ids.sort();
        meter_ids.dedup();

        // Generate Merkle tree from record hashes
        let record_hashes: Vec<String> = records.iter()
            .map(|r| r.record_hash.clone())
            .collect();

        let merkle_tree = MerkleTree::new(record_hashes)?;
        
        Ok(ProofData {
            proof_id: Uuid::new_v4(),
            aggregate_kwh,
            merkle_root: merkle_tree.root,
            window_start: window.window_start,
            window_end: window.window_end,
            record_count: records.len(),
            meter_ids,
            generated_at: Utc::now(),
            version: "1.0.0".to_string(),
        })
    }

    /// Save proof to JSON file
    async fn save_proof(&self, proof: &ProofData) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let filename = format!("proof_{}.json", proof.proof_id);
        let filepath = format!("{}/{}", self.config.output_dir, filename);
        
        let json_content = serde_json::to_string_pretty(proof)?;
        fs::write(&filepath, json_content).await?;
        
        // Also save as latest.json for easy access
        let latest_path = format!("{}/latest.json", self.config.output_dir);
        let json_content = serde_json::to_string_pretty(proof)?;
        fs::write(latest_path, json_content).await?;
        
        info!("Saved proof to {}", filepath);
        Ok(())
    }

    /// Get latest proof from file
    pub async fn get_latest_proof(&self) -> Result<Option<ProofData>, Box<dyn std::error::Error + Send + Sync>> {
        let latest_path = format!("{}/latest.json", self.config.output_dir);
        
        match fs::read_to_string(latest_path).await {
            Ok(content) => {
                let proof: ProofData = serde_json::from_str(&content)?;
                Ok(Some(proof))
            }
            Err(_) => Ok(None), // File doesn't exist
        }
    }

    /// Get current window status
    pub fn get_window_status(&self) -> Option<WindowStatus> {
        self.current_window.as_ref().map(|window| {
            let now = Utc::now();
            let time_remaining = (window.window_end - now).num_seconds().max(0);
            
            WindowStatus {
                window_start: window.window_start,
                window_end: window.window_end,
                records_collected: window.records.len(),
                time_remaining_seconds: time_remaining,
            }
        })
    }

    /// Get aggregator statistics
    pub fn get_stats(&self) -> &AggregatorStats {
        &self.stats
    }

    /// Force finalization of current window (for testing/manual triggers)
    pub async fn force_finalize(&mut self) -> Result<Option<ProofData>, Box<dyn std::error::Error + Send + Sync>> {
        if self.current_window.is_some() {
            self.finalize_current_window().await
        } else {
            Ok(None)
        }
    }
}